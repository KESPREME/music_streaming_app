// lib/services/api_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../utils/network_config.dart';
import 'network_service.dart';

class ApiService {
  final YoutubeExplode _yt = YoutubeExplode();
  final NetworkService _networkService = NetworkService();

  // Cache for audio stream URLs to reduce API calls
  final Map<String, Map<String, dynamic>> _streamUrlCache = {};

  // Queue for pending operations
  final List<_PendingOperation> _pendingOperations = [];
  bool _isProcessingQueue = false;

  Future<List<Track>> fetchTracks() async {
    try {
      // Use cache for popular tracks with longer expiry
      final cacheKey = 'popular_music_tracks';
      final cachedTracks = await _getCachedTracks(cacheKey);

      if (cachedTracks != null) {
        return cachedTracks;
      }

      // Check if we're connected
      if (!_networkService.isConnected) {
        throw Exception('No internet connection');
      }

      final searchResults = await _yt.search.search('popular music');
      final tracks = searchResults.take(5).map((video) {
        return Track(
          id: video.id.value,
          trackName: video.title,
          artistName: video.author,
          albumName: 'YouTube Music',
          previewUrl: video.url,
          albumArtUrl: video.thumbnails.lowResUrl,
          source: 'youtube',
        );
      }).toList();

      // Cache the tracks
      await _cacheTracks(cacheKey, tracks, NetworkConfig.longCacheValidity);

      return tracks;
    } catch (e) {
      print('Error fetching tracks: $e');

      // Try to get from cache even if expired
      final cachedTracks = await _getCachedTracks('popular_music_tracks', ignoreExpiry: true);
      if (cachedTracks != null) {
        return cachedTracks;
      }

      // Add to pending operations if it's a network error
      if (e.toString().contains('network') ||
          e.toString().contains('connection') ||
          e.toString().contains('socket')) {
        _addToPendingOperations(_PendingOperation(
          'Fetch popular tracks',
          fetchTracks,
        ));
      }

      throw Exception('Failed to load tracks: $e');
    }
  }

  Future<List<Track>> fetchTrendingTracks() async {
    try {
      // Use cache for trending tracks with shorter expiry
      final cacheKey = 'trending_music_tracks';
      final cachedTracks = await _getCachedTracks(cacheKey);

      if (cachedTracks != null) {
        return cachedTracks;
      }

      // Check if we're connected
      if (!_networkService.isConnected) {
        throw Exception('No internet connection');
      }

      final searchResults = await _yt.search.search('trending music');
      final tracks = searchResults.take(10).map((video) {
        return Track(
          id: video.id.value,
          trackName: video.title,
          artistName: video.author,
          albumName: 'YouTube Trending',
          previewUrl: video.url,
          albumArtUrl: video.thumbnails.lowResUrl,
          source: 'youtube',
        );
      }).toList();

      // Cache the tracks
      await _cacheTracks(cacheKey, tracks, NetworkConfig.shortCacheValidity);

      return tracks;
    } catch (e) {
      print('Error fetching trending tracks: $e');

      // Try to get from cache even if expired
      final cachedTracks = await _getCachedTracks('trending_music_tracks', ignoreExpiry: true);
      if (cachedTracks != null) {
        return cachedTracks;
      }

      // Add to pending operations if it's a network error
      if (e.toString().contains('network') ||
          e.toString().contains('connection') ||
          e.toString().contains('socket')) {
        _addToPendingOperations(_PendingOperation(
          'Fetch trending tracks',
          fetchTrendingTracks,
        ));
      }

      throw Exception('Failed to load trending tracks: $e');
    }
  }

  Future<List<Track>> fetchTracksByQuery(String query) async {
    try {
      // Use cache for search queries
      final cacheKey = 'search_${query.hashCode}';
      final cachedTracks = await _getCachedTracks(cacheKey);

      if (cachedTracks != null) {
        return cachedTracks;
      }

      // Check if we're connected
      if (!_networkService.isConnected) {
        throw Exception('No internet connection');
      }

      final searchResults = await _yt.search.search(query);
      final tracks = searchResults.take(5).map((video) {
        return Track(
          id: video.id.value,
          trackName: video.title,
          artistName: video.author,
          albumName: 'YouTube Music',
          previewUrl: video.url,
          albumArtUrl: video.thumbnails.lowResUrl,
          source: 'youtube',
        );
      }).toList();

      // Cache the tracks with shorter expiry for search results
      await _cacheTracks(cacheKey, tracks, NetworkConfig.shortCacheValidity);

      return tracks;
    } catch (e) {
      print('Error fetching tracks by query: $e');

      // Try to get from cache even if expired
      final cachedTracks = await _getCachedTracks('search_${query.hashCode}', ignoreExpiry: true);
      if (cachedTracks != null) {
        return cachedTracks;
      }

      throw Exception('Failed to load tracks for query "$query": $e');
    }
  }

  Future<List<Map<String, String>>> fetchTopArtists() async {
    try {
      // Use cache for top artists with longer expiry
      final cacheKey = 'top_artists';
      final cachedArtists = await _getCachedArtists(cacheKey);

      if (cachedArtists != null) {
        return cachedArtists;
      }

      // Check if we're connected
      if (!_networkService.isConnected) {
        throw Exception('No internet connection');
      }

      final searchResults = await _yt.search.search('top music artists');
      final artists = searchResults.take(4).map((video) {
        return {
          'name': video.author,
          'image': video.thumbnails.mediumResUrl,
        };
      }).toList();

      // Cache the artists
      await _cacheArtists(cacheKey, artists, NetworkConfig.longCacheValidity);

      return artists;
    } catch (e) {
      print('Error fetching top artists: $e');

      // Try to get from cache even if expired
      final cachedArtists = await _getCachedArtists('top_artists', ignoreExpiry: true);
      if (cachedArtists != null) {
        return cachedArtists;
      }

      throw Exception('Failed to load top artists: $e');
    }
  }

  Future<String> getAudioStreamUrl(String videoId, int bitrate) async {
    print('ApiService: Fetching audio stream for video ID: $videoId with bitrate: $bitrate');

    try {
      // Check if we have a cached URL that's still valid
      if (_streamUrlCache.containsKey(videoId)) {
        final cachedData = _streamUrlCache[videoId]!;
        final expiryTime = cachedData['expiry'] as int;

        // If the URL is still valid (not expired)
        if (DateTime.now().millisecondsSinceEpoch < expiryTime) {
          final streamUrl = cachedData['url'] as String;
          print('ApiService: Using cached stream URL: $streamUrl');

          // Check if the URL is still accessible
          final isReachable = await _networkService.isUrlReachable(streamUrl);
          if (isReachable) {
            return streamUrl;
          } else {
            // Remove invalid cache entry
            _streamUrlCache.remove(videoId);
            print('ApiService: Cached URL is no longer valid, fetching new URL');
          }
        } else {
          // Remove expired cache entry
          _streamUrlCache.remove(videoId);
        }
      }

      // Check if this is a valid YouTube ID or a Spotify ID
      if (!isValidYoutubeID(videoId)) {
        print('ApiService: Not a valid YouTube ID, searching for equivalent content');
        final searchQuery = await getSearchQueryForTrack(videoId);
        final searchResults = await _yt.search.search(searchQuery);

        if (searchResults.isEmpty) {
          throw Exception('No YouTube results found for ID: $videoId');
        }

        // Use the first search result's ID
        videoId = searchResults.first.id.value;
        print('ApiService: Converted to YouTube ID: $videoId');
      }

      // Adjust bitrate based on network quality
      int adjustedBitrate = bitrate;
      final networkQuality = _networkService.networkQuality;

      if (networkQuality == NetworkQuality.poor) {
        adjustedBitrate = NetworkConfig.poorNetworkBitrate;
        print('ApiService: Using low bitrate ($adjustedBitrate kbps) due to poor network');
      } else if (networkQuality == NetworkQuality.moderate) {
        adjustedBitrate = NetworkConfig.moderateNetworkBitrate;
        print('ApiService: Using moderate bitrate ($adjustedBitrate kbps) due to network conditions');
      }

      // Implement retry logic with exponential backoff
      int attempts = 0;
      const maxRetries = NetworkConfig.maxRetries;

      while (attempts < maxRetries) {
        try {
          final video = await _yt.videos.get(videoId);
          print('ApiService: Video fetched: ${video.title}');

          final manifest = await _yt.videos.streamsClient.getManifest(video.id);
          final audioStreams = manifest.audioOnly;

          if (audioStreams.isEmpty) {
            throw Exception('No audio streams available for video ID: $videoId');
          }

          print('ApiService: Available audio streams: ${audioStreams.map((s) => s.bitrate.bitsPerSecond ~/ 1000).toList()} kbps');

          // Find the best matching stream based on adjusted bitrate
          final streamInfo = audioStreams.reduce((a, b) {
            final aDiff = (a.bitrate.bitsPerSecond ~/ 1000 - adjustedBitrate).abs();
            final bDiff = (b.bitrate.bitsPerSecond ~/ 1000 - adjustedBitrate).abs();
            if (aDiff == bDiff) {
              // If difference is the same, prefer the one with lower bitrate to save data
              return a.bitrate.bitsPerSecond < b.bitrate.bitsPerSecond ? a : b;
            }
            return aDiff < bDiff ? a : b;
          });

          final streamUrl = streamInfo.url.toString();
          print('ApiService: Selected stream URL with bitrate: ${streamInfo.bitrate.bitsPerSecond ~/ 1000} kbps');

          // Cache the stream URL with expiry time (usually 6 hours for YouTube URLs)
          // Subtract 10 minutes to be safe
          final expiryTime = DateTime.now().add(const Duration(hours: 6, minutes: -10)).millisecondsSinceEpoch;
          _streamUrlCache[videoId] = {
            'url': streamUrl,
            'expiry': expiryTime,
            'bitrate': streamInfo.bitrate.bitsPerSecond ~/ 1000,
          };

          return streamUrl;
        } catch (e) {
          attempts++;

          // If it's the last attempt, rethrow
          if (attempts >= maxRetries) {
            print('ApiService: Error fetching audio stream after $maxRetries attempts: $e');
            throw Exception('Failed to get audio stream for video ID $videoId: $e');
          }

          // Calculate backoff time (exponential with jitter)
          final backoffSeconds = pow(2, attempts) + (Random().nextInt(1000) / 1000.0);
          print('ApiService: Retrying in $backoffSeconds seconds...');
          await Future.delayed(Duration(milliseconds: (backoffSeconds * 1000).round()));

          // Check connectivity before retrying
          if (!_networkService.isConnected) {
            throw Exception('Lost internet connection while fetching audio stream');
          }
        }
      }

      throw Exception('Failed to get audio stream after $maxRetries attempts');
    } catch (e) {
      print('ApiService: Error fetching audio stream: $e');

      // Add to pending operations if it's a network error
      if (e.toString().contains('network') ||
          e.toString().contains('connection') ||
          e.toString().contains('socket')) {
        _addToPendingOperations(_PendingOperation(
          'Get audio stream for $videoId',
              () => getAudioStreamUrl(videoId, bitrate),
        ));
      }

      throw Exception('Failed to get audio stream for video ID $videoId: $e');
    }
  }

  // Helper method to check if a string is a valid YouTube ID
  bool isValidYoutubeID(String id) {
    // YouTube IDs are typically 11 characters long and contain alphanumeric chars, underscores, and hyphens
    final RegExp youtubeIDRegex = RegExp(r'^[A-Za-z0-9_-]{11}$');
    return youtubeIDRegex.hasMatch(id);
  }

  // Helper method to create a search query from a track ID
  Future<String> getSearchQueryForTrack(String id) async {
    try {
      // For imported Spotify tracks, we need to use the track name and artist
      // Check if we have this track in our cache or playlists
      final track = await _getTrackInfoFromCache(id);
      if (track != null) {
        return "${track.trackName} ${track.artistName} official audio";
      }

      // If we don't have the track info, just use the ID
      return id;
    } catch (e) {
      print('Error getting search query for track: $e');
      return id;
    }
  }

  // This method would normally check your local database or cache
  Future<Track?> _getTrackInfoFromCache(String id) async {
    // In a real implementation, you would check your local storage
    // for track information based on the ID
    final prefs = await SharedPreferences.getInstance();
    final tracksJson = prefs.getString('all_tracks_cache');

    if (tracksJson != null) {
      try {
        final List<dynamic> tracksList = jsonDecode(tracksJson);
        final trackData = tracksList.firstWhere(
              (t) => t['id'] == id,
          orElse: () => null,
        );

        if (trackData != null) {
          return Track.fromJson(trackData);
        }
      } catch (e) {
        print('Error getting track from cache: $e');
      }
    }

    return null;
  }

  // Cache tracks to shared preferences
  Future<void> _cacheTracks(String key, List<Track> tracks, Duration expiry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tracksJson = jsonEncode(tracks.map((t) => t.toJson()).toList());
      final expiryTime = DateTime.now().add(expiry).millisecondsSinceEpoch;

      await prefs.setString('tracks_$key', tracksJson);
      await prefs.setInt('tracks_expiry_$key', expiryTime);

      // Also cache in the all tracks cache for lookup
      final allTracksJson = prefs.getString('all_tracks_cache') ?? '[]';
      final List<dynamic> allTracksList = jsonDecode(allTracksJson);

      // Add new tracks to the all tracks cache if not already there
      for (final track in tracks) {
        if (!allTracksList.any((t) => t['id'] == track.id)) {
          allTracksList.add(track.toJson());
        }
      }

      await prefs.setString('all_tracks_cache', jsonEncode(allTracksList));
    } catch (e) {
      print('Error caching tracks: $e');
    }
  }

  // Get cached tracks from shared preferences
  Future<List<Track>?> _getCachedTracks(String key, {bool ignoreExpiry = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tracksJson = prefs.getString('tracks_$key');

      if (tracksJson == null) {
        return null;
      }

      if (!ignoreExpiry) {
        final expiryTime = prefs.getInt('tracks_expiry_$key') ?? 0;
        if (DateTime.now().millisecondsSinceEpoch > expiryTime) {
          return null; // Cache expired
        }
      }

      final List<dynamic> tracksList = jsonDecode(tracksJson);
      return tracksList.map((t) => Track.fromJson(t)).toList();
    } catch (e) {
      print('Error getting cached tracks: $e');
      return null;
    }
  }

  // Cache artists to shared preferences
  Future<void> _cacheArtists(String key, List<Map<String, String>> artists, Duration expiry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final artistsJson = jsonEncode(artists);
      final expiryTime = DateTime.now().add(expiry).millisecondsSinceEpoch;

      await prefs.setString('artists_$key', artistsJson);
      await prefs.setInt('artists_expiry_$key', expiryTime);
    } catch (e) {
      print('Error caching artists: $e');
    }
  }

  // Get cached artists from shared preferences
  Future<List<Map<String, String>>?> _getCachedArtists(String key, {bool ignoreExpiry = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final artistsJson = prefs.getString('artists_$key');

      if (artistsJson == null) {
        return null;
      }

      if (!ignoreExpiry) {
        final expiryTime = prefs.getInt('artists_expiry_$key') ?? 0;
        if (DateTime.now().millisecondsSinceEpoch > expiryTime) {
          return null; // Cache expired
        }
      }

      final List<dynamic> artistsList = jsonDecode(artistsJson);
      return artistsList.map((a) => Map<String, String>.from(a)).toList();
    } catch (e) {
      print('Error getting cached artists: $e');
      return null;
    }
  }

  // Add operation to pending queue
  void _addToPendingOperations(_PendingOperation operation) {
    _pendingOperations.add(operation);

    // Start processing queue if not already processing
    if (!_isProcessingQueue && _networkService.isConnected) {
      _processOperationsQueue();
    }

    // Listen for connectivity changes to process queue when connection is restored
    _networkService.onConnectivityChanged.listen((isConnected) {
      if (isConnected && _pendingOperations.isNotEmpty && !_isProcessingQueue) {
        _processOperationsQueue();
      }
    });
  }

  // Process pending operations queue
  Future<void> _processOperationsQueue() async {
    if (_pendingOperations.isEmpty || _isProcessingQueue) {
      return;
    }

    _isProcessingQueue = true;

    while (_pendingOperations.isNotEmpty && _networkService.isConnected) {
      final operation = _pendingOperations.removeAt(0);
      try {
        print('Processing pending operation: ${operation.description}');
        await operation.execute();
        print('Successfully completed pending operation: ${operation.description}');
      } catch (e) {
        print('Failed to execute pending operation: ${operation.description}, Error: $e');

        // Re-add to queue if not exceeded max attempts
        if (operation.attempts < NetworkConfig.maxRetries) {
          operation.attempts++;
          _pendingOperations.add(operation);
        } else {
          print('Dropping operation after ${operation.attempts} attempts: ${operation.description}');
        }

        // Take a break before next operation
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    _isProcessingQueue = false;
  }

  // Clear cache
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) =>
      key.startsWith('tracks_') ||
          key.startsWith('artists_') ||
          key.startsWith('all_tracks_cache')
      ).toList();

      for (final key in keys) {
        await prefs.remove(key);
      }

      _streamUrlCache.clear();
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  void dispose() {
    _yt.close();
  }
}

// Class to represent a pending operation
class _PendingOperation {
  final String description;
  final Future<dynamic> Function() execute;
  int attempts = 1;

  _PendingOperation(this.description, this.execute);
}
