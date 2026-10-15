// lib/services/replay/replay_summary.dart
//
// REPLAY: your listening, summarised from the local play log (ListeningStats).
//
// Pure: plays in, a summary out, so every number on the Replay surfaces is a
// test and none is a property of a widget. Rules, stated once:
//
//   * A period is this month, this calendar year, or all time, by the play's
//     start time in local time.
//   * Minutes are every millisecond audio played. Plays are only plays that
//     reached ListeningStats.countedPlay - a skip adds minutes, not a play.
//   * Rankings are by plays, then minutes, then name (so ties are stable).
//   * An artist credit "A & B", "A, B", "A feat. B", "A x B" credits each of
//     them: a duet is a play of both artists.
//   * Albums are named albums only; a track whose album is its own title (a
//     single) or empty is not an album.
//   * Genres appear only when the source said so (Track.genre). Nothing is
//     guessed from an artist name.

import '../../models/track.dart';
import '../listening_stats.dart';

enum ReplayPeriod {
  month('This month'),
  year('This year'),
  allTime('All time');

  const ReplayPeriod(this.label);
  final String label;
}

/// One ranked row: a song, artist, album or genre.
class ReplayEntry {
  ReplayEntry({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.artUrl,
  });

  final String key;
  final String title;

  /// Artist for songs and albums; empty for artists and genres.
  final String subtitle;
  final String artUrl;

  int plays = 0;
  int ms = 0;

  /// For songs: a playable track.
  Track? track;

  /// Most-played track id inside this entry (choose the art from it).
  final Map<String, int> _trackMs = {};
}

class ReplaySummary {
  ReplaySummary._({
    required this.period,
    required this.label,
    required this.totalMs,
    required this.plays,
    required this.topSongs,
    required this.topArtists,
    required this.topAlbums,
    required this.topGenres,
    required this.distinctSongs,
    required this.distinctArtists,
    required this.distinctAlbums,
    required this.peakHour,
    required this.biggestDay,
    required this.biggestDayMs,
    required this.memberSince,
  });

  final ReplayPeriod period;

  /// "October 2026", "2026", "All time".
  final String label;
  final int totalMs;
  final int plays;
  final List<ReplayEntry> topSongs;
  final List<ReplayEntry> topArtists;
  final List<ReplayEntry> topAlbums;
  final List<ReplayEntry> topGenres;
  final int distinctSongs;
  final int distinctArtists;
  final int distinctAlbums;

  /// Hour of day (0-23) with the most listening, when there is any.
  final int? peakHour;

  /// The calendar day with the most listening, and how much.
  final DateTime? biggestDay;
  final int biggestDayMs;

  /// The first play ever (not just in this period).
  final DateTime? memberSince;

  int get minutes => totalMs ~/ Duration.millisecondsPerMinute;
  bool get isEmpty => totalMs < Duration.millisecondsPerMinute && plays == 0;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  static String monthName(int month) => _monthNames[month - 1];

  /// Splits an artist credit into the artists it names.
  static List<String> splitArtists(String credit) {
    final parts = credit
        .split(RegExp(r'\s*(?:,|&|\bfeat\.?|\bft\.?|\bfeaturing\b|\s+x\s+)\s*',
            caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? const [] : parts;
  }

  static bool _inPeriod(DateTime t, ReplayPeriod p, DateTime now) =>
      switch (p) {
        ReplayPeriod.month => t.year == now.year && t.month == now.month,
        ReplayPeriod.year => t.year == now.year,
        ReplayPeriod.allTime => true,
      };

  static ReplaySummary compute({
    required List<PlayRecord> records,
    required Map<String, ListenedTrack> tracks,
    Map<int, int> untrackedMs = const {},
    PlayRecord? open,
    required ReplayPeriod period,
    required DateTime now,
    int limit = 5,
  }) {
    final counted = ListeningStats.countedPlay.inMilliseconds;
    final songs = <String, ReplayEntry>{};
    final artists = <String, ReplayEntry>{};
    final albums = <String, ReplayEntry>{};
    final genres = <String, ReplayEntry>{};
    final byHour = List<int>.filled(24, 0);
    final byDay = <DateTime, int>{};
    var total = 0;
    var plays = 0;
    DateTime? first;

    void credit(Map<String, ReplayEntry> into, String key, ReplayEntry Function() make,
        int ms, bool isPlay, String trackId) {
      final e = into.putIfAbsent(key, make);
      e.ms += ms;
      if (isPlay) e.plays++;
      e._trackMs[trackId] = (e._trackMs[trackId] ?? 0) + ms;
    }

    final all = [...records, if (open != null) open];
    for (final r in all) {
      final start = r.start;
      if (first == null || start.isBefore(first)) first = start;
      if (!_inPeriod(start, period, now)) continue;

      total += r.ms;
      byHour[start.hour] += r.ms;
      final day = DateTime(start.year, start.month, start.day);
      byDay[day] = (byDay[day] ?? 0) + r.ms;

      final t = r.trackId == null ? null : tracks[r.trackId];
      final isPlay = r.ms >= counted;
      if (isPlay) plays++;
      if (t == null) continue;

      credit(songs, t.id, () => ReplayEntry(
            key: t.id,
            title: t.title,
            subtitle: t.artist,
            artUrl: t.artUrl,
          )..track = t.toTrack(), r.ms, isPlay, t.id);

      for (final a in splitArtists(t.artist)) {
        credit(artists, a.toLowerCase(),
            () => ReplayEntry(key: a.toLowerCase(), title: a, subtitle: '', artUrl: t.artUrl),
            r.ms, isPlay, t.id);
      }

      final album = t.album.trim();
      if (album.isNotEmpty && album.toLowerCase() != t.title.trim().toLowerCase()) {
        final lead = splitArtists(t.artist).firstOrNull ?? t.artist;
        credit(albums, '${album.toLowerCase()}|${lead.toLowerCase()}',
            () => ReplayEntry(
                  key: '${album.toLowerCase()}|${lead.toLowerCase()}',
                  title: album,
                  subtitle: lead,
                  artUrl: t.artUrl,
                ),
            r.ms, isPlay, t.id);
      }

      final g = t.genre;
      if (g != null && g.isNotEmpty) {
        credit(genres, g.toLowerCase(),
            () => ReplayEntry(key: g.toLowerCase(), title: g, subtitle: '', artUrl: ''),
            r.ms, isPlay, t.id);
      }
    }

    // Untracked minutes (the pre-log counter) count toward the total only.
    untrackedMs.forEach((year, ms) {
      final inPeriod = switch (period) {
        ReplayPeriod.month => false, // no month is known for them
        ReplayPeriod.year => year == now.year,
        ReplayPeriod.allTime => true,
      };
      if (inPeriod) total += ms;
    });

    List<ReplayEntry> rank(Map<String, ReplayEntry> m) {
      final list = m.values.where((e) => e.plays > 0 || e.ms >= counted).toList()
        ..sort((a, b) {
          final p = b.plays.compareTo(a.plays);
          if (p != 0) return p;
          final ms = b.ms.compareTo(a.ms);
          if (ms != 0) return ms;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      return list.take(limit).toList(growable: false);
    }

    List<ReplayEntry> withBestArt(List<ReplayEntry> list) => [
          for (final e in list)
            _rearted(e, tracks),
        ];

    int? peakHour;
    var peak = 0;
    for (var h = 0; h < 24; h++) {
      if (byHour[h] > peak) {
        peak = byHour[h];
        peakHour = h;
      }
    }
    DateTime? bigDay;
    var bigMs = 0;
    byDay.forEach((d, ms) {
      if (ms > bigMs) {
        bigMs = ms;
        bigDay = d;
      }
    });

    final label = switch (period) {
      ReplayPeriod.month => '${monthName(now.month)} ${now.year}',
      ReplayPeriod.year => '${now.year}',
      ReplayPeriod.allTime => 'All time',
    };

    bool real(ReplayEntry e) => e.plays > 0 || e.ms >= counted;

    return ReplaySummary._(
      period: period,
      label: label,
      totalMs: total,
      plays: plays,
      topSongs: rank(songs),
      topArtists: withBestArt(rank(artists)),
      topAlbums: withBestArt(rank(albums)),
      topGenres: rank(genres),
      distinctSongs: songs.values.where(real).length,
      distinctArtists: artists.values.where(real).length,
      distinctAlbums: albums.values.where(real).length,
      peakHour: peak > 0 ? peakHour : null,
      biggestDay: bigDay,
      biggestDayMs: bigMs,
      memberSince: first,
    );
  }

  /// An artist or album shown with the art of its most-listened track.
  static ReplayEntry _rearted(ReplayEntry e, Map<String, ListenedTrack> tracks) {
    if (e._trackMs.isEmpty) return e;
    final best = e._trackMs.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    final art = tracks[best]?.artUrl ?? '';
    if (art.isEmpty || art == e.artUrl) return e;
    final copy = ReplayEntry(key: e.key, title: e.title, subtitle: e.subtitle, artUrl: art)
      ..plays = e.plays
      ..ms = e.ms
      ..track = e.track;
    copy._trackMs.addAll(e._trackMs);
    return copy;
  }

  /// Convenience: a summary straight from the live log.
  static ReplaySummary of(ListeningStats stats, ReplayPeriod period, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final opened = stats.openedAt;
    final current = stats.currentTrack;
    return compute(
      records: stats.records,
      tracks: {
        ...stats.tracks,
        if (current != null) current.id: current,
      },
      untrackedMs: stats.untrackedMs,
      // The session still running is shown live but is not yet a record.
      open: opened == null
          ? null
          : PlayRecord(
              startMs: opened.millisecondsSinceEpoch,
              ms: stats.openSessionMs,
              trackId: current?.id,
            ),
      period: period,
      now: clock,
    );
  }
}

// ── Formatting shared by the Replay surfaces ─────────────────────────────

/// "1513" -> "1,513".
String groupThousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 167 min -> "2h 47m"; 48 min -> "48 min"; under a minute -> "<1 min".
String formatListenTime(int ms) {
  final minutes = ms ~/ Duration.millisecondsPerMinute;
  if (minutes < 1) return '<1 min';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// 20 -> "8 PM", 0 -> "midnight", 12 -> "noon".
String formatHour(int hour) {
  if (hour == 0) return 'midnight';
  if (hour == 12) return 'noon';
  return hour < 12 ? '$hour AM' : '${hour - 12} PM';
}

/// The artist with the most plays among [recents] (newest first), or null when
/// no artist appears at least twice - one play is not a pattern.
String? topRecentArtist(List<Track> recents, {int window = 50}) {
  final counts = <String, int>{};
  for (final t in recents.take(window)) {
    final a = t.artistName.trim();
    if (a.isEmpty) continue;
    counts[a] = (counts[a] ?? 0) + 1;
  }
  String? best;
  var bestCount = 1;
  counts.forEach((artist, count) {
    if (count > bestCount) {
      best = artist;
      bestCount = count;
    }
  });
  return best;
}
