import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/track.dart';
import '../innertube/innertube_service.dart';
import 'home_diagnostics.dart';
import 'home_models.dart';

/// Internal: a discovered shelf candidate before parsing.
class _ShelfCandidate {
  const _ShelfCandidate({
    required this.path,
    required this.renderer,
    required this.shelf,
    this.unsupported = false,
  });

  final String path;
  final String renderer;
  final Map<String, dynamic>? shelf;
  final bool unsupported;
}

/// Native YouTube Music Home source (browseId = FEmusic_home).
///
/// Preserves shelf semantics: each musicCarouselShelfRenderer becomes one
/// [HomeSection] with its real title ("Quick picks", "Listen again", …).
/// Defensive parsing throughout — one malformed shelf or unknown renderer
/// is skipped, never crashes the feed.
class YouTubeMusicHomeSource {
  YouTubeMusicHomeSource(this._innerTube);

  final InnerTubeService _innerTube;

  /// Whether a visitor context was established before the Home request
  /// (degraded-context detection for diagnostics).
  bool get hasVisitorData => _innerTube.visitorData != null;

  static const _homeBrowseId = 'FEmusic_home';

  Future<HomeFeed?> fetch({int perShelfLimit = 10}) async {
    try {
      final data = await _innerTube
          .browseJson(_homeBrowseId)
          .timeout(const Duration(seconds: 12));
      return await _parse(data, perShelfLimit);
    } catch (e) {
      if (kDebugMode) debugPrint('YTMHomeSource: fetch failed: $e');
      return null;
    }
  }

  /// Testable parse entry: raw browse JSON → HomeFeed (no network).
  /// Also exposes the forensic accounting report.
  Future<HomeFeed?> parseResponse(Map<String, dynamic> data,
          {int perShelfLimit = 10}) =>
      _parse(data, perShelfLimit);

  ParseReport? lastReport;

  Future<HomeFeed?> _parse(Map<String, dynamic> data, int perShelfLimit) async {
    try {
      final sections = <HomeSection>[];
      final root = _findSectionListRoot(data);
      if (root == null) {
        lastReport = ParseReport(
          discoveredShelves: 0,
          parsedShelves: 0,
          unsupportedShelves: 0,
          malformedShelves: 0,
          emptyShelves: 0,
          rawItems: 0,
          retainedItems: 0,
          rejectedItems: 0,
          duplicateItems: 0,
          shelves: const [],
          heroCandidate: null,
        );
        return null;
      }

      // ── Stage A: discovery ───────────────────────────────────────────────
      // Walk every node under the section list; collect candidate shelves
      // with their JSON paths. Handles both flat carousel layouts and
      // musicSectionListRenderer-wrapped nested groups (chip-filtered
      // Home surfaces), which the previous walker silently dropped.
      final candidates = <_ShelfCandidate>[];
      String? continuationToken;
      void walk(dynamic node, String path, int depth) {
        if (node is List) {
          var i = 0;
          for (final child in node) {
            walk(child, '$path[$i]', depth + 1);
            i++;
          }
          return;
        }
        if (node is! Map<String, dynamic> || depth > 8) return;
        node.forEach((key, value) {
          if (key == 'musicCarouselShelfRenderer' ||
              key == 'musicShelfRenderer') {
            if (value is Map<String, dynamic>) {
              candidates.add(_ShelfCandidate(
                path: '$path.$key',
                renderer: key,
                shelf: value,
              ));
            }
            return; // do not descend into a shelf we claimed
          }
          // Continuation tokens: recorded, never auto-consumed (spec #24).
          if (key == 'continuationItemRenderer') {
            String? token;
            if (value is Map<String, dynamic>) {
              token = value['continuationEndpoint']?['continuationCommand']
                      ?['token'] as String? ??
                  value['nextContinuationData']?['continuation'] as String?;
            }
            if (token != null && token.isNotEmpty) {
              continuationToken = token;
              if (kDebugMode) {
                debugPrint(
                    'YTMHomeSource: continuation available (${token.length} chars)');
              }
            }
            return;
          }
          // Known non-shelf containers to traverse.
          if (key == 'musicSectionListRenderer' ||
              key == 'sectionListRenderer' ||
              key == 'tabRenderer' ||
              key == 'content' ||
              key == 'contents') {
            walk(value, '$path.$key', depth + 1);
            return;
          }
          // Unknown top-level renderers → diagnostics, no silent drop.
          if (value is Map<String, dynamic> && key.endsWith('Renderer')) {
            candidates.add(_ShelfCandidate(
              path: '$path.$key',
              renderer: key,
              shelf: null,
              unsupported: true,
            ));
          }
        });
      }

      walk(root, 'sectionList', 0);

      // ── Stages B–E: parse each candidate with full accounting ───────────
      final reports = <ShelfReport>[];
      var parsed = 0, unsupported = 0, malformed = 0, empty = 0;
      var rawTotal = 0, retainedTotal = 0, rejectedTotal = 0, dupTotal = 0;
      HomeItem? heroCandidate;

      for (final candidate in candidates) {
        final shelf = candidate.shelf;
        if (shelf == null) {
          reports.add(ShelfReport(
            path: candidate.path,
            renderer: candidate.renderer,
            status: ShelfStatus.unsupportedRenderer,
            title: _shelfTitleOf(candidate.renderer, shelf),
          ));
          unsupported++;
          continue;
        }

        final title = _headerText(shelf['header']) ??
            _headerTextFromTitleNode(shelf['title']);
        if (title == null || title.isEmpty) {
          malformed++;
          reports.add(ShelfReport(
            path: candidate.path,
            renderer: candidate.renderer,
            status: ShelfStatus.malformed,
            title: title,
          ));
          continue;
        }

        // Carousel shelves nest items under `contents`; list shelves keep
        // them there too.
        final carousel = shelf['contents'];
        if (carousel is! List || carousel.isEmpty) {
          empty++;
          reports.add(ShelfReport(
            path: candidate.path,
            renderer: candidate.renderer,
            status: ShelfStatus.empty,
            title: title,
            rawItemCount: 0,
          ));
          continue;
        }

        final items = <HomeItem>[];
        final seenIds = <String>{};
        final reasons = <String>[];
        var rejected = 0, dupes = 0;

        for (final wrapper in carousel) {
          if (items.length >= perShelfLimit) break;
          if (wrapper is! Map<String, dynamic>) continue;

          HomeItem? item;
          final responsive = wrapper['musicResponsiveListItemRenderer'];
          final twoRow = wrapper['musicTwoRowItemRenderer'];
          if (responsive is Map<String, dynamic>) {
            item = _itemFromResponsive(responsive);
          } else if (twoRow is Map<String, dynamic>) {
            item = _itemFromTwoRow(twoRow);
          }

          if (item == null) {
            rejected++;
            final kinds =
                wrapper.keys.where((k) => k.endsWith('Renderer')).join(',');
            reasons.add(
                'unparseable item renderer: ${kinds.isEmpty ? '?' : kinds}');
            continue;
          }
          if (!seenIds.add(item.id)) {
            dupes++;
            continue;
          }
          items.add(item);
        }

        final rawCount = carousel.length;
        rawTotal += rawCount;
        retainedTotal += items.length;
        rejectedTotal += rejected;
        dupTotal += dupes;

        if (items.length >= 2) {
          parsed++;
          final section = HomeSection(
            id: _sectionId(title, items),
            title: title,
            items: items,
            presentation: _presentationFor(items),
            sourcePath: candidate.path,
            renderer: candidate.renderer,
          );
          sections.add(section);

          // Hero: first strong song shelf's first playable item.
          if (heroCandidate == null &&
              section.dominantType == HomeContentType.song &&
              items.any((i) => i.videoId != null)) {
            heroCandidate = items.firstWhere((i) => i.videoId != null);
          }

          reports.add(ShelfReport(
            path: candidate.path,
            renderer: candidate.renderer,
            status: ShelfStatus.parsed,
            title: title,
            rawItemCount: rawCount,
            recognizedItemCount: items.length + rejected,
            rejectedItemCount: rejected,
            duplicateItemCount: dupes,
            rejectionReasons: reasons,
          ));
        } else {
          empty++;
          reports.add(ShelfReport(
            path: candidate.path,
            renderer: candidate.renderer,
            status: ShelfStatus.empty,
            title: title,
            rawItemCount: rawCount,
            recognizedItemCount: items.length,
            rejectedItemCount: rejected,
            duplicateItemCount: dupes,
            rejectionReasons: reasons,
          ));
        }
      }

      lastReport = ParseReport(
        discoveredShelves: candidates.length,
        parsedShelves: parsed,
        unsupportedShelves: unsupported,
        malformedShelves: malformed,
        emptyShelves: empty,
        rawItems: rawTotal,
        retainedItems: retainedTotal,
        rejectedItems: rejectedTotal,
        duplicateItems: dupTotal,
        shelves: reports,
        heroCandidate: heroCandidate,
      );
      if (kDebugMode) debugPrint(lastReport.toString());
      if (!lastReport!.invariantsHold && kDebugMode) {
        debugPrint('YTMHomeSource: ⚠️ ACCOUNTING INVARIANT VIOLATION');
      }

      if (sections.isEmpty) return null;
      return HomeFeed(
        sections: sections,
        fetchedAt: DateTime.now(),
        source: 'ytm_home',
        heroCandidate: heroCandidate,
        continuationToken: continuationToken,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('YTMHomeSource: parse error: $e');
      return null;
    }
  }

  /// Walks toward the Home section list defensively. Handles both the
  /// classic layout and chip-filtered layouts that wrap shelves inside
  /// musicSectionListRenderer (handled by the deep walker below).
  static Map<String, dynamic>? _findSectionListRoot(Map<String, dynamic> data) {
    final tabs =
        data['contents']?['singleColumnBrowseResultsRenderer']?['tabs'];
    if (tabs is! List || tabs.isEmpty) return null;
    final content = tabs[0]?['tabRenderer']?['content'];
    if (content is! Map<String, dynamic>) return null;
    final sectionList = content['sectionListRenderer'];
    if (sectionList is! Map<String, dynamic>) return null;
    return sectionList;
  }

  static String? _shelfTitleOf(String renderer, Map<String, dynamic>? shelf) {
    if (shelf == null) return null;
    return _headerText(shelf['header']) ??
        _headerTextFromTitleNode(shelf['title']);
  }

  /// Header text from carousel or list shelf headers.
  static String? _headerText(dynamic header) {
    if (header is! Map<String, dynamic>) return null;
    final candidates = [
      header['musicCarouselShelfBasicHeaderRenderer'],
      header['musicResponsiveHeaderRenderer'],
    ];
    for (final r in candidates) {
      if (r is! Map<String, dynamic>) continue;
      final title = r['title'];
      if (title is Map<String, dynamic>) {
        final simple = title['simpleText'];
        if (simple is String && simple.isNotEmpty) return simple;
        final runs = title['runs'];
        if (runs is List && runs.isNotEmpty) {
          final t = runs[0]?['text'];
          if (t is String && t.isNotEmpty) return t;
        }
      }
    }
    return null;
  }

  /// List-shelf title lives in its own title node (musicShelfRenderer).
  static String? _headerTextFromTitleNode(dynamic titleNode) {
    if (titleNode is! Map<String, dynamic>) return null;
    final simple = titleNode['simpleText'];
    if (simple is String && simple.isNotEmpty) return simple;
    final runs = titleNode['runs'];
    if (runs is List && runs.isNotEmpty) {
      final t = runs[0]?['text'];
      if (t is String && t.isNotEmpty) return t;
    }
    return null;
  }

  static String _sectionId(String title, List<HomeItem> items) {
    final dominant = <String, int>{};
    for (final i in items) {
      dominant[i.contentType.name] = (dominant[i.contentType.name] ?? 0) + 1;
    }
    final best =
        dominant.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return '${title.toLowerCase().trim()}:$best';
  }

  static HomePresentation _presentationFor(List<HomeItem> items) {
    final types = items.map((i) => i.contentType).toSet();
    if (types.length == 1) {
      switch (types.first) {
        case HomeContentType.artist:
          return HomePresentation.artistRail;
        case HomeContentType.playlist:
          return HomePresentation.playlistRail;
        case HomeContentType.album:
          return HomePresentation.grid;
        default:
          break;
      }
    }
    return HomePresentation.artworkRail;
  }

  /// Video/browse id from the usual InnerTube endpoint shapes.
  static String? _idFrom(Map<String, dynamic> r) {
    final vid = r['playlistItemData']?['videoId'];
    if (vid is String && vid.isNotEmpty) return vid;

    final flexFirst = (r['flexColumns'] as List?)?.firstOrNull;
    final nav = flexFirst?['musicResponsiveListItemFlexColumnRenderer']?['text']
        ?['runs']?[0]?['navigationEndpoint'];
    final watch = nav?['watchEndpoint']?['videoId'];
    if (watch is String && watch.isNotEmpty) return watch;

    final overlay = r['overlay']?['musicItemThumbnailOverlayRenderer']
            ?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']
        ?['watchEndpoint']?['videoId'];
    if (overlay is String && overlay.isNotEmpty) return overlay;

    final navEndpoint = r['navigationEndpoint'];
    final directWatch = navEndpoint?['watchEndpoint']?['videoId'];
    if (directWatch is String && directWatch.isNotEmpty) return directWatch;
    final browse = navEndpoint?['browseEndpoint']?['browseId'];
    if (browse is String && browse.isNotEmpty) return browse;

    return null;
  }

  static String? _thumbFrom(dynamic thumbnails) {
    if (thumbnails is! List || thumbnails.isEmpty) return null;
    final last = thumbnails.last;
    final url = last?['url'];
    if (url is! String || url.isEmpty) return null;
    // Centralized resolution policy: upgrade Googleusercontent art to a
    // consistent display size (widgets stay resolution-agnostic).
    if (url.contains('googleusercontent.com')) {
      return url.replaceAll(RegExp(r'=w\d+-h\d+.*$'), '=w544-h544');
    }
    return url;
  }

  static HomeItem? _itemFromResponsive(Map<String, dynamic> r) {
    try {
      final id = _idFrom(r);
      if (id == null) return null;

      final flexColumns = r['flexColumns'];
      if (flexColumns is! List || flexColumns.isEmpty) return null;

      String title = '';
      if (flexColumns.isNotEmpty) {
        title = _runsText(flexColumns[0]
            ?['musicResponsiveListItemFlexColumnRenderer']?['text']);
      }
      if (title.isEmpty) return null;

      String subtitle = '';
      if (flexColumns.length > 1) {
        subtitle = _runsText(flexColumns[1]
            ?['musicResponsiveListItemFlexColumnRenderer']?['text']);
      }

      final thumb = _thumbFrom(r['thumbnail']?['musicThumbnailRenderer']
          ?['thumbnail']?['thumbnails']);
      if (thumb == null) return null;

      final type = _typeFromSubtitle(subtitle, id);
      final meta = _metadataFromSubtitle(subtitle);
      return HomeItem(
        id: id,
        videoId: type == HomeContentType.song ? id : null,
        browseId: type == HomeContentType.song ? null : id,
        title: title,
        subtitle: subtitle,
        artworkUrl: thumb,
        contentType: type,
        artists: meta.artists,
        publishedText: meta.publishedText,
        playability: type == HomeContentType.song
            ? Playability.playable
            : Playability.unknown,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('YTMHomeSource: responsive item failed: $e');
      return null;
    }
  }

  static HomeItem? _itemFromTwoRow(Map<String, dynamic> r) {
    try {
      final nav = r['navigationEndpoint'];
      final watch = nav?['watchEndpoint']?['videoId'];
      final browse = nav?['browseEndpoint']?['browseId'];
      final id = (watch is String && watch.isNotEmpty)
          ? watch
          : (browse is String && browse.isNotEmpty ? browse : null);
      if (id == null) return null;

      final title = _runsText(r['title']);
      if (title.isEmpty) return null;
      final subtitle = _runsText(r['subtitle']);

      final thumb = _thumbFrom(r['thumbnailRenderer']?['musicThumbnailRenderer']
              ?['thumbnail']?['thumbnails'] ??
          r['menu']?['menuRenderer']?['items']?[0]
              ?['menuNavigationItemRenderer']?['icon']);
      if (thumb == null) return null;

      // Two-row: type from explicit navigation shape.
      final isPlaylist = id.startsWith('PL') ||
          id.startsWith('VL') ||
          id.startsWith('OLAK') ||
          id.startsWith('MPREb');
      final isArtist = id.startsWith('UC');
      final type = isArtist
          ? HomeContentType.artist
          : (isPlaylist
              ? (subtitle.contains('Album') ||
                      id.startsWith('OLAK') ||
                      id.startsWith('MPREb')
                  ? HomeContentType.album
                  : HomeContentType.playlist)
              : HomeContentType.song);

      final meta = _metadataFromSubtitle(subtitle);
      return HomeItem(
        id: id,
        videoId: type == HomeContentType.song ? id : null,
        browseId: type == HomeContentType.song ? null : id,
        title: title,
        subtitle: subtitle,
        artworkUrl: thumb,
        contentType: type,
        artists: meta.artists,
        publishedText: meta.publishedText,
        playability: type == HomeContentType.song && watch != null
            ? Playability.playable
            : (type == HomeContentType.song
                ? Playability.notPlayable
                : Playability.unknown),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('YTMHomeSource: two-row item failed: $e');
      return null;
    }
  }

  /// Structured metadata from the subtitle's run segments (spec #27):
  /// "Arijit Singh • Brahmastra • 2024" → artists=[Arijit Singh],
  /// publishedText=2024. Run boundaries are semantic — never split a
  /// single concatenated string heuristically beyond these separators.
  static ({List<String> artists, String? publishedText}) _metadataFromSubtitle(
      String subtitle) {
    if (subtitle.isEmpty) return (artists: const [], publishedText: null);
    final segments = subtitle
        .split(RegExp(r'\s*[•·|]\s*'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final artists = <String>[];
    String? published;
    for (final seg in segments) {
      final yearMatch = RegExp(r'^(19|20)\d{2}$').firstMatch(seg);
      if (yearMatch != null) {
        published = seg;
      } else if (seg.toLowerCase().startsWith('album') ||
          seg.toLowerCase().startsWith('single') ||
          seg.toLowerCase().startsWith('ep') ||
          seg.toLowerCase().startsWith('video') ||
          seg.toLowerCase().startsWith('song') ||
          seg.toLowerCase().startsWith('playlist') ||
          seg.toLowerCase().startsWith('artist')) {
        continue; // type labels, not artists
      } else if (artists.length < 4) {
        artists.add(seg);
      }
    }
    return (artists: artists, publishedText: published);
  }

  /// Type derivation from actual identity — ID prefix first, subtitle hint
  /// second. Never from image dimensions.
  static HomeContentType _typeFromSubtitle(String subtitle, String id) {
    if (id.startsWith('UC')) return HomeContentType.artist;
    if (id.startsWith('PL') || id.startsWith('VL')) {
      return HomeContentType.playlist;
    }
    if (id.startsWith('OLAK') || id.startsWith('MPREb')) {
      return HomeContentType.album;
    }
    final lower = subtitle.toLowerCase();
    if (lower.startsWith('video')) return HomeContentType.video;
    if (lower.contains('single') || lower.contains('ep')) {
      return HomeContentType.album;
    }
    return HomeContentType.song;
  }

  static String _runsText(dynamic text) {
    if (text is! Map<String, dynamic>) return '';
    final simple = text['simpleText'];
    if (simple is String && simple.isNotEmpty) return simple;
    final runs = text['runs'];
    if (runs is! List) return '';
    final buffer = StringBuffer();
    for (final run in runs) {
      final t = run?['text'];
      if (t is String) buffer.write(t);
    }
    return buffer.toString();
  }
}

/// Fallback feed when the native Home surface fails: trusted sectioned
/// sources only (trending chart + new releases), real section semantics,
/// source order preserved. Never random searches, never shuffles.
class FallbackHomeSource {
  FallbackHomeSource(this._innerTube);

  final InnerTubeService _innerTube;

  Future<HomeFeed?> fetch() async {
    try {
      final trending = await _innerTube
          .getTrendingTracks(limit: 20)
          .timeout(const Duration(seconds: 12));
      final releases = await _innerTube
          .getNewReleases(limit: 12)
          .timeout(const Duration(seconds: 12));

      final sections = <HomeSection>[];
      if (trending.isNotEmpty) {
        sections.add(_sectionFromTracks(
          id: 'trending',
          title: 'Trending',
          tracks: trending,
          presentation: HomePresentation.artworkRail,
        ));
      }
      if (releases.isNotEmpty) {
        sections.add(_sectionFromTracks(
          id: 'new_releases',
          title: 'New releases',
          tracks: releases,
          presentation: HomePresentation.grid,
        ));
      }

      if (sections.isEmpty) return null;
      return HomeFeed(
        sections: sections,
        fetchedAt: DateTime.now(),
        source: 'fallback',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('FallbackHomeSource: fetch failed: $e');
      return null;
    }
  }

  static HomeSection _sectionFromTracks({
    required String id,
    required String title,
    required List<Track> tracks,
    required HomePresentation presentation,
  }) {
    final seen = <String>{};
    final items = <HomeItem>[];
    for (final t in tracks) {
      if (t.id.isEmpty || !seen.add(t.id)) continue;
      if (t.trackName.isEmpty || t.albumArtUrl.isEmpty) continue;
      items.add(HomeItem(
        id: t.id,
        videoId: t.id,
        title: t.trackName,
        subtitle: t.artistName,
        artworkUrl: t.albumArtUrl,
        contentType: HomeContentType.song,
      ));
      if (items.length >= 10) break;
    }
    return HomeSection(
        id: id, title: title, items: items, presentation: presentation);
  }
}

/// Cache + orchestration: stale-while-revalidate, schema-validated,
/// in-flight coalescing, exponential backoff on repeated failures.
/// Publishes one coherent snapshot — never partial updates.
///
/// Cache key binds to (schema, parserVersion, source, locale) — a feed
/// generated under one context is never reused under another.
class HomeRepository {
  HomeRepository({
    required YouTubeMusicHomeSource primary,
    required FallbackHomeSource fallback,
  })  : _primary = primary,
        _fallback = fallback;

  final YouTubeMusicHomeSource _primary;
  final FallbackHomeSource _fallback;

  static const _cachePrefix = 'home_feed_snapshot_v3';
  static const _freshTtl = Duration(minutes: 45);
  static const _maxBackoff = Duration(hours: 2);

  HomeFeed? _current;
  bool _loadedFromCache = false;
  Future<HomeFeed?>? _inFlight;
  int _failureCount = 0;
  DateTime _nextAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Current best feed (cache-first). Triggers background refresh when
  /// stale. Null until first load completes.
  HomeFeed? get current => _current;
  bool get isRefreshDue {
    if (_current == null) return true;
    return DateTime.now().difference(_current!.fetchedAt) > _freshTtl;
  }

  /// Cache key bound to the context the feed was generated under.
  static String _cacheKeyFor(String source, String locale) =>
      '${_cachePrefix}_${source}_$locale';

  static String _localeTag() => PlatformDispatcher.instance.locale.toString();

  /// Load: cache-first (immediate), then validate + refresh if due.
  /// Concurrent callers coalesce onto one request.
  Future<HomeFeed?> load() async {
    if (!_loadedFromCache) {
      _loadedFromCache = true;
      _current = await _readCache(source: _currentSourceTag());
      if (kDebugMode && _current != null) {
        debugPrint(
            'HomeRepository: cache hit (${_current!.sections.length} sections, '
            '${_current!.sections.fold<int>(0, (n, s) => n + s.items.length)} items, '
            'age=${DateTime.now().difference(_current!.fetchedAt).inMinutes}min, '
            'source=${_current!.source}, schema=$kHomeFeedSchemaVersion)');
      } else if (kDebugMode) {
        debugPrint('HomeRepository: cache miss — fetching fresh');
      }
    }
    if (_current == null || isRefreshDue) {
      // Don't await: UI renders cache immediately, refresh replaces when done.
      unawaited(refresh());
    }
    return _current;
  }

  /// Explicit refresh (pull-to-refresh). Coalesced, backoff-aware.
  Future<HomeFeed?> refresh() async {
    if (_inFlight != null) return _inFlight;
    if (DateTime.now().isBefore(_nextAttemptAt)) return _current;

    _inFlight = _fetchFresh().whenComplete(() => _inFlight = null);
    return _inFlight;
  }

  String _currentSourceTag() => 'primary';

  bool _primaryHasVisitor() => _primary.hasVisitorData;

  Future<HomeFeed?> _fetchFresh() async {
    try {
      final sw = Stopwatch()..start();
      // Primary → fallback. Never merge degraded sources.
      var feed = await _primary.fetch();
      String sourceTag = 'primary';
      if (feed == null) {
        feed = await _fallback.fetch();
        sourceTag = 'fallback';
        if (kDebugMode && feed != null) {
          debugPrint('HomeRepository: FALLBACK active (primary failed)');
        }
      }
      final requestMs = sw.elapsedMilliseconds;

      if (feed == null) {
        _failureCount++;
        _scheduleBackoff();
        if (kDebugMode) debugPrint('HomeRepository: all sources failed');
        return _current; // keep cached content
      }

      // Quality gate: a fresh feed must be structurally sane before it
      // replaces a known-good cache (spec: bad fresh data must not poison
      // good cache).
      if (!feedPassesQualityGate(feed)) {
        _failureCount++;
        _scheduleBackoff();
        if (kDebugMode) {
          debugPrint(
              'HomeRepository: fresh feed FAILED quality gate — keeping cache');
        }
        return _current;
      }

      _failureCount = 0;
      _current = feed;
      unawaited(_writeCache(feed, sourceTag));
      HomeDiagnostics.logRequestContext(
        source: feed.source,
        clientName: 'WEB_REMIX',
        clientVersion: 'dynamic (1.YYYYMMDD.01.00)',
        hl: PlatformDispatcher.instance.locale.languageCode,
        hasVisitorId: _primaryHasVisitor(),
        hasSignatureTimestamp: true,
      );
      HomeDiagnostics.logFeedReport(
        feed: feed,
        cacheHit: false,
        requestMs: requestMs,
        fallbackActive: sourceTag == 'fallback',
      );
      HomeDiagnostics.logProvenance(feed);
      if (kDebugMode) {
        final items = feed.sections.fold<int>(0, (n, s) => n + s.items.length);
        debugPrint(
            'HomeRepository: fresh feed source=${feed.source} sections=${feed.sections.length} '
            'items=$items requestMs=$requestMs quality=${HomeDiagnostics.qualityDimensions(feed)}');
      }
      return feed;
    } catch (e) {
      _failureCount++;
      _scheduleBackoff();
      if (kDebugMode) debugPrint('HomeRepository: refresh error: $e');
      return _current;
    }
  }

  /// Structural sanity: ≥2 sections, ≥1 item per section already enforced
  /// by the parser; here we guard against catastrophic regressions.
  static bool feedPassesQualityGate(HomeFeed feed) {
    if (feed.sections.isEmpty) return false;
    if (feed.sections.length < 2) return false;
    final items = feed.sections.fold<int>(0, (n, s) => n + s.items.length);
    if (items < 4) return false;
    // Every section must have a non-empty title and ≥2 items.
    for (final s in feed.sections) {
      if (s.title.isEmpty || s.items.length < 2) return false;
    }
    return true;
  }

  void _scheduleBackoff() {
    final seconds = (30 * (1 << _failureCount.clamp(0, 7))) +
        DateTime.now().millisecondsSinceEpoch % 1000;
    final delay = Duration(seconds: seconds);
    _nextAttemptAt =
        DateTime.now().add(delay > _maxBackoff ? _maxBackoff : delay);
  }

  Future<HomeFeed?> _readCache({required String source}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _cacheKeyFor(source, _localeTag());
      final raw = prefs.getString(key);
      if (raw == null) return null;
      // Defensive: corrupt cache must not crash Home.
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return HomeFeed.fromJson(json);
    } catch (e) {
      if (kDebugMode) debugPrint('HomeRepository: cache read failed: $e');
      return null;
    }
  }

  Future<void> _writeCache(HomeFeed feed, String source) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _cacheKeyFor(source, _localeTag()), jsonEncode(feed.toJson()));
    } catch (e) {
      if (kDebugMode) debugPrint('HomeRepository: cache write failed: $e');
    }
  }

  /// Dev-only: clear Home cache without touching anything else.
  Future<void> clearHomeCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_cachePrefix)) await prefs.remove(key);
    }
    _current = null;
    _loadedFromCache = false;
    _failureCount = 0;
    _nextAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
