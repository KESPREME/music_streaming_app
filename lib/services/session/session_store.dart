// lib/services/session/session_store.dart
//
// Where a session lives between launches, and the thing that keeps it current.
//
// DISABLED BY DEFAULT. `SessionStore.instance` does nothing until `main()` calls
// [enable]. That is what keeps the ~2,400 existing tests, and any MusicProvider
// built in a widget test, from writing preferences or leaving timers behind;
// a test that wants the behaviour builds its own store.
//
// Everything here swallows its own errors. A failed write costs the listener
// their place; it must never cost them the song that is playing.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_snapshot.dart';

class SessionStore {
  SessionStore({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  static final SessionStore instance = SessionStore();

  static const _coreKey = 'session_v1_core';
  static const _posKey = 'session_v1_pos';
  static const _uiKey = 'session_v1_ui';
  static const _restoreKey = 'session_restore_enabled';

  final Future<SharedPreferences> Function() _prefs;

  bool _enabled = false;
  bool get enabled => _enabled;

  /// Turns persistence on (the app does; tests do not).
  void enable() => _enabled = true;

  bool _restoreEnabled = true;

  /// "Remember what I was playing" (Settings > Playback). On by default.
  bool get restoreEnabled => _restoreEnabled;

  UiSession _ui = const UiSession();

  /// The saved UI session, valid after [preload]. Synchronous on purpose: the
  /// shell reads it in `initState`, before the first frame.
  UiSession get ui => _ui;

  /// Reads the small things the first frame needs.
  Future<void> preload() async {
    try {
      final p = await _prefs();
      _restoreEnabled = p.getBool(_restoreKey) ?? true;
      _ui = UiSession.decode(p.getString(_uiKey));
    } catch (e) {
      if (kDebugMode) debugPrint('SessionStore.preload: $e');
    }
  }

  Future<SessionSnapshot?> loadPlayback() async {
    if (!_enabled || !_restoreEnabled) return null;
    try {
      final p = await _prefs();
      final core = SessionCore.decode(p.getString(_coreKey));
      if (core == null) return null;
      return SessionSnapshot(core, positionMs: p.getInt(_posKey) ?? 0);
    } catch (e) {
      if (kDebugMode) debugPrint('SessionStore.loadPlayback: $e');
      return null;
    }
  }

  String? _lastCore;

  Future<void> saveCore(SessionCore core) async {
    if (!_enabled || !_restoreEnabled) return;
    try {
      final encoded = core.encode();
      if (encoded == _lastCore) return;
      _lastCore = encoded;
      final p = await _prefs();
      await p.setString(_coreKey, encoded);
    } catch (e) {
      _lastCore = null;
      if (kDebugMode) debugPrint('SessionStore.saveCore: $e');
    }
  }

  Future<void> savePosition(int ms) async {
    if (!_enabled || !_restoreEnabled) return;
    try {
      final p = await _prefs();
      await p.setInt(_posKey, ms < 0 ? 0 : ms);
    } catch (e) {
      if (kDebugMode) debugPrint('SessionStore.savePosition: $e');
    }
  }

  Future<void> clearPlayback() async {
    _lastCore = null;
    try {
      final p = await _prefs();
      await p.remove(_coreKey);
      await p.remove(_posKey);
    } catch (e) {
      if (kDebugMode) debugPrint('SessionStore.clearPlayback: $e');
    }
  }

  Future<void> setRestoreEnabled(bool value) async {
    _restoreEnabled = value;
    try {
      final p = await _prefs();
      await p.setBool(_restoreKey, value);
    } catch (e) {
      if (kDebugMode) debugPrint('SessionStore.setRestoreEnabled: $e');
    }
    if (!value) await clearPlayback();
  }

  Future<void> saveUi(UiSession ui) async {
    if (ui == _ui) return;
    _ui = ui;
    if (!_enabled) return;
    try {
      final p = await _prefs();
      await p.setString(_uiKey, jsonEncode(ui.toJson()));
    } catch (e) {
      if (kDebugMode) debugPrint('SessionStore.saveUi: $e');
    }
  }

}

/// Decides WHEN to write. The provider calls [note] after every change it
/// announces; the recorder keeps only the changes that matter.
///
///   * a different track / list / queue / mode  -> write the core, 1.5 s later
///     (a burst of skips is one write);
///   * playing                                  -> write the playhead every 5 s;
///   * pause, background, detach                -> write everything now.
class SessionRecorder {
  SessionRecorder({
    required this.store,
    required this.capture,
    required this.positionMs,
    this.debounce = const Duration(milliseconds: 1500),
    this.tick = const Duration(seconds: 5),
  });

  final SessionStore store;

  /// The current core, or null when nothing is loaded.
  final SessionCore? Function() capture;
  final int Function() positionMs;
  final Duration debounce;
  final Duration tick;

  String? _lastSignature;
  Timer? _debounceTimer;
  Timer? _tickTimer;
  bool _playing = false;
  bool _disposed = false;

  void note({required bool playing}) {
    if (_disposed || !store.enabled) return;
    if (playing != _playing) {
      _playing = playing;
      if (playing) {
        _tickTimer ??= Timer.periodic(tick, (_) => _writePosition());
      } else {
        _tickTimer?.cancel();
        _tickTimer = null;
        // Paused: the playhead is final until the listener moves it.
        unawaited(flush());
      }
    }
    final core = capture();
    final signature = core?.signature;
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(flush()));
  }

  Future<void> flush() async {
    if (_disposed || !store.enabled) return;
    _debounceTimer?.cancel();
    final core = capture();
    if (core == null) {
      await store.clearPlayback();
      return;
    }
    await store.saveCore(core);
    await store.savePosition(positionMs());
  }

  void _writePosition() {
    if (_disposed || capture() == null) return;
    unawaited(store.savePosition(positionMs()));
  }

  /// Forget the session now (sign-out, "close player").
  Future<void> clear() async {
    _debounceTimer?.cancel();
    _lastSignature = null;
    await store.clearPlayback();
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _tickTimer?.cancel();
  }
}
