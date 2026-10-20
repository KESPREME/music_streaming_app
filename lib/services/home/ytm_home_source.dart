import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/track.dart';
import '../auth_service.dart';
import '../innertube/innertube_service.dart';
import 'home_convergence.dart';
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

  Future<HomeFeed?> fetch({int perShelfLimit = 12}) async {
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
  Future<HomeFeed?> parseResponse(Map<String, dynamic> data,
          {int perShelfLimit = 12}) =>
      _parse(data, perShelfLimit);

  ParseReport? lastReport;

  Future<HomeFeed?> _parse(Map<String, dynamic> data, int perShelfLimit) async {
    try {
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
      return await _parseSectionList(root, perShelfLimit);
    } catch (e) {
      if (kDebugMode) debugPrint('YTMHomeSource: parse error: $e');
      return null;
    }
  }

  Future<HomeFeed?> _parseSectionList(
      Map<String, dynamic> root, int perShelfLimit) async {
    try {
      final sections = <HomeSection>[];

      // ── Stage A: discovery ───────────────────────────────────────────────
      // Walk every node under the section list; collect candidate shelves
      // with their JSON paths. Handles both flat carousel layouts and
      // musicSectionListRenderer-wrapped nested groups (chip-filtered
      // Home surfaces), which the previous walker silently dropped.
      //
      // Continuation: Metrolist parity — Home continuation lives on the
      // sectionListRenderer itself (sectionList.continuations), not inside
      // shelf contents.
      final candidates = <_ShelfCandidate>[];
      String? continuationToken = _continuationOf(root);
      if (continuationToken != null && kDebugMode) {
        debugPrint(
            'YTMHomeSource: sectionList continuation available (${continuationToken.length} chars)');
      }
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
      var rawTotal = 0,
          retainedTotal = 0,
          rejectedTotal = 0,
          dupTotal = 0,
          partialTotal = 0;
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
        var rejected = 0, dupes = 0, partial = 0;

        for (final wrapper in carousel) {
          if (items.length >= perShelfLimit) {
            // Per-shelf render budget (spec #12): the remainder is an
            // accounted trim, NOT silent loss — the invariant
            // raw = retained + rejected + dupes must hold.
            rejected++;
            reasons.add('per-shelf budget trim (>$perShelfLimit items)');
            continue;
          }
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
          // Spec #8: shelf failure must not destroy the section — a shelf
          // with 10 raw / 7 full / 2 partial / 1 unsupported yields 9
          // renderable items, not 0.
          if (item.supportLevel == SupportLevel.partiallySupported ||
              item.artworkUrl.isEmpty) {
            partial++;
          }
          items.add(item);
        }

        final rawCount = carousel.length;
        rawTotal += rawCount;
        retainedTotal += items.length;
        rejectedTotal += rejected;
        dupTotal += dupes;
        partialTotal += partial;

        if (items.length >= 2) {
          parsed++;
          final section = HomeSection(
            id: _sectionId(title, items),
            title: title,
            items: items,
            presentation: _presentationFor(items),
            sourcePath: candidate.path,
            renderer: candidate.renderer,
            sourceSubtitle: _straplineOf(shelf['header']),
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
            partialItemCount: partial,
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
            partialItemCount: partial,
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
        partialItems: partialTotal,
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

  /// Metrolist parity: Home continuation token sits on the
  /// sectionListRenderer (`continuations[0].nextContinuationData.
  /// continuation`).
  static String? _continuationOf(Map<String, dynamic> sectionList) {
    final conts = sectionList['continuations'];
    if (conts is! List || conts.isEmpty) return null;
    final first = conts.first;
    if (first is! Map<String, dynamic>) return null;
    final token = first['nextContinuationData']?['continuation'] as String?;
    return (token != null && token.isNotEmpty) ? token : null;
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

  /// The grey line YouTube Music runs with a shelf heading ("Similar to",
  /// "From the community"): `musicCarouselShelfBasicHeaderRenderer.strapline`.
  /// Shown under the title, as BitChord does.
  static String? _straplineOf(dynamic header) {
    if (header is! Map<String, dynamic>) return null;
    final r = header['musicCarouselShelfBasicHeaderRenderer'];
    if (r is! Map<String, dynamic>) return null;
    final text = _runsText(r['strapline']).trim();
    return text.isEmpty ? null : text;
  }

  /// Next page of Home shelves after [token] (the section list's
  /// continuation). Same parser, same accounting; [lastReport] keeps
  /// describing the first page.
  Future<HomeFeed?> fetchMore(String token, {int perShelfLimit = 12}) async {
    try {
      final data = await _innerTube
          .browseContinuationJson(token)
          .timeout(const Duration(seconds: 12));
      return await parseContinuation(data, perShelfLimit: perShelfLimit);
    } catch (e) {
      if (kDebugMode) debugPrint('YTMHomeSource: fetchMore failed: $e');
      return null;
    }
  }

  /// Testable continuation parse (no network). Handles the classic
  /// `continuationContents.sectionListContinuation` page and the newer
  /// `onResponseReceivedActions[].appendContinuationItemsAction` shape.
  Future<HomeFeed?> parseContinuation(Map<String, dynamic> data,
      {int perShelfLimit = 12}) async {
    final root = continuationRootOf(data);
    if (root == null) return null;
    final firstPage = lastReport;
    try {
      return await _parseSectionList(root, perShelfLimit);
    } finally {
      lastReport = firstPage;
    }
  }

  @visibleForTesting
  static Map<String, dynamic>? continuationRootOf(Map<String, dynamic> data) {
    final classic = data['continuationContents']?['sectionListContinuation'];
    if (classic is Map<String, dynamic>) return classic;
    final actions = data['onResponseReceivedActions'];
    if (actions is List) {
      for (final a in actions) {
        if (a is! Map<String, dynamic>) continue;
        final append = a['appendContinuationItemsAction'];
        final items =
            append is Map<String, dynamic> ? append['continuationItems'] : null;
        if (items is List) return {'contents': items};
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

      final thumbs = _thumbsFrom(r['thumbnail']?['musicThumbnailRenderer']
          ?['thumbnail']?['thumbnails']);
      // Tolerance (spec #8): missing artwork retains the item as PARTIAL
      // (placeholder render) — artwork alone never kills valid identity.
      if (thumbs.isEmpty) {
        final type = _typeFromSubtitle(subtitle, id);
        final meta = _metadataFromSubtitle(subtitle);
        return HomeItem(
          id: id,
          videoId: type == HomeContentType.song ? id : null,
          browseId: type == HomeContentType.song ? null : id,
          title: title,
          subtitle: subtitle,
          artworkUrl: '',
          contentType: type,
          artists: meta.artists,
          publishedText: meta.publishedText,
          supportLevel: SupportLevel.partiallySupported,
        );
      }

      final type = _typeFromSubtitle(subtitle, id);
      final meta = _metadataFromSubtitle(subtitle);
      return HomeItem(
        id: id,
        videoId: type == HomeContentType.song ? id : null,
        browseId: type == HomeContentType.song ? null : id,
        title: title,
        subtitle: subtitle,
        artworkUrl: thumbs.last.url,
        contentType: type,
        artists: meta.artists,
        publishedText: meta.publishedText,
        playability: type == HomeContentType.song
            ? Playability.playable
            : Playability.unknown,
        supportLevel: SupportLevel.fullySupported,
        thumbnails: thumbs,
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

      final thumbs = _thumbsFrom(r['thumbnailRenderer']
              ?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] ??
          r['menu']?['menuRenderer']?['items']?[0]
              ?['menuNavigationItemRenderer']?['icon']);
      // Tolerance (spec #8): missing artwork → PARTIAL, not rejected.
      if (thumbs.isEmpty) {
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
          artworkUrl: '',
          contentType: type,
          artists: meta.artists,
          publishedText: meta.publishedText,
          supportLevel: SupportLevel.partiallySupported,
        );
      }

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
        artworkUrl: thumbs.last.url,
        contentType: type,
        artists: meta.artists,
        publishedText: meta.publishedText,
        playability: type == HomeContentType.song && watch != null
            ? Playability.playable
            : (type == HomeContentType.song
                ? Playability.notPlayable
                : Playability.unknown),
        supportLevel: SupportLevel.fullySupported,
        thumbnails: thumbs,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('YTMHomeSource: two-row item failed: $e');
      return null;
    }
  }

  /// ALL thumbnail variants with dimensions (spec #6) — presentation picks
  /// the right one; the parser never hardcodes a single resolution.
  static List<HomeThumb> _thumbsFrom(dynamic thumbnails) {
    if (thumbnails is! List) return const [];
    final out = <HomeThumb>[];
    for (final t in thumbnails) {
      if (t is! Map<String, dynamic>) continue;
      final url = t['url'];
      if (url is! String || url.isEmpty) continue;
      out.add(HomeThumb(
        url: url.contains('googleusercontent.com')
            ? url.replaceAll(RegExp(r'=w\d+-h\d+.*$'), '=w544-h544')
            : url,
        width: t['width'] is int ? t['width'] as int : null,
        height: t['height'] is int ? t['height'] as int : null,
      ));
    }
    return out;
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
      } else if (
          // Live bug: durations ("3:44") and view counts ("106M plays")
          // leaked into artist lists ("Tame Impala, Deadbeat, 3:44").
          RegExp(r'^\d{1,3}:\d{2}(:\d{2})?$').hasMatch(seg) ||
              RegExp(
                r'^[\d,.]+\s*[KMB]?\s*(plays?|views?|streams?|listeners?|monthly listeners?)$',
                caseSensitive: false,
              ).hasMatch(seg)) {
        continue; // metadata, not artists
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
        sections.add(sectionFromTracks(
          id: 'trending',
          title: 'Trending',
          tracks: trending,
          presentation: HomePresentation.artworkRail,
        ));
      }
      if (releases.isNotEmpty) {
        sections.add(sectionFromTracks(
          id: 'new_releases',
          title: 'New releases',
          tracks: releases,
          presentation: HomePresentation.grid,
          provenance: 'new_release',
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

  static HomeSection sectionFromTracks({
    required String id,
    required String title,
    required List<Track> tracks,
    required HomePresentation presentation,
    String provenance = 'chart',
  }) {
    final seen = <String>{};
    final items = <HomeItem>[];
    for (final t in tracks) {
      if (t.id.isEmpty || !seen.add(t.id)) continue;
      if (t.trackName.isEmpty) continue;

      // LIVE-RUN FIX: getNewReleases returns Track objects whose ids are
      // frequently MPREb album browse ids (or VL playlists). Classifying
      // them as songs with videoId=MPREb… produced the "Skipping
      // non-playable track" failures on every hero/grid tap. Identity
      // prefix decides the type here — exactly the parser discipline.
      final isAlbum = t.id.startsWith('MPREb') || t.id.startsWith('OLAK');
      final isPlaylist = t.id.startsWith('VL') || t.id.startsWith('PL');
      final isArtist = t.id.startsWith('UC');
      final isSong = !isAlbum && !isPlaylist && !isArtist && t.id.length == 11;

      items.add(HomeItem(
        id: t.id,
        videoId: isSong ? t.id : null,
        browseId: isSong ? null : t.id,
        title: t.trackName,
        subtitle: t.artistName,
        artworkUrl: t.albumArtUrl,
        contentType: isAlbum
            ? HomeContentType.album
            : isPlaylist
                ? HomeContentType.playlist
                : isArtist
                    ? HomeContentType.artist
                    : HomeContentType.song,
        supportLevel: t.albumArtUrl.isEmpty
            ? SupportLevel.partiallySupported
            : SupportLevel.fullySupported,
        playability: isSong ? Playability.playable : Playability.unknown,
      ));
      if (items.length >= 12) break;
    }
    return HomeSection(
        id: id,
        title: title,
        items: items,
        presentation: presentation,
        provenance: provenance);
  }
}

/// Cache + orchestration: stale-while-revalidate, schema-validated,
/// in-flight coalescing, exponential backoff, BEST-KNOWN-GOOD convergence,
/// bounded deterministic enrichment.
///
/// Convergence (spec #9/#10/#22): upstream Home genuinely varies between
/// requests. The repository tracks a HIGH-WATER MARK feed (largest past
/// accepted feed), not merely the latest accepted one — otherwise each
/// reload just above the degradation threshold re-accepts a thinner feed
/// and the UI ratchets 10→6→4→3→2 shelves. Thin-but-valid fresh feeds are
/// ENRICHED with deterministic chart/new-release sections (provenance
/// stamped), never fabricated labels.
class HomeRepository {
  HomeRepository({
    required YouTubeMusicHomeSource primary,
    required FallbackHomeSource fallback,
  })  : _primary = primary,
        _fallback = fallback;

  final YouTubeMusicHomeSource _primary;
  final FallbackHomeSource _fallback;

  static const _cachePrefix = 'home_feed_snapshot_v5';
  static const _freshTtl = Duration(minutes: 45);
  static const _maxBackoff = Duration(hours: 2);

  /// Enrichment floor (spec #11): a native feed below this section count
  /// is "sparse" — bounded enrichment applies. Above it, native order is
  /// authoritative and nothing is added.
  static const _sparseFloorSections = 4;

  HomeFeed? _current;
  HomeFeed? _bestKnown;
  bool _loadedFromCache = false;
  Future<HomeFeed?>? _inFlight;
  int _failureCount = 0;
  DateTime _nextAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Set once the first network fetch for this process has run to completion,
  /// whether it produced a feed or not. Drives the cold-start placeholder and
  /// the exhausted state above.
  bool _firstFetchSettled = false;

  /// Section memory (spec #3): identity → last-known-good shelf. Populated
  /// from every ACCEPTED feed; consulted by HomeConvergence when a fresh
  /// response omits previously valid categories.
  final Map<String, SectionMemoryEntry> _sectionMemory = {};
  void _rememberSections(HomeFeed feed) {
    for (final s in feed.sections) {
      _sectionMemory[SectionIdentity.forSection(s)] = SectionMemoryEntry(
          section: s,
          identity: SectionIdentity.forSection(s),
          cachedAt: DateTime.now());
    }
    // Drop expired entries so the map cannot grow unbounded.
    _sectionMemory.removeWhere((_, e) =>
        DateTime.now().difference(e.cachedAt) >
        SectionMemoryPolicy.ttlFor(e.section));
    unawaited(_persistMemory());
  }

  /// Persist section memory (spec #55): survives process death, so a cold
  /// start after force-stop retains category continuity. Schema-versioned.
  ///
  /// SCOPED TO WHO IS SIGNED IN, like the feed snapshot. It used to be one
  /// global key: memory is personalised (it pins which shelves exist and in what
  /// order), so after an account switch the previous account's shelves were
  /// restored from disk and merged into the new account's feed - Quick picks and
  /// Listen again from somebody else's history, standing in for shelves the new
  /// feed had not sent. The unscoped v1 key is deleted on first load.
  static const _memoryPrefix = 'home_section_memory';
  static const _legacyMemoryKey = 'home_section_memory_v1';

  static String memoryKeyFor(String identity) =>
      '${_memoryPrefix}_v2_$identity';

  Future<void> _persistMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = <String, dynamic>{
        'schema': 1,
        'entries': _sectionMemory.entries
            .map((e) => {
                  'id': e.key,
                  'at': e.value.cachedAt.millisecondsSinceEpoch,
                  'section': e.value.section.toJson(),
                })
            .toList(),
      };
      await prefs.setString(memoryKeyFor(_identityTag()), jsonEncode(json));
    } catch (e) {
      if (kDebugMode) debugPrint('HomeRepository: memory persist failed: $e');
    }
  }

  Future<void> _loadMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Whose shelves the unscoped v1 memory held is unknowable. Drop it.
      if (prefs.containsKey(_legacyMemoryKey)) {
        await prefs.remove(_legacyMemoryKey);
      }
      final raw = prefs.getString(memoryKeyFor(_identityTag()));
      if (raw == null) return;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> || json['schema'] != 1) return;
      final entries = json['entries'] as List? ?? [];
      for (final e in entries) {
        if (e is! Map<String, dynamic>) continue;
        final id = e['id'] as String?;
        final at = e['at'] as int?;
        final sectionJson = e['section'];
        if (id == null || at == null || sectionJson == null) continue;
        final section = HomeSection.fromJson(sectionJson);
        if (!SectionMemoryPolicy.isRenderable(section)) continue;
        // TTL check on load: expired entries don't survive restart.
        final age =
            DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
        if (age > SectionMemoryPolicy.ttlFor(section)) continue;
        _sectionMemory[id] = SectionMemoryEntry(
          section: section,
          identity: id,
          cachedAt: DateTime.fromMillisecondsSinceEpoch(at),
        );
      }
      if (kDebugMode && _sectionMemory.isNotEmpty) {
        debugPrint(
            'HomeRepository: section memory restored (${_sectionMemory.length} entries)');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('HomeRepository: memory load failed: $e');
    }
  }

  HomeFeed? get current => _current;
  HomeFeed? get bestKnown => _bestKnown;
  bool get isRefreshDue {
    if (_current == null) return true;
    return DateTime.now().difference(_current!.fetchedAt) > _freshTtl;
  }

  /// Whether a first-page fetch has run to completion, successfully or not.
  ///
  /// Separate from `_current == null` because "we are still working on it" and
  /// "it is not coming" are different states, and a screen that cannot tell them
  /// apart has exactly two bad options: show a spinner forever, or show an empty
  /// page and pretend the work already failed.
  bool get hasSettledFirstFetch => _firstFetchSettled;

  /// True only while the very first load is in flight *and* there is nothing to
  /// show yet. This is the one condition under which a loading placeholder is
  /// honest.
  ///
  /// Deliberately false while a refresh runs against a cached feed: the content
  /// is already on screen, and flashing a skeleton over a good feed reads as the
  /// app throwing away work it had already done.
  bool get isColdStarting =>
      _current == null && _inFlight != null && !_firstFetchSettled;

/// The first load finished and still produced no feed at all.
///
/// A distinct state from "loading" on purpose, and the reason this is not
/// simply `!isColdStarting && _current == null`: an anonymous session that
/// gets no usable sections at all, or a request that failed, must land on a
/// retry the user can act on rather than on a shimmer that never resolves.
bool get isColdStartExhausted => _current == null && _firstFetchSettled;

  /// Completes once a first-page fetch has settled, or immediately if none is
  /// running.
  ///
  /// [load] deliberately does not block on the network - it returns whatever
  /// the cache held so a warm start paints instantly. That is the right call
  /// when there is something to paint, and the wrong one when there is not: a
  /// caller with an empty screen has no way to learn how the fetch ended.
  Future<void> awaitFirstFetchSettled() async {
    final pending = _inFlight;
    if (pending != null) await pending;
  }

  /// The cache key carries WHO the feed is for, not just where it came from.
  ///
  /// Without the identity a personalized snapshot saved while signed in is
  /// served to the next anonymous launch - and, worse, signing out leaves the
  /// previous user's recommendations on screen. `anon` is a real bucket, not a
  /// special case that shares with a real account.
  static String _cacheKeyFor(String source, String locale) =>
      '${_cachePrefix}_${_identityTag()}_${source}_$locale';

  /// Tests set this to stand in for a signed-in account.
  @visibleForTesting
  static String? debugIdentity;

  static String _identityTag() {
    final forced = debugIdentity;
    if (forced != null) return forced;
    try {
      return AuthService().identityKey;
    } catch (_) {
      // Auth not initialized yet. Anonymous is the safe answer: it cannot leak
      // one identity's feed to another.
      return 'anon';
    }
  }

  static String _localeTag() => PlatformDispatcher.instance.locale.toString();

  Future<HomeFeed?> load() async {
    if (!_loadedFromCache) {
      _loadedFromCache = true;
      _current = await _readCache(source: 'primary');
      await _loadMemory();
      _bestKnown = _current;
      HomeLoadTrace.log(
        cacheRead: _current != null ? 'HIT' : 'MISS',
        cacheSections: _current?.sections.length ?? 0,
        cacheItems:
            _current?.sections.fold<int>(0, (n, s) => n + s.items.length) ?? 0,
        cacheAgeMin: _current == null
            ? null
            : DateTime.now().difference(_current!.fetchedAt).inMinutes,
      );
    }
    if (_current == null || isRefreshDue) {
      unawaited(refresh());
    }
    return _current;
  }

  /// Who the fetch in flight is for.
  String? _inFlightIdentity;

  Future<HomeFeed?> refresh() async {
    final identity = _identityTag();
    // Coalesce only with a fetch for the SAME person. A fetch begun before an
    // account switch carries the old account's feed; handing its result to the
    // new account (which is what returning it here did) put one person's
    // personalised shelves on another's Home.
    if (_inFlight != null && _inFlightIdentity == identity) return _inFlight;
    if (DateTime.now().isBefore(_nextAttemptAt)) return _current;

    _inFlightIdentity = identity;
    Future<HomeFeed?>? run;
    run = _fetchFresh(identity).whenComplete(() {
      // Only the fetch that is still THE fetch settles anything: a superseded
      // one finishing late must not clear its successor.
      if (identical(_inFlight, run)) {
        _inFlight = null;
        _firstFetchSettled = true;
      }
    });
    _inFlight = run;
    return run;
  }

  @visibleForTesting
  Future<void> rememberForTest(HomeFeed feed) async {
    _rememberSections(feed);
    await _persistMemory();
  }

  @visibleForTesting
  Future<void> loadMemoryForTest() => _loadMemory();

  @visibleForTesting
  Map<String, SectionMemoryEntry> get memoryForTest =>
      Map.unmodifiable(_sectionMemory);

  String get _currentSourceTag => 'primary';
  bool _primaryHasVisitor() => _primary.hasVisitorData;

  Future<HomeFeed?> _fetchFresh(String identity) async {
    try {
      final sw = Stopwatch()..start();
      var feed = await _primary.fetch();
      String sourceTag = 'primary';
      if (feed == null) {
        feed = await _fallback.fetch();
        sourceTag = 'fallback';
      }
      final requestMs = sw.elapsedMilliseconds;

      // The account changed while the request was out: this is somebody else's
      // Home. Remembering it, caching it, or showing it would be the leak.
      if (_identityTag() != identity) {
        HomeLoadTrace.log(
          decision: 'IDENTITY_CHANGED_DISCARD',
          requestMs: requestMs,
        );
        return _current;
      }

      if (feed == null) {
        _failureCount++;
        _scheduleBackoff();
        HomeLoadTrace.log(
          decision: 'ALL_SOURCES_FAILED_KEEP_CACHE',
          requestMs: requestMs,
          freshSections: 0,
          freshItems: 0,
        );
        return _current;
      }

      // Stamp native provenance on primary shelves (spec #30) before any
      // comparison/enrichment — provenance belongs to the parser boundary.
      if (sourceTag == 'primary') {
        feed = _withProvenance(feed, 'native');
      }

      // Convergence (spec #12): merge with section memory BEFORE gate/
      // degradation checks so a temporarily-omitted category doesn't make
      // the fresh candidate look artificially thin. Fresh sections always
      // win for their identity; remembered sections fill omissions.
      final previousOrder =
          _current?.sections.map(SectionIdentity.forSection).toList() ??
              const <String>[];
      feed = const HomeConvergence().convergeWithOrder(
          fresh: feed, memory: _sectionMemory, previousOrder: previousOrder);
      if (kDebugMode) {
        debugPrint(
            'HOME_LOAD convergedSections=${feed.sections.length} memory=${_sectionMemory.length}');
        // Section-level diff (spec #43): added/removed/retained/updated —
        // distinguishes content refresh from destructive structural change.
        final prevById = <String, HomeSection>{
          for (final s in (_current?.sections ?? const <HomeSection>[]))
            SectionIdentity.forSection(s): s,
        };
        final freshById = <String, HomeSection>{
          for (final s in feed.sections) SectionIdentity.forSection(s): s,
        };
        final added = freshById.keys.where((k) => !prevById.containsKey(k));
        final removed = prevById.keys.where((k) => !freshById.containsKey(k));
        final updated = freshById.keys.where((k) {
          final prev = prevById[k];
          if (prev == null) return false;
          return prev.items.map((i) => i.id).join(',') !=
              freshById[k]!.items.map((i) => i.id).join(',');
        });
        debugPrint('HOME_DIFF added=${added.length} '
            'removed=${removed.length} retained=${freshById.length - updated.length} '
            'updated=${updated.length}');
        if (removed.isNotEmpty) {
          debugPrint('HOME_DIFF removedShelves=${removed.take(4).toList()}');
        }
      }

      if (!feedPassesQualityGate(feed)) {
        _failureCount++;
        _scheduleBackoff();
        HomeLoadTrace.log(
          decision: 'FAILED_QUALITY_GATE_KEEP_CACHE',
          requestMs: requestMs,
          freshSections: feed.sections.length,
          freshItems: feed.sections.fold<int>(0, (n, s) => n + s.items.length),
        );
        return _current;
      }

      // Best-known-good (spec #22): compare against the HIGH-WATER MARK,
      // not the latest accepted feed — the degradation ratchet is what
      // made reloads collapse a rich Home to 2 shelves.
      if (HomeDiagnostics.isDegraded(previous: _bestKnown, next: feed)) {
        _failureCount++;
        _scheduleBackoff();
        // Spec #31 Priority 2: keep the rich feed visible AND still try to
        // serve fresh value by enriching the thin native response for the
        // NEXT attempt only if enrichment would bring it above the floor.
        final enriched = await _enrichSparse(feed);
        if (enriched != null &&
            enriched.sections.length >= _bestKnown!.sections.length / 2) {
          _current = enriched;
          HomeLoadTrace.log(
            decision: 'DEGRADED_BUT_ENRICHED_TO_FLOOR',
            requestMs: requestMs,
            freshSections: feed.sections.length,
            freshItems:
                feed.sections.fold<int>(0, (n, s) => n + s.items.length),
            outputSections: enriched.sections.length,
            outputItems:
                enriched.sections.fold<int>(0, (n, s) => n + s.items.length),
          );
          return enriched;
        }
        HomeLoadTrace.log(
          decision: 'DEGRADED_KEEP_BEST_KNOWN',
          requestMs: requestMs,
          freshSections: feed.sections.length,
          freshItems: feed.sections.fold<int>(0, (n, s) => n + s.items.length),
          bestKnownSections: _bestKnown!.sections.length,
          bestKnownItems:
              _bestKnown!.sections.fold<int>(0, (n, s) => n + s.items.length),
        );
        return _current;
      }

      // Accepted. Track high-water mark.
      _failureCount = 0;
      final acceptedItems =
          feed.sections.fold<int>(0, (n, s) => n + s.items.length);
      final bestItems = _bestKnown?.sections
              .fold<int>(0, (n, s) => n + s.items.length ?? 0) ??
          0;
      if (_bestKnown == null || acceptedItems > bestItems) {
        _bestKnown = feed;
      }

      // Sparse-but-valid native feed → bounded enrichment (spec #30/#31):
      // deterministic chart/new-release sections appended, provenance
      // stamped, native shelves always first and untouched.
      if (feed.sections.length < _sparseFloorSections) {
        final enriched = await _enrichSparse(feed);
        if (enriched != null) feed = enriched;
      }

      // Section memory runs AFTER enrichment (live-run fix): enriched
      // shelves must be remembered too, otherwise the enriched section
      // gets dropped and re-added every refresh
      // (removedShelves=[new_release:...] in the runtime log).
      _rememberSections(feed);

      _current = feed;
      unawaited(_writeCache(feed, sourceTag));
      HomeLoadTrace.log(
        decision: feed == _bestKnown ? 'ACCEPTED_NEW_BEST' : 'ACCEPTED',
        requestMs: requestMs,
        freshSections: feed.sections.length,
        freshItems: feed.sections.fold<int>(0, (n, s) => n + s.items.length),
        bestKnownSections: _bestKnown?.sections.length,
        bestKnownItems:
            _bestKnown?.sections.fold<int>(0, (n, s) => n + s.items.length),
      );
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
      return feed;
    } catch (e) {
      _failureCount++;
      _scheduleBackoff();
      if (kDebugMode) debugPrint('HomeRepository: refresh error: $e');
      return _current;
    }
  }

  /// Bounded enrichment (spec #30/#31): native shelves first and untouched;
  /// deterministic chart + new-release shelves appended only when the feed
  /// is sparse; provenance stamped; never random searches; dedupe against
  /// native items so enrichment never duplicates what's already shown.
  Future<HomeFeed?> _enrichSparse(HomeFeed native) async {
    if (native.sections.length >= _sparseFloorSections) return null;
    final nativeIds =
        native.sections.expand((s) => s.items.map((i) => i.id)).toSet();

    final extra = <HomeSection>[];
    final innerTube = InnerTubeService.instance;
    try {
      final trending = await innerTube.getTrendingTracks(limit: 15);
      final fresh =
          trending.where((t) => nativeIds.add(t.id)).toList(growable: false);
      if (fresh.length >= 4) {
        extra.add(FallbackHomeSource.sectionFromTracks(
          id: 'trending_enriched',
          title: 'Trending',
          tracks: fresh,
          presentation: HomePresentation.artworkRail,
        ));
      }
    } catch (_) {}

    try {
      final releases = await innerTube.getNewReleases(limit: 12);
      final fresh =
          releases.where((t) => nativeIds.add(t.id)).toList(growable: false);
      if (fresh.length >= 4) {
        extra.add(FallbackHomeSource.sectionFromTracks(
          id: 'new_releases_enriched',
          title: 'New releases',
          tracks: fresh,
          presentation: HomePresentation.grid,
          provenance: 'new_release',
        ));
      }
    } catch (_) {}

    if (extra.isEmpty) return null;
    if (kDebugMode) {
      debugPrint(
          'HomeRepository: enriched sparse native feed (${native.sections.length} sections) '
          'with ${extra.length} deterministic sections');
    }
    return HomeFeed(
      sections: [...native.sections, ...extra],
      fetchedAt: native.fetchedAt,
      source: 'native+enriched',
      heroCandidate: native.heroCandidate,
      continuationToken: native.continuationToken,
    );
  }

  // Enrichment uses the single shared InnerTube instance — no second
  // Home pipeline (spec #28).

  HomeFeed _withProvenance(HomeFeed feed, String provenance) {
    return HomeFeed(
      sections: feed.sections
          .map((s) => HomeSection(
                id: s.id,
                title: s.title,
                items: s.items,
                presentation: s.presentation,
                sourcePath: s.sourcePath,
                renderer: s.renderer,
                sourceSubtitle: s.sourceSubtitle,
                provenance: s.provenance ?? provenance,
              ))
          .toList(),
      fetchedAt: feed.fetchedAt,
      source: feed.source,
      heroCandidate: feed.heroCandidate,
      continuationToken: feed.continuationToken,
    );
  }

  /// Structural sanity: ≥2 sections, ≥1 item per section already enforced
  /// by the parser; here we guard against catastrophic regressions.
  static bool feedPassesQualityGate(HomeFeed feed) {
    if (feed.sections.isEmpty) return false;
    if (feed.sections.length < 2) return false;
    final items = feed.sections.fold<int>(0, (n, s) => n + s.items.length);
    if (items < 4) return false;
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
      final key = _cacheKeyFor(_currentSourceTag, _localeTag());
      final raw = prefs.getString(key);
      if (raw == null) return null;
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
      await prefs.setString(_cacheKeyFor(_currentSourceTag, _localeTag()),
          jsonEncode(feed.toJson()));
    } catch (e) {
      if (kDebugMode) debugPrint('HomeRepository: cache write failed: $e');
    }
  }

  /// Dev-only: clear Home cache without touching anything else.
  Future<void> clearHomeCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      // The snapshot AND the memory, for every identity: this runs when who is
      // signed in changes, and neither may outlive that.
      if (key.startsWith(_cachePrefix) || key.startsWith(_memoryPrefix)) {
        await prefs.remove(key);
      }
    }
    _current = null;
    _bestKnown = null;
    _sectionMemory.clear();
    _loadedFromCache = false;
    _failureCount = 0;
    _nextAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// Compact end-of-load accounting (spec #37): one HOME_LOAD line per load,
/// HOME_LOSS lines only when something was actually lost.
class HomeLoadTrace {
  HomeLoadTrace._();

  static void log({
    String? decision,
    String? cacheRead,
    int? cacheSections,
    int? cacheItems,
    int? cacheAgeMin,
    int? requestMs,
    int? freshSections,
    int? freshItems,
    int? outputSections,
    int? outputItems,
    int? bestKnownSections,
    int? bestKnownItems,
  }) {
    if (!kDebugMode) return;
    final parts = <String>['HOME_LOAD'];
    if (decision != null) parts.add('decision=$decision');
    if (cacheRead != null) parts.add('cache=$cacheRead');
    if (cacheSections != null) parts.add('cacheSections=$cacheSections');
    if (cacheItems != null) parts.add('cacheItems=$cacheItems');
    if (cacheAgeMin != null) parts.add('cacheAgeMin=$cacheAgeMin');
    if (requestMs != null) parts.add('requestMs=$requestMs');
    if (freshSections != null) parts.add('freshSections=$freshSections');
    if (freshItems != null) parts.add('freshItems=$freshItems');
    if (outputSections != null) parts.add('outputSections=$outputSections');
    if (outputItems != null) parts.add('outputItems=$outputItems');
    if (bestKnownSections != null) {
      parts.add('bestKnownSections=$bestKnownSections');
    }
    if (bestKnownItems != null) parts.add('bestKnownItems=$bestKnownItems');
    debugPrint(parts.join(' '));
  }

  static void loss({
    required String stage,
    required String shelf,
    required String reason,
  }) {
    if (!kDebugMode) return;
    debugPrint('HOME_LOSS stage=$stage shelf="$shelf" reason="$reason"');
  }
}
