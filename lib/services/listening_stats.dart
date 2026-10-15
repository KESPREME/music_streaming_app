// lib/services/listening_stats.dart
//
// HOW LONG YOU LISTENED THIS YEAR - measured, never estimated.
//
// The Library's listening card shows one number, so that number has to be true.
// It is wall-clock time with audio actually playing: a session opens when the
// player reports playing and closes when it reports anything else. Nothing is
// inferred from track durations or play counts (a skipped song is seconds, not
// three minutes), and nothing ticks: no timer runs, so this costs nothing while
// music plays and cannot keep a widget test from settling.
//
// Known gap, stated rather than hidden: a session still open when the process is
// killed is lost, because it is only written when it closes.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ListeningStats extends ChangeNotifier {
  ListeningStats({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const String storageKey = 'listening_stats_v1';

  /// A single session longer than this is a clock jump (time zone change, a
  /// device clock corrected by the network), not listening. It is capped.
  static const Duration maxSession = Duration(hours: 12);

  final DateTime Function() _clock;

  int _year = 0;
  int _storedMs = 0;
  DateTime? _openedAt;
  bool _loaded = false;

  /// Milliseconds played this calendar year, the open session included.
  int get msThisYear {
    final now = _clock();
    var ms = _year == now.year ? _storedMs : 0;
    final open = _openedAt;
    if (open != null) ms += _sessionMs(open, now);
    return ms;
  }

  int get minutesThisYear => msThisYear ~/ Duration.millisecondsPerMinute;

  bool get isLoaded => _loaded;

  /// Restores the stored total. Safe to call while a session is already open:
  /// what was counted before it finished is added, not overwritten.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null) {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) {
          final year = json['y'];
          final ms = json['ms'];
          if (year is int && ms is int && year == _clock().year && ms >= 0) {
            if (_year != year) _storedMs = 0;
            _year = year;
            _storedMs += ms;
          }
        }
      }
    } catch (e) {
      debugPrint('ListeningStats: load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Feed from the player's playing / not-playing transitions.
  void onPlayingChanged(bool playing) {
    final now = _clock();
    if (playing) {
      _openedAt ??= now;
      return;
    }
    final open = _openedAt;
    if (open == null) return;
    _openedAt = null;
    final ms = _sessionMs(open, now);
    if (ms <= 0) return;
    if (_year != now.year) {
      _year = now.year;
      _storedMs = 0;
    }
    _storedMs += ms;
    notifyListeners();
    _persist();
  }

  /// The part of a session that falls in [now]'s year, capped.
  int _sessionMs(DateTime open, DateTime now) {
    final yearStart = DateTime(now.year);
    final from = open.isBefore(yearStart) ? yearStart : open;
    final ms = now.difference(from).inMilliseconds;
    if (ms <= 0) return 0;
    return ms > maxSession.inMilliseconds ? maxSession.inMilliseconds : ms;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          storageKey, jsonEncode({'y': _year, 'ms': _storedMs}));
    } catch (e) {
      debugPrint('ListeningStats: save failed: $e');
    }
  }
}
