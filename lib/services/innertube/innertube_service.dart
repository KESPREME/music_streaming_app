import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../auth_service.dart';
import '../youtube_stream_source.dart';
import '../cobalt_service.dart';
import '../piped_service.dart';
import '../piped_service.dart';
import '../../models/track.dart';
import '../../models/album.dart'; // Import Album model
import '../youtube_clients.dart'; // Import custom clients

/// YouTube client types for different use cases
enum YouTubeClientType {
  webRemix,      // For search and browse
  androidVr143,  // Primary player 
  androidVr161,  // Secondary player
  ios,           // Fallback player
}

/// InnerTube API client for YouTube Music

class InnerTubeService {
  static const String _apiUrl = 'https://music.youtube.com/youtubei/v1';
  static const String _origin = 'https://music.youtube.com';
  static const String _referer = 'https://music.youtube.com/';
  
  // WEB_REMIX client (for search, browse)
  static const String _webRemixClientName = 'WEB_REMIX';
  static const String _webRemixClientVersion = '1.20251227.01.00';
  static const String _webRemixClientId = '67';
  static const String _webRemixUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0';
  
  // ANDROID_VR client 1.43.32 
  // "Uses non adaptive bitrate, which fixes audio stuttering... Does not use AV1"
  static const String _androidVr143ClientName = 'ANDROID_VR';
  static const String _androidVr143ClientVersion = '1.43.32';
  static const String _androidVrClientId = '28';
  static const String _androidVr143UserAgent = 'com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)';
  
  // ANDROID_VR client 1.61.48 (Fallback)
  static const String _androidVr161ClientName = 'ANDROID_VR';
  static const String _androidVr161ClientVersion = '1.61.48';
  static const String _androidVr161UserAgent = 'com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)';

  // iOS client (Fallback)
  static const String _iosClientName = 'IOS';
  static const String _iosClientVersion = '20.51.39';
  static const String _iosClientId = '5';
  static const String _iosUserAgent = 'com.google.ios.youtube/20.51.39 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)';
  
  String? visitorData;
  String? cookie;
  
  final http.Client _httpClient = http.Client();
  final CobaltService _cobaltService = CobaltService();
  final YoutubeExplode _yt = YoutubeExplode(); // Persistent instance optimization
  
  // --- URL Cache ---
  static final Map<String, _CachedUrlEntry> _urlCache = {};
  static const Duration _cacheDuration = Duration(minutes: 90);

  /// Prefetch a song's URL and cache it
  Future<void> prefetch(String videoId) async {
    if (_urlCache.containsKey(videoId)) {
      final entry = _urlCache[videoId]!;
      if (!entry.isExpired(_cacheDuration)) return;
    }
    
    if (kDebugMode) print('InnerTubeService: Prefetching $videoId...');
    try {
      // Just call getAudioStreamUrl, it will handle fetching and caching
      await getAudioStreamUrl(videoId);
    } catch (e) {
      if (kDebugMode) print('InnerTubeService: Prefetch failed for $videoId: $e');
    }
  }
  
  /// Helper to get cached URL if valid
  Future<String?> _getCachedUrl(String videoId) async {
    if (!_urlCache.containsKey(videoId)) return null;
    
    final entry = _urlCache[videoId]!;
    if (entry.isExpired(_cacheDuration)) {
      _urlCache.remove(videoId);
      return null;
    }
    
    // Optional: Validate if the URL is still accessible (HEAD request)
    // This adds latency, so maybe skip for very recent entries (e.g. < 10 mins)
    // For now, trusting the 90m expiration as Musify does.
    return entry.url;
  }
  
  void _cacheUrl(String videoId, String url) {
    _urlCache[videoId] = _CachedUrlEntry(url, DateTime.now());
  }

  
  /// Build the context object required for all InnerTube requests
  Map<String, dynamic> _buildContext({YouTubeClientType clientType = YouTubeClientType.webRemix}) {
    switch (clientType) {
      case YouTubeClientType.androidVr143:
        return {
          'client': {
            'clientName': _androidVr143ClientName,
            'clientVersion': _androidVr143ClientVersion,
            'osName': 'Android',
            'osVersion': '12',
            'deviceMake': 'Oculus',
            'deviceModel': 'Quest 3',
            'androidSdkVersion': '32',
            'hl': 'en',
            'gl': 'US',
          },
        };
      case YouTubeClientType.androidVr161:
        return {
          'client': {
            'clientName': _androidVr161ClientName,
            'clientVersion': _androidVr161ClientVersion,
            'osName': 'Android',
            'osVersion': '12',
            'deviceMake': 'Oculus',
            'deviceModel': 'Quest 3',
            'androidSdkVersion': '32',
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
      default:
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
  Map<String, String> _buildHeaders({YouTubeClientType clientType = YouTubeClientType.webRemix}) {
    String userAgent;
    String clientId;
    String clientVersion;
    
    switch (clientType) {
      case YouTubeClientType.androidVr143:
        userAgent = _androidVr143UserAgent;
        clientId = _androidVrClientId;
        clientVersion = _androidVr143ClientVersion;
        break;
      case YouTubeClientType.androidVr161:
        userAgent = _androidVr161UserAgent;
        clientId = _androidVrClientId;
        clientVersion = _androidVr161ClientVersion;
        break;
      case YouTubeClientType.ios:
        userAgent = _iosUserAgent;
        clientId = _iosClientId;
        clientVersion = _iosClientVersion;
        break;
      case YouTubeClientType.webRemix:
      default:
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
    
    // Inject Authentication (Cookies + SAPISIDHASH)
    // This upgrades the client to a "Logged In" state
    final authHeaders = AuthService().getHeaders();
    if (authHeaders.isNotEmpty) {
       headers.addAll(authHeaders);
    } else if (cookie != null && clientType == YouTubeClientType.webRemix) {
       // Legacy/Manual cookie fallback (if AuthService specific logic not used)
       headers['Cookie'] = cookie!;
    }
    
    return headers;
  }
  


  /// Search for artists
  Future<List<Track>> searchArtists(String query, {int limit = 20}) async {
    return _searchWithParams(query, 'EgWKAQIgAWoKEAkQBRAKEAMQBA%3D%3D', limit); // FILTER_ARTIST
  }

  /// Search for playlists
  Future<List<Track>> searchPlaylists(String query, {int limit = 20}) async {
    return _searchWithParams(query, 'EgWKAQIoAWoKEAkQBRAKEAMQBA%3D%3D', limit); // FILTER_PLAYLIST
  }

  Future<List<Track>> _searchWithParams(String query, String params, int limit) async {
    try {
      if (kDebugMode) print('InnerTubeService: Searching "$query" with params $params');
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

      if (response.statusCode != 200) throw Exception('Search failed: ${response.statusCode}');
      final data = jsonDecode(response.body);
      
      // Parse Logic (Similar to _parseSearchResults but generic)
      // Note: Layout might differ for artists/playlists (TwoRowItemRenderer often)
      // I'll reuse _parseSearchResults or create a unified one.
      // Actually standard _parseSearchResults handles ResponsiveList and TwoRow.
      return _parseSearchResults(data, limit);
    } catch (e) {
      if (kDebugMode) print('InnerTubeService: Search error: $e');
      rethrow;
    }
  }

  /// Search for songs on YouTube Music
  Future<List<Track>> searchSongs(String query, {int limit = 20}) async {
    try {
      if (kDebugMode) {
        print('InnerTubeService: Searching for "$query"');
      }
      return _searchWithParams(query, 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D', limit);
    } catch (e) {
       rethrow;
    }
  }
  
  /// Parse search results into Track objects
  /// Parse search results into Track objects
  List<Track> _parseSearchResults(Map<String, dynamic> data, int limit) {
    final tracks = <Track>[];
    
    try {
      // Navigate to the music shelf renderer
      final tabs = data['contents']?['tabbedSearchResultsRenderer']?['tabs'];
      if (tabs == null || tabs.isEmpty) return tracks;
      
      final contents = tabs[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
      if (contents == null) return tracks;
      
      for (final section in contents) {
        // 1. Check for standard MusicShelfRenderer (List)
        final shelfContents = section['musicShelfRenderer']?['contents'];
        if (shelfContents != null) {
          for (final item in shelfContents) {
            if (tracks.length >= limit) break;
            
            // Try responsive list item
            if (item['musicResponsiveListItemRenderer'] != null) {
               final track = _parseTrackFromRenderer(item['musicResponsiveListItemRenderer']);
               if (track != null) tracks.add(track);
            }
            // Try multi-row item (sometimes used)
            else if (item['musicTwoRowItemRenderer'] != null) {
               final track = _parseTrackFromTwoRowRenderer(item['musicTwoRowItemRenderer']);
               if (track != null) tracks.add(track);
            }
          }
        }
        
        // 2. Check for MusicCardShelfRenderer (Top Result / Artist Card)
        final cardShelf = section['musicCardShelfRenderer'];
        if (cardShelf != null && tracks.length < limit) {
           final title = cardShelf['title']?['runs']?[0]?['text'];
           final subtitle = cardShelf['subtitle']?['runs']?[0]?['text'];
           final videoId = cardShelf['onTap']?['watchEndpoint']?['videoId'] ?? 
                           cardShelf['buttons']?[0]?['buttonRenderer']?['command']?['watchEndpoint']?['videoId'];
           // Thumbnail
           final thumbnails = cardShelf['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
           String? thumbnail = (thumbnails != null && thumbnails.isNotEmpty) ? thumbnails.last['url'] : null;

           if (videoId != null || title != null) {
              // Create a synthesized track for the card (Artist/Top Result)
              // For Artist mode, the "videoId" might be a browseId, which generic Track doesn't fully support as ID?
              // But searchArtists returns Track objects. If videoId is null, we might need a browseId logic.
              // However, our Track model expects ID. 
              // Usually Top Result for Song has ID. Top Result for Artist has navigationEndpoint -> browseId.
              // If we are searching Artists, we might want to skip if no ID, OR use browseId as ID.
              // Let's rely on standard parsing for now, or minimal ID generation.
              // For now, if videoId is missing, we skip, as playback requires videoId.
              // UNLESS it's an Artist search where we just want metadata? 
              // The UI likely tries to play it or open artist page. 
              // Let's handle the Card carefully.
              
              if (videoId != null) {
                  tracks.add(Track(
                    id: videoId,
                    trackName: title ?? 'Unknown',
                    artistName: subtitle ?? '',
                    albumName: '', 
                    previewUrl: '', // Added missing required parameter
                    albumArt: thumbnail ?? '',
                    source: 'youtube',
                    durationMs: 0
                  ));
              }
           }
        }

        if (tracks.length >= limit) break;
      }
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: Parse error: $e');
      }
    }
    
    return tracks;
  }
  
  /// Parse a track from MusicResponsiveListItemRenderer
  Track? _parseTrackFromRenderer(Map<String, dynamic> renderer) {
    try {
      // Get video ID or Browse ID (for playlists/artists)
      String? videoId = renderer['playlistItemData']?['videoId'];
      
      // Check watch endpoint
      videoId ??= renderer['overlay']?['musicItemThumbnailOverlayRenderer']
            ?['content']?['musicPlayButtonRenderer']?['playNavigationEndpoint']
            ?['watchEndpoint']?['videoId'];
            
      // Check navigation endpoint (Browse ID for artists/playlists fallback)
      if (videoId == null) {
          final navEndpoint = renderer['navigationEndpoint'];
          videoId = navEndpoint?['watchEndpoint']?['videoId'] ?? 
                    navEndpoint?['browseEndpoint']?['browseId'];
      }
      
      // If still null, return null (item not usable)
      if (videoId == null) return null;
      
      // FIX: Filter out non-playable items (artists, playlists, albums)
      // These IDs start with specific prefixes and can't be streamed directly
      if (videoId.startsWith('UC') ||    // Artist/Channel
          videoId.startsWith('VL') ||    // Playlist
          videoId.startsWith('PL') ||    // Playlist  
          videoId.startsWith('OLAK') ||  // Album
          videoId.startsWith('MPREb')) { // Album browse ID
        if (kDebugMode) print('InnerTubeService: Skipping non-playable ID: $videoId');
        return null;
      }
      
      // Get flex columns for title and artist
      final flexColumns = renderer['flexColumns'] as List?;
      if (flexColumns == null || flexColumns.isEmpty) return null;
      
      // Title from first column
      String title = 'Unknown';
      final titleRuns = flexColumns[0]?['musicResponsiveListItemFlexColumnRenderer']
          ?['text']?['runs'] as List?;
      if (titleRuns != null && titleRuns.isNotEmpty) {
        title = titleRuns[0]['text'] ?? 'Unknown';
      }
      
      // Artist from second column
      String artist = 'Unknown Artist';
      if (flexColumns.length > 1) {
        final artistRuns = flexColumns[1]?['musicResponsiveListItemFlexColumnRenderer']
            ?['text']?['runs'] as List?;
        if (artistRuns != null && artistRuns.isNotEmpty) {
          // Join all artist names
          artist = artistRuns
              .where((r) => r['text'] != null && r['text'] != ' • ' && r['text'] != ' & ')
              .map((r) => r['text'])
              .take(3)
              .join(', ');
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
        if (thumbnail != null && thumbnail.contains('lh3.googleusercontent.com')) {
          thumbnail = thumbnail.replaceAll(RegExp(r'=w\d+-h\d+'), '=w500-h500');
        }
      }
      
      // Duration (from third column or fixed columns)
      int? durationMs;
      if (flexColumns.length > 2) {
        final durationText = flexColumns[2]?['musicResponsiveListItemFlexColumnRenderer']
            ?['text']?['runs']?[0]?['text'];
        if (durationText != null) {
          durationMs = _parseDuration(durationText);
        }
      }
      // Also try fixed columns
      final fixedColumns = renderer['fixedColumns'] as List?;
      if (fixedColumns != null && fixedColumns.isNotEmpty) {
        final durationText = fixedColumns[0]?['musicResponsiveListItemFixedColumnRenderer']
            ?['text']?['runs']?[0]?['text'];
        if (durationText != null) {
          durationMs = _parseDuration(durationText);
        }
      }
      
      return Track(
        id: videoId,
        trackName: title,
        artistName: artist,
        albumName: '', // Not always available in search
        albumArt: thumbnail ?? '',
        previewUrl: '', // Will be fetched when playing
        source: 'youtube',
        durationMs: durationMs,
      );
      
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: Track parse error: $e');
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
        print('InnerTubeService: Getting player for $videoId using ANDROID_VR');
      }
      
      final result = await _getPlayerWithClient(videoId, YouTubeClientType.androidVr143);
      
      // Check if playable
      final status = result['playabilityStatus']?['status'];
      if (status == 'OK') {
        return result;
      }
      
      // If not OK, try iOS client as fallback
      if (kDebugMode) {
        print('InnerTubeService: ANDROID_VR failed ($status), trying iOS client');
      }
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: ANDROID_VR error: $e, trying iOS');
      }
    }
    
    // Fallback to iOS client
    try {
      final result = await _getPlayerWithClient(videoId, YouTubeClientType.ios);
      return result;
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: iOS client also failed: $e');
      }
      rethrow;
    }
  }
  
  /// Get player response with specific client type
  Future<Map<String, dynamic>> _getPlayerWithClient(String videoId, YouTubeClientType clientType) async {
    final body = jsonEncode({
      'context': _buildContext(clientType: clientType),
      'videoId': videoId,
      'racyCheckOk': true,
      'contentCheckOk': true,
    });
    
    final response = await _httpClient.post(
      Uri.parse('$_apiUrl/player?prettyPrint=false'),
      headers: _buildHeaders(clientType: clientType),
      body: body,
    );
    
    if (response.statusCode != 200) {
      throw Exception('Player request failed: ${response.statusCode}');
    }
    
    return jsonDecode(response.body);
  }
  
  /// Get the best audio stream
  /// Returns [AudioSource] (for YoutubeExplode proxy) or [String] (for URL fallback)
  Future<dynamic> getAudioStream(String videoId, {int preferredBitrate = 128}) async {
    // ... (This method logic remains the same as previously implemented)
    // I am just inserting the legacy URL method below it or ensuring it exists
    
    // Actually, I can leave this method as is (it's new) and ADD the old one back.
    // But since I can't "add" easily without context, I will replace the start of this method
    // to include the OLD method above it.
    
    return await _getAudioStreamInternal(videoId, preferredBitrate, returnSource: true);
  }

  /// Get audio stream URL (Legacy/Download support)
  /// Always returns a String URL.
  Future<String> getAudioStreamUrl(String videoId, {int preferredBitrate = 128}) async {
    // 1. Check Cache
    final cached = await _getCachedUrl(videoId);
    if (cached != null) {
      if (kDebugMode) print('InnerTubeService: Cache HIT for $videoId');
      return cached;
    }

    final result = await _getAudioStreamInternal(videoId, preferredBitrate, returnSource: false);
    if (result is String) {
      // 2. Update Cache
      _cacheUrl(videoId, result);
      return result;
    }
    // If internal returned a Source (shouldn't happen if returnSource=false), throw
    throw Exception('Failed to get URL string');
  }

  /// Internal implementation to avoid duplication
  Future<dynamic> _getAudioStreamInternal(String videoId, int preferredBitrate, {required bool returnSource}) async {
    // 1. Primary: YoutubeExplode (The "Dart NewPipe") -> ROBUST & FAST (with persistent instance)
    try {
      if (kDebugMode) print('InnerTubeService: Fetching stream via YoutubeExplode for $videoId');
      
      // Use shared instance (Optimized)
      // final yt = YoutubeExplode(); 

      try {
        if (kDebugMode) print('InnerTubeService: Fetching stream via YoutubeExplode (Optimized Clients) for $videoId');

        // Use custom clients to avoid throttling (Android VR / Sdkless)
        final manifest = await _yt.videos.streamsClient.getManifest(
          videoId, 
          ytClients: [customAndroidVr, customAndroidSdkless]
        );
        final audioStream = manifest.audioOnly.withHighestBitrate();
        
          if (returnSource) {
             // ROBUSTNESS FIX: Return the stream proxy source directly.
             // Inject Auth headers (Cookies + Auth)
             final headers = AuthService().getHeaders();
             if (kDebugMode) print('InnerTubeService: Using YoutubeExplode Stream Proxy (Fix 403) with Auth: ${headers.isNotEmpty}');
             
             // Cache the URL even if using Proxy Source, so parallel/future calls can benefit
             _cacheUrl(videoId, audioStream.url.toString());
             
             return YoutubeExplodeSource(audioStream, headers: headers);
          } else {
             // For downloads: Return the URL string
             final url = audioStream.url.toString();
             if (await _validateStreamUrl(url)) {
                return url;
             }
          }
        
      } catch (e) {
          // _yt.close(); // Do not close shared instance
          if (kDebugMode) print('InnerTubeService: YoutubeExplode failed: $e. Switching to Manual/Piped Fallbacks.');
          
          // Fallback 1: Manual InnerTube (Android VR / iOS)
          try {
            if (kDebugMode) print('InnerTubeService: Trying Manual InnerTube fallback...');
            final playerResponse = await getPlayer(videoId);
            final playabilityStatus = playerResponse['playabilityStatus'];
            if (playabilityStatus?['status'] == 'OK') {
              final streamingData = playerResponse['streamingData'];
              if (streamingData != null) {
                final directUrl = await _extractBestStream(streamingData, preferredBitrate);
                if (directUrl != null && await _validateStreamUrl(directUrl)) {
                   if (kDebugMode) print('InnerTubeService: Found valid stream via Manual InnerTube');
                   return directUrl;
                }
              }
            }
          } catch (manualErr) {
             if (kDebugMode) print('InnerTubeService: Manual InnerTube failed: $manualErr');
          }

          // Fallback 2: Cobalt
          try {
             if (kDebugMode) print('InnerTubeService: Trying Cobalt Fallback...');
             final cobaltUrl = await CobaltService().getAudioStreamUrl(videoId);
             if (returnSource) {
               return AudioSource.uri(Uri.parse(cobaltUrl), tag: videoId);
             } else {
               return cobaltUrl;
             }
          } catch (cobaltErr) {
             if (kDebugMode) print('InnerTubeService: Cobalt failed: $cobaltErr');
          }
      }
      // _yt.close(); // Do not close shared instance
    } catch (e) {
      if (kDebugMode) print('InnerTubeService: YoutubeExplode wrapper failed: $e');
    }

    // 2. Secondary: Piped API (Last Resort)
    try {
        if (kDebugMode) print('InnerTubeService: All internal methods failed. Trying Piped...');
        return await PipedService().getAudioStreamUrl(videoId);
    } catch (_) {}

    throw Exception("No valid stream found for $videoId");
  }

  // Legacy Piped method removed. Use PipedService class.

  /// Helper to extract best stream from InnerTube response
  Future<String?> _extractBestStream(Map<String, dynamic> streamingData, int preferredBitrate) async {
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

  /// Validate if a stream URL is accessible (not 403)
  Future<bool> _validateStreamUrl(String url) async {
    try {
      // CRITICAL: Dynamic User-Agent for validation
      // Must match AudioService logic to ensure valid streams aren't rejected (403).
      String? userAgent;
      if (url.contains('c=ANDROID')) {
         userAgent = 'com.google.android.youtube/17.31.35 (Linux; U; Android 11) gzip';
      } else if (url.contains('c=IOS')) {
         userAgent = 'com.google.ios.youtube/19.29.1 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X)';
      }
      
      final headers = <String, String>{
        'Accept-Encoding': 'gzip',
      };
      if (userAgent != null) {
        headers['User-Agent'] = userAgent;
      }

      final response = await _httpClient.head(
        Uri.parse(url),
        headers: headers,
      );
      if (kDebugMode) print('InnerTubeService: Stream validation status: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 206;
    } catch (e) {
      if (kDebugMode) print('InnerTubeService: Stream validation failed: $e');
      return false;
    }
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
        print('InnerTubeService: Home error: $e');
      }
      rethrow;
    }
  }
  
  /// Parse home/browse results
  List<Track> _parseHomeResults(Map<String, dynamic> data, int limit) {
    final tracks = <Track>[];
    
    try {
      final tabs = data['contents']?['singleColumnBrowseResultsRenderer']?['tabs'];
      if (tabs == null || tabs.isEmpty) return tracks;
      
      final contents = tabs[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
      if (contents == null) return tracks;
      
      for (final section in contents) {
        final carouselContents = section['musicCarouselShelfRenderer']?['contents'];
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
            final track = _parseTrackFromTwoRowRenderer(renderer);
            if (track != null) {
              tracks.add(track);
            }
          }
        }
        
        if (tracks.length >= limit) break;
      }
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: Home parse error: $e');
      }
    }
    
    return tracks;
  }

  /// Get Artist Details (Top Songs)
  Future<Map<String, dynamic>> getArtistDetails(String browseId) async {
    try {
      if (kDebugMode) print('InnerTubeService: Getting artist details for $browseId');
      
      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': browseId,
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );

      if (response.statusCode != 200) throw Exception('Artist browse failed: ${response.statusCode}');
      
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
      final tabs = data['contents']?['singleColumnBrowseResultsRenderer']?['tabs'];
      if (tabs == null || tabs.isEmpty) return {'tracks': [], 'albums': [], 'singles': []};
      
      final sections = tabs[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?;
                       
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
             final title = (carouselShelf['header']?['musicCarouselShelfBasicHeaderRenderer']?['title']?['runs']?[0]?['text'] ?? '').toString();
             final contents = carouselShelf['contents'] as List?;
             
             if (contents != null) {
               final isAlbums = title.contains('Albums');
               final isSingles = title.contains('Singles') || title.contains('EPs');
               
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
      if (kDebugMode) print('InnerTubeService: Artist details error: $e');
      return {'tracks': <Track>[], 'albums': <Album>[], 'singles': <Album>[]};
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
        final thumbnails = renderer['thumbnailRenderer']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
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
      if (kDebugMode) print('InnerTubeService: Getting playlist details for $browseId');
      // Ensure browseId starts with VL if needed? Usually passing ID directly works.
      
      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': browseId.startsWith('PL') ? 'VL$browseId' : browseId,
      });

      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );

      if (response.statusCode != 200) throw Exception('Playlist browse failed: ${response.statusCode}');
      
      final data = jsonDecode(response.body);
      final tracks = <Track>[];
      
      // Playlist structure:
      // contents -> twoColumnBrowseResultsRenderer -> secondaryContents -> sectionListRenderer -> contents -> musicPlaylistShelfRenderer
      // OR singleColumn...
      
      final secondaryContents = data['contents']?['twoColumnBrowseResultsRenderer']?['secondaryContents']
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
      
      // Fallback for SingleColumn (sometimes user created playlists?)
      if (tracks.isEmpty) {
         return _parseHomeResults(data, 100); // reuse mostly similar parser
      }
      
      return tracks;
      
    } catch (e) {
      if (kDebugMode) print('InnerTubeService: Playlist details error: $e');
      return [];
    }
  }

  /// Get Album Tracks (for browsing from artist detail screen)
  /// Album browseIds typically start with 'MPREb_' for music albums
  Future<List<Track>> getAlbumTracks(String browseId) async {
    try {
      if (kDebugMode) print('InnerTubeService: Getting album tracks for $browseId');
      
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
      final secondaryContents = data['contents']?['twoColumnBrowseResultsRenderer']
                                ?['secondaryContents']?['sectionListRenderer']?['contents'];
                                
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
        final tabs = data['contents']?['singleColumnBrowseResultsRenderer']?['tabs'];
        if (tabs != null && (tabs as List).isNotEmpty) {
          final sections = tabs[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?;
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
      
      if (kDebugMode) print('InnerTubeService: Found ${tracks.length} tracks in album');
      return tracks;
      
    } catch (e) {
      if (kDebugMode) print('InnerTubeService: Album tracks error: $e');
      return [];
    }
  }

  Track? _parseTrackFromTwoRowRenderer(Map<String, dynamic> renderer) {
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
        final isPlaylist = firstRun == 'Playlist' || (videoId.startsWith('VL') || videoId.startsWith('PL') || videoId.startsWith('OLAK'));
        
        // FIX: Skip non-playable items entirely - they can't be played as tracks
        // Artists and Playlists need to be navigated to, not played directly
        if (isArtist || isPlaylist) {
           if (kDebugMode) print('InnerTubeService: Skipping non-playable item: $title (ID: $videoId)');
           return null;
        }
        
        // Normal Song
        artist = subtitleRuns
          .where((r) => r['text'] != null && r['text'] != ' • ' && r['text'] != ' & ')
          .map((r) => r['text'])
          .take(2)
          .join(', ');
      }
      
      // Thumbnail
      String? thumbnail;
      final thumbnails = renderer['thumbnailRenderer']?['musicThumbnailRenderer']
          ?['thumbnail']?['thumbnails'] as List?;
      if (thumbnails != null && thumbnails.isNotEmpty) {
        thumbnail = thumbnails.last['url'];
      }
      
      return Track(
        id: videoId,
        trackName: title,
        artistName: artist,
        albumName: album,
        albumArt: thumbnail ?? '',
        previewUrl: '',
        source: 'youtube',
      );
      
    } catch (e) {
      return null;
    }
  }
  
  /// Get YouTube Music transcript (for lyrics)
  Future<String?> getTranscript(String videoId) async {
    try {
      if (kDebugMode) {
        print('InnerTubeService: Getting transcript for $videoId');
      }
      
      // Encode the params properly
      final params = base64Encode(utf8.encode('\n\x0b$videoId'));
      
      final body = jsonEncode({
        'context': _buildContext(),
        'params': params,
      });
      
      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/get_transcript?key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX3&prettyPrint=false'),
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
        print('InnerTubeService: Transcript error: $e');
      }
      return null;
    }
  }
  
  /// Parse transcript response into LRC format
  String? _parseTranscript(Map<String, dynamic> data) {
    try {
      final cueGroups = data['actions']?[0]?['updateEngagementPanelAction']
          ?['content']?['transcriptRenderer']?['body']?['transcriptBodyRenderer']
          ?['cueGroups'] as List?;
      
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
        
        buffer.writeln('[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}]$text');
      }
      
      final result = buffer.toString().trim();
      return result.isEmpty ? null : result;
      
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: Transcript parse error: $e');
      }
      return null;
    }
  }
  
  /// Get suggestions/recommendations for a track
  Future<List<Track>> getSuggestions(String videoId, {int limit = 10}) async {
    try {
      final body = jsonEncode({
        'context': _buildContext(),
        'videoId': videoId,
      });
      
      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/next?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );
      
      if (response.statusCode != 200) {
        throw Exception('Next failed: ${response.statusCode}');
      }
      
      final data = jsonDecode(response.body);
      return _parseNextResults(data, limit);
      
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: Suggestions error: $e');
      }
      return [];
    }
  }
  
  /// Parse next/suggestions results
  List<Track> _parseNextResults(Map<String, dynamic> data, int limit) {
    final tracks = <Track>[];
    
    try {
      final contents = data['contents']?['singleColumnMusicWatchNextResultsRenderer']
          ?['tabbedRenderer']?['watchNextTabbedResultsRenderer']?['tabs']?[0]
          ?['tabRenderer']?['content']?['musicQueueRenderer']?['content']
          ?['playlistPanelRenderer']?['contents'] as List?;
      
      if (contents == null) return tracks;
      
      for (final item in contents) {
        if (tracks.length >= limit) break;
        
        final renderer = item['playlistPanelVideoRenderer'];
        if (renderer == null) continue;
        
        final videoId = renderer['videoId'];
        if (videoId == null) continue;
        
        final title = renderer['title']?['runs']?[0]?['text'] ?? 'Unknown';
        
        String artist = 'Unknown Artist';
        final artistRuns = renderer['shortBylineText']?['runs'] as List?;
        if (artistRuns != null && artistRuns.isNotEmpty) {
          artist = artistRuns.map((r) => r['text']).join('');
        }
        
        String? thumbnail;
        final thumbnails = renderer['thumbnail']?['thumbnails'] as List?;
        if (thumbnails != null && thumbnails.isNotEmpty) {
          thumbnail = thumbnails.last['url'];
        }
        
        final durationText = renderer['lengthText']?['runs']?[0]?['text'];
        final durationMs = durationText != null ? _parseDuration(durationText) : null;
        
        tracks.add(Track(
          id: videoId,
          trackName: title,
          artistName: artist,
          albumName: '',
          albumArt: thumbnail ?? '',
          previewUrl: '',
          source: 'youtube',
          durationMs: durationMs,
        ));
      }
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: Next parse error: $e');
      }
    }
    
    return tracks;
  }
  
  /// Search for trending/charts
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
        // Fallback to search for popular music
        return searchSongs('top hits 2024', limit: limit);
      }
      
      final data = jsonDecode(response.body);
      final tracks = _parseHomeResults(data, limit);
      
      if (tracks.isEmpty) {
        // Fallback to search
        return searchSongs('trending music 2024', limit: limit);
      }
      
        return tracks;
      
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: Trending error: $e');
      }
      // Fallback to search
      return searchSongs('popular songs', limit: limit);
    }
  }
  
  /// Get search suggestions (autocomplete)
  Future<List<String>> getSearchSuggestions(String query) async {
    try {
      final body = jsonEncode({
        'context': _buildContext(),
        'input': query,
      });
      
      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/music/get_search_suggestions?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );
      
      if (response.statusCode != 200) return [];
      
      final data = jsonDecode(response.body);
      final suggestions = <String>[];
      
      final contents = data['contents'] as List?;
      if (contents != null) {
        for (final section in contents) {
          final sectionContents = section['searchSuggestionsSectionRenderer']?['contents'] as List?;
          if (sectionContents == null) continue;
          
          for (final item in sectionContents) {
            final suggestion = item['searchSuggestionRenderer']?['suggestion']?['runs'] as List?;
            if (suggestion != null) {
              final text = suggestion.map((r) => r['text'] ?? '').join('');
              if (text.isNotEmpty) suggestions.add(text);
            }
          }
        }
      }
      
      return suggestions;
      
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: Suggestions error: $e');
      }
      return [];
    }
  }
  
  /// Get explore page (new releases, moods & genres)
  Future<Map<String, dynamic>> getExplorePage() async {
    try {
      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': 'FEmusic_explore',
      });
      
      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );
      
      if (response.statusCode != 200) {
        throw Exception('Explore failed: ${response.statusCode}');
      }
      
      final data = jsonDecode(response.body);
      
      final result = <String, dynamic>{
        'newReleases': <Track>[],
        'moodGenres': <Map<String, String>>[],
      };
      
      // Parse explore page
      final contents = data['contents']?['singleColumnBrowseResultsRenderer']
          ?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?;
      
      if (contents != null) {
        for (final section in contents) {
          final carousel = section['musicCarouselShelfRenderer'];
          if (carousel == null) continue;
          
          final header = carousel['header']?['musicCarouselShelfBasicHeaderRenderer'];
          final browseId = header?['moreContentButton']?['buttonRenderer']
              ?['navigationEndpoint']?['browseEndpoint']?['browseId'];
          
          // New releases albums
          if (browseId == 'FEmusic_new_releases_albums') {
            final items = carousel['contents'] as List?;
            if (items != null) {
              for (final item in items) {
                final renderer = item['musicTwoRowItemRenderer'];
                if (renderer != null) {
                  final track = _parseTrackFromTwoRowRenderer(renderer);
                  if (track != null) {
                    (result['newReleases'] as List<Track>).add(track);
                  }
                }
              }
            }
          }
          
          // Moods and genres
          if (browseId == 'FEmusic_moods_and_genres') {
            final items = carousel['contents'] as List?;
            if (items != null) {
              for (final item in items) {
                final navButton = item['musicNavigationButtonRenderer'];
                if (navButton != null) {
                  final title = navButton['buttonText']?['runs']?[0]?['text'];
                  final params = navButton['clickCommand']?['browseEndpoint']?['params'];
                  final color = navButton['solid']?['leftStripeColor'];
                  
                  if (title != null) {
                    (result['moodGenres'] as List<Map<String, String>>).add({
                      'title': title,
                      'params': params ?? '',
                      'color': color?.toString() ?? '',
                    });
                  }
                }
              }
            }
          }
        }
      }
      
      return result;
      
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: Explore error: $e');
      }
      return {'newReleases': <Track>[], 'moodGenres': <Map<String, String>>[]};
    }
  }
  
  /// Get tracks for a specific mood/genre
  Future<List<Track>> getMoodGenreTracks(String params, {int limit = 30}) async {
    try {
      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': 'FEmusic_moods_and_genres_category',
        'params': params,
      });
      
      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );
      
      if (response.statusCode != 200) {
        throw Exception('Mood/Genre browse failed: ${response.statusCode}');
      }
      
      final data = jsonDecode(response.body);
      return _parseHomeResults(data, limit);
      
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: Mood/Genre error: $e');
      }
      return [];
    }
  }
  
  /// Get new release albums
  Future<List<Track>> getNewReleases({int limit = 20}) async {
    try {
      final body = jsonEncode({
        'context': _buildContext(),
        'browseId': 'FEmusic_new_releases_albums',
      });
      
      final response = await _httpClient.post(
        Uri.parse('$_apiUrl/browse?prettyPrint=false'),
        headers: _buildHeaders(),
        body: body,
      );
      
      if (response.statusCode != 200) {
        return searchSongs('new releases 2024', limit: limit);
      }
      
      final data = jsonDecode(response.body);
      final tracks = <Track>[];
      
      // Parse grid of albums
      final contents = data['contents']?['singleColumnBrowseResultsRenderer']
          ?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']
          ?['contents']?[0]?['gridRenderer']?['items'] as List?;
      
      if (contents != null) {
        for (final item in contents) {
          if (tracks.length >= limit) break;
          
          final renderer = item['musicTwoRowItemRenderer'];
          if (renderer != null) {
            final track = _parseTrackFromTwoRowRenderer(renderer);
            if (track != null) tracks.add(track);
          }
        }
      }
      
      if (tracks.isEmpty) {
        return searchSongs('new music releases', limit: limit);
      }
      
      return tracks;
      
    } catch (e) {
      if (kDebugMode) {
        print('InnerTubeService: New releases error: $e');
      }
      return searchSongs('latest hits', limit: limit);
    }
  }
  
  /// Get related tracks for autoplay/radio
  Future<List<Track>> getRelatedTracks(String videoId, {int limit = 25}) async {
    // Use the existing suggestions method
    return getSuggestions(videoId, limit: limit);
  }
  
  void dispose() {
    _httpClient.close();
    _yt.close(); // FIX: Close YoutubeExplode instance to prevent memory leaks
  }
}

class _CachedUrlEntry {
  final String url;
  final DateTime timestamp;

  _CachedUrlEntry(this.url, this.timestamp);

  bool isExpired(Duration duration) {
    return DateTime.now().difference(timestamp) > duration;
  }
}
