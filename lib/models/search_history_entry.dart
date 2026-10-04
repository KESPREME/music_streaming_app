import 'dart:convert';

/// What a recent-searches row points at, which is what decides what tapping it
/// does.
///
/// Two kinds, and only two, because those are the only two things the search
/// screen can hand back today: a bare query the user typed, or a track they
/// actually played. Albums, artists and playlists would each need their own tap
/// behaviour (navigate to a detail screen), so they are deliberately not
/// modelled until something can act on them.
enum SearchHistoryKind {
  /// A typed query. No artwork; tapping re-runs the search.
  query,

  /// A track played from search results. Carries artwork; tapping plays it.
  track,
}

/// One row in "Recent searches".
///
/// Modelled on identity rather than on a snapshot of a [Track]: the row stores
/// what is needed to render it and to act on it (id, title, subtitle,
/// artwork), and nothing that would go stale. That is also why tapping a track
/// row reconstructs a [Track] rather than storing one.
class SearchHistoryEntry {
  /// Stable identity. A track's is its video id; a query's is the text itself.
  ///
  /// Dedupe is by this, case-insensitively - so re-searching a term moves the
  /// existing row to the top rather than leaving a duplicate behind, and
  /// re-playing a track does the same.
  final String id;

  final String title;

  /// Artist for a track, empty for a query.
  final String subtitle;

  /// Cover art for a track, empty for a query.
  final String artworkUrl;

  final SearchHistoryKind kind;

  /// When this entry was last recorded. Only used to keep the list ordered; the
  /// list is stored newest-first so this is not persisted per-row ordering
  /// state that could disagree with the list itself.
  final DateTime timestamp;

  const SearchHistoryEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.artworkUrl,
    required this.kind,
    required this.timestamp,
  });

  /// A typed query. Carries no artwork, which is what makes the row fall back to
  /// the clock icon rather than a cover.
  factory SearchHistoryEntry.query(String raw) => SearchHistoryEntry(
        id: raw.trim(),
        title: raw.trim(),
        subtitle: '',
        artworkUrl: '',
        kind: SearchHistoryKind.query,
        timestamp: DateTime.now(),
      );

  factory SearchHistoryEntry.track({
    required String id,
    required String title,
    required String artist,
    required String artworkUrl,
  }) =>
      SearchHistoryEntry(
        id: id,
        title: title,
        subtitle: artist,
        artworkUrl: artworkUrl,
        kind: SearchHistoryKind.track,
        timestamp: DateTime.now(),
      );

  bool get hasArtwork =>
      artworkUrl.isNotEmpty && kind == SearchHistoryKind.track;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'artworkUrl': artworkUrl,
        'kind': kind.name,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  /// Tolerant on purpose: a row that cannot be read is dropped, not fatal. This
  /// is a convenience list, and a single bad record must never take the search
  /// tab down with it.
  static SearchHistoryEntry? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String || id.isEmpty) return null;

    final kindName = json['kind'];
    final kind = SearchHistoryKind.values.firstWhere(
      (k) => k.name == kindName,
      // An unrecognised kind is a query: the oldest, always-supported shape.
      orElse: () => SearchHistoryKind.query,
    );

    final ts = json['ts'];
    return SearchHistoryEntry(
      id: id,
      title: title,
      subtitle: json['subtitle'] is String ? json['subtitle'] as String : '',
      artworkUrl:
          json['artworkUrl'] is String ? json['artworkUrl'] as String : '',
      kind: kind,
      timestamp: ts is int
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static String encodeList(List<SearchHistoryEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());

  /// Tolerant on purpose, at both levels.
  ///
  /// A payload that is not JSON at all, or not a list, yields an empty list; a
  /// record inside a good list that cannot be read is skipped. This is a
  /// convenience list, so a bad record must cost the user their other rows at
  /// most - never the whole screen.
  static List<SearchHistoryEntry> decodeList(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];
    final out = <SearchHistoryEntry>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        final entry = SearchHistoryEntry.fromJson(item);
        if (entry != null) out.add(entry);
      }
    }
    return out;
  }
}
