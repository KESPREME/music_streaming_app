// lib/services/equalizer_service.dart
//
// THE EQUALIZER: state, persistence, and the conversation with Android's audio
// effects.
//
// What changed from the first version, and why:
//
//   * It used to drive `AndroidEqualizer` from just_audio. That effect has to be
//     built into the player up front, the app kept it out (it threw out of play()
//     on devices that cannot create it), and the instance this class talked to
//     was not even the one the player owned - so it did nothing, anywhere.
//     Effects now live in a native engine (EqualizerChannel.java), created on
//     demand per audio session, each in its own try/catch.
//   * An attached effect stops Android's low-power audio path, so the engine is
//     attached ONLY while the equalizer is on and released the moment it is off.
//   * Both players of a crossfade are processed: each reports its audio session
//     id and the engine attaches to all of them.
//   * The "honest" part: it reads the device's real bands and range, and refuses
//     to claim it is on when there is nothing behind the switch.
//
// The public surface the Material You equalizer screen already uses is kept
// (`presets`, `bandLabels`, `bandCount`, `isEnabled`, `selectPreset`,
// `setBandGain`, `reset`, `initialize`, listeners) so that screen keeps working,
// now for real.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_output_service.dart';
import 'eq/eq_curves.dart';
import 'eq/eq_models.dart';
import 'eq/eq_platform.dart';
import 'eq/eq_presets.dart';

/// Legacy preset shape, kept for the Material You screen: 5 fixed bands.
class EQPreset {
  final String name;
  final String id;
  final List<double> bandGains;

  const EQPreset({
    required this.name,
    required this.id,
    required this.bandGains,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'id': id,
        'bandGains': bandGains,
      };

  factory EQPreset.fromJson(Map<String, dynamic> json) => EQPreset(
        name: json['name'] as String,
        id: json['id'] as String,
        bandGains: [for (final g in (json['bandGains'] as List)) (g as num).toDouble()],
      );
}

class EqualizerService extends ChangeNotifier {
  EqualizerService._(
    this._platform, {
    required bool supported,
    Duration pushDelay = const Duration(milliseconds: 24),
    Duration saveDelay = const Duration(milliseconds: 350),
    Future<SharedPreferences> Function()? prefs,
  })  : _supported = supported,
        _pushDelay = pushDelay,
        _saveDelay = saveDelay,
        _prefs = prefs ?? SharedPreferences.getInstance;

  static final EqualizerService _instance = EqualizerService._(
    MethodChannelEqPlatform(),
    supported: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
  );

  factory EqualizerService() => _instance;

  /// A separate instance over a fake platform, for tests.
  @visibleForTesting
  factory EqualizerService.test({
    required EqPlatform platform,
    bool supported = true,
    Duration pushDelay = Duration.zero,
    Duration saveDelay = Duration.zero,
    Future<SharedPreferences> Function()? prefs,
  }) =>
      EqualizerService._(platform,
          supported: supported,
          pushDelay: pushDelay,
          saveDelay: saveDelay,
          prefs: prefs);

  static const String _stateKey = 'eq_state_v2';

  final EqPlatform _platform;
  final bool _supported;
  final Duration _pushDelay;
  final Duration _saveDelay;
  final Future<SharedPreferences> Function() _prefs;

  EqCapabilities _caps = EqCapabilities.unavailable;
  EqState _state = const EqState();
  final Map<Object, int> _sessions = {};
  bool _bypass = false;
  bool _engineOk = true;
  String _outputKey = 'speaker';
  String _outputName = 'This phone';
  AudioOutputService? _output;

  // ── What the screen reads ────────────────────────────────────────────────

  /// What this phone can do. Probed once at start-up.
  EqCapabilities get capabilities => _caps;

  /// Whether the device exposes an equalizer at all.
  bool get isPlatformAvailable => _caps.available;

  /// The device's bands (a typical five when it reports none, for drawing only).
  List<EqBand> get bands => _caps.displayBands;

  /// The profile in force: the global one, or the current output's.
  EqProfile get profile => _fit(_state.profile(_activeKey));

  String get _activeKey => _state.perOutput ? _outputKey : 'all';

  /// Whether the equalizer is switched on AND there is an effect behind it.
  bool get isEnabled => profile.enabled && _caps.available;

  bool get perOutput => _state.perOutput;
  String get outputKey => _outputKey;
  String get outputName => _outputName;
  List<UserEqPreset> get userPresets => _state.userPresets;

  /// Hold-to-compare: the effects stay attached but pass the signal untouched.
  bool get bypass => _bypass;

  /// False when the host could not create any effect for the live sessions.
  bool get engineHealthy => _engineOk;

  /// How many audio sessions are being processed.
  int get sessionCount => _sessions.length;

  /// Per-band gain the listener set, dB.
  List<double> get gains => profile.gains;

  /// The headroom being paid back, dB (0 when auto headroom is off).
  double get headroomDb {
    final p = profile;
    return p.autoHeadroom ? eqHeadroom(p.gains, p.preampDb) : 0;
  }

  /// Per-band level actually applied, dB.
  List<double> get effectiveGains {
    final p = profile;
    return effectiveLevels(
      p.gains,
      preampDb: p.preampDb,
      autoHeadroom: p.autoHeadroom,
      minDb: _caps.minDb,
      maxDb: _caps.maxDb,
    );
  }

  /// The built-in or saved preset the profile is on, if it is on one.
  String get currentPresetId => profile.presetId;

  String get currentPresetName {
    final id = profile.presetId;
    if (id == 'custom') return 'Custom';
    if (id.startsWith('user:')) {
      for (final u in _state.userPresets) {
        if (u.presetId == id) return u.name;
      }
      return 'Custom';
    }
    return presetById(id)?.name ?? 'Custom';
  }

  // ── Legacy surface (Material You equalizer screen) ───────────────────────

  static List<EQPreset> get presets {
    const five = [60.0, 230.0, 910.0, 3600.0, 14000.0];
    return [
      for (final p in kEqPresets)
        EQPreset(name: p.name, id: p.id, bandGains: p.gainsFor(five)),
      const EQPreset(
          name: 'Custom', id: 'custom', bandGains: [0, 0, 0, 0, 0]),
    ];
  }

  static List<String> get bandLabels =>
      [for (final c in _instance._caps.centers) formatHzShort(c)];

  static int get bandCount => _instance._caps.displayBands.length;

  List<double> get currentBandGains => List<double>.of(profile.gains);

  EQPreset get currentPreset => presets.firstWhere(
        (p) => p.id == profile.presetId,
        orElse: () => presets.first,
      );

  // ── Start-up ─────────────────────────────────────────────────────────────

  bool _initializing = false;

  /// Loads the saved state and asks the device what it can do. Safe to call
  /// more than once; the argument is accepted for the old call sites and
  /// ignored (the player no longer owns the effect).
  Future<void> initialize([Object? legacyAudioService]) async {
    if (_initializing) return;
    _initializing = true;
    try {
      _state = await _load();
      _caps = _supported ? await _platform.probe() : EqCapabilities.unavailable;
      _state = _normalized(_state);
      notifyListeners();
      _schedulePush();
    } finally {
      _initializing = false;
    }
  }

  /// Kept for the old call site; the player no longer carries the effect.
  void setAudioService(Object audioService) {}

  // ── Sessions & output ────────────────────────────────────────────────────

  /// A player (deck) reports its Android audio session id, or null/0 when it
  /// is gone. The effects follow.
  void reportSession(Object owner, int? sessionId) {
    final had = _sessions[owner];
    if (sessionId == null || sessionId <= 0) {
      if (_sessions.remove(owner) != null) _schedulePush();
      return;
    }
    if (had == sessionId) return;
    _sessions[owner] = sessionId;
    _schedulePush();
  }

  /// Follow the phone's active output (speaker / wired / Bluetooth).
  void bindOutput(AudioOutputService service) {
    _output?.removeListener(_onOutputChanged);
    _output = service..addListener(_onOutputChanged);
    _onOutputChanged();
  }

  static String outputKeyFor(String kind) => switch (kind) {
        'bluetooth' => 'bluetooth',
        'wired' || 'usb' => 'wired',
        _ => 'speaker',
      };

  void _onOutputChanged() {
    final active = _output?.active;
    final key = outputKeyFor(active?.kind ?? 'speaker');
    final name = _output?.activeName ?? 'This phone';
    if (key == _outputKey && name == _outputName) return;
    _outputKey = key;
    _outputName = name;
    // The profile in force may have just changed.
    notifyListeners();
    if (_state.perOutput) _schedulePush();
  }

  // ── Editing ──────────────────────────────────────────────────────────────

  Future<void> setEnabled(bool enabled) async {
    // Refuse rather than pretend. Reporting "on" with no effect behind it is how
    // a screen ends up lying about what is happening to the audio.
    if (enabled && !_caps.available) {
      if (kDebugMode) {
        debugPrint('EqualizerService: ignored enable - no platform equalizer');
      }
      _setProfile(profile.copyWith(enabled: false));
      return;
    }
    _setProfile(profile.copyWith(enabled: enabled));
  }

  /// Picks a built-in (`flat`, `rock`...) or saved (`user:<id>`) preset.
  Future<void> selectPreset(String presetId) async {
    final centers = _caps.centers;
    if (presetId == 'custom') {
      _setProfile(profile.copyWith(presetId: 'custom'));
      return;
    }
    if (presetId.startsWith('user:')) {
      for (final u in _state.userPresets) {
        if (u.presetId == presetId) {
          _setProfile(profile.copyWith(
              presetId: presetId, gains: resamplePoints(u.points, centers)));
          return;
        }
      }
      return;
    }
    final def = presetById(presetId);
    if (def == null) return;
    _setProfile(profile.copyWith(presetId: def.id, gains: def.gainsFor(centers)));
  }

  /// Sets one band. Moving a band leaves the preset behind: it is now Custom.
  Future<void> setBandGain(int bandIndex, double gain) async {
    final p = profile;
    if (bandIndex < 0 || bandIndex >= p.gains.length) return;
    final next = List<double>.of(p.gains);
    next[bandIndex] = snapDb(gain, _caps.minDb, _caps.maxDb);
    if (next[bandIndex] == p.gains[bandIndex] && p.presetId == 'custom') return;
    _setProfile(p.copyWith(presetId: 'custom', gains: next));
  }

  /// Replaces every band at once (a gesture across the curve).
  void setGains(List<double> gains) {
    final p = profile;
    if (gains.length != p.gains.length) return;
    _setProfile(p.copyWith(presetId: 'custom', gains: [
      for (final g in gains) snapDb(g, _caps.minDb, _caps.maxDb)
    ]));
  }

  void setPreamp(double db) => _setProfile(profile.copyWith(
      preampDb: ((db * 2).round() / 2).clamp(-EqProfile.maxPreamp, EqProfile.maxPreamp).toDouble()));

  void setAutoHeadroom(bool on) =>
      _setProfile(profile.copyWith(autoHeadroom: on));

  void setLoudness(double db) => _setProfile(profile.copyWith(
      loudnessDb: ((db * 2).round() / 2).clamp(0, EqProfile.maxLoudness).toDouble()));

  void setBassBoost(double v) =>
      _setProfile(profile.copyWith(bassBoost: v.clamp(0, 1).toDouble()));

  void setVirtualizer(double v) =>
      _setProfile(profile.copyWith(virtualizer: v.clamp(0, 1).toDouble()));

  /// Flat, no pre-amp, no effects. Leaves the on/off switch where it was.
  Future<void> reset() async {
    final p = profile;
    _setProfile(EqProfile(
      enabled: p.enabled,
      presetId: 'flat',
      gains: List<double>.filled(_caps.displayBands.length, 0),
    ));
  }

  void setBypass(bool on) {
    if (_bypass == on) return;
    _bypass = on;
    notifyListeners();
    _schedulePush();
  }

  Future<void> setPerOutput(bool on) async {
    if (_state.perOutput == on) return;
    var s = _state.copyWith(perOutput: on);
    if (on) {
      // Each output starts as a copy of what is in force now, so turning the
      // switch on changes nothing audible until the listener changes something.
      final base = _state.profile('all');
      final profiles = {...s.profiles};
      for (final k in const ['speaker', 'wired', 'bluetooth']) {
        profiles.putIfAbsent(k, () => base);
      }
      s = s.copyWith(profiles: profiles);
    }
    _state = s;
    notifyListeners();
    _schedulePush();
    _scheduleSave();
  }

  // ── User presets ─────────────────────────────────────────────────────────

  /// Saves the current curve under [name]; returns the new preset.
  UserEqPreset saveUserPreset(String name) {
    final centers = _caps.centers;
    final g = profile.gains;
    final preset = UserEqPreset(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: name.trim().isEmpty ? 'My preset' : name.trim(),
      points: [
        for (var i = 0; i < centers.length && i < g.length; i++) (centers[i], g[i])
      ],
    );
    _state = _state.copyWith(userPresets: [..._state.userPresets, preset]);
    _setProfile(profile.copyWith(presetId: preset.presetId));
    return preset;
  }

  void renameUserPreset(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _state = _state.copyWith(userPresets: [
      for (final u in _state.userPresets)
        if (u.id == id) u.rename(trimmed) else u
    ]);
    notifyListeners();
    _scheduleSave();
  }

  void deleteUserPreset(String id) {
    final doomed = 'user:$id';
    // Anything standing on the deleted preset keeps its curve and becomes Custom.
    final profiles = {
      for (final e in _state.profiles.entries)
        e.key: e.value.presetId == doomed
            ? e.value.copyWith(presetId: 'custom')
            : e.value
    };
    _state = _state.copyWith(
      profiles: profiles,
      userPresets: [for (final u in _state.userPresets) if (u.id != id) u],
    );
    notifyListeners();
    _scheduleSave();
  }

  // ── Internals ────────────────────────────────────────────────────────────

  void _setProfile(EqProfile p) {
    final key = _activeKey;
    if (_state.profile(key) == p && _state.profiles.containsKey(key)) return;
    _state = _state.withProfile(key, p);
    notifyListeners();
    _scheduleSave();
    _schedulePush();
  }

  /// A profile whose gains match the device's band count.
  EqProfile _fit(EqProfile p) {
    final n = _caps.displayBands.length;
    if (p.gains.length == n) return p;
    final centers = _caps.centers;
    final List<double> g;
    if (p.isUser) {
      g = _userGains(p.presetId, centers);
    } else if (presetById(p.presetId) != null) {
      g = presetById(p.presetId)!.gainsFor(centers);
    } else {
      g = List<double>.filled(n, 0);
    }
    return p.copyWith(gains: g);
  }

  List<double> _userGains(String presetId, List<double> centers) {
    for (final u in _state.userPresets) {
      if (u.presetId == presetId) return resamplePoints(u.points, centers);
    }
    return List<double>.filled(centers.length, 0);
  }

  EqState _normalized(EqState s) => s.copyWith(profiles: {
        for (final e in s.profiles.entries) e.key: _fit(e.value)
      });

  Future<EqState> _load() async {
    try {
      final p = await _prefs();
      final v2 = EqState.decode(p.getString(_stateKey));
      if (v2 != null) return v2;
      return _migrateLegacy(p);
    } catch (e) {
      if (kDebugMode) debugPrint('EqualizerService: load failed: $e');
      return const EqState();
    }
  }

  /// The first version stored three loose keys. Carry the listener's choice over.
  EqState _migrateLegacy(SharedPreferences p) {
    final enabled = p.getBool('eq_enabled') ?? false;
    final presetId = p.getString('eq_preset') ?? 'flat';
    final raw = p.getStringList('eq_custom_gains');
    const five = [60.0, 230.0, 910.0, 3600.0, 14000.0];
    var id = kLegacyPresetIds[presetId] ?? presetId;
    var gains = <double>[];
    if (id == 'custom' && raw != null && raw.length == 5) {
      final g = [for (final s in raw) (double.tryParse(s) ?? 0).clamp(-12, 12).toDouble()];
      gains = resamplePoints([for (var i = 0; i < 5; i++) (five[i], g[i])], _caps.centers);
    } else if (presetById(id) == null) {
      id = 'flat';
    }
    return EqState(profiles: {
      'all': EqProfile(enabled: enabled, presetId: id, gains: gains),
    });
  }

  // Persistence, debounced: a drag is dozens of changes a second.
  Timer? _saveTimer;
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_save()));
  }

  Future<void> _save() async {
    try {
      final p = await _prefs();
      await p.setString(_stateKey, _state.encode());
    } catch (e) {
      if (kDebugMode) debugPrint('EqualizerService: save failed: $e');
    }
  }

  /// Writes now (tests; app going to the background).
  Future<void> flushSave() async {
    _saveTimer?.cancel();
    await _save();
  }

  // Pushing to the platform, coalesced and serialised.
  Timer? _pushTimer;
  bool _pushing = false;
  bool _pushAgain = false;
  EqSync? _lastSent;

  EqSync _desired() {
    final p = profile;
    if (!isEnabled || _sessions.isEmpty || !_caps.available) return EqSync.off;
    final ids = _sessions.values.toSet().toList()..sort();
    if (_bypass) {
      return EqSync(
          sessions: ids,
          levelsDb: List<double>.filled(_caps.bands.length, 0));
    }
    return EqSync(
      sessions: ids,
      levelsDb: effectiveGains,
      bass: _caps.bassBoost ? p.bassBoost : 0,
      virtualizer: _caps.virtualizer ? p.virtualizer : 0,
      loudnessDb: _caps.loudness ? p.loudnessDb : 0,
    );
  }

  void _schedulePush() {
    if (!_supported) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDelay, () => unawaited(_push()));
  }

  Future<void> _push() async {
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    _pushing = true;
    try {
      do {
        _pushAgain = false;
        final want = _desired();
        if (want == _lastSent) continue;
        final r = await _platform.sync(want);
        _lastSent = want;
        final healthy = want.isOff || r.ok;
        if (healthy != _engineOk) {
          _engineOk = healthy;
          notifyListeners();
        }
      } while (_pushAgain);
    } finally {
      _pushing = false;
    }
  }

  /// Pushes now (tests).
  Future<void> flushPush() async {
    _pushTimer?.cancel();
    await _push();
  }

  @visibleForTesting
  Future<void> resetForTest() async {
    _pushTimer?.cancel();
    _saveTimer?.cancel();
    _state = const EqState();
    _sessions.clear();
    _bypass = false;
    _lastSent = null;
    _engineOk = true;
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    _saveTimer?.cancel();
    _output?.removeListener(_onOutputChanged);
    super.dispose();
  }

  /// JSON of the persisted state (diagnostics).
  String debugState() => jsonEncode(jsonDecode(_state.encode()));
}

/// The headroom for a set of gains; a thin wrapper so the service reads clearly.
double eqHeadroom(List<double> gains, double preampDb) =>
    headroomDb(gains, preampDb);
