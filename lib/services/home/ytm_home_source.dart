import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/track.dart';
import '../innertube/innertube_service.dart';
import 'home_models.dart';

/// Native YouTube Music Home source (browseId = FEmusic_home).
///
/// Preserves shelf semantics: each musicCarouselShelfRenderer becomes one
/// [HomeSection] with its real title ("Quick picks", "Listen again", …).
/// Defensive parsing throughout — one malformed shelf or unknown renderer
/// is skipped, never crashes the feed.
class YouTubeMusicHomeSource {
  YouTubeMusicHomeSource(this._innerTube);

  final InnerTubeService _innerTube;

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

  Future<HomeFeed?> _parse(Map<String, dynamic> data, int perShelfLimit) async {
    try {
      final sections = <HomeSection>[];
      final contents = _findSectionList(data);
      if (contents == null) return null;

      for (final section in contents) {
        // Shelf header.
        final shelf = section['musicCarouselShelfRenderer'];
        if (shelf is! Map<String, dynamic>) {
          if (kDebugMode) {
            final kind =
                section.keys.where((k) => k.endsWith('Renderer')).join(',');
            if (kind.isNotEmpty) {
              debugPrint('YTMHomeSource: ignored renderer: $kind');
            }
          }
          continue;
        }

        final title = _headerText(shelf['header']);
        if (title == null || title.isEmpty) continue;

        final items = <HomeItem>[];
        final seenIds = <String>{};
        final carousel = shelf['contents'];
        if (carousel is! List) continue;

        for (final wrapper in carousel) {
          if (items.length >= perShelfLimit) break;

          final responsive = wrapper['musicResponsiveListItemRenderer'];
          if (responsive is Map<String, dynamic>) {
            final item = _itemFromResponsive(responsive);
            if (item != null && seenIds.add(item.id)) items.add(item);
            continue;
          }

          final twoRow = wrapper['musicTwoRowItemRenderer'];
          if (twoRow is Map<String, dynamic>) {
            final item = _itemFromTwoRow(twoRow);
            if (item != null && seenIds.add(item.id)) items.add(item);
            continue;
          }

          if (kDebugMode) {
            final kinds =
                wrapper.keys.where((k) => k.endsWith('Renderer')).join(',');
            if (kinds.isNotEmpty) {
              debugPrint('YTMHomeSource: unknown item renderer: $kinds');
            }
          }
        }

        if (items.length >= 2) {
          sections.add(HomeSection(
            id: _sectionId(title, items),
            title: title,
            items: items,
            presentation: _presentationFor(items),
          ));
        }
      }

      if (sections.isEmpty) return null;
      return HomeFeed(
        sections: sections,
        fetchedAt: DateTime.now(),
        source: 'ytm_home',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('YTMHomeSource: parse error: $e');
      return null;
    }
  }

  /// Walks toward sectionListRenderer.contents defensively — the Home
  /// response shape varies between tabs/shelf arrangements.
  static List? _findSectionList(Map<String, dynamic> data) {
    final tabs =
        data['contents']?['singleColumnBrowseResultsRenderer']?['tabs'];
    if (tabs is! List || tabs.isEmpty) return null;
    return tabs[0]?['tabRenderer']?['content']?['sectionListRenderer']
        ?['contents'];
  }

  static String? _headerText(dynamic header) {
    if (header is! Map<String, dynamic>) return null;
    final r = header['musicCarouselShelfBasicHeaderRenderer'];
    if (r is! Map<String, dynamic>) return null;
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
      return HomeItem(
        id: id,
        videoId: type == HomeContentType.song ? id : null,
        browseId: type == HomeContentType.song ? null : id,
        title: title,
        subtitle: subtitle,
        artworkUrl: thumb,
        contentType: type,
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

      return HomeItem(
        id: id,
        videoId: type == HomeContentType.song ? id : null,
        browseId: type == HomeContentType.song ? null : id,
        title: title,
        subtitle: subtitle,
        artworkUrl: thumb,
        contentType: type,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('YTMHomeSource: two-row item failed: $e');
      return null;
    }
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
class HomeRepository {
  HomeRepository({
    required YouTubeMusicHomeSource primary,
    required FallbackHomeSource fallback,
  })  : _primary = primary,
        _fallback = fallback;

  final YouTubeMusicHomeSource _primary;
  final FallbackHomeSource _fallback;

  static const _cacheKey = 'home_feed_snapshot_v1';
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

  /// Load: cache-first (immediate), then validate + refresh if due.
  /// Concurrent callers coalesce onto one request.
  Future<HomeFeed?> load() async {
    if (!_loadedFromCache) {
      _loadedFromCache = true;
      _current = await _readCache();
      if (kDebugMode && _current != null) {
        debugPrint(
            'HomeRepository: cache hit (${_current!.sections.length} sections)');
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

  Future<HomeFeed?> _fetchFresh() async {
    try {
      // Primary → fallback. Never merge degraded sources.
      var feed = await _primary.fetch();
      if (feed == null) {
        feed = await _fallback.fetch();
      }
      if (feed == null) {
        _failureCount++;
        _scheduleBackoff();
        if (kDebugMode) debugPrint('HomeRepository: all sources failed');
        return _current; // keep cached content
      }
      _failureCount = 0;
      _current = feed;
      unawaited(_writeCache(feed));
      if (kDebugMode) {
        debugPrint(
            'HomeRepository: fresh feed (${feed.source}, ${feed.sections.length} sections, '
            '${feed.sections.fold<int>(0, (n, s) => n + s.items.length)} items)');
      }
      return feed;
    } catch (e) {
      _failureCount++;
      _scheduleBackoff();
      if (kDebugMode) debugPrint('HomeRepository: refresh error: $e');
      return _current;
    }
  }

  void _scheduleBackoff() {
    final seconds = (30 * (1 << _failureCount.clamp(0, 7))) +
        DateTime.now().millisecondsSinceEpoch % 1000;
    final delay = Duration(seconds: seconds);
    _nextAttemptAt =
        DateTime.now().add(delay > _maxBackoff ? _maxBackoff : delay);
  }

  Future<HomeFeed?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
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

  Future<void> _writeCache(HomeFeed feed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(feed.toJson()));
    } catch (e) {
      if (kDebugMode) debugPrint('HomeRepository: cache write failed: $e');
    }
  }
}
