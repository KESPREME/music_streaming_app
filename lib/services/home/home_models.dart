/// Structured Home feed domain models.
///
/// One feed = ordered sections from semantic sources. Item identity is
/// explicit (videoId and/or browseId) — never a title, never an array index.
/// Snapshot serialization is versioned so schema changes invalidate old
/// caches safely.
library;

/// v2: type resolution reworked (ID-prefix + nav-shape, never subtitle
/// startsWith guesses alone), source provenance added. Old v1 snapshots
/// invalidate automatically.
const int kHomeFeedSchemaVersion = 2;

enum HomeContentType { song, video, album, artist, playlist, unknown }

enum HomePresentation {
  compactTracks,
  artworkRail,
  playlistRail,
  artistRail,
  grid
}

class HomeItem {
  const HomeItem({
    required this.id,
    this.videoId,
    this.browseId,
    required this.title,
    required this.subtitle,
    required this.artworkUrl,
    required this.contentType,
  });

  /// Stable identity: videoId when playable, else browseId. Never derived
  /// from title or position.
  final String id;
  final String? videoId;
  final String? browseId;
  final String title;
  final String subtitle;
  final String artworkUrl;
  final HomeContentType contentType;

  bool get isPlayable =>
      videoId != null ||
      contentType == HomeContentType.playlist ||
      contentType == HomeContentType.album;

  Map<String, dynamic> toJson() => {
        'id': id,
        'v': videoId,
        'b': browseId,
        't': title,
        's': subtitle,
        'a': artworkUrl,
        'c': contentType.index,
      };

  static HomeItem fromJson(Map<String, dynamic> json) => HomeItem(
        id: json['id'] as String? ?? '',
        videoId: json['v'] as String?,
        browseId: json['b'] as String?,
        title: json['t'] as String? ?? '',
        subtitle: json['s'] as String? ?? '',
        artworkUrl: json['a'] as String? ?? '',
        contentType: json['c'] is int &&
                json['c'] >= 0 &&
                json['c'] < HomeContentType.values.length
            ? HomeContentType.values[json['c'] as int]
            : HomeContentType.unknown,
      );
}

class HomeSection {
  const HomeSection({
    required this.id,
    required this.title,
    required this.items,
    required this.presentation,
  });

  /// Stable section identity: normalized source title + dominant type.
  final String id;
  final String title;
  final List<HomeItem> items;
  final HomePresentation presentation;

  HomeContentType get dominantType {
    final counts = <HomeContentType, int>{};
    for (final item in items) {
      counts[item.contentType] = (counts[item.contentType] ?? 0) + 1;
    }
    HomeContentType best = HomeContentType.unknown;
    var bestCount = -1;
    counts.forEach((type, count) {
      if (count > bestCount) {
        best = type;
        bestCount = count;
      }
    });
    return best;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'p': presentation.index,
        'items': items.map((i) => i.toJson()).toList(),
      };

  static HomeSection fromJson(Map<String, dynamic> json) => HomeSection(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        presentation: json['p'] is int &&
                json['p'] >= 0 &&
                json['p'] < HomePresentation.values.length
            ? HomePresentation.values[json['p'] as int]
            : HomePresentation.artworkRail,
        items: ((json['items'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(HomeItem.fromJson)
            .toList(),
      );
}

class HomeFeed {
  const HomeFeed({
    required this.sections,
    required this.fetchedAt,
    required this.source,
  });

  final List<HomeSection> sections;
  final DateTime fetchedAt;

  /// 'ytm_home' | 'fallback' — surfaces provenance in debug logging.
  final String source;

  Map<String, dynamic> toJson() => {
        'schema': kHomeFeedSchemaVersion,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
        'source': source,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  static HomeFeed? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    if (json['schema'] != kHomeFeedSchemaVersion) return null;
    final fetched = json['fetchedAt'];
    if (fetched is! int) return null;
    final sections = ((json['sections'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .map(HomeSection.fromJson)
        .where((s) => s.items.isNotEmpty)
        .toList();
    if (sections.isEmpty) return null;
    return HomeFeed(
      sections: sections,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetched),
      source: json['source'] as String? ?? 'unknown',
    );
  }
}
