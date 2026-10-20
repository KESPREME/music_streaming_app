// lib/services/eq/eq_models.dart
//
// The equalizer's vocabulary: what the phone's audio system can do
// ([EqCapabilities]), and what the listener asked for ([EqProfile]).
//
// Pure Dart. The numbers are in dB everywhere in this layer; millibels exist
// only at the platform boundary.

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One band of the device's equalizer.
@immutable
class EqBand {
  const EqBand({
    required this.centerHz,
    required this.lowHz,
    required this.highHz,
  });

  final double centerHz;
  final double lowHz;
  final double highHz;

  /// A typical 5-band layout, used only to draw an honest placeholder when the
  /// device reports nothing (never to claim the effect works).
  static const List<EqBand> typicalFive = [
    EqBand(centerHz: 60, lowHz: 20, highHz: 120),
    EqBand(centerHz: 230, lowHz: 120, highHz: 460),
    EqBand(centerHz: 910, lowHz: 460, highHz: 1800),
    EqBand(centerHz: 3600, lowHz: 1800, highHz: 7000),
    EqBand(centerHz: 14000, lowHz: 7000, highHz: 20000),
  ];

  static EqBand fromMap(Map<Object?, Object?> m) => EqBand(
        centerHz: (m['centerHz'] as num?)?.toDouble() ?? 1000,
        lowHz: (m['lowHz'] as num?)?.toDouble() ?? 20,
        highHz: (m['highHz'] as num?)?.toDouble() ?? 20000,
      );

  @override
  bool operator ==(Object other) =>
      other is EqBand &&
      other.centerHz == centerHz &&
      other.lowHz == lowHz &&
      other.highHz == highHz;

  @override
  int get hashCode => Object.hash(centerHz, lowHz, highHz);
}

/// What this phone's audio system can actually do, as the platform reported it.
@immutable
class EqCapabilities {
  const EqCapabilities({
    required this.available,
    this.bands = const [],
    this.minDb = -12,
    this.maxDb = 12,
    this.bassBoost = false,
    this.virtualizer = false,
    this.loudness = false,
    this.engine = 'Android audio effects',
  });

  /// Nothing reachable: not Android, or the device has no equalizer effect.
  static const EqCapabilities unavailable = EqCapabilities(available: false);

  final bool available;
  final List<EqBand> bands;
  final double minDb;
  final double maxDb;
  final bool bassBoost;
  final bool virtualizer;
  final bool loudness;
  final String engine;

  int get bandCount => bands.length;

  /// Bands to draw: the device's, or a typical five when the device has none.
  List<EqBand> get displayBands => bands.isEmpty ? EqBand.typicalFive : bands;

  List<double> get centers => [for (final b in displayBands) b.centerHz];

  /// "Android audio effects · 5 bands · ±15 dB".
  String get summary {
    if (!available) return 'Not available on this device';
    final range = maxDb.abs() == minDb.abs()
        ? '±${maxDb.abs().toStringAsFixed(0)} dB'
        : '${minDb.toStringAsFixed(0)} to +${maxDb.toStringAsFixed(0)} dB';
    return '$engine · ${bands.length} bands · $range';
  }

  static EqCapabilities fromMap(Map<Object?, Object?> m) {
    final bands = <EqBand>[
      for (final b in (m['bands'] as List?) ?? const [])
        if (b is Map) EqBand.fromMap(b)
    ];
    return EqCapabilities(
      available: m['available'] == true && bands.isNotEmpty,
      bands: bands,
      minDb: (m['minDb'] as num?)?.toDouble() ?? -12,
      maxDb: (m['maxDb'] as num?)?.toDouble() ?? 12,
      bassBoost: m['bassBoost'] == true,
      virtualizer: m['virtualizer'] == true,
      loudness: m['loudness'] == true,
      engine: (m['engine'] as String?) ?? 'Android audio effects',
    );
  }
}

/// Everything the listener can set for one listening situation.
@immutable
class EqProfile {
  const EqProfile({
    this.enabled = false,
    this.presetId = 'flat',
    this.gains = const [],
    this.preampDb = 0,
    this.autoHeadroom = true,
    this.loudnessDb = 0,
    this.bassBoost = 0,
    this.virtualizer = 0,
  });

  final bool enabled;

  /// `flat`, a built-in id, `custom`, or `user:<id>`.
  final String presetId;

  /// Per-band gain in dB, one per DEVICE band (empty until bands are known).
  final List<double> gains;

  /// Pre-amplifier, -12..+12 dB.
  final double preampDb;

  /// Lower everything by the biggest boost so a boosted band cannot clip.
  final bool autoHeadroom;

  /// Loudness enhancer target gain, 0..9 dB.
  final double loudnessDb;

  /// Bass boost strength, 0..1.
  final double bassBoost;

  /// Spatial widening strength, 0..1.
  final double virtualizer;

  static const double maxPreamp = 12;
  static const double maxLoudness = 9;

  bool get isCustom => presetId == 'custom';
  bool get isUser => presetId.startsWith('user:');

  EqProfile copyWith({
    bool? enabled,
    String? presetId,
    List<double>? gains,
    double? preampDb,
    bool? autoHeadroom,
    double? loudnessDb,
    double? bassBoost,
    double? virtualizer,
  }) =>
      EqProfile(
        enabled: enabled ?? this.enabled,
        presetId: presetId ?? this.presetId,
        gains: gains ?? this.gains,
        preampDb: preampDb ?? this.preampDb,
        autoHeadroom: autoHeadroom ?? this.autoHeadroom,
        loudnessDb: loudnessDb ?? this.loudnessDb,
        bassBoost: bassBoost ?? this.bassBoost,
        virtualizer: virtualizer ?? this.virtualizer,
      );

  /// Whether anything other than "on" differs from a neutral profile.
  bool get isNeutral =>
      gains.every((g) => g == 0) &&
      preampDb == 0 &&
      loudnessDb == 0 &&
      bassBoost == 0 &&
      virtualizer == 0;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'preset': presetId,
        'gains': gains,
        'preamp': preampDb,
        'headroom': autoHeadroom,
        'loudness': loudnessDb,
        'bass': bassBoost,
        'virt': virtualizer,
      };

  static EqProfile fromJson(Object? raw) {
    if (raw is! Map) return const EqProfile();
    double d(Object? v, double lo, double hi, double fallback) {
      final n = v is num ? v.toDouble() : fallback;
      if (n.isNaN || n.isInfinite) return fallback;
      return n.clamp(lo, hi).toDouble();
    }

    return EqProfile(
      enabled: raw['enabled'] == true,
      presetId: (raw['preset'] as String?) ?? 'flat',
      gains: [
        for (final g in (raw['gains'] as List?) ?? const [])
          d(g, -24, 24, 0),
      ],
      preampDb: d(raw['preamp'], -maxPreamp, maxPreamp, 0),
      autoHeadroom: raw['headroom'] != false,
      loudnessDb: d(raw['loudness'], 0, maxLoudness, 0),
      bassBoost: d(raw['bass'], 0, 1, 0),
      virtualizer: d(raw['virt'], 0, 1, 0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EqProfile &&
      other.enabled == enabled &&
      other.presetId == presetId &&
      listEquals(other.gains, gains) &&
      other.preampDb == preampDb &&
      other.autoHeadroom == autoHeadroom &&
      other.loudnessDb == loudnessDb &&
      other.bassBoost == bassBoost &&
      other.virtualizer == virtualizer;

  @override
  int get hashCode => Object.hash(enabled, presetId, Object.hashAll(gains),
      preampDb, autoHeadroom, loudnessDb, bassBoost, virtualizer);
}

/// A preset the listener saved: control points, so it fits any band layout.
@immutable
class UserEqPreset {
  const UserEqPreset({required this.id, required this.name, required this.points});

  final String id;
  final String name;

  /// (Hz, dB) pairs, ascending by frequency.
  final List<(double, double)> points;

  String get presetId => 'user:$id';

  UserEqPreset rename(String name) =>
      UserEqPreset(id: id, name: name, points: points);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'points': [
          for (final p in points) [p.$1, p.$2]
        ],
      };

  static UserEqPreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || name is! String || id.isEmpty) return null;
    final pts = <(double, double)>[];
    for (final p in (raw['points'] as List?) ?? const []) {
      if (p is List && p.length == 2 && p[0] is num && p[1] is num) {
        pts.add(((p[0] as num).toDouble(), (p[1] as num).toDouble()));
      }
    }
    if (pts.length < 2) return null;
    pts.sort((a, b) => a.$1.compareTo(b.$1));
    return UserEqPreset(id: id, name: name, points: pts);
  }
}

/// All persisted equalizer state.
@immutable
class EqState {
  const EqState({
    this.perOutput = false,
    this.profiles = const {},
    this.userPresets = const [],
  });

  static const int version = 2;

  /// Keep separate settings for speaker / wired / Bluetooth.
  final bool perOutput;

  /// `all`, and (when [perOutput]) `speaker`, `wired`, `bluetooth`.
  final Map<String, EqProfile> profiles;
  final List<UserEqPreset> userPresets;

  EqProfile profile(String key) =>
      profiles[key] ?? profiles['all'] ?? const EqProfile();

  EqState withProfile(String key, EqProfile p) => EqState(
        perOutput: perOutput,
        profiles: {...profiles, key: p},
        userPresets: userPresets,
      );

  EqState copyWith({
    bool? perOutput,
    Map<String, EqProfile>? profiles,
    List<UserEqPreset>? userPresets,
  }) =>
      EqState(
        perOutput: perOutput ?? this.perOutput,
        profiles: profiles ?? this.profiles,
        userPresets: userPresets ?? this.userPresets,
      );

  String encode() => jsonEncode({
        'v': version,
        'perOutput': perOutput,
        'profiles': {for (final e in profiles.entries) e.key: e.value.toJson()},
        'userPresets': [for (final p in userPresets) p.toJson()],
      });

  static EqState? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['v'] != version) return null;
      final profiles = <String, EqProfile>{};
      final pj = j['profiles'];
      if (pj is Map) {
        for (final e in pj.entries) {
          profiles[e.key.toString()] = EqProfile.fromJson(e.value);
        }
      }
      return EqState(
        perOutput: j['perOutput'] == true,
        profiles: profiles,
        userPresets: [
          for (final p in (j['userPresets'] as List?) ?? const [])
            if (UserEqPreset.fromJson(p) != null) UserEqPreset.fromJson(p)!
        ],
      );
    } catch (_) {
      return null;
    }
  }
}
