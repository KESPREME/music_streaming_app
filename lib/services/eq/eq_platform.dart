// lib/services/eq/eq_platform.dart
//
// The seam between the equalizer's logic and Android's audio effects.
//
// The native side (EqualizerChannel.java) is deliberately stateless from Dart's
// point of view: every call to [EqPlatform.sync] says what the whole world should
// look like - which audio sessions, which levels - and the host makes it so. A
// missed event can therefore never leave an effect attached to a dead session.
//
// Every call is guarded. The reason this whole layer exists is a device on which
// the effect cannot be created: that must read as "unavailable", never as a
// playback error.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'eq_models.dart';

/// One full description of the desired effect state.
@immutable
class EqSync {
  const EqSync({
    required this.sessions,
    required this.levelsDb,
    this.bass = 0,
    this.virtualizer = 0,
    this.loudnessDb = 0,
  });

  /// An empty sync: release everything.
  static const EqSync off =
      EqSync(sessions: [], levelsDb: [], bass: 0, virtualizer: 0, loudnessDb: 0);

  /// Android audio session ids to process (both players of a crossfade).
  final List<int> sessions;

  /// Level per device band, dB.
  final List<double> levelsDb;

  /// 0..1
  final double bass;

  /// 0..1
  final double virtualizer;

  /// 0..9 dB
  final double loudnessDb;

  bool get isOff => sessions.isEmpty;

  Map<String, Object?> toMap() => {
        'sessions': sessions,
        // Millibels at the boundary: that is the unit Android speaks.
        'levelsMb': [for (final l in levelsDb) (l * 100).round()],
        'bass': (bass.clamp(0, 1) * 1000).round(),
        'virt': (virtualizer.clamp(0, 1) * 1000).round(),
        'loudnessMb': (loudnessDb.clamp(0, 9) * 100).round(),
      };

  @override
  bool operator ==(Object other) =>
      other is EqSync &&
      listEquals(other.sessions, sessions) &&
      listEquals(other.levelsDb, levelsDb) &&
      other.bass == bass &&
      other.virtualizer == virtualizer &&
      other.loudnessDb == loudnessDb;

  @override
  int get hashCode => Object.hash(Object.hashAll(sessions),
      Object.hashAll(levelsDb), bass, virtualizer, loudnessDb);
}

/// What the host reported after a sync.
@immutable
class EqSyncResult {
  const EqSyncResult({this.ok = true, this.equalizer = true});

  /// At least one effect is now processing.
  final bool ok;
  final bool equalizer;

  static const EqSyncResult failed = EqSyncResult(ok: false, equalizer: false);
}

abstract class EqPlatform {
  Future<EqCapabilities> probe();
  Future<EqSyncResult> sync(EqSync s);
  Future<void> release();
}

class MethodChannelEqPlatform implements EqPlatform {
  MethodChannelEqPlatform([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('mine_music/equalizer');

  final MethodChannel _channel;

  @override
  Future<EqCapabilities> probe() async {
    try {
      final m = await _channel
          .invokeMapMethod<Object?, Object?>('probe')
          .timeout(const Duration(seconds: 4));
      if (m == null) return EqCapabilities.unavailable;
      return EqCapabilities.fromMap(m);
    } catch (e) {
      if (kDebugMode) debugPrint('EqPlatform.probe: $e');
      return EqCapabilities.unavailable;
    }
  }

  @override
  Future<EqSyncResult> sync(EqSync s) async {
    try {
      final m = await _channel
          .invokeMapMethod<Object?, Object?>('sync', s.toMap())
          .timeout(const Duration(seconds: 4));
      if (m == null) return EqSyncResult.failed;
      return EqSyncResult(
        ok: m['ok'] != false,
        equalizer: m['eq'] != false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('EqPlatform.sync: $e');
      return EqSyncResult.failed;
    }
  }

  @override
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {}
  }
}

/// An in-memory platform for tests and previews.
class FakeEqPlatform implements EqPlatform {
  FakeEqPlatform({this.capabilities = const EqCapabilities(
      available: true,
      bands: EqBand.typicalFive,
      minDb: -15,
      maxDb: 15,
      bassBoost: true,
      virtualizer: true,
      loudness: true,
    )});

  EqCapabilities capabilities;
  final List<EqSync> syncs = [];
  int releases = 0;
  EqSyncResult result = const EqSyncResult();

  EqSync? get last => syncs.isEmpty ? null : syncs.last;

  @override
  Future<EqCapabilities> probe() async => capabilities;

  @override
  Future<EqSyncResult> sync(EqSync s) async {
    syncs.add(s);
    return result;
  }

  @override
  Future<void> release() async => releases++;
}
