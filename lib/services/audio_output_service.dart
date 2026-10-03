import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One audio sink, as reported by Android's [AudioManager.getDevices].
///
/// The listing rules live natively (see MainActivity): telephony SCO,
/// earpiece, remote submix and recorder sinks are never offered, Bluetooth
/// entries collapse to the A2DP one, and the active row is a pure function of
/// the connected list so it cannot flicker mid-negotiation. This class is only
/// display data plus the labels for the nameless kinds.
class AudioOutputDevice {
  final int id;
  final String kind;
  final String name;
  final bool isActive;

  const AudioOutputDevice({
    required this.id,
    required this.kind,
    required this.name,
    required this.isActive,
  });

  factory AudioOutputDevice.fromMap(Map<String, dynamic> m) {
    return AudioOutputDevice(
      id: (m['id'] as int?) ?? 0,
      kind: (m['kind'] as String?) ?? 'other',
      name: (m['name'] as String?) ?? '',
      isActive: (m['isActive'] as bool?) ?? false,
    );
  }

  /// What the row - and the Now Playing label - actually shows. The speaker
  /// and wired outputs report the phone model as their product name, which is
  /// not what anybody calls the thing in their ears.
  String get displayName {
    if (name.isNotEmpty) return name;
    switch (kind) {
      case 'wired':
        return 'Wired headphones';
      case 'usb':
        return 'USB audio';
      case 'hdmi':
        return 'HDMI';
      case 'bluetooth':
        return 'Bluetooth';
      default:
        return 'This phone';
    }
  }
}

/// The phone's media output: which sinks exist, which one is active, and the
/// *device* media volume (STREAM_MUSIC) - not the player's internal gain.
///
/// Two halves with different owners. The route list is read-only display data;
/// an unprivileged app cannot move the system route, so tapping a row opens
/// system sound settings instead of pretending to switch. The volume half is
/// fully ours: the slider writes the stream index, and a broadcast keeps it
/// truthful when hardware buttons or another output change it underneath us.
class AudioOutputService extends ChangeNotifier {
  static const MethodChannel _methods =
      MethodChannel('mine_music/audio_output');
  static const EventChannel _events =
      EventChannel('mine_music/audio_output_events');

  List<AudioOutputDevice> outputs = const [];
  double volume = 1.0;
  int _max = 15;
  int _lastSentIndex = -1;
  StreamSubscription<dynamic>? _subscription;
  bool _ready = false;

  /// The sink audio is reaching, or null before the first read.
  AudioOutputDevice? get active =>
      outputs.firstWhereOrNull((d) => d.isActive);

  /// What the Now Playing row shows. Never blank: before the first read, and
  /// if the native side ever returns nothing, it says the phone.
  String get activeName => active?.displayName ?? 'This phone';

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    await refreshOutputs();
    await refreshVolume();
    _subscription = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final type = event['type'];
        if (type == 'volume') {
          _applyVolumeMap(event);
        } else if (type == 'routes') {
          unawaited(refreshOutputs());
          unawaited(refreshVolume());
        }
      },
      onError: (_) {},
    );
  }

  Future<void> refreshOutputs() async {
    try {
      final res = await _methods.invokeMethod<List<dynamic>>('getOutputs');
      if (res == null) return;
      outputs = res
          .whereType<Map>()
          .map((m) => AudioOutputDevice.fromMap(
              Map<String, dynamic>.from(m)))
          .toList();
      notifyListeners();
    } catch (_) {
      // A missing channel (tests, desktop) leaves the last known list.
    }
  }

  Future<void> refreshVolume() async {
    try {
      final res = await _methods.invokeMethod<Map<dynamic, dynamic>>(
        'getVolume',
      );
      if (res == null) return;
      _applyVolumeMap(Map<String, dynamic>.from(res));
    } catch (_) {}
  }

  void _applyVolumeMap(Map<dynamic, dynamic> m) {
    final max = (m['max'] as int?) ?? 0;
    final index = (m['volume'] as int?) ?? 0;
    if (max > 0) {
      _max = max;
      _lastSentIndex = index;
      volume = (index / max).clamp(0.0, 1.0);
      notifyListeners();
    }
  }

  /// Writes the *device* media volume. Optimistic: the slider moves now, and
  /// the broadcast echo re-confirms it a moment later.
  ///
  /// Pass `notify: false` while a finger is down. Every tick would otherwise
  /// rebuild whoever watches this (the whole Now Playing page) 60 times a
  /// second for a value only the thumb needs to see - that rebuild storm is
  /// what made the slider feel laggy. The widget commits (notifies) on release.
  /// Channel writes are deduped by integer index: a drag sweep crosses each
  /// step once, and ticks inside a step send nothing at all.
  Future<void> setDeviceVolume(double value, {bool notify = true}) async {
    volume = value.clamp(0.0, 1.0);
    if (notify) notifyListeners();
    final index = (volume * _max).round();
    if (index == _lastSentIndex) return;
    _lastSentIndex = index;
    try {
      await _methods.invokeMethod('setVolume', {'index': index});
    } catch (_) {}
  }

  Future<void> openSoundSettings() async {
    try {
      await _methods.invokeMethod('openSoundSettings');
    } catch (_) {}
  }

  /// Bluetooth settings: the direct path to connect/disconnect a headset.
  /// Used when tapping a Bluetooth row that is not active, instead of the
  /// generic sound page.
  Future<void> openBluetoothSettings() async {
    try {
      await _methods.invokeMethod('openBluetoothSettings');
    } catch (_) {}
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
