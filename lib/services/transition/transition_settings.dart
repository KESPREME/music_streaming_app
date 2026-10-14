// lib/services/transition/transition_settings.dart
//
// What the listener chose about how songs join.
//
// The names and the 1-12 second range follow Apple Music (Settings > Music >
// Song Transitions: Crossfade or AutoMix, a 1-12 second slider). The rest are
// options BitChord exposes that matter here: albums stay gapless, tempo changes
// are opt-in, the sleep timer fades instead of cutting, and skip-silence.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a transition is made.
enum TransitionStyle {
  /// A fixed-length fade, the same for every pair of songs.
  crossfade,

  /// The length and the join point are chosen per pair from analysis of both
  /// songs: dead air and fade-out tails are skipped, the incoming song is cued
  /// at its first audible moment, and (optionally) tempos are matched.
  automix,
}

class TransitionSettings extends ChangeNotifier {
  TransitionSettings({SharedPreferences? preferences}) : _prefs = preferences;

  /// The app-wide instance. Tests construct their own.
  static final TransitionSettings shared = TransitionSettings();

  // Preference keys: snake_case, like the other recent settings.
  static const String keyEnabled = 'transitions_enabled';
  static const String keyStyle = 'transitions_style';
  static const String keyCrossfadeSeconds = 'crossfade_seconds';
  static const String keyAlbums = 'transitions_crossfade_albums';
  static const String keyMatchTempo = 'transitions_match_tempo';
  static const String keySleepFade = 'transitions_sleep_fade';
  static const String keySkipSilence = 'skip_silence';
  static const String keyAnalyzeCellular = 'transitions_analyze_cellular';

  static const int minSeconds = 1;
  static const int maxSeconds = 12;
  static const int defaultSeconds = 6;

  SharedPreferences? _prefs;
  bool _loaded = false;
  bool get loaded => _loaded;

  bool _enabled = false;
  TransitionStyle _style = TransitionStyle.crossfade;
  int _crossfadeSeconds = defaultSeconds;
  bool _crossfadeAlbums = false;
  bool _matchTempo = false;
  bool _sleepFade = true;
  bool _skipSilence = false;
  bool _analyzeOnCellular = false;

  /// Master switch. Off by default, as in Apple Music: a listener who never
  /// opens this screen hears exactly what they always heard.
  bool get enabled => _enabled;

  TransitionStyle get style => _style;

  /// The crossfade length. In AutoMix it is the length used when analysis has
  /// nothing better to say (a song with a hard ending, or not yet analysed).
  int get crossfadeSeconds => _crossfadeSeconds;
  Duration get crossfade => Duration(seconds: _crossfadeSeconds);

  /// Whether consecutive tracks of one album are crossfaded. Off: they stay
  /// gapless, because live and concept albums are written to run into each
  /// other.
  bool get crossfadeAlbums => _crossfadeAlbums;

  /// AutoMix only: speed the incoming song by a few percent so its tempo
  /// matches the outgoing one's, and start both on a bar line. Beta - it is a
  /// judgement call on analysis, so it is off until the listener asks for it.
  bool get matchTempo => _matchTempo;

  /// Fade out instead of cutting when the sleep timer ends playback.
  bool get sleepFade => _sleepFade;

  /// Skip silent passages inside a song.
  bool get skipSilence => _skipSilence;

  /// AutoMix reads each upcoming song once to analyse it. On mobile data that
  /// is a few megabytes per song, so it waits for Wi-Fi unless allowed.
  bool get analyzeOnCellular => _analyzeOnCellular;

  /// Whether a transition may happen at all.
  bool get active => _enabled;

  bool get isAutomix => _enabled && _style == TransitionStyle.automix;

  Future<void> load() async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    _enabled = p.getBool(keyEnabled) ?? false;
    final style = p.getString(keyStyle);
    _style = TransitionStyle.values.firstWhere(
      (s) => s.name == style,
      orElse: () => TransitionStyle.crossfade,
    );
    _crossfadeSeconds = (p.getInt(keyCrossfadeSeconds) ?? defaultSeconds)
        .clamp(minSeconds, maxSeconds);
    _crossfadeAlbums = p.getBool(keyAlbums) ?? false;
    _matchTempo = p.getBool(keyMatchTempo) ?? false;
    _sleepFade = p.getBool(keySleepFade) ?? true;
    _skipSilence = p.getBool(keySkipSilence) ?? false;
    _analyzeOnCellular = p.getBool(keyAnalyzeCellular) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) =>
      _set(value, _enabled, (v) => _enabled = v, (p) => p.setBool(keyEnabled, value));

  Future<void> setStyle(TransitionStyle value) => _set(value, _style,
      (v) => _style = v, (p) => p.setString(keyStyle, value.name));

  Future<void> setCrossfadeSeconds(int value) {
    final v = value.clamp(minSeconds, maxSeconds);
    return _set(v, _crossfadeSeconds, (x) => _crossfadeSeconds = x,
        (p) => p.setInt(keyCrossfadeSeconds, v));
  }

  Future<void> setCrossfadeAlbums(bool value) => _set(value, _crossfadeAlbums,
      (v) => _crossfadeAlbums = v, (p) => p.setBool(keyAlbums, value));

  Future<void> setMatchTempo(bool value) => _set(value, _matchTempo,
      (v) => _matchTempo = v, (p) => p.setBool(keyMatchTempo, value));

  Future<void> setSleepFade(bool value) => _set(value, _sleepFade,
      (v) => _sleepFade = v, (p) => p.setBool(keySleepFade, value));

  Future<void> setSkipSilence(bool value) => _set(value, _skipSilence,
      (v) => _skipSilence = v, (p) => p.setBool(keySkipSilence, value));

  Future<void> setAnalyzeOnCellular(bool value) => _set(
      value,
      _analyzeOnCellular,
      (v) => _analyzeOnCellular = v,
      (p) => p.setBool(keyAnalyzeCellular, value));

  Future<void> _set<T>(
    T value,
    T current,
    void Function(T) assign,
    Future<bool> Function(SharedPreferences) persist,
  ) async {
    if (value == current) return;
    assign(value);
    notifyListeners();
    final p = _prefs ??= await SharedPreferences.getInstance();
    await persist(p);
  }

  /// A value that changes whenever anything that changes a PLAN changes. The
  /// engine caches plans against it.
  int get planVersion => Object.hash(_enabled, _style, _crossfadeSeconds,
      _crossfadeAlbums, _matchTempo);
}
