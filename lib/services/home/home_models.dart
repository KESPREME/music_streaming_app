/// Structured Home feed domain models.
///
/// One feed = ordered sections from semantic sources. Item identity is
/// explicit (videoId and/or browseId) — never a title, never an array index.
/// Snapshot serialization is versioned so schema changes invalidate old
/// caches safely.
library;

/// v4: structured metadata (artists[], publishedText), continuation
/// capture, multi-dimension quality, parser/context version binding.
/// parser v5: support levels, section-local dedupe, thumbnail variants,
/// degradation detection, item-tolerance retention (no-artwork items
/// retained as PARTIAL instead of rejected).
const int kHomeFeedSchemaVersion = 4;
const int kHomeParserVersion = 5;
const int kHomeRequestContextVersion = 2;

enum HomeContentType { song, video, album, artist, playlist, unknown }

enum HomePresentation {
  compactTracks,
  artworkRail,
  playlistRail,
  artistRail,
  grid,
  videoRail,
}

/// Per-shelf accounting record (debug): full reconciliation of what the
/// raw response contained vs what survived. Invariants (spec #33):
/// discovered = parsed + unsupported + malformed
/// rawItems   = retained + rejected + duplicate
class ShelfReport {
  const ShelfReport({
    required this.path,
    required this.renderer,
    required this.status,
    this.title,
    this.rawItemCount = 0,
    this.recognizedItemCount = 0,
    this.rejectedItemCount = 0,
    this.duplicateItemCount = 0,
    this.rejectionReasons = const [],
    this.partialItemCount = 0,
    this.hasContinuation = false,
  });

  final String path;
  final String renderer;
  final ShelfStatus status;
  final String? title;
  final int rawItemCount;
  final int recognizedItemCount;
  final int rejectedItemCount;
  final int duplicateItemCount;
  final List<String> rejectionReasons;

  /// Items retained as PARTIAL (renderable but incomplete) — counted
  /// separately from fully-parsed items (spec #3: retained = full + partial).
  final int partialItemCount;

  /// Continuation token presence — recorded, never auto-consumed (spec #24).
  final bool hasContinuation;

  Map<String, dynamic> toJson() => {
        'path': path,
        'renderer': renderer,
        'status': status.name,
        if (title != null) 'title': title,
        'raw': rawItemCount,
        'recognized': recognizedItemCount,
        'rejected': rejectedItemCount,
        'dupes': duplicateItemCount,
        'partial': partialItemCount,
        if (rejectionReasons.isNotEmpty)
          'why': rejectionReasons.take(5).toList(),
      };
}

enum ShelfStatus { parsed, unsupportedRenderer, malformed, empty, filtered }

/// Support levels (spec #3): binary SUPPORTED/UNSUPPORTED destroyed valid
/// content. PARTIAL items (e.g. playlist identity + artwork but no direct
/// playback) MUST render as navigation cards, never be discarded.
enum SupportLevel { fullySupported, partiallySupported, unsupported }

/// Semantic section type (spec #2): content type ≠ playability. A playlist
/// shelf is valid content even though it is not a song.
enum HomeSectionType {
  songShelf,
  albumShelf,
  artistShelf,
  playlistShelf,
  videoShelf,
  episodeShelf,
  mixedShelf,
  unknownContent,
}

/// Aggregate accounting for one parse pass.
class ParseReport {
  const ParseReport({
    required this.discoveredShelves,
    required this.parsedShelves,
    required this.unsupportedShelves,
    required this.malformedShelves,
    required this.emptyShelves,
    required this.rawItems,
    required this.retainedItems,
    required this.rejectedItems,
    required this.duplicateItems,
    this.partialItems = 0,
    required this.shelves,
    required this.heroCandidate,
  });

  final int discoveredShelves;
  final int parsedShelves;
  final int unsupportedShelves;
  final int malformedShelves;
  final int emptyShelves;
  final int rawItems;
  final int retainedItems;
  final int rejectedItems;
  final int duplicateItems;

  /// Subset of [retainedItems] that render with placeholders (spec #3:
  /// retained = fullySupported + partiallySupported).
  final int partialItems;
  final List<ShelfReport> shelves;

  /// Eligible hero: immersive header feature or first strong song shelf.
  final HomeItem? heroCandidate;

  /// Invariant check — any violation is a parser bug.
  bool get invariantsHold =>
      discoveredShelves ==
          parsedShelves +
              unsupportedShelves +
              malformedShelves +
              emptyShelves &&
      rawItems == retainedItems + rejectedItems + duplicateItems;

  Map<String, dynamic> toJson() => {
        'discovered': discoveredShelves,
        'parsed': parsedShelves,
        'unsupported': unsupportedShelves,
        'malformed': malformedShelves,
        'empty': emptyShelves,
        'rawItems': rawItems,
        'retained': retainedItems,
        'rejected': rejectedItems,
        'duplicates': duplicateItems,
        'invariantsHold': invariantsHold,
        'heroCandidate': heroCandidate?.id,
        'shelves': shelves.map((s) => s.toJson()).toList(),
      };

  @override
  String toString() {
    final buf = StringBuffer(
        'ParseReport: discovered=$discoveredShelves parsed=$parsedShelves '
        'unsupported=$unsupportedShelves malformed=$malformedShelves empty=$emptyShelves | '
        'items raw=$rawItems retained=$retainedItems rejected=$rejectedItems '
        'dupes=$duplicateItems | invariants=${invariantsHold ? "OK" : "VIOLATED"} | '
        'hero=${heroCandidate?.id ?? "none"}');
    for (final s in shelves) {
      buf.write('\n  [${s.status.name}] ${s.renderer} "${s.title ?? '?'}" '
          'raw=${s.rawItemCount} ok=${s.recognizedItemCount} '
          'rej=${s.rejectedItemCount} dupe=${s.duplicateItemCount}');
      for (final reason in s.rejectionReasons.take(3)) {
        buf.write('\n      reason: $reason');
      }
    }
    return buf.toString();
  }
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
    this.artists = const [],
    this.publishedText,
    this.playability = Playability.unknown,
    this.supportLevel = SupportLevel.fullySupported,
    this.thumbnails = const [],
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

  /// Structured metadata (spec #26/#27) — nullable where source data is
  /// absent; never populated with guesses. Artists parsed from subtitle
  /// run segments; publishedText = year / relative-age text when present.
  final List<String> artists;
  final String? publishedText;

  /// Playability is separate from identity (spec #23): a valid album is
  /// not directly playable; a song without videoId is not playable.
  final Playability playability;

  /// Support level (spec #3): FULL items parse completely; PARTIAL items
  /// render safely with placeholders (e.g. missing artwork); UNSUPPORTED
  /// items are the only ones discarded.
  final SupportLevel supportLevel;

  /// All available thumbnail variants (spec #6): parsed with dimensions,
  /// presentation picks the right one. Empty = none provided (placeholder).
  final List<HomeThumb> thumbnails;

  bool get isPlayable =>
      playability == Playability.playable ||
      (playability == Playability.unknown &&
          (videoId != null ||
              contentType == HomeContentType.playlist ||
              contentType == HomeContentType.album));

  Map<String, dynamic> toJson() => {
        'id': id,
        'v': videoId,
        'b': browseId,
        't': title,
        's': subtitle,
        'a': artworkUrl,
        'c': contentType.index,
        if (artists.isNotEmpty) 'ar': artists,
        if (publishedText != null) 'pub': publishedText,
        'pl': playability.index,
        'sup': supportLevel.index,
        if (thumbnails.isNotEmpty)
          'th': thumbnails.map((t) => t.toJson()).toList(),
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
        artists:
            (json['ar'] as List?)?.whereType<String>().toList() ?? const [],
        publishedText: json['pub'] as String?,
        playability: json['pl'] is int &&
                json['pl'] >= 0 &&
                json['pl'] < Playability.values.length
            ? Playability.values[json['pl'] as int]
            : Playability.unknown,
        supportLevel: json['sup'] is int &&
                json['sup'] >= 0 &&
                json['sup'] < SupportLevel.values.length
            ? SupportLevel.values[json['sup'] as int]
            : SupportLevel.fullySupported,
        thumbnails: ((json['th'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(HomeThumb.fromJson)
            .toList(),
      );
}

enum Playability { unknown, playable, notPlayable }

/// One thumbnail variant with its dimensions (spec #6): the UI selects by
/// presentation (square rail vs 16:9 video card vs hero) instead of every
/// parser hardcoding its own resolution upgrade.
class HomeThumb {
  const HomeThumb({required this.url, this.width, this.height});

  final String url;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson() => {'u': url, 'w': width, 'h': height};

  static HomeThumb fromJson(Map<String, dynamic> json) => HomeThumb(
        url: json['u'] as String? ?? '',
        width: json['w'] as int?,
        height: json['h'] as int?,
      );
}

class HomeSection {
  const HomeSection({
    required this.id,
    required this.title,
    required this.items,
    required this.presentation,
    this.sourcePath,
    this.renderer,
    this.sourceSubtitle,
  });

  /// Stable section identity: normalized source title + dominant type.
  final String id;
  final String title;
  final List<HomeItem> items;
  final HomePresentation presentation;

  /// Debug provenance: where this shelf lived in the raw response and
  /// which renderer produced it. Serialized for forensics.
  final String? sourcePath;
  final String? renderer;
  final String? sourceSubtitle;

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
        if (sourcePath != null) 'path': sourcePath,
        if (renderer != null) 'renderer': renderer,
        if (sourceSubtitle != null) 'sub': sourceSubtitle,
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
        sourcePath: json['path'] as String?,
        renderer: json['renderer'] as String?,
        sourceSubtitle: json['sub'] as String?,
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
    this.heroCandidate,
    this.continuationToken,
  });

  final List<HomeSection> sections;
  final DateTime fetchedAt;

  /// 'ytm_home' | 'fallback' - surfaces provenance in debug logging.
  final String source;

  /// Parser-nominated hero (first strong song shelf's first playable item).
  /// Eligibility enforced by the UI — never sections.first blindly.
  final HomeItem? heroCandidate;

  /// Home continuation token when the source offers more shelves. Recorded
  /// for future explicit "load more" — never auto-consumed (spec #24).
  final String? continuationToken;

  Map<String, dynamic> toJson() => {
        'schema': kHomeFeedSchemaVersion,
        'parser': kHomeParserVersion,
        'ctx': kHomeRequestContextVersion,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
        'source': source,
        if (continuationToken != null) 'cont': continuationToken,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  static HomeFeed? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    // Schema + parser + context version binding (spec #11): any mismatch
    // invalidates the snapshot — never partially deserialize.
    if (json['schema'] != kHomeFeedSchemaVersion) return null;
    if (json['parser'] != kHomeParserVersion) return null;
    if (json['ctx'] != kHomeRequestContextVersion) return null;
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
      continuationToken: json['cont'] as String?,
    );
  }
}
