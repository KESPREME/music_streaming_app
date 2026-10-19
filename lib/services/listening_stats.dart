// lib/services/listening_stats.dart
//
// WHAT YOU LISTENED TO, AND FOR HOW LONG - measured, never estimated.
//
// One local log feeds every listening surface (the Library's Replay cards, the
// Replay screen, the story). It records PLAYS: one entry each time a track
// becomes current, carrying the wall-clock time audio was actually playing
// while it was. A session opens when the player reports playing and closes when
// it reports anything else or the track changes. Nothing is inferred from
// durations (a skipped song is seconds, not three minutes) and nothing ticks:
// no timer runs, so this costs nothing while music plays and cannot keep a
// widget test from settling.
//
// A play COUNTS as a play once it reaches [countedPlay] (30 s, the common
// industry threshold); shorter ones still add their minutes.
//
// Private by construction: the log lives in this device's preferences and is
// never sent anywhere.
//
// Known gap, stated rather than hidden: a session still open when the process is
// killed is lost, because it is only written when it closes.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// What the log remembers about a track: enough to draw it, nothing more.
@immutable
class ListenedTrack {
  const ListenedTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.artUrl,
    this.genre,
    this.source = 'youtube',
  });

  factory ListenedTrack.of(Track t) => ListenedTrack(
        id: t.id,
        title: t.trackName,
        artist: t.artistName,
        album: t.albumName,
        artUrl: t.albumArtUrl,
        genre: (t.genre?.trim().isEmpty ?? true) ? null : t.genre!.trim(),
        source: t.source,
      );

  final String id;
  final String title;
  final String artist;
  final String album;
  final String artUrl;
  final String? genre;
  final String source;

  Track toTrack() => Track(
        id: id,
        trackName: title,
        artistName: artist,
        albumName: album,
        albumArtUrl: artUrl,
        previewUrl: '',
        genre: genre,
        source: source,
      );

  Map<String, dynamic> toJson() => {
        't': title,
        'a': artist,
        'l': album,
        'u': artUrl,
        if (genre != null) 'g': genre,
        if (source != 'youtube') 's': source,
      };

  static ListenedTrack fromJson(String id, Map<String, dynamic> j) =>
      ListenedTrack(
        id: id,
        title: j['t'] as String? ?? '',
        artist: j['a'] as String? ?? '',
        album: j['l'] as String? ?? '',
        artUrl: j['u'] as String? ?? '',
        genre: j['g'] as String?,
        source: j['s'] as String? ?? 'youtube',
      );
}

/// One play: when it started, how long audio played, and what (null = time the
/// player reported playing with no track known, which still counts as minutes).
@immutable
class PlayRecord {
  const PlayRecord({required this.startMs, required this.ms, this.trackId});

  final int startMs;
  final int ms;
  final String? trackId;

  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startMs);

  PlayRecord withMs(int value) =>
      PlayRecord(startMs: startMs, ms: value, trackId: trackId);
}

class ListeningStats extends ChangeNotifier {
  ListeningStats({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// The original minutes-only total (`{"y": year, "ms": total}`). Read once and
  /// kept as untracked minutes for its year; never written again.
  static const String storageKey = 'listening_stats_v1';

  /// The play log.
  static const String logKey = 'listening_log_v1';

  /// A single session longer than this is a clock jump (time zone change, a
  /// device clock corrected by the network), not listening. It is capped.
  static const Duration maxSession = Duration(hours: 12);

  /// How long a play must last to count as a play.
  static const Duration countedPlay = Duration(seconds: 30);

  /// Oldest plays are dropped beyond this, which bounds the stored size
  /// (~40 bytes a play) at well under a megabyte - years of listening.
  static const int maxRecords = 20000;

  final DateTime Function() _clock;

  final List<PlayRecord> _records = [];
  final Map<String, ListenedTrack> _tracks = {};

  /// Minutes known only as a total, per year (the pre-log counter).
  final Map<int, int> _untrackedMs = {};

  ListenedTrack? _current;
  DateTime? _openedAt;

  /// Index in [_records] of the play the current track is adding to, or null
  /// when the current track has not played yet.
  int? _openRecord;

  bool _loaded = false;
  bool _loading = false;
  bool get isLoaded => _loaded;

  /// Every play, oldest first. Read-only.
  List<PlayRecord> get records => List.unmodifiable(_records);

  /// Metadata for every track in [records].
  Map<String, ListenedTrack> get tracks => Map.unmodifiable(_tracks);

  /// Counted plays (>= [countedPlay]) per track id, over the whole log.
  Map<String, int> playCounts() {
    final counted = countedPlay.inMilliseconds;
    final out = <String, int>{};
    for (final r in _records) {
      final id = r.trackId;
      if (id == null || r.ms < counted) continue;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  /// Minutes known only as a yearly total.
  Map<int, int> get untrackedMs => Map.unmodifiable(_untrackedMs);

  /// The open session's elapsed time, for totals shown while music plays.
  int get openSessionMs {
    final open = _openedAt;
    return open == null ? 0 : _sessionMs(open, _clock());
  }

  /// When the open session started, if one is open.
  DateTime? get openedAt => _openedAt;

  /// The track the open session belongs to.
  ListenedTrack? get currentTrack => _current;

  /// Milliseconds played this calendar year, the open session included.
  int get msThisYear {
    final now = _clock();
    var ms = _untrackedMs[now.year] ?? 0;
    for (final r in _records) {
      if (r.start.year == now.year) ms += r.ms;
    }
    final open = _openedAt;
    if (open != null) ms += _sessionMs(open, now);
    return ms;
  }

  int get minutesThisYear => msThisYear ~/ Duration.millisecondsPerMinute;

  // ── Feeding ────────────────────────────────────────────────────────────

  /// Feed from the player's playing / not-playing transitions.
  void onPlayingChanged(bool playing) {
    final now = _clock();
    if (playing) {
      _openedAt ??= now;
      return;
    }
    if (_closeSession(now)) _changed();
  }

  /// Feed whenever the current track changes. The time played so far belongs
  /// to the outgoing track; a new play starts for the incoming one.
  void onTrackChanged(Track? track) {
    final next = track == null ? null : ListenedTrack.of(track);
    if (next?.id == _current?.id) {
      // Same track, possibly with better metadata (enrichment). Keep the newer.
      if (next != null) {
        _current = next;
        if (_tracks.containsKey(next.id)) _tracks[next.id] = next;
      }
      return;
    }
    final now = _clock();
    final wasPlaying = _openedAt != null;
    final wrote = _closeSession(now);
    _current = next;
    _openRecord = null;
    if (wasPlaying) _openedAt = now;
    if (wrote) _changed();
  }

  /// Closes the open session into the current play. True when anything was
  /// recorded.
  bool _closeSession(DateTime now) {
    final open = _openedAt;
    if (open == null) return false;
    _openedAt = null;
    var from = open;
    var wrote = false;

    // A session that began last year: its last-year part is last year's play,
    // and this year's part starts a new one at midnight.
    final yearStart = DateTime(now.year);
    if (from.isBefore(yearStart)) {
      wrote |= _add(from, yearStart);
      _openRecord = null;
      from = yearStart;
    }
    wrote |= _add(from, now);
    return wrote;
  }

  bool _add(DateTime from, DateTime to) {
    var ms = to.difference(from).inMilliseconds;
    if (ms <= 0) return false;
    if (ms > maxSession.inMilliseconds) ms = maxSession.inMilliseconds;

    final track = _current;
    if (track != null) _tracks[track.id] = track;
    final at = _openRecord;
    if (at != null && at < _records.length) {
      _records[at] = _records[at].withMs(_records[at].ms + ms);
    } else {
      _records.add(PlayRecord(
        startMs: from.millisecondsSinceEpoch,
        ms: ms,
        trackId: track?.id,
      ));
      _openRecord = _records.length - 1;
    }
    return true;
  }

  void _changed() {
    _trim();
    notifyListeners();
    _persist();
  }

  void _trim() {
    final excess = _records.length - maxRecords;
    if (excess <= 0) return;
    _records.removeRange(0, excess);
    final open = _openRecord;
    _openRecord = open == null || open < excess ? null : open - excess;
    final live = {for (final r in _records) r.trackId};
    _tracks.removeWhere((id, _) => !live.contains(id) && id != _current?.id);
  }

  int _sessionMs(DateTime open, DateTime now) {
    final yearStart = DateTime(now.year);
    final from = open.isBefore(yearStart) ? yearStart : open;
    final ms = now.difference(from).inMilliseconds;
    if (ms <= 0) return 0;
    return ms > maxSession.inMilliseconds ? maxSession.inMilliseconds : ms;
  }

  // ── Storage ────────────────────────────────────────────────────────────

  /// Restores the log. Safe to call while a session is open or after plays were
  /// recorded: what was counted before it finished is kept, not overwritten.
  Future<void> load() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      final legacy = prefs.getString(storageKey);
      if (legacy != null) {
        try {
          final json = jsonDecode(legacy);
          if (json is Map<String, dynamic> &&
              json['y'] is int &&
              json['ms'] is int &&
              (json['ms'] as int) >= 0) {
            final y = json['y'] as int;
            _untrackedMs[y] = (_untrackedMs[y] ?? 0) + (json['ms'] as int);
          }
        } catch (_) {}
        // Folded into the log below; the old key is not read twice.
        await prefs.remove(storageKey);
      }

      final raw = prefs.getString(logKey);
      if (raw != null) {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic> && json['v'] == 1) {
          final tracks = json['tracks'];
          if (tracks is Map<String, dynamic>) {
            tracks.forEach((id, value) {
              if (value is Map<String, dynamic>) {
                _tracks.putIfAbsent(id, () => ListenedTrack.fromJson(id, value));
              }
            });
          }
          final untracked = json['untracked'];
          if (untracked is Map<String, dynamic>) {
            untracked.forEach((y, ms) {
              final year = int.tryParse(y);
              if (year != null && ms is int && ms >= 0) {
                _untrackedMs[year] = (_untrackedMs[year] ?? 0) + ms;
              }
            });
          }
          final plays = json['plays'];
          if (plays is List) {
            final restored = <PlayRecord>[];
            for (final p in plays) {
              if (p is List && p.length >= 2 && p[0] is int && p[1] is int) {
                final id = p.length > 2 ? p[2] as String? : null;
                restored.add(PlayRecord(
                  startMs: (p[0] as int) * 1000,
                  ms: p[1] as int,
                  trackId: id,
                ));
              }
            }
            // Restored plays are older than anything recorded this session.
            _records.insertAll(0, restored);
            final open = _openRecord;
            if (open != null) _openRecord = open + restored.length;
          }
        }
      }
      if (legacy != null) _dirtyBeforeLoad = true;
    } catch (e) {
      debugPrint('ListeningStats: load failed: $e');
    }
    _loaded = true;
    if (_dirtyBeforeLoad) {
      _dirtyBeforeLoad = false;
      _persist();
    }
    notifyListeners();
  }

  /// Something changed before the stored log was read: write once after it is.
  bool _dirtyBeforeLoad = false;

  Future<void> _persist() async {
    // Never write before the stored log has been read: the write would replace
    // years of plays with this session's, and the read would then count this
    // session twice.
    if (!_loaded) {
      _dirtyBeforeLoad = true;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final used = {for (final r in _records) r.trackId}..remove(null);
      await prefs.setString(
        logKey,
        jsonEncode({
          'v': 1,
          'tracks': {
            for (final id in used)
              if (_tracks[id] != null) id: _tracks[id]!.toJson(),
          },
          'untracked': {
            for (final e in _untrackedMs.entries) '${e.key}': e.value,
          },
          'plays': [
            for (final r in _records)
              [
                r.startMs ~/ 1000,
                r.ms,
                if (r.trackId != null) r.trackId,
              ],
          ],
        }),
      );
    } catch (e) {
      debugPrint('ListeningStats: save failed: $e');
    }
  }

  /// Forget everything (Replay > Clear listening history).
  Future<void> clear() async {
    _records.clear();
    _tracks.clear();
    _untrackedMs.clear();
    _openRecord = null;
    if (_openedAt != null) _openedAt = _clock();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(logKey);
      await prefs.remove(storageKey);
    } catch (_) {}
  }
}
