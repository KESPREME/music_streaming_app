// lib/services/session/session_snapshot.dart
//
// WHAT "WHERE I WAS" MEANS, as plain data.
//
// Split in two on purpose, because the two halves change at very different
// rates and cost very different amounts to write:
//
//   * [SessionCore]  - the track, the list it came from, the queue, the modes.
//     Tens of KB of JSON; rewritten only when one of those actually changes.
//   * the position   - one integer; rewritten every few seconds while playing.
//
// Pure Dart (no Flutter, no I/O) so the shape, the trimming and the tolerance
// for damaged data are all unit-testable.

import 'dart:convert';

import '../../models/track.dart';

/// The part of a session that is not the playhead.
class SessionCore {
  const SessionCore({
    required this.track,
    this.context = const [],
    this.order = const [],
    this.playlistId,
    this.queue = const [],
    this.shuffle = false,
    this.repeat = 0,
    this.durationMs = 0,
  });

  /// Bumped when the shape changes; an unknown version is ignored, not guessed at.
  static const int version = 1;

  /// How many tracks of the playing list are kept. A 2,000-song library played
  /// from the top must not become a 1 MB preference.
  static const int maxContext = 200;
  static const int maxQueue = 100;

  /// The track in the player (may be paused or stopped).
  final Track track;

  /// The list the track is being played from, in its original order.
  final List<Track> context;

  /// The order actually played when shuffle is on (ids). Empty when it is not.
  final List<String> order;
  final String? playlistId;

  /// "Up next" the listener added by hand.
  final List<Track> queue;
  final bool shuffle;

  /// `RepeatMode.index`.
  final int repeat;
  final int durationMs;

  /// A cheap fingerprint: two cores with the same signature serialise the same.
  String get signature =>
      '${track.id}|${context.length}|${context.isEmpty ? '' : context.first.id}|'
      '${order.length}|$playlistId|${queue.length}|'
      '${queue.isEmpty ? '' : queue.first.id}|$shuffle|$repeat';

  /// Keeps at most [maxContext] tracks of the list, windowed around the current
  /// one so "what plays next" survives, and drops [order] ids that fell out.
  SessionCore trimmed() {
    var ctx = context;
    if (ctx.length > maxContext) {
      final at = ctx.indexWhere((t) => t.id == track.id);
      final centre = at < 0 ? 0 : at;
      var start = centre - maxContext ~/ 4;
      if (start < 0) start = 0;
      var end = start + maxContext;
      if (end > ctx.length) {
        end = ctx.length;
        start = (end - maxContext).clamp(0, end);
      }
      ctx = ctx.sublist(start, end);
    }
    final keep = {for (final t in ctx) t.id};
    return SessionCore(
      track: track,
      context: ctx,
      order: order.where(keep.contains).toList(growable: false),
      playlistId: playlistId,
      queue: queue.length > maxQueue ? queue.sublist(0, maxQueue) : queue,
      shuffle: shuffle,
      repeat: repeat,
      durationMs: durationMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'track': track.toJson(),
        'context': [for (final t in context) t.toJson()],
        'order': order,
        'playlistId': playlistId,
        'queue': [for (final t in queue) t.toJson()],
        'shuffle': shuffle,
        'repeat': repeat,
        'durationMs': durationMs,
      };

  String encode() => jsonEncode(trimmed().toJson());

  /// Null when [raw] is not a readable session. Never throws: a damaged
  /// preference must cost the listener their place, not the app its start.
  static SessionCore? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['v'] != version) return null;
      Track? one(Object? j) => j is Map
          ? Track.fromJson(Map<String, dynamic>.from(j))
          : null;
      List<Track> many(Object? j) => j is List
          ? [
              for (final e in j)
                if (one(e) != null) one(e)!
            ]
          : const [];
      final track = one(json['track']);
      if (track == null || track.id.isEmpty) return null;
      return SessionCore(
        track: track,
        context: many(json['context']),
        order: json['order'] is List
            ? [for (final e in json['order'] as List) e.toString()]
            : const [],
        playlistId: json['playlistId'] as String?,
        queue: many(json['queue']),
        shuffle: json['shuffle'] == true,
        repeat: (json['repeat'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A restored session: the core plus the playhead.
class SessionSnapshot {
  const SessionSnapshot(this.core, {this.positionMs = 0});

  final SessionCore core;
  final int positionMs;

  Duration get position {
    final cap = core.durationMs > 0 ? core.durationMs : positionMs;
    return Duration(milliseconds: positionMs.clamp(0, cap < 0 ? 0 : cap));
  }

  /// Resuming a song 3 seconds from its start is just starting it, and
  /// resuming one 2 seconds from its end would be a flash of the wrong thing.
  /// Inside either margin the song restarts from the top.
  static const Duration edge = Duration(seconds: 5);

  Duration get resumeAt {
    final p = position;
    if (p < edge) return Duration.zero;
    if (core.durationMs > 0 &&
        Duration(milliseconds: core.durationMs) - p < edge) {
      return Duration.zero;
    }
    return p;
  }
}

/// UI state that is worth a cold start: where you were, not what you were doing.
class UiSession {
  const UiSession({this.tab = 0, this.libraryFilter = 'All', this.librarySort = 0});

  final int tab;
  final String libraryFilter;

  /// The Library sort's enum index.
  final int librarySort;

  UiSession copyWith({int? tab, String? libraryFilter, int? librarySort}) =>
      UiSession(
        tab: tab ?? this.tab,
        libraryFilter: libraryFilter ?? this.libraryFilter,
        librarySort: librarySort ?? this.librarySort,
      );

  Map<String, dynamic> toJson() =>
      {'tab': tab, 'filter': libraryFilter, 'sort': librarySort};

  static UiSession decode(String? raw) {
    if (raw == null || raw.isEmpty) return const UiSession();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return const UiSession();
      final tab = (j['tab'] as num?)?.toInt() ?? 0;
      return UiSession(
        // 0..2 are the tabs; anything else is data from some other build.
        tab: tab >= 0 && tab <= 2 ? tab : 0,
        libraryFilter: (j['filter'] as String?) ?? 'All',
        librarySort: (j['sort'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const UiSession();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is UiSession &&
      other.tab == tab &&
      other.libraryFilter == libraryFilter &&
      other.librarySort == librarySort;

  @override
  int get hashCode => Object.hash(tab, libraryFilter, librarySort);
}
