import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_exp;
import '../auth_service.dart';
import '../../models/track.dart';
import '../../models/discover_models.dart';
import '../potoken/po_token_webview.dart';
import '../../models/album.dart';
import '../metadata/track_metadata_enricher.dart';
import '../../models/bitchord_page_models.dart';

/// YouTube client types for different use cases
enum YouTubeClientType {
  webRemix, // For search and browse
  visionos, // Player (Vision Pro client, id 101 — token-free, Muzza's primary)
  androidVr, // Player (bot-gated Aug 2026, kept as fallback)
  tvEmbedded, // Player fallback
  ios, // Resolves but URLs may 403 (not in ladder)
}

/// InnerTube API client for YouTube Music

class InnerTubeService {
  InnerTubeService._internal();
  factory InnerTubeService() => instance;
  static final InnerTubeService instance = InnerTubeService._internal();

  static const String _apiUrl = 'https://music.youtube.com/youtubei/v1';
  static const String _origin = 'https://music.youtube.com';
  static const String _referer = 'https://music.youtube.com/';

  // WEB_REMIX client (for search, browse)
  static const String _webRemixClientName = 'WEB_REMIX';
  // innertubex v0.1.2 parity (Metrolist's working pin, July 2026).
  static const String _webRemixClientVersion = '1.20260707.12.00';
  static const String _webRemixClientId = '67';
  static const String _webRemixUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';

  // ANDROID_VR client — the only InnerTube client that still serves
  // direct signed stream URLs without a PO token (verified Feb 2026).
  // Bump clientVersion + UA together when playback starts failing.
  // Ref: https://github.com/Tyrrrz/YoutubeExplode/pull/936
  // NOTE: client versions rotate as YouTube bot-gates old ones. If playback
  // dies with LOGIN_REQUIRED, bump these (1.60.19 died Aug 2026).
  // 1.65.10 + 1.43.32 are Metrolist's current pins (fallback ladder).
  static const String _androidVrClientName = 'ANDROID_VR';
  static const String _androidVrClientVersion = '1.65.10';
  static const String _androidVrClientId = '28';
  static const String _androidVrUserAgent =
      'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; Quest 3 Build/SQ3A.220605.009.A1) gzip';

  // iOS client (Fallback)
  static const String _iosClientName = 'IOS';
  static const String _iosClientVersion = '20.51.39';
  static const String _iosClientId = '5';
  static const String _iosUserAgent =
      'com.google.ios.youtube/20.51.39 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)';

  // TV client — yt-dlp's current PO-token-free playback workhorse.
  static const String _tvClientName = 'TVHTML5';
  static const String _tvClientVersion = '7.20250312.16.00';
  static const String _tvClientId = '7';
  static const String _tvUserAgent =
      'Mozilla/5.0 (ChromiumStyle) Sony/BDP/1.0 CE-HTML; smartTV';

  /// Pick the stream User-Agent matching the client that signed [url].
  /// googlevideo enforces UA/client consistency on full playback.
  static String? userAgentForStreamUrl(String url) {
    if (url.contains('c=IOS')) return _iosUserAgent;
    if (url.contains('c=ANDROID_VR')) return _androidVrUserAgent;
    if (url.contains('c=ANDROID')) {
      return 'com.google.android.youtube/17.31.35 (Linux; U; Android 11) gzip';
    }
    if (url.contains('c=WEB_REMIX')) return _webRemixUserAgent;
    if (url.contains('c=TVHTML5')) return _tvUserAgent;
    return null;
  }

  String? visitorData;
  String? cookie;

  final http.Client _httpClient = http.Client();

  static const Duration _cacheDuration = Duration(minutes: 30);

  /// Browse-response memoization: TTL cache + in-flight coalescing, so
  /// Discover tabs that mount simultaneously share one network round trip.
  final Map<String, _CachedBrowseEntry> _browseCache = {};
  final Map<String, Future<Object?>> _browseInFlight = {};

  Future<T> _cachedBrowse<T>(
    String key,
    Future<T> Function() fetch, {
    Duration ttl = _cacheDuration,
  }) async {
    final cached = _browseCache[key];
    if (cached != null && !cached.isExpired(ttl)) {
      return cached.value as T;
    }
    final inFlight = _browseInFlight[key];
    if (inFlight != null) {
      return inFlight as Future<T>;
    }
    final future = fetch().then((value) {
      _browseCache[key] = _CachedBrowseEntry(value);
      return value;
    }).whenComplete(() {
      _browseInFlight.remove(key); // block body: must not return a Future
    });
    // Store before awaiting so concurrent callers coalesce onto this future.
    _browseInFlight[key] = future;
    return future;
  }

  /// Build the context object required for all InnerTube requests
  Map<String, dynamic> _buildContext(
      {YouTubeClientType clientType = YouTubeClientType.webRemix}) {
    switch (clientType) {
      case YouTubeClientType.visionos:
        // Muzza-parity: Vision Pro client (id 101) — token-free, login-free.
        return {
          'client': {
            'clientName': 'VISIONOS',
            'clientVersion': '0.1',
            'osName': 'visionOS',
            'osVersion': '1.3.21O771',
            'deviceMake': 'Apple',
            'deviceModel': 'RealityDevice14,1',
            'hl': 'en',
            'gl': 'US',
          },
        };
      case YouTubeClientType.androidVr:
        return {
          'client': {
            'clientName': _androidVrClientName,
            'clientVersion': _androidVrClientVersion,
            'osName': 'Android',
            'osVersion': '12',
            'deviceMake': 'Oculus',
            'deviceModel': 'Quest 3',
            'androidSdkVersion': '32',
            'hl': 'en',
            'gl': 'US',
          },
        };
      case YouTubeClientType.tvEmbedded:
        return {
          'client': {
            'clientName': _tvClientName,
            'clientVersion': _tvClientVersion,
            'hl': 'en',
            'gl': 'US',
          },
        };
      case YouTubeClientType.ios:
        return {
          'client': {
            'clientName': _iosClientName,
            'clientVersion': _iosClientVersion,
            'osVersion': '18.2.22C152',
            'hl': 'en',
            'gl': 'US',
          },
        };
      case YouTubeClientType.webRemix:
        return {
          'client': {
            'clientName': _webRemixClientName,
            'clientVersion': _webRemixClientVersion,
            'hl': 'en',
            'gl': 'US',
            'platform': 'DESKTOP',
          },
        };
    }
  }

  /// Build headers for InnerTube requests
  Map<String, String> _buildHeaders(
      {YouTubeClientType clientType = YouTubeClientType.webRemix}) {
    String userAgent;
    String clientId;
    String clientVersion;

    switch (clientType) {
      case YouTubeClientType.visionos:
        userAgent =
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
        clientId = '101';
        clientVersion = '0.1';
        break;
      case YouTubeClientType.androidVr:
        userAgent = _androidVrUserAgent;
        clientId = _androidVrClientId;
        clientVersion = _androidVrClientVersion;
        break;
      case YouTubeClientType.tvEmbedded:
        userAgent = _tvUserAgent;
        clientId = _tvClientId;
        clientVersion = _tvClientVersion;
        break;
      case YouTubeClientType.ios:
        userAgent = _iosUserAgent;
        clientId = _iosClientId;
        clientVersion = _iosClientVersion;
        break;
      case YouTubeClientType.webRemix:
        userAgent = _webRemixUserAgent;
        clientId = _webRemixClientId;
        clientVersion = _webRemixClientVersion;
        break;
    }

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Accept-Language': 'en-US,en;q=0.9',
      'X-Goog-Api-Format-Version': '1',
      'X-YouTube-Client-Name': clientId,
      'X-YouTube-Client-Version': clientVersion,
      'X-Origin': _origin,
      'Referer': _referer,
      'Origin': _origin,
      'User-Agent': userAgent,
    };

    if (visitorData != null) {
      headers['X-Goog-Visitor-Id'] = visitorData!;
    }

    // Muzo parity: anonymous requests carry a consent cookie; without it
    // google can serve an EU-consent-gated degraded surface.
    // Login-bound headers (Cookie + SAPISIDHASH) attach ONLY to the
    // session-bound webRemix client. The fallback ladder (visionos /
    // androidVr / tvEmbedded) is documented token-free/login-free — sending
    // login cookies there gets player 400s while browse keeps working.
    final sessionHeaders = InnerTubeService.sessionHeadersFor(
      clientType,
      AuthService().getHeaders(),
    );
    if (sessionHeaders.isNotEmpty) {
      headers.addAll(sessionHeaders);
    } else if (cookie != null && clientType == YouTubeClientType.webRemix) {
      // Legacy/Manual cookie fallback (if AuthService specific logic not used)
      headers['Cookie'] = cookie!;
    } else {
      headers['Cookie'] = 'CONSENT=YES+1';
    }

    return headers;
  }

  /// Pure auth-attach policy (unit-testable seam): session-bound clients
  /// get the login headers; login-free ladder clients never do, so a
  /// logged-in request degrades to exactly the anonymous ladder behavior.
  @visibleForTesting
  static Map<String, String> sessionHeadersFor(
    YouTubeClientType clientType,
    Map<String, String> authHeaders,
  ) {
    if (clientType == YouTubeClientType.webRemix) return authHeaders;
    return const {};
  }

  /// Search for artists
  Future<List<Track>> searchArtists(String query, {int limit = 20}) async {
    return _searchWithParams(
        query, 'EgWKAQIgAWoKEAkQBRAKEAMQBA%3D%3D', limit); // FILTER_ARTIST
  }

  /// Search for playlists
  Future<List<Track>> searchPlaylists(String query, {int limit = 20}) async {
    return _searchWithParams(
        query, 'EgWKAQIoAWoKEAkQBRAKEAMQBA%3D%3D', limit); // FILTER_PLAYLIST
  }

  Future<List<Track>> _searchWithParams(
      String query, String params, int limit) async {
    try {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Searching "$query" with params $params');
      }
      final body = jsonEncode({
        'context': _buildContext(clientType: YouTubeClientType.webRemix),
        'query': query,
        'params': params,
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/search?prettyPrint=false'),
        headers: _buildHeaders(clientType: YouTubeClientType.webRemix),
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Search failed: ${response.statusCode}');
      }
      final data = jsonDecode(response.body);

      // Parse Logic - pass allowBrowseIds: true for artist/playlist search
      // This allows UC/VL/PL browse IDs to be returned for navigation purposes
      _captureVisitorData(data);
      return _parseSearchResults(data, limit, allowBrowseIds: true);
    } catch (e) {
      if (kDebugMode) debugPrint('InnerTubeService: Search error: $e');
      rethrow;
    }
  }

  /// Search for songs on YouTube Music
  Future<List<Track>> searchSongs(String query, {int limit = 20}) async {
    try {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Searching for "$query"');
      }
      return await _searchWithParams(
          query, 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D', limit);
    } catch (e) {
      rethrow;
    }
  }

  /// Search for official music videos on YouTube Music (OMV / UGC)
  Future<List<Track>> searchVideos(String query, {int limit = 10}) async {
    try {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Searching videos for "$query"');
      }
      return await _searchWithParams(
          query, 'EgWKAQIQAWoKEAkQBRAKEAMQBA%3D%3D', limit);
    } catch (e) {
      if (kDebugMode) debugPrint('InnerTubeService: searchVideos error: $e');
      return const [];
    }
  }

  /// Parse search results into Track objects
  /// [allowBrowseIds] - when true, allows UC/VL/PL IDs (for artist/playlist search)
  List<Track> _parseSearchResults(Map<String, dynamic> data, int limit,
      {bool allowBrowseIds = false}) {
    final tracks = <Track>[];

    try {
      // 1. Try structured section hierarchy first
      List? contents;
      final tabs = data['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?;
      if (tabs != null && tabs.isNotEmpty) {
        contents = tabs[0]?['tabRenderer']?['content']
            ?['sectionListRenderer']?['contents'] as List?;
      }
      contents ??= data['contents']?['sectionListRenderer']?['contents'] as List?;

      if (contents != null) {
        for (final section in contents) {
          // Check standard MusicShelfRenderer
          final shelfContents = section['musicShelfRenderer']?['contents'] as List?;
          if (shelfContents != null) {
            for (final item in shelfContents) {
              if (tracks.length >= limit) break;

              if (item['musicResponsiveListItemRenderer'] != null) {
                final track = _parseTrackFromRenderer(
                    item['musicResponsiveListItemRenderer'],
                    allowBrowseIds: allowBrowseIds);
                if (track != null && !tracks.any((t) => t.id == track.id)) {
                  tracks.add(track);
                }
              } else if (item['musicTwoRowItemRenderer'] != null) {
                final track = _parseTrackFromTwoRowRenderer(
                    item['musicTwoRowItemRenderer'],
                    allowBrowseIds: allowBrowseIds);
                if (track != null && !tracks.any((t) => t.id == track.id)) {
                  tracks.add(track);
                }
              }
            }
          }

          // Check MusicCardShelfRenderer (Top Result / Hero Card - BitChord parseCardShelf parity)
          final cardShelf = section['musicCardShelfRenderer'];
          if (cardShelf != null && tracks.length < limit) {
            final titleRuns = cardShelf['title']?['runs'] as List?;
            final title = titleRuns != null && titleRuns.isNotEmpty
                ? titleRuns.map((r) => r['text']?.toString() ?? '').join('')
                : cardShelf['title']?['runs']?[0]?['text']?.toString();
            final subtitleRuns = cardShelf['subtitle']?['runs'] as List?;
            final subtitle = subtitleRuns != null && subtitleRuns.isNotEmpty
                ? subtitleRuns.map((r) => r['text']?.toString() ?? '').join('')
                : cardShelf['subtitle']?['runs']?[0]?['text']?.toString();

            String? videoId = cardShelf['onTap']?['watchEndpoint']?['videoId']?.toString() ??
                cardShelf['buttons']?[0]?['buttonRenderer']?['command']
                    ?['watchEndpoint']?['videoId']?.toString();

            // When searching for artists or playlists, the hero card contains a browseId
            // (e.g. UC... for artist, VL.../PL... for playlist) rather than a watchEndpoint videoId.
            if (videoId == null && allowBrowseIds) {
              videoId = cardShelf['onTap']?['browseEndpoint']?['browseId']?.toString() ??
                  cardShelf['buttons']?[0]?['buttonRenderer']?['command']
                      ?['browseEndpoint']?['browseId']?.toString();
            }

            final thumbnails = cardShelf['thumbnail']?['musicThumbnailRenderer']
                ?['thumbnail']?['thumbnails'] as List?;
            final thumbnail = (thumbnails != null && thumbnails.isNotEmpty)
                ? thumbnails.last['url']?.toString()
                : null;

            if (videoId != null && !tracks.any((t) => t.id == videoId)) {
              if (allowBrowseIds ||
                  (!videoId.startsWith('UC') &&
                      !videoId.startsWith('VL') &&
                      !videoId.startsWith('PL') &&
                      !videoId.startsWith('OLAK') &&
                      !videoId.startsWith('MPREb'))) {
                tracks.insert(0, Track(
                  id: videoId,
                  trackName: title ?? 'Unknown',
                  artistName: subtitle ?? '',
                  albumName: '',
                  previewUrl: '',
                  albumArt: thumbnail ?? '',
                  source: 'youtube',
                  durationMs: 0,
                ));
              }
            }
          }

          if (tracks.length >= limit) break;
        }
      }

      // 2. Resilient fallback: if structured walk yielded no results,
      // recursively collect all musicResponsiveListItemRenderers (BitChord parser parity)
      if (tracks.isEmpty) {
        final listRenderers = _collectRenderers(data, 'musicResponsiveListItemRenderer');
        for (final renderer in listRenderers) {
          if (tracks.length >= limit) break;
          final track = _parseTrackFromRenderer(renderer, allowBrowseIds: allowBrowseIds);
          if (track != null && !tracks.any((t) => t.id == track.id)) {
            tracks.add(track);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Parse error: $e');
      }
    }

    return tracks;
  }

  /// Parse a track from MusicResponsiveListItemRenderer
  /// [allowBrowseIds] - when true, allows UC/VL/PL IDs (for artist/playlist search)
  @visibleForTesting
  Track? parseTrackFromRendererForTest(Map<String, dynamic> renderer,
          {bool allowBrowseIds = false}) =>
      _parseTrackFromRenderer(renderer, allowBrowseIds: allowBrowseIds);

  Track? _parseTrackFromRenderer(Map<String, dynamic> renderer,
      {bool allowBrowseIds = false}) {
    try {
      // Get video ID or Browse ID (for playlists/artists)
      String? videoId = renderer['playlistItemData']?['videoId'];

      // Check watch endpoint
      videoId ??= renderer['overlay']?['musicItemThumbnailOverlayRenderer']
              ?['content']?['musicPlayButtonRenderer']
          ?['playNavigationEndpoint']?['watchEndpoint']?['videoId'];

      // Check navigation endpoint (Browse ID for artists/playlists fallback)
      if (videoId == null) {
        final navEndpoint = renderer['navigationEndpoint'];
        videoId = navEndpoint?['watchEndpoint']?['videoId'] ??
            navEndpoint?['browseEndpoint']?['browseId'];
      }

      // If still null, return null (item not usable)
      if (videoId == null) return null;

      // Filter out non-playable items (artists, playlists, albums) when NOT in browse mode
      // These IDs start with specific prefixes and can't be streamed directly
      if (!allowBrowseIds &&
          (videoId.startsWith('UC') || // Artist/Channel
              videoId.startsWith('VL') || // Playlist
              videoId.startsWith('PL') || // Playlist
              videoId.startsWith('OLAK') || // Album
              videoId.startsWith('MPREb'))) {
        // Album browse ID
        if (kDebugMode) {
          debugPrint('InnerTubeService: Skipping non-playable ID: $videoId');
        }
        return null;
      }

      // Get flex columns for title and artist
      final flexColumns = renderer['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) return null;

      // Title from first column
      String title = 'Unknown';
      final titleRuns = flexColumns[0]
              ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
          as List?;
      if (titleRuns != null && titleRuns.isNotEmpty) {
        title = titleRuns[0]['text'] ?? 'Unknown';
      }

      // Artist and Album from second column
      String artist = 'Unknown Artist';
      String album = '';

      if (flexColumns.length > 1) {
        final artistRuns = flexColumns[1]
                ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
            as List?;
        if (artistRuns != null && artistRuns.isNotEmpty) {
          final extracted = _extractCreditsFromRuns(artistRuns, trackTitle: title);
          if (extracted.artist.isNotEmpty) artist = extracted.artist;
          if (extracted.album.isNotEmpty) album = extracted.album;
        }
      }

      // Thumbnail
      String? thumbnail;
      final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']
          ?['thumbnail']?['thumbnails'] as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        // Get highest quality thumbnail
        thumbnail = thumbnails.last['url'];
        // Convert to high quality if it's a YouTube thumbnail
        if (thumbnail != null &&
            thumbnail.contains('lh3.googleusercontent.com')) {
          thumbnail = thumbnail.replaceAll(RegExp(r'=w\d+-h\d+'), '=w500-h500');
        }
      }

      // Duration (from third column or fixed columns)
      int? durationMs;
      if (flexColumns.length > 2) {
        final durationText = flexColumns[2]
                ?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
            ?[0]?['text'];
        if (durationText != null) {
          durationMs = _parseDuration(durationText);
        }
      }
      // Also try fixed columns
      final fixedColumns = renderer['fixedColumns'] as List?;
      if (fixedColumns != null && fixedColumns.isNotEmpty) {
        final durationText = fixedColumns[0]
                ?['musicResponsiveListItemFixedColumnRenderer']?['text']
            ?['runs']?[0]?['text'];
        if (durationText != null) {
          durationMs = _parseDuration(durationText);
        }
      }

      // Check for explicit badge [E] (BitChord parity)
      bool isExplicit = false;
      final badgeList = [
        if (renderer['badges'] is List) ...renderer['badges'] as List,
        if (renderer['subtitleBadges'] is List) ...renderer['subtitleBadges'] as List,
      ];
      for (final b in badgeList) {
        if (b is Map<String, dynamic>) {
          final inline = b['musicInlineBadgeRenderer'];
          if (inline is Map<String, dynamic>) {
            final iconType = inline['icon']?['iconType']?.toString();
            if (iconType == 'MUSIC_EXPLICIT_BADGE') {
              isExplicit = true;
              break;
            }
            final label = inline['accessibilityData']?['accessibilityData']?['label']
                ?.toString()
                .toLowerCase();
            if (label != null && label.contains('explicit')) {
              isExplicit = true;
              break;
            }
          }
        }
      }

      final rawTrack = Track(
        id: videoId,
        trackName: title,
        artistName: artist,
        albumName: album,
        albumArt: thumbnail ?? '',
        previewUrl: '', // Will be fetched when playing
        source: 'youtube',
        durationMs: durationMs,
        isExplicit: isExplicit,
      );

      return TrackMetadataEnricher.sanitizeTrack(rawTrack);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Track parse error: $e');
      }
      return null;
    }
  }

  /// Parse duration string (e.g., "3:45") to milliseconds
  int? _parseDuration(String duration) {
    try {
      final parts = duration.split(':');
      if (parts.length == 2) {
        final minutes = int.parse(parts[0]);
        final seconds = int.parse(parts[1]);
        return (minutes * 60 + seconds) * 1000;
      } else if (parts.length == 3) {
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final seconds = int.parse(parts[2]);
        return (hours * 3600 + minutes * 60 + seconds) * 1000;
      }
    } catch (_) {}
    return null;
  }

  /// Get player response for a video (contains stream URLs)
  /// Uses ANDROID_VR client which doesn't require authentication
  Future<Map<String, dynamic>> getPlayer(String videoId) async {
    // Try ANDROID_VR first (no auth required)
    try {
      if (kDebugMode) {
        debugPrint(
            'InnerTubeService: Getting player for $videoId using ANDROID_VR');
      }

      final result =
          await _getPlayerWithClient(videoId, YouTubeClientType.androidVr);

      // Check if playable
      final status = result['playabilityStatus']?['status'];
      if (status == 'OK') {
        return result;
      }

      // If not OK, try iOS client as fallback
      if (kDebugMode) {
        debugPrint(
            'InnerTubeService: ANDROID_VR failed ($status), trying iOS client');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: ANDROID_VR error: $e, trying iOS');
      }
    }

    // Fallback to iOS client
    try {
      final result = await _getPlayerWithClient(videoId, YouTubeClientType.ios);
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: iOS client also failed: $e');
      }
      rethrow;
    }
  }

  /// Get player response with specific client type
  Future<Map<String, dynamic>> _getPlayerWithClient(
      String videoId, YouTubeClientType clientType,
      {String? poToken}) async {
    final context = _buildContext(clientType: clientType);
    if (poToken != null && visitorData != null) {
      (context['client'] as Map<String, dynamic>)['visitorData'] = visitorData;
    }
    final body = jsonEncode({
      'context': context,
      'videoId': videoId,
      'racyCheckOk': true,
      'contentCheckOk': true,
      if (poToken != null)
        'playbackContext': {
          'contentPlaybackContext': {
            if (_signatureTimestamp != null)
              'signatureTimestamp': _signatureTimestamp,
            'html5Preference': 'HTML5_PREF_WANTS',
          },
        },
      if (poToken != null) 'serviceIntegrityDimensions': {'poToken': poToken},
    });

    // Bounded: a stalled player POST must degrade to the fallback ladder
    // (or an audible error), never an eternal spinner. Callers already
    // catch and continue on failure.
    final response = await _httpClient
        .post(
          Uri.parse('$_apiUrl/player?prettyPrint=false'),
          headers: _buildHeaders(clientType: clientType),
          body: body,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Player request failed: ${response.statusCode}');
    }

    return jsonDecode(response.body);
  }

  int? _signatureTimestamp;
  DateTime? _signatureFetchedAt;

  /// YouTube player JS signature timestamp — WEB clients require it in
  /// playbackContext or /player answers UNPLAYABLE.
  Future<int?> _getSignatureTimestamp() async {
    final cached = _signatureTimestamp;
    if (cached != null &&
        _signatureFetchedAt != null &&
        DateTime.now().difference(_signatureFetchedAt!) <
            const Duration(hours: 6)) {
      return cached;
    }
    try {
      final iframe = await _httpClient
          .get(Uri.parse('https://www.youtube.com/iframe_api'))
          .timeout(const Duration(seconds: 8));
      final hashMatch = RegExp(r'/s/player/([a-zA-Z0-9_-]+)/')
          .firstMatch(iframe.body)
          ?.group(1);
      if (hashMatch == null) return null;
      final playerJs = await _httpClient
          .get(Uri.parse(
              'https://www.youtube.com/s/player/$hashMatch/player_ias.vflset/en_GB/base.js'))
          .timeout(const Duration(seconds: 8));
      final stsMatch =
          RegExp(r'signatureTimestamp\s*=\s*(\d+)').firstMatch(playerJs.body);
      if (stsMatch == null) return null;
      _signatureTimestamp = int.parse(stsMatch.group(1)!);
      _signatureFetchedAt = DateTime.now();
      if (kDebugMode) {
        debugPrint('InnerTubeService: signatureTimestamp=$_signatureTimestamp');
      }
      return _signatureTimestamp;
    } catch (e) {
      if (kDebugMode) debugPrint('InnerTubeService: sigTimestamp failed: $e');
      return null;
    }
  }

  /// Drop session-bound state after a login/logout flip. visitorData is
  /// captured once per session; a stale anonymous visitorData sent with
  /// login cookies (or vice versa) makes /player reject playback while
  /// browse keeps working. The next request re-captures from the live
  /// session. Frozen player logic untouched — this only clears the cache.
  void resetSession() {
    visitorData = null;
    if (kDebugMode) {
      debugPrint('InnerTubeService: session reset (auth flip)');
    }
  }

  /// Capture visitorData from any InnerTube response's responseContext so
  /// PO-token player requests can bind to the same session.
  void _captureVisitorData(Map<String, dynamic> data) {
    if (visitorData != null) return;
    final ctx = data['responseContext'];
    if (ctx is Map<String, dynamic>) {
      final vd = ctx['visitorData'];
      if (vd is String && vd.isNotEmpty) {
        visitorData = vd;
        if (kDebugMode) debugPrint('InnerTubeService: visitorData captured');
      }
    }
  }

  Future<void> _ensureVisitorData() async {
    if (visitorData != null) return;
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_apiUrl/browse?prettyPrint=false'),
            headers: _buildHeaders(),
            body: jsonEncode(
                {'context': _buildContext(), 'browseId': 'FEmusic_home'}),
          )
          // Unbounded POSTs stall app start forever on hostile networks;
          // a miss just means the next call retries (callers tolerate null).
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        _captureVisitorData(jsonDecode(response.body));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: visitorData fetch failed: $e');
      }
    }
  }

  /// Fast path used by [StreamResolutionService].
  /// [preferredBitrate] is an upper bound in kbps; the closest stream at or
  /// under it wins, else the highest available.
  Future<String?> getDirectAudioStreamUrl(
    String videoId, {
    int preferredBitrate = 256,
  }) async {
    // PRIMARY: WEB_REMIX + BotGuard PO token (the only reliable path since
    // YouTube bot-gated every token-less client in Aug 2026 — mirrors
    // Metrolist's MAIN_CLIENT strategy).
    try {
      await _ensureVisitorData();
      await _getSignatureTimestamp();
      final pots = await PoTokenWebGenerator.instance.generateForVideo(videoId);
      final playerResponse = await _getPlayerWithClient(
        videoId,
        YouTubeClientType.webRemix,
        poToken: pots.playerRequest,
      );
      final status = playerResponse['playabilityStatus'];
      if (status?['status'] == 'OK') {
        final streamingData = playerResponse['streamingData'];
        if (streamingData != null) {
          final url = await _extractBestStream(streamingData, preferredBitrate);
          if (url != null) {
            final sep = url.contains('?') ? '&' : '?';
            debugPrint('InnerTubeService: stream via webRemix+poToken');
            return '$url${sep}pot=${Uri.encodeComponent(pots.streaming)}';
          }
          // Visible fallthrough: OK status but cipher-only formats (no
          // plain url) — the ladder is next, not a silent mystery.
          debugPrint('InnerTubeService: webRemix+poToken OK but no plain '
              'stream url (cipher-only?) for $videoId');
        } else {
          debugPrint('InnerTubeService: webRemix+poToken OK but no '
              'streamingData for $videoId');
        }
      } else {
        debugPrint(
            'InnerTubeService: webRemix+poToken not OK: ${status?['status']} ${status?['reason']}');
      }
    } catch (e) {
      debugPrint('InnerTubeService: webRemix+poToken failed: $e');
    }

    // FALLBACK ladder (token-less; usually bot-gated, kept for rotation waves
    // where a client briefly opens up).
    const ladder = <YouTubeClientType>[
      YouTubeClientType.visionos,
      YouTubeClientType.androidVr,
      YouTubeClientType.tvEmbedded,
    ];
    for (final client in ladder) {
      try {
        final playerResponse = await _getPlayerWithClient(videoId, client);
        final status = playerResponse['playabilityStatus'];
        if (status?['status'] != 'OK') {
          debugPrint(
              'InnerTubeService: $client not OK for $videoId: ${status?['status']} ${status?['reason']}');
          continue;
        }
        final streamingData = playerResponse['streamingData'];
        if (streamingData == null) continue;
        final url = await _extractBestStream(streamingData, preferredBitrate);
        if (url != null) {
          debugPrint('InnerTubeService: stream via $client');
          return url;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('InnerTubeService: $client stream failed: $e');
        }
      }
    }
    return null;
  }

  /// Resolves a direct, playable video stream URL for [videoId] using InnerTube client ladder
  /// (webRemix+poToken -> VISIONOS -> ANDROID_VR -> TVHTML5 -> YoutubeExplode).
  Future<String?> getDirectVideoStreamUrl(
    String videoId, {
    int preferredHeight = 480,
  }) async {
    // 1. Primary: webRemix with PoToken (consistent with getDirectAudioStreamUrl)
    try {
      await _ensureVisitorData();
      await _getSignatureTimestamp();
      final pots = await PoTokenWebGenerator.instance.generateForVideo(videoId);
      final playerResponse = await _getPlayerWithClient(
        videoId,
        YouTubeClientType.webRemix,
        poToken: pots.playerRequest,
      );
      final status = playerResponse['playabilityStatus'];
      if (status?['status'] == 'OK') {
        final streamingData = playerResponse['streamingData'];
        if (streamingData != null) {
          final url = _extractBestVideoStream(streamingData, preferredHeight);
          if (url != null) {
            final sep = url.contains('?') ? '&' : '?';
            debugPrint('InnerTubeService: video stream resolved via webRemix+poToken');
            return '$url${sep}pot=${Uri.encodeComponent(pots.streaming)}';
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: webRemix video stream failed: $e');
      }
    }

    // 2. Token-less client ladder
    const ladder = <YouTubeClientType>[
      YouTubeClientType.visionos,
      YouTubeClientType.androidVr,
      YouTubeClientType.tvEmbedded,
      YouTubeClientType.ios,
    ];
    for (final client in ladder) {
      try {
        final playerResponse = await _getPlayerWithClient(videoId, client);
        final status = playerResponse['playabilityStatus'];
        if (status?['status'] != 'OK') {
          continue;
        }
        final streamingData = playerResponse['streamingData'];
        if (streamingData == null) continue;
        final url = _extractBestVideoStream(streamingData, preferredHeight);
        if (url != null) {
          debugPrint('InnerTubeService: video stream resolved via $client');
          return url;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('InnerTubeService: $client video stream failed: $e');
        }
      }
    }

    // 3. Resilient fallback via YoutubeExplode
    try {
      final yt = yt_exp.YoutubeExplode();
      try {
        final manifest = await yt.videos.streamsClient.getManifest(videoId);
        final muxed = manifest.muxed.sortByVideoQuality();
        if (muxed.isNotEmpty) {
          final chosen = muxed.firstWhere(
            (s) => s.videoQuality.index <= 4, // 360p - 720p range
            orElse: () => muxed.first,
          );
          debugPrint('InnerTubeService: video stream resolved via YoutubeExplode muxed');
          return chosen.url.toString();
        }
        final videoOnly = manifest.videoOnly
            .where((s) => s.container.name == 'mp4' || s.container.name == 'webm')
            .toList();
        if (videoOnly.isNotEmpty) {
          debugPrint('InnerTubeService: video stream resolved via YoutubeExplode video-only');
          return videoOnly.first.url.toString();
        }
      } finally {
        yt.close();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: YoutubeExplode fallback failed: $e');
      }
    }

    return null;
  }

  /// Extracts the best looping video stream from InnerTube streamingData.
  /// Prefers lightweight 360p or 480p MP4 formats (hardware-decoded, low bandwidth),
  /// falling back to WebM if MP4 is unavailable.
  String? _extractBestVideoStream(
      Map<String, dynamic> streamingData, int preferredHeight) {
    // 1. Check adaptive formats (video-only)
    final adaptiveFormats = streamingData['adaptiveFormats'] as List?;
    if (adaptiveFormats != null && adaptiveFormats.isNotEmpty) {
      final videoFormats = adaptiveFormats.where((f) {
        final mimeType = f['mimeType'] as String?;
        return mimeType != null &&
            (mimeType.startsWith('video/mp4') || mimeType.startsWith('video/webm')) &&
            f['url'] != null;
      }).toList();

      if (videoFormats.isNotEmpty) {
        // Sort: prefer mp4 over webm, then closest height to preferredHeight
        videoFormats.sort((a, b) {
          final isMp4A = (a['mimeType'] as String? ?? '').startsWith('video/mp4') ? 0 : 1;
          final isMp4B = (b['mimeType'] as String? ?? '').startsWith('video/mp4') ? 0 : 1;
          if (isMp4A != isMp4B) return isMp4A.compareTo(isMp4B);
          final hA = (a['height'] as int? ?? 360) - preferredHeight;
          final hB = (b['height'] as int? ?? 360) - preferredHeight;
          return hA.abs().compareTo(hB.abs());
        });
        return videoFormats.first['url'] as String?;
      }
    }

    // 2. Check muxed formats (video + audio) as fallback
    final formats = streamingData['formats'] as List?;
    if (formats != null && formats.isNotEmpty) {
      final videoFormats = formats.where((f) {
        final mimeType = f['mimeType'] as String?;
        return mimeType != null &&
            (mimeType.startsWith('video/mp4') || mimeType.startsWith('video/webm')) &&
            f['url'] != null;
      }).toList();

      if (videoFormats.isNotEmpty) {
        videoFormats.sort((a, b) {
          final isMp4A = (a['mimeType'] as String? ?? '').startsWith('video/mp4') ? 0 : 1;
          final isMp4B = (b['mimeType'] as String? ?? '').startsWith('video/mp4') ? 0 : 1;
          if (isMp4A != isMp4B) return isMp4A.compareTo(isMp4B);
          final hA = (a['height'] as int? ?? 360) - preferredHeight;
          final hB = (b['height'] as int? ?? 360) - preferredHeight;
          return hA.abs().compareTo(hB.abs());
        });
        return videoFormats.first['url'] as String?;
      }
    }

    return null;
  }

  // Legacy Piped method removed. Use PipedService class.

  /// Helper to extract best stream from InnerTube response
  Future<String?> _extractBestStream(
      Map<String, dynamic> streamingData, int preferredBitrate) async {
    // Prefer adaptive formats for audio-only streams
    final adaptiveFormats = streamingData['adaptiveFormats'] as List?;
    if (adaptiveFormats != null && adaptiveFormats.isNotEmpty) {
      // Filter audio-only formats
      final audioFormats = adaptiveFormats.where((f) {
        final mimeType = f['mimeType'] as String?;
        return mimeType != null && mimeType.startsWith('audio/');
      }).toList();

      if (audioFormats.isNotEmpty) {
        // Sort by bitrate (descending)
        audioFormats.sort((a, b) {
          final bitrateA = a['bitrate'] as int? ?? 0;
          final bitrateB = b['bitrate'] as int? ?? 0;
          return bitrateB.compareTo(bitrateA);
        });

        // Find closest to preferred bitrate
        Map<String, dynamic>? bestFormat;
        for (final format in audioFormats) {
          final bitrate = (format['bitrate'] as int? ?? 0) ~/ 1000;
          if (bitrate <= preferredBitrate || bestFormat == null) {
            bestFormat = format;
            if (bitrate <= preferredBitrate) break;
          }
        }

        // Only return if it contains a signature/url that looks usable
        // Note: We are not deciphering signatures here. If 'signatureCipher' is present instead of 'url',
        // it means we need decryption which we are skipping in favor of Piped fallback.
        if (bestFormat?['url'] != null) {
          return bestFormat!['url'];
        }
      }
    }
    return null;
  }

  /// Raw browse endpoint for dedicated sources (e.g. the Home feed).
  /// Additive passthrough — no parsing here; the caller owns semantics.
  ///
  /// Muzo-parity browse context: dynamic clientVersion (1.YYYYMMDD.01.00),
  /// platform-locale hl, no gl override (hardcoded gl=US served US-centric
  /// content to every user), playbackContext with the real signature
  /// timestamp, CONSENT cookie when no auth is present. Player contexts
  /// keep the frozen static clientVersion — the playback pipeline
  /// (BotGuard/PO token) is version-sensitive and deliberately untouched.
  Future<Map<String, dynamic>> browseJson(String browseId,
      {String? params}) async {
    await _ensureVisitorData();
    // Signature timestamp for playbackContext — best-effort, cached 6h.
    if (_signatureTimestamp == null) {
      await _getSignatureTimestamp();
    }
    final response = await _httpClient.post(
      Uri.parse('$_apiUrl/browse?prettyPrint=false'),
      headers: _buildHeaders(),
      body: jsonEncode({
        'context': _buildBrowseContext(),
        'browseId': browseId,
        if (params != null && params.isNotEmpty) 'params': params,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Browse $browseId failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      _captureVisitorData(decoded);
      return decoded;
    }
    throw Exception('Browse $browseId returned unexpected payload');
  }

  /// Browse-only context (Muzo v3.9 parity). Dynamic clientVersion —
  /// stale versions receive a degraded/limited Home surface.
  Map<String, dynamic> _buildBrowseContext() {
    final now = DateTime.now();
    final clientVersion =
        '1.${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.01.00';
    final hl = PlatformDispatcher.instance.locale.languageCode;

    final context = <String, dynamic>{
      'client': {
        'clientName': _webRemixClientName,
        'clientVersion': clientVersion,
        'hl': hl,
        'platform': 'DESKTOP',
      },
      'user': {},
      // Real signature timestamp (Muzo approximates with now-86400s; ours
      // comes from the player JS pipeline and is fresher).
      if (_signatureTimestamp != null)
        'playbackContext': {
          'contentPlaybackContext': {
            'signatureTimestamp': _signatureTimestamp,
          },
        },
    };
    if (visitorData != null) {
      (context['client'] as Map<String, dynamic>)['visitorData'] = visitorData;
    }
    return context;
  }

  /// Get home/browse content (trending, recommendations)
  Future<List<Track>> getHomeTracks({int limit = 20}) async {
    try {
      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': 'FEmusic_home',
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Browse failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      return _parseHomeResults(data, limit);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Home error: $e');
      }
      rethrow;
    }
  }

  /// New Releases shelf (albums/singles/playlists). Items carry browse or
  /// video ids — the UI routes PL/VL/OLAK ids to the playlist flow.
  Future<List<Track>> getNewReleases({int limit = 20}) {
    return _cachedBrowse('new_releases:$limit', () async {
      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: jsonEncode({
          'context': _buildContext(),
          'browseId': 'FEmusic_new_releases',
        }),
      );
      if (response.statusCode != 200) {
        throw Exception('New releases browse failed: ${response.statusCode}');
      }
      return _parseHomeResults(jsonDecode(response.body), limit,
          allowBrowseIds: true);
    });
  }

  /// Moods & Genres chips. The response nests navigation buttons at varying
  /// depths, so collect them recursively instead of hardcoding a path.
  Future<List<DiscoverMood>> getMoodsAndGenres() {
    return _cachedBrowse('moods', () async {
      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: jsonEncode({
          'context': _buildContext(),
          'browseId': 'FEmusic_moods_and_genres',
        }),
      );
      if (response.statusCode != 200) {
        throw Exception('Moods browse failed: ${response.statusCode}');
      }
      final moods = <DiscoverMood>[];
      void walk(dynamic node) {
        if (node is List) {
          for (final child in node) {
            walk(child);
          }
          return;
        }
        if (node is Map<String, dynamic>) {
          final button = node['musicNavigationButtonRenderer'];
          if (button != null) {
            final title = button['title']?['simpleText'] ??
                (button['title']?['runs'] as List?)?.firstOrNull?['text'];
            final params = button['clickPayload'];
            if (title is String && params is String && params.isNotEmpty) {
              moods.add(DiscoverMood(title: title, params: params));
            }
            return;
          }
          node.values.forEach(walk);
        }
      }

      walk(jsonDecode(response.body));
      // Dedupe chips that repeat across sections.
      final seen = <String>{};
      return moods.where((m) => seen.add(m.params)).toList();
    });
  }

  /// Tracks/playlists for a Moods & Genres category chip.
  Future<List<Track>> getMoodTracks(String params, {int limit = 30}) {
    return _cachedBrowse('mood_tracks:$params:$limit', () async {
      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: jsonEncode({
          'context': _buildContext(),
          'browseId': 'FEmusic_moods_and_genres',
          'params': params,
        }),
      );
      if (response.statusCode != 200) {
        throw Exception('Mood tracks failed: ${response.statusCode}');
      }
      return _parseHomeResults(jsonDecode(response.body), limit,
          allowBrowseIds: true);
    });
  }

  /// Parse home/browse results. When [allowBrowseIds] is true, playlist and
  /// album cards are kept (their ids route through the playlist flow).
  List<Track> _parseHomeResults(Map<String, dynamic> data, int limit,
      {bool allowBrowseIds = false}) {
    final tracks = <Track>[];

    try {
      final tabs =
          data['contents']?['singleColumnBrowseResultsRenderer']?['tabs'];
      if (tabs == null || tabs.isEmpty) return tracks;

      final contents = tabs[0]?['tabRenderer']?['content']
          ?['sectionListRenderer']?['contents'];
      if (contents == null) return tracks;

      for (final section in contents) {
        final carouselContents =
            section['musicCarouselShelfRenderer']?['contents'];
        if (carouselContents == null) continue;

        for (final item in carouselContents) {
          if (tracks.length >= limit) break;

          // Try MusicResponsiveListItemRenderer first
          var renderer = item['musicResponsiveListItemRenderer'];
          if (renderer != null) {
            final track = _parseTrackFromRenderer(renderer);
            if (track != null) {
              tracks.add(track);
              continue;
            }
          }

          // Try MusicTwoRowItemRenderer
          renderer = item['musicTwoRowItemRenderer'];
          if (renderer != null) {
            final track = _parseTrackFromTwoRowRenderer(renderer,
                allowBrowseIds: allowBrowseIds);
            if (track != null) {
              tracks.add(track);
            }
          }
        }

        if (tracks.length >= limit) break;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Home parse error: $e');
      }
    }

    return tracks;
  }

  /// Get Artist Details (Top Songs)
  Future<Map<String, dynamic>> getArtistDetails(String browseId) async {
    try {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Getting artist details for $browseId');
      }

      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': browseId,
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Artist browse failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final tracks = <Track>[];
      final albums = <Album>[];
      final singles = <Album>[];

      // Parse "Songs" section (Top Songs)
      // Usually under 'contents' -> 'singleColumnBrowseResultsRenderer' -> 'tabs' -> tab 0 -> 'sectionListRenderer'
      // Parse Header for proper Artist Name (if needed by UI, though UI passes name usually)
      // The UI uses the name passed from Search, which we fixed to be clean.
      // However, if the user navigates deep, we might want the name from details.
      // Let's stick to parsing content for now.

      // Parse "Songs" section (Top Songs)
      // Usually under 'contents' -> 'singleColumnBrowseResultsRenderer' -> 'tabs' -> tab 0 -> 'sectionListRenderer'
      final tabs =
          data['contents']?['singleColumnBrowseResultsRenderer']?['tabs'];
      if (tabs == null || tabs.isEmpty) {
        return {'tracks': [], 'albums': [], 'singles': []};
      }

      final sections = tabs[0]?['tabRenderer']?['content']
          ?['sectionListRenderer']?['contents'] as List?;

      if (sections != null) {
        for (final section in sections) {
          // 1. Check MusicShelfRenderer (List of Songs)
          final musicShelf = section['musicShelfRenderer'];
          if (musicShelf != null) {
            // We don't rely on shelf title for Artist Name.
            final contents = musicShelf['contents'] as List?;
            if (contents != null) {
              for (final item in contents) {
                final renderer = item['musicResponsiveListItemRenderer'];
                if (renderer != null) {
                  final track = _parseTrackFromRenderer(renderer);
                  if (track != null) tracks.add(track);
                }
              }
            }
          }

          // 2. Check MusicCarouselShelfRenderer (Albums/Singles)
          final carouselShelf = section['musicCarouselShelfRenderer'];
          if (carouselShelf != null) {
            final title = (carouselShelf['header']
                            ?['musicCarouselShelfBasicHeaderRenderer']?['title']
                        ?['runs']?[0]?['text'] ??
                    '')
                .toString();
            final contents = carouselShelf['contents'] as List?;

            if (contents != null) {
              final isAlbums = title.contains('Albums');
              final isSingles =
                  title.contains('Singles') || title.contains('EPs');

              if (isAlbums || isSingles) {
                for (final item in contents) {
                  final renderer = item['musicTwoRowItemRenderer'];
                  if (renderer != null) {
                    final album = _parseAlbumFromRenderer(renderer);
                    if (album != null) {
                      if (isAlbums) albums.add(album);
                      if (isSingles) singles.add(album);
                    }
                  }
                }
              }
            }
          }
        }
      }

      return {
        'tracks': tracks,
        'albums': albums,
        'singles': singles,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('InnerTubeService: Artist details error: $e');
      return {'tracks': <Track>[], 'albums': <Album>[], 'singles': <Album>[]};
    }
  }

  /// Get full BitChord Artist Page Data with hero portrait, stats, bio, and carousels
  Future<ArtistDetailData> getArtistPageData(String browseId) async {
    try {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Getting full artist page data for $browseId');
      }

      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': browseId,
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Artist browse failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      // 1. Header parsing (musicImmersiveHeaderRenderer or musicVisualHeaderRenderer)
      final header = data['header'];
      String artistName = 'Artist';
      String heroImageUrl = '';
      String? subscriberCountText;
      String? monthlyListenerCount;

      if (header != null) {
        final immersive = header['musicImmersiveHeaderRenderer'];
        final visual = header['musicVisualHeaderRenderer'];
        final activeHeader = immersive ?? visual;

        if (activeHeader != null) {
          final titleRuns = activeHeader['title']?['runs'] as List?;
          if (titleRuns != null && titleRuns.isNotEmpty) {
            artistName = titleRuns.map((r) => r['text']?.toString() ?? '').join('').trim();
          }

          // Hero Image
          final thumbMap = immersive?['thumbnail'] ?? visual?['foregroundThumbnail'] ?? visual?['thumbnail'];
          final thumbs = thumbMap?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
          if (thumbs != null && thumbs.isNotEmpty) {
            heroImageUrl = thumbs.last['url']?.toString() ?? '';
            if (heroImageUrl.contains('lh3.googleusercontent.com')) {
              heroImageUrl = heroImageUrl.replaceAll(RegExp(r'=w\d+-h\d+'), '=w1200-h800');
            }
          }

          // Subscriber Count
          final subBtn2 = immersive?['subscriptionButton2']?['subscribeButtonRenderer'];
          final subBtn1 = immersive?['subscriptionButton']?['subscribeButtonRenderer'];
          final subRuns = (subBtn2?['subscriberCountWithSubscribeText']?['runs'] ??
              subBtn1?['longSubscriberCountText']?['runs'] ??
              subBtn1?['shortSubscriberCountText']?['runs']) as List?;
          if (subRuns != null && subRuns.isNotEmpty) {
            final raw = subRuns.first['text']?.toString() ?? '';
            subscriberCountText = raw.contains('subscribers') ? raw : '$raw subscribers';
          }

          // Monthly Listeners
          final listenerRuns = immersive?['monthlyListenerCount']?['runs'] as List?;
          if (listenerRuns != null && listenerRuns.isNotEmpty) {
            final raw = listenerRuns.first['text']?.toString() ?? '';
            monthlyListenerCount = raw.contains('listeners') ? raw : '$raw monthly listeners';
          }
        }
      }

      // 2. Editorial Description ("About the artist")
      String? description;
      final descShelves = _collectRenderers(data, 'musicDescriptionShelfRenderer');
      if (descShelves.isNotEmpty) {
        final descRuns = descShelves.first['description']?['runs'] as List?;
        if (descRuns != null && descRuns.isNotEmpty) {
          description = descRuns.map((r) => r['text']?.toString() ?? '').join('').trim();
        }
      }
      if (description == null && header != null) {
        final hdrDesc = header['musicImmersiveHeaderRenderer']?['description']?['runs'] as List?;
        if (hdrDesc != null && hdrDesc.isNotEmpty) {
          description = hdrDesc.map((r) => r['text']?.toString() ?? '').join('').trim();
        }
      }

      // 3. Top Songs
      final topSongs = <Track>[];
      String? moreSongsBrowseId;
      final shelfRenderers = _collectRenderers(data, 'musicShelfRenderer');
      if (shelfRenderers.isNotEmpty) {
        final firstShelf = shelfRenderers.first;
        final contents = firstShelf['contents'] as List?;
        if (contents != null) {
          for (final item in contents) {
            final renderer = item['musicResponsiveListItemRenderer'];
            if (renderer != null) {
              final track = _parseTrackFromRenderer(renderer);
              if (track != null) topSongs.add(track);
            }
          }
        }

        // BitChord YtMusicRepository.artistPage parity:
        // Landing page only lists ~5 songs, so linked "Top songs" playlist is fetched
        final titleRuns = firstShelf['title']?['runs'] as List?;
        if (titleRuns != null && titleRuns.isNotEmpty) {
          moreSongsBrowseId = titleRuns.first['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
        }
        moreSongsBrowseId ??= firstShelf['bottomEndpoint']?['browseEndpoint']?['browseId']?.toString();
      }

      if (moreSongsBrowseId != null && moreSongsBrowseId.isNotEmpty) {
        try {
          final fullSongs = await getPlaylistDetails(moreSongsBrowseId);
          if (fullSongs.isNotEmpty) {
            topSongs.clear();
            topSongs.addAll(fullSongs);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('InnerTubeService: getArtistPageData moreSongs fetch error: $e');
        }
      }

      // 4. Horizontal Shelves & Carousels
      final shelves = <DetailShelf>[];
      final carouselRenderers = _collectRenderers(data, 'musicCarouselShelfRenderer');
      for (final carousel in carouselRenderers) {
        final carouselHeader = carousel['header']?['musicCarouselShelfBasicHeaderRenderer'];
        final titleRuns = carouselHeader?['title']?['runs'] as List?;
        final shelfTitle = titleRuns?.map((r) => r['text']?.toString() ?? '').join('').trim() ?? '';
        if (shelfTitle.isEmpty || RegExp(r'\bvideos?\b', caseSensitive: false).hasMatch(shelfTitle)) {
          continue;
        }

        final contents = carousel['contents'] as List?;
        if (contents == null || contents.isEmpty) continue;

        final shelfItems = <DetailShelfItem>[];
        for (final item in contents) {
          final renderer = item['musicTwoRowItemRenderer'];
          if (renderer == null) continue;

          final browseId = renderer['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
          if (browseId == null || browseId.isEmpty) continue;

          final itemTitle = (renderer['title']?['runs'] as List?)
                  ?.map((r) => r['text']?.toString() ?? '')
                  .join('')
                  .trim() ??
              '';
          final subRuns = renderer['subtitle']?['runs'] as List?;
          final itemSubtitle = subRuns
                  ?.map((r) => r['text']?.toString() ?? '')
                  .where((s) => s.trim().isNotEmpty && s.trim() != '•')
                  .join(' • ') ??
              '';

          final thumbs = renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
          String itemImage = thumbs?.last['url']?.toString() ?? '';
          if (itemImage.contains('lh3.googleusercontent.com')) {
            itemImage = itemImage.replaceAll(RegExp(r'=w\d+-h\d+'), '=w500-h500');
          }

          String itemType = 'album';
          final lowerShelf = shelfTitle.toLowerCase();
          if (lowerShelf.contains('album')) {
            itemType = 'album';
          } else if (lowerShelf.contains('single') || lowerShelf.contains('ep')) {
            itemType = 'single';
          } else if (lowerShelf.contains('feature') || lowerShelf.contains('playlist')) {
            itemType = 'playlist';
          } else if (lowerShelf.contains('fan') || lowerShelf.contains('like') || lowerShelf.contains('artist')) {
            itemType = 'artist';
          }

          shelfItems.add(DetailShelfItem(
            title: itemTitle,
            subtitle: itemSubtitle,
            browseId: browseId,
            imageUrl: itemImage,
            type: itemType,
          ));
        }

        if (shelfItems.isNotEmpty) {
          shelves.add(DetailShelf(title: shelfTitle, items: shelfItems));
        }
      }

      return ArtistDetailData(
        name: artistName,
        heroImageUrl: heroImageUrl,
        subscriberCountText: subscriberCountText,
        monthlyListenerCount: monthlyListenerCount,
        description: description,
        topSongs: topSongs,
        shelves: shelves,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('InnerTubeService: getArtistPageData error: $e');
      return const ArtistDetailData(
        name: 'Artist',
        heroImageUrl: '',
      );
    }
  }

  /// Get full BitChord Album Page Data with title, artist, year, track count, cover, and editorial blurb
  Future<AlbumDetailData> getAlbumPageData(String browseId) async {
    try {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Getting full album page data for $browseId');
      }

      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': browseId,
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Album browse failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      // 1. Header parsing (musicResponsiveHeaderRenderer or musicDetailHeaderRenderer)
      final headerRenderers = [
        ..._collectRenderers(data, 'musicResponsiveHeaderRenderer'),
        ..._collectRenderers(data, 'musicDetailHeaderRenderer'),
      ];

      String title = 'Album';
      String artistName = '';
      String? artistBrowseId;
      String? year;
      int? trackCount;
      String coverUrl = '';

      if (headerRenderers.isNotEmpty) {
        final header = headerRenderers.first;
        final titleRuns = header['title']?['runs'] as List?;
        if (titleRuns != null && titleRuns.isNotEmpty) {
          title = titleRuns.map((r) => r['text']?.toString() ?? '').join('').trim();
        }

        final straplineRuns = header['straplineTextOne']?['runs'] as List?;
        if (straplineRuns != null && straplineRuns.isNotEmpty) {
          artistName = straplineRuns.first['text']?.toString() ?? '';
          artistBrowseId = straplineRuns.first['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
        }

        final subtitleRuns = header['subtitle']?['runs'] as List?;
        if (artistName.isEmpty && subtitleRuns != null && subtitleRuns.isNotEmpty) {
          for (final run in subtitleRuns) {
            final text = run['text']?.toString() ?? '';
            final bId = run['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
            if (bId != null && bId.startsWith('UC')) {
              artistName = text;
              artistBrowseId = bId;
              break;
            }
          }
          if (artistName.isEmpty) artistName = subtitleRuns.first['text']?.toString() ?? '';
        }

        final allRuns = [
          if (subtitleRuns != null) ...subtitleRuns,
          if (header['secondSubtitle']?['runs'] != null) ...header['secondSubtitle']['runs'] as List,
        ];
        for (final run in allRuns) {
          final text = run['text']?.toString() ?? '';
          final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(text);
          if (match != null) {
            year = match.group(1);
            break;
          }
        }

        final thumbs = _collectRenderers(header, 'musicThumbnailRenderer').firstOrNull?['thumbnail']?['thumbnails'] as List?;
        if (thumbs != null && thumbs.isNotEmpty) {
          coverUrl = thumbs.last['url']?.toString() ?? '';
          if (coverUrl.contains('lh3.googleusercontent.com')) {
            coverUrl = coverUrl.replaceAll(RegExp(r'=w\d+-h\d+'), '=w800-h800');
          }
        }
      }

      // 2. Editorial Description ("About the album")
      String? description;
      final descShelves = _collectRenderers(data, 'musicDescriptionShelfRenderer');
      if (descShelves.isNotEmpty) {
        final descRuns = descShelves.first['description']?['runs'] as List?;
        if (descRuns != null && descRuns.isNotEmpty) {
          description = descRuns.map((r) => r['text']?.toString() ?? '').join('').trim();
        }
      }
      if (description == null && headerRenderers.isNotEmpty) {
        final descRuns = headerRenderers.first['description']?['runs'] as List?;
        if (descRuns != null && descRuns.isNotEmpty) {
          description = descRuns.map((r) => r['text']?.toString() ?? '').join('').trim();
        }
      }

      // 3. Tracks
      final tracks = <Track>[];
      final itemRenderers = _collectRenderers(data, 'musicResponsiveListItemRenderer');
      final seenIds = <String>{};
      for (final renderer in itemRenderers) {
        final track = _parseTrackFromRenderer(renderer);
        if (track != null && seenIds.add(track.id)) {
          tracks.add(track);
        }
      }

      trackCount = tracks.length;

      return AlbumDetailData(
        title: title,
        artistName: artistName,
        artistBrowseId: artistBrowseId,
        year: year,
        trackCount: trackCount,
        coverUrl: coverUrl,
        description: description,
        tracks: tracks,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('InnerTubeService: getAlbumPageData error: $e');
      return const AlbumDetailData(
        title: 'Album',
        artistName: '',
        coverUrl: '',
      );
    }
  }

  /// Get full BitChord Playlist Page Data with title, curator, views, collage/cover, and tracks
  Future<PlaylistDetailData> getPlaylistPageData(String browseId) async {
    try {
      final String resolvedBrowseId;
      if (browseId.startsWith('VL')) {
        resolvedBrowseId = browseId;
      } else if (browseId.startsWith('PL') || browseId.startsWith('RDCLAK')) {
        resolvedBrowseId = 'VL$browseId';
      } else {
        resolvedBrowseId = browseId;
      }

      if (kDebugMode) {
        debugPrint('InnerTubeService: Getting full playlist page data for $resolvedBrowseId');
      }

      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': resolvedBrowseId,
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Playlist browse failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      // 1. Header parsing
      final headerRenderers = [
        ..._collectRenderers(data, 'musicResponsiveHeaderRenderer'),
        ..._collectRenderers(data, 'musicDetailHeaderRenderer'),
      ];

      String title = 'Playlist';
      String curatorName = 'YouTube Music';
      String? viewsText;
      String coverUrl = '';
      String? description;

      if (headerRenderers.isNotEmpty) {
        final header = headerRenderers.first;
        final titleRuns = header['title']?['runs'] as List?;
        if (titleRuns != null && titleRuns.isNotEmpty) {
          title = titleRuns.map((r) => r['text']?.toString() ?? '').join('').trim();
        }

        final straplineRuns = header['straplineTextOne']?['runs'] as List?;
        if (straplineRuns != null && straplineRuns.isNotEmpty) {
          curatorName = straplineRuns.first['text']?.toString() ?? 'YouTube Music';
        }

        final subtitleRuns = header['subtitle']?['runs'] as List?;
        if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
          for (final run in subtitleRuns) {
            final text = run['text']?.toString() ?? '';
            if (RegExp(r'\b\d+(?:\.\d+)?[KM]?\s+views\b', caseSensitive: false).hasMatch(text)) {
              viewsText = text;
              break;
            }
          }
        }

        final thumbs = _collectRenderers(header, 'musicThumbnailRenderer').firstOrNull?['thumbnail']?['thumbnails'] as List?;
        if (thumbs != null && thumbs.isNotEmpty) {
          coverUrl = thumbs.last['url']?.toString() ?? '';
        }

        final descRuns = header['description']?['runs'] as List?;
        if (descRuns != null && descRuns.isNotEmpty) {
          description = descRuns.map((r) => r['text']?.toString() ?? '').join('').trim();
        }
      }

      // 2. Tracks from playlist shelf
      final tracks = <Track>[];
      final itemRenderers = _collectRenderers(data, 'musicResponsiveListItemRenderer');
      final seenIds = <String>{};
      for (final renderer in itemRenderers) {
        final track = _parseTrackFromRenderer(renderer);
        if (track != null && seenIds.add(track.id)) {
          tracks.add(track);
        }
      }

      // 3. Collage thumbnails (if playlist has multiple tracks)
      List<String>? collageThumbnails;
      final uniqueArtworks = tracks
          .map((t) => t.albumArt)
          .where((art) => art.isNotEmpty)
          .toSet()
          .take(4)
          .toList();
      if (uniqueArtworks.length >= 4) {
        collageThumbnails = uniqueArtworks;
      }

      return PlaylistDetailData(
        title: title,
        curatorName: curatorName,
        viewsText: viewsText,
        trackCount: tracks.length,
        coverUrl: coverUrl,
        collageThumbnails: collageThumbnails,
        description: description,
        tracks: tracks,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('InnerTubeService: getPlaylistPageData error: $e');
      return const PlaylistDetailData(
        title: 'Playlist',
        curatorName: 'YouTube Music',
        coverUrl: '',
      );
    }
  }

  Album? _parseAlbumFromRenderer(Map<String, dynamic> renderer) {
    try {
      final navEndpoint = renderer['navigationEndpoint'];
      final browseId = navEndpoint?['browseEndpoint']?['browseId'];
      if (browseId == null) return null;

      final title = renderer['title']?['runs']?[0]?['text'] ?? 'Unknown Album';
      final subtitleRuns = renderer['subtitle']?['runs'] as List?;
      String artist = '';
      if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
        artist = subtitleRuns[0]['text'] ?? '';
      }

      String? thumbnail;
      final thumbnails = renderer['thumbnailRenderer']
          ?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnail = thumbnails.last['url'];
      }

      return Album(
        id: browseId,
        name: title,
        artistName: artist,
        imageUrl: thumbnail ?? '',
        tracks: [],
      );
    } catch (e) {
      return null;
    }
  }

  /// Get Playlist Details
  Future<List<Track>> getPlaylistDetails(String browseId) async {
    try {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Getting playlist details for $browseId');
      }
      // Ensure browseId starts with VL if needed? Usually passing ID directly works.

      final String resolvedBrowseId;
      if (browseId.startsWith('VL')) {
        resolvedBrowseId = browseId;
      } else if (browseId.startsWith('PL') || browseId.startsWith('RDCLAK')) {
        resolvedBrowseId = 'VL$browseId';
      } else {
        resolvedBrowseId = browseId;
      }

      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': resolvedBrowseId,
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Playlist browse failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final tracks = <Track>[];

      // Playlist structure:
      // contents -> twoColumnBrowseResultsRenderer -> secondaryContents -> sectionListRenderer -> contents -> musicPlaylistShelfRenderer
      // OR singleColumn...

      final secondaryContents = data['contents']
              ?['twoColumnBrowseResultsRenderer']?['secondaryContents']
          ?['sectionListRenderer']?['contents'];

      if (secondaryContents != null) {
        for (final section in secondaryContents) {
          final shelf = section['musicPlaylistShelfRenderer'];
          if (shelf != null) {
            final contents = shelf['contents'] as List?;
            if (contents != null) {
              for (final item in contents) {
                final renderer = item['musicResponsiveListItemRenderer'];
                if (renderer != null) {
                  final track = _parseTrackFromRenderer(renderer);
                  if (track != null) tracks.add(track);
                }
              }
            }
          }
        }
      }

      // Fallback for SingleColumn (official YouTube chart playlists, user playlists)
      if (tracks.isEmpty) {
        return _songsFromAllShelves(data, 100);
      }

      return tracks;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Playlist details error: $e');
      }
      return [];
    }
  }

  /// Get Album Tracks (for browsing from artist detail screen)
  /// Album browseIds typically start with 'MPREb_' for music albums
  Future<List<Track>> getAlbumTracks(String browseId) async {
    try {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Getting album tracks for $browseId');
      }

      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': browseId,
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Album browse failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final tracks = <Track>[];

      // Album Structure:
      // contents -> twoColumnBrowseResultsRenderer -> secondaryContents ->
      //   sectionListRenderer -> contents -> musicShelfRenderer -> contents
      // OR singleColumnBrowseResultsRenderer for some albums

      // Try twoColumn first (standard album layout)
      final secondaryContents = data['contents']
              ?['twoColumnBrowseResultsRenderer']?['secondaryContents']
          ?['sectionListRenderer']?['contents'];

      if (secondaryContents != null) {
        for (final section in secondaryContents) {
          final shelf = section['musicShelfRenderer'];
          if (shelf != null) {
            final contents = shelf['contents'] as List?;
            if (contents != null) {
              for (final item in contents) {
                final renderer = item['musicResponsiveListItemRenderer'];
                if (renderer != null) {
                  final track = _parseTrackFromRenderer(renderer);
                  if (track != null) tracks.add(track);
                }
              }
            }
          }
        }
      }

      // Fallback: Try singleColumn (for some album formats)
      if (tracks.isEmpty) {
        final tabs =
            data['contents']?['singleColumnBrowseResultsRenderer']?['tabs'];
        if (tabs != null && (tabs as List).isNotEmpty) {
          final sections = tabs[0]?['tabRenderer']?['content']
              ?['sectionListRenderer']?['contents'] as List?;
          if (sections != null) {
            for (final section in sections) {
              final shelf = section['musicShelfRenderer'];
              if (shelf != null) {
                final contents = shelf['contents'] as List?;
                if (contents != null) {
                  for (final item in contents) {
                    final renderer = item['musicResponsiveListItemRenderer'];
                    if (renderer != null) {
                      final track = _parseTrackFromRenderer(renderer);
                      if (track != null) tracks.add(track);
                    }
                  }
                }
              }
            }
          }
        }
      }

      if (kDebugMode) {
        debugPrint('InnerTubeService: Found ${tracks.length} tracks in album');
      }
      return tracks;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Album tracks error: $e');
      }
      return [];
    }
  }

  /// [allowBrowseIds] - when true, allows UC/VL/PL IDs (for artist/playlist search)
  Track? _parseTrackFromTwoRowRenderer(Map<String, dynamic> renderer,
      {bool allowBrowseIds = false}) {
    try {
      // Get video ID or Browse ID
      final navEndpoint = renderer['navigationEndpoint'];
      final videoId = navEndpoint?['watchEndpoint']?['videoId'] ??
          navEndpoint?['browseEndpoint']?['browseId'];

      if (videoId == null) return null;

      // Title
      final title = renderer['title']?['runs']?[0]?['text'] ?? 'Unknown';

      // Subtitle (artist/metadata)
      String artist = 'Unknown Artist';
      String album = '';

      final subtitleRuns = renderer['subtitle']?['runs'] as List?;
      if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
        // Check if this is an Artist or Playlist card based on subtitle text or ID
        final firstRun = subtitleRuns[0]['text'];
        final isArtist = firstRun == 'Artist' || (videoId.startsWith('UC'));
        final isPlaylist = firstRun == 'Playlist' ||
            (videoId.startsWith('VL') ||
                videoId.startsWith('PL') ||
                videoId.startsWith('OLAK'));

        // Skip non-playable items ONLY when NOT in browse mode
        // Artists and Playlists need to be navigated to, not played directly
        if (!allowBrowseIds && (isArtist || isPlaylist)) {
          if (kDebugMode) {
            debugPrint(
                'InnerTubeService: Skipping non-playable item: $title (ID: $videoId)');
          }
          return null;
        }

        // Normal Song or browse mode: extract clean artist and album
        final extracted = _extractCreditsFromRuns(subtitleRuns, trackTitle: title);
        if (extracted.artist.isNotEmpty) artist = extracted.artist;
        if (extracted.album.isNotEmpty) album = extracted.album;
      }

      // Thumbnail
      String? thumbnail;
      final thumbnails = renderer['thumbnailRenderer']
          ?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnail = thumbnails.last['url'];
      }

      final rawTrack = Track(
        id: videoId,
        trackName: title,
        artistName: artist,
        albumName: album,
        albumArt: thumbnail ?? '',
        previewUrl: '',
        source: 'youtube',
      );

      return TrackMetadataEnricher.sanitizeTrack(rawTrack);
    } catch (e) {
      return null;
    }
  }

  /// Get YouTube Music transcript (for lyrics)
  Future<String?> getTranscript(String videoId) async {
    try {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Getting transcript for $videoId');
      }

      // Encode the params properly
      final params = base64Encode(utf8.encode('\n\x0b$videoId'));

      final body = jsonEncode({
        'context': _buildContext(),
        'params': params,
      });

      final response = await _httpClient.post(
        Uri.parse(
            '$_apiUrl/get_transcript?key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX3&prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);
      return _parseTranscript(data);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Transcript error: $e');
      }
      return null;
    }
  }

  /// Parse transcript response into LRC format
  String? _parseTranscript(Map<String, dynamic> data) {
    try {
      final cueGroups = data['actions']?[0]?['updateEngagementPanelAction']
              ?['content']?['transcriptRenderer']?['body']
          ?['transcriptBodyRenderer']?['cueGroups'] as List?;

      if (cueGroups == null || cueGroups.isEmpty) return null;

      final buffer = StringBuffer();

      for (final group in cueGroups) {
        final cue = group['transcriptCueGroupRenderer']?['cues']?[0]
            ?['transcriptCueRenderer'];
        if (cue == null) continue;

        final startMs = cue['startOffsetMs'] as int? ?? 0;
        final text = (cue['cue']?['simpleText'] as String? ?? '')
            .replaceAll('♪', '')
            .trim();

        if (text.isEmpty) continue;

        // Convert to LRC format [mm:ss.xxx]
        final minutes = startMs ~/ 60000;
        final seconds = (startMs ~/ 1000) % 60;
        final millis = startMs % 1000;

        buffer.writeln(
            '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}]$text');
      }

      final result = buffer.toString().trim();
      return result.isEmpty ? null : result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Transcript parse error: $e');
      }
      return null;
    }
  }

  /// Get suggestions/recommendations for a track. Feeds AutoPlay with
  /// YouTube Music's official "RDAMVM" radio mix.
  Future<List<Track>> getSuggestions(String videoId, {int limit = 15}) async {
    return getRadioTracks(videoId, limit: limit);
  }

  /// What YouTube Music would play on after [videoId]. Feeds AutoPlay; the
  /// seed track itself comes back first, followed by curated similar tracks.
  Future<List<Track>> getRadioTracks(String videoId, {int limit = 15}) async {
    try {
      final body = jsonEncode({
        'context': _buildContext(clientType: YouTubeClientType.webRemix),
        'videoId': videoId,
        'playlistId': 'RDAMVM$videoId',
        'isAudioOnly': true,
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/next?prettyPrint=false'),
        headers: _buildHeaders(clientType: YouTubeClientType.webRemix),
        body: body,
      );

      if (response.statusCode != 200) {
        throw Exception('Next failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      return _parseNextResults(data, limit);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Suggestions error: $e');
      }
      return [];
    }
  }

  /// Resolves the authoritative artist and album metadata for a track from its
  /// watch queue entry (matching BitChord's `trackLinks`).
  Future<Track?> fetchTrackLinks(String videoId) async {
    try {
      final body = jsonEncode({
        'context': _buildContext(clientType: YouTubeClientType.webRemix),
        'videoId': videoId,
        'playlistId': 'RDAMVM$videoId',
        'isAudioOnly': true,
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/next?prettyPrint=false'),
        headers: _buildHeaders(clientType: YouTubeClientType.webRemix),
        body: body,
      );

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final renderers = _collectRenderers(data, 'playlistPanelVideoRenderer');
      if (renderers.isEmpty) return null;

      final match = renderers.firstWhere(
        (r) => r['videoId'] == videoId,
        orElse: () => renderers.first,
      );

      return _parsePlaylistPanelVideoRenderer(match);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: fetchTrackLinks error: $e');
      }
      return null;
    }
  }

  /// Parses watch queue entries from [data] using recursive renderer scanning.
  List<Track> _parseNextResults(Map<String, dynamic> data, int limit) {
    final tracks = <Track>[];
    final seenIds = <String>{};

    try {
      final renderers = _collectRenderers(data, 'playlistPanelVideoRenderer');
      for (final renderer in renderers) {
        if (tracks.length >= limit) break;
        final track = _parsePlaylistPanelVideoRenderer(renderer);
        if (track != null && seenIds.add(track.id)) {
          tracks.add(track);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Next parse error: $e');
      }
    }

    return tracks;
  }

  /// Parses a single `playlistPanelVideoRenderer` into a clean [Track].
  Track? _parsePlaylistPanelVideoRenderer(Map<String, dynamic> renderer) {
    final videoId = renderer['videoId']?.toString();
    if (videoId == null || videoId.isEmpty) return null;

    final title = (renderer['title']?['runs'] as List?)
            ?.map((r) => r['text']?.toString() ?? '')
            .join('')
            .trim() ??
        'Unknown';
    if (title.isEmpty) return null;

    final bylineRuns = (renderer['longBylineText']?['runs'] ??
        renderer['shortBylineText']?['runs']) as List?;

    String artist = 'Unknown Artist';
    String album = '';

    if (bylineRuns != null && bylineRuns.isNotEmpty) {
      final extracted = _extractCreditsFromRuns(bylineRuns, trackTitle: title);
      if (extracted.artist.isNotEmpty) artist = extracted.artist;
      if (extracted.album.isNotEmpty) album = extracted.album;
    }

    String? thumbnail;
    final thumbnails = renderer['thumbnail']?['thumbnails'] as List?;
    if (thumbnails != null && thumbnails.isNotEmpty) {
      thumbnail = thumbnails.last['url']?.toString();
      if (thumbnail != null && thumbnail.contains('lh3.googleusercontent.com')) {
        thumbnail = thumbnail.replaceAll(RegExp(r'=w\d+-h\d+'), '=w500-h500');
      }
    }

    final durationText = (renderer['lengthText']?['runs'] as List?)
        ?.firstOrNull?['text']
        ?.toString();
    final durationMs = durationText != null ? _parseDuration(durationText) : null;

    final rawTrack = Track(
      id: videoId,
      trackName: title,
      artistName: artist,
      albumName: album,
      albumArt: thumbnail ?? '',
      previewUrl: '',
      source: 'youtube',
      durationMs: durationMs,
    );

    return TrackMetadataEnricher.sanitizeTrack(rawTrack);
  }

  /// Recursively walks [root] collecting all maps matching [rendererName].
  List<Map<String, dynamic>> _collectRenderers(dynamic root, String rendererName) {
    final out = <Map<String, dynamic>>[];
    void walk(dynamic node) {
      if (node is Map<String, dynamic>) {
        final match = node[rendererName];
        if (match is Map<String, dynamic>) out.add(match);
        for (final val in node.values) {
          walk(val);
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }
    walk(root);
    return out;
  }

  /// Extracts clean artist and album strings from run elements using
  /// browseEndpoints (when present) or delimiter separation, avoiding
  /// concatenating albums/song names into artist credits.
  ({String artist, String album}) _extractCreditsFromRuns(
    List runs, {
    String? trackTitle,
  }) {
    final artistNames = <String>[];
    String? albumName;

    for (final run in runs) {
      if (run is! Map) continue;
      final text = run['text'];
      if (text is! String || text.trim().isEmpty) continue;
      final trimmed = text.trim();
      if (trimmed == '•' || trimmed == '·' || trimmed == '|' || _isMetadataRun(trimmed)) {
        continue;
      }

      final browse = run['navigationEndpoint']?['browseEndpoint'];
      if (browse is Map) {
        final pageType = browse['browseEndpointContextSupportedConfigs']
                ?['browseEndpointContextMusicConfig']?['pageType']
            ?.toString() ??
            '';
        final browseId = browse['browseId']?.toString() ?? '';

        if (pageType.contains('ARTIST') || browseId.startsWith('UC')) {
          if (!artistNames.contains(trimmed)) artistNames.add(trimmed);
          continue;
        }
        if (pageType.contains('ALBUM') ||
            browseId.startsWith('MPRE') ||
            browseId.startsWith('OLAK')) {
          albumName ??= trimmed;
          continue;
        }
      }
    }

    if (artistNames.isNotEmpty || albumName != null) {
      final sanitized = TrackMetadataEnricher.sanitize(
        title: trackTitle ?? '',
        artist: artistNames.join(', '),
        album: albumName ?? '',
      );
      return (artist: sanitized.artist, album: sanitized.album);
    }

    // Fallback when runs do not carry browse endpoints:
    // 1. Safely filter for maps with string 'text' (ignores null, int, etc.)
    final validRuns = runs
        .whereType<Map>()
        .where((r) => r['text'] != null && r['text'] is String)
        .toList();

    // 2. Partition runs by bullets ('•', '·', '|'):
    //    Section 0 = artists (which may contain '&' or ',' delimiters)
    //    Section 1+ = album or metadata
    final sections = <List<String>>[];
    var currentSection = <String>[];

    for (final r in validRuns) {
      final text = (r['text'] as String).trim();
      if (text == '•' || text == '·' || text == '|') {
        if (currentSection.isNotEmpty) {
          sections.add(currentSection);
          currentSection = [];
        }
      } else if (text.isNotEmpty && !_isMetadataRun(text)) {
        currentSection.add(text);
      }
    }
    if (currentSection.isNotEmpty) {
      sections.add(currentSection);
    }

    if (sections.isEmpty) {
      return (artist: '', album: '');
    }

    // Artist names from section 0 (skipping '&', ',', '/', 'feat.', 'ft.')
    final artistCandidates = sections[0]
        .where((t) =>
            t != '&' &&
            t != ',' &&
            t != '/' &&
            t.toLowerCase() != 'feat.' &&
            t.toLowerCase() != 'ft.')
        .where((t) {
          final lower = t.toLowerCase();
          return lower != 'song' && lower != 'video';
        })
        .where((t) => trackTitle == null || t.toLowerCase() != trackTitle.toLowerCase())
        .toList();

    final rawArtist = artistCandidates.join(', ');

    // Album name from remaining sections (if not generic label or metadata)
    String rawAlbum = '';
    if (sections.length > 1) {
      for (int i = 1; i < sections.length; i++) {
        final cand = sections[i]
            .where((t) => t != '&' && t != ',' && t != '/')
            .join(' ')
            .trim();
        final lower = cand.toLowerCase();
        if (lower != 'song' &&
            lower != 'video' &&
            lower != 'single' &&
            lower != 'ep' &&
            !_isMetadataRun(cand) &&
            (trackTitle == null || lower != trackTitle.toLowerCase())) {
          rawAlbum = cand;
          break;
        }
      }
    }

    if (rawArtist.isEmpty && rawAlbum.isEmpty) {
      return (artist: '', album: '');
    }

    final sanitized = TrackMetadataEnricher.sanitize(
      title: trackTitle ?? '',
      artist: rawArtist,
      album: rawAlbum,
    );
    return (artist: sanitized.artist, album: sanitized.album);
  }

  /// Trusted trending/charts browse (FEmusic_charts).
  ///
  /// NO search-keyword fallback: hardcoded searches ('top hits 2024') were
  /// returning stale arbitrary uploads under the "Trending" name. Empty or
  /// failed chart browse now propagates — the Home pipeline falls back to
  /// new releases, and callers decide, instead of silently getting random
  /// search results dressed as trending.
  Future<List<Track>> getTrendingTracks({int limit = 20}) async {
    try {
      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': 'FEmusic_charts',
        'params': 'ggMGCgQIgAQ%3D',
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
              'InnerTubeService: charts browse failed: ${response.statusCode}');
        }
        return [];
      }

      final tracks = _parseHomeResults(jsonDecode(response.body), limit);
      if (tracks.isNotEmpty) return tracks;
      // Charts sometimes serve music-video/playlist shelves first (all
      // VL/UC ids → skipped by _parseHomeResults). Walk every shelf and
      // keep real songs (11-char videoId) from anywhere in the payload
      // before giving up — "Trending" must not silently be empty.
      return _songsFromAllShelves(jsonDecode(response.body), limit);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InnerTubeService: Trending error: $e');
      }
      return [];
    }
  }

  void dispose() {
    _httpClient.close();
  }

  /// Metadata-run detector shared by artist-run joins: durations ("3:44",
  /// "1:02:33") and engagement counts ("106M plays", "1.8B views") are
  /// never artists.
  static final RegExp _metadataDuration = RegExp(r'^\d{1,3}:\d{2}(:\d{2})?$');
  static final RegExp _metadataCount = RegExp(
      r'^[\d,.]+\s*[KMB]?\s*(plays?|views?|streams?|listeners?|monthly listeners?)$',
      caseSensitive: false);
  static bool _isMetadataRun(String text) =>
      _metadataDuration.hasMatch(text.trim()) ||
      _metadataCount.hasMatch(text.trim());

  /// Deep walk of a browse payload collecting ONLY real songs (11-char
  /// videoId, no browse-prefix ids) from every shelf, in source order.
  /// Used when the standard first-shelf parse yields nothing (charts that
  /// lead with music-video/playlist shelves).
  List<Track> _songsFromAllShelves(Map<String, dynamic> data, int limit) {
    final tracks = <Track>[];
    final seen = <String>{};
    void walk(dynamic node) {
      if (tracks.length >= limit) return;
      if (node is List) {
        for (final child in node) {
          walk(child);
        }
        return;
      }
      if (node is! Map<String, dynamic>) return;
      final responsive = node['musicResponsiveListItemRenderer'];
      if (responsive is Map<String, dynamic>) {
        final track = _parseTrackFromRenderer(responsive);
        if (track != null &&
            track.id.length == 11 &&
            seen.add(track.id)) {
          tracks.add(track);
        }
        return;
      }
      node.values.forEach(walk);
    }

    walk(data);
    if (kDebugMode && tracks.isNotEmpty) {
      debugPrint(
          'InnerTubeService: charts deep-walk recovered ${tracks.length} songs');
    }
    return tracks;
  }
}

class _CachedBrowseEntry {
  final Object? value;
  final DateTime timestamp;

  _CachedBrowseEntry(this.value) : timestamp = DateTime.now();

  bool isExpired(Duration duration) {
    return DateTime.now().difference(timestamp) > duration;
  }
}
