// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io'; // For SocketException
import 'dart:math';
import 'package:collection/collection.dart'; // For sortBy, firstWhereOrNull
import 'package:dio/dio.dart'; // For DioException, DioExceptionType
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../models/album.dart'; // Import new Album model
import '../models/artist.dart'; // Import new Artist model
import '../utils/network_config.dart';
import 'network_service.dart';

class ApiService {
  final YoutubeExplode _yt = YoutubeExplode();
  final NetworkService _networkService = NetworkService();

  // In-memory cache for lists (tracks, artists)
  final Map<String, _CacheEntry> _inMemoryListCache = {};
  static const int _maxInMemoryCacheEntries = 5; // Max number of list entries in memory
  static const Duration _inMemoryCacheDuration = Duration(minutes: 5); // Short duration for in-memory

  // Cache for audio stream URLs (remains specific for stream URLs)
  final Map<String, Map<String, dynamic>> _streamUrlCache = {};

  // Pending operations queue (Consider consolidating this with MusicProvider's retry queue)
  final List<_PendingOperation> _pendingOperations = [];
  bool _isProcessingQueue = false;

  // --- In-Memory Cache Helpers ---
  T? _getInMemoryCache<T>(String key) {
    final entry = _inMemoryListCache[key];
    if (entry != null && !entry.isExpired && entry.data is T) {
      print("ApiService: Returning from in-memory cache for key $key");
      return entry.data as T;
    }
    _inMemoryListCache.remove(key); // Remove if expired or type mismatch
    return null;
  }

  void _setInMemoryCache<T>(String key, T data) {
    if (_inMemoryListCache.length >= _maxInMemoryCacheEntries) {
      // Simple FIFO eviction, could be LRU for more sophistication
      _inMemoryListCache.remove(_inMemoryListCache.keys.first);
    }
    _inMemoryListCache[key] = _CacheEntry(data, _inMemoryCacheDuration);
    print("ApiService: Set in-memory cache for key $key");
  }

  // --- Track Fetching Methods ---

  Future<List<Track>> fetchTracks() async {
    const cacheKey = 'popular_music_tracks';
    // Try in-memory cache first
    final List<Track>? memoryCached = _getInMemoryCache<List<Track>>(cacheKey);
    if (memoryCached != null) return memoryCached;

    try {
      final cached = await _getCachedTracks(cacheKey); // SharedPreferences cache
      if (cached != null) {
        print("ApiService: Returning cached popular tracks from SharedPreferences.");
        _setInMemoryCache(cacheKey, cached); // Populate in-memory cache
        return cached;
      }
      if (!_networkService.isConnected) throw Exception('No internet connection');

      print("ApiService: Fetching popular tracks from YouTube search...");
      final results = await _yt.search.search('popular music'); // Simple query
      final tracks = _mapVideoResultsToTracks(results.take(15).toList()); // Take more for popular
      await _cacheTracks(cacheKey, tracks, NetworkConfig.longCacheValidity); // Save to SharedPreferences
      _setInMemoryCache(cacheKey, tracks); // Also save to in-memory cache
      print("ApiService: Fetched and cached ${tracks.length} popular tracks.");
      return tracks;
    } catch (e) {
      print('Error fetching tracks: $e');
      final cached = await _getCachedTracks(cacheKey, ignoreExpiry: true);
      if (cached != null) {
        print("ApiService: Returning stale cached popular tracks due to error.");
        return cached;
      }
      if (_isNetworkError(e)) _addToPendingOperations(_PendingOperation('Fetch popular', fetchTracks));
      throw Exception('Failed to load tracks: $e');
    }
  }

  Future<List<Track>> fetchTrendingTracks() async {
    const cacheKey = 'trending_music_tracks';
    // Try in-memory cache first
    final List<Track>? memoryCached = _getInMemoryCache<List<Track>>(cacheKey);
    if (memoryCached != null) return memoryCached;

    try {
      final cached = await _getCachedTracks(cacheKey); // SharedPreferences cache
      if (cached != null) {
        print("ApiService: Returning cached trending tracks from SharedPreferences.");
        _setInMemoryCache(cacheKey, cached); // Populate in-memory cache
        return cached;
      }
      if (!_networkService.isConnected) throw Exception('No internet connection');

      print("ApiService: Fetching trending tracks from YouTube search...");
      // Using YouTube's trending might require region specific or more complex calls
      // Falling back to a search query for simplicity here
      final results = await _yt.search.search('top new music videos this week');
      final tracks = _mapVideoResultsToTracks(results.take(20).toList()); // Take more for trending
      await _cacheTracks(cacheKey, tracks, NetworkConfig.shortCacheValidity); // Shorter cache for trending
      _setInMemoryCache(cacheKey, tracks); // Also save to in-memory cache
      print("ApiService: Fetched and cached ${tracks.length} trending tracks.");
      return tracks;
    } catch (e) {
      print('Error fetching trending: $e');
      final cached = await _getCachedTracks(cacheKey, ignoreExpiry: true);
      if (cached != null) {
        print("ApiService: Returning stale cached trending tracks due to error.");
        return cached;
      }
      if (_isNetworkError(e)) _addToPendingOperations(_PendingOperation('Fetch trending', fetchTrendingTracks));
      throw Exception('Failed to load trending: $e');
    }
  }

  Future<List<Track>> fetchTracksByQuery(String query) async {
    final cacheKey = 'search_${query.hashCode}'; // Using hashCode of query for key
    // Try in-memory cache first
    final List<Track>? memoryCached = _getInMemoryCache<List<Track>>(cacheKey);
    if (memoryCached != null) return memoryCached;

    try {
      final cached = await _getCachedTracks(cacheKey); // SharedPreferences cache
      if (cached != null) {
        print("ApiService: Returning cached search results for '$query' from SharedPreferences.");
        _setInMemoryCache(cacheKey, cached); // Populate in-memory cache
        return cached;
      }
      if (!_networkService.isConnected) throw Exception('No internet connection');

      print("ApiService: Searching YouTube for query: '$query'");
      final results = await _yt.search.search(query); // Execute search
      final tracks = _mapVideoResultsToTracks(results.toList()); // Map all results initially
      print("ApiService: Found ${tracks.length} potential tracks for query '$query'");

      // Limit results after mapping if needed, e.g., results.take(20)
      final limitedTracks = tracks.take(20).toList();

      await _cacheTracks(cacheKey, limitedTracks, NetworkConfig.shortCacheValidity); // Use defined short validity
      _setInMemoryCache(cacheKey, limitedTracks); // Also save to in-memory cache
      print("ApiService: Cached ${limitedTracks.length} search results for '$query'.");
      return limitedTracks;
    } catch (e) {
      print('Error fetching by query "$query": $e');
      final cached = await _getCachedTracks(cacheKey, ignoreExpiry: true);
      if (cached != null) {
        print("ApiService: Returning stale cached search results for '$query' due to error.");
        return cached;
      }
      // Don't typically retry search queries automatically
      throw Exception('Search failed for "$query": $e');
    }
  }

  // Helper to map YouTube video results to Track objects
  List<Track> _mapVideoResultsToTracks(List<Video> videoResults) {
    return videoResults
    // Basic filtering: Ensure it has duration, is longer than 30s, and not live
        .where((video) => video.duration != null && video.duration! > const Duration(seconds: 30) && video.isLive == false)
        .map((video) {
      String title = video.title;
      String artist = video.author;

      return Track(
        id: video.id.value, // YouTube Video ID
        trackName: title.isEmpty ? "Unknown Title" : title,
        artistName: artist.isEmpty ? "Unknown Artist" : artist,
        albumName: 'YouTube', // Default album name from YT search
        previewUrl: video.url, // URL to the YouTube video page
        albumArtUrl: video.thumbnails.highResUrl, // Use high resolution thumbnail
        source: 'youtube',
        duration: video.duration, // Use duration from video object
      );
    }).toList();
  }


  Future<List<Map<String, String>>> fetchTopArtists() async {
    const cacheKey = 'top_artists';
    // Try in-memory cache first
    final List<Map<String, String>>? memoryCached = _getInMemoryCache<List<Map<String, String>>>(cacheKey);
    if (memoryCached != null) return memoryCached;

    try {
      final cached = await _getCachedArtists(cacheKey); // SharedPreferences cache
      if (cached != null) {
        print("ApiService: Returning cached top artists from SharedPreferences.");
        _setInMemoryCache(cacheKey, cached); // Populate in-memory cache
        return cached;
      }
      if (!_networkService.isConnected) throw Exception('No internet connection');

      print("ApiService: Fetching top artists (placeholder via YT search)...");
      // This placeholder uses a generic search. Replace with a real music API call.
      final results = await _yt.search.search('top music artists 2024');
      // Crude grouping by author to simulate artists
      final artistMap = <String, String>{};
      results.take(20).forEach((video) {
        if (video.author.isNotEmpty && !artistMap.containsKey(video.author)) {
          artistMap[video.author] = video.thumbnails.highResUrl; // Store name and image url
        }
      });

      final artists = artistMap.entries.take(10).map((entry) { // Take top 10 simulated artists
        return {'name': entry.key, 'image': entry.value};
      }).toList();

      await _cacheArtists(cacheKey, artists, NetworkConfig.longCacheValidity); // Save to SharedPreferences
      _setInMemoryCache(cacheKey, artists); // Also save to in-memory cache
      print("ApiService: Fetched and cached ${artists.length} top artists (simulated).");
      return artists;
    } catch (e) {
      print('Error fetching top artists: $e');
      final cached = await _getCachedArtists(cacheKey, ignoreExpiry: true);
      if (cached != null) {
        print("ApiService: Returning stale cached top artists due to error.");
        return cached;
      }
      if (_isNetworkError(e)) _addToPendingOperations(_PendingOperation('Fetch top artists', fetchTopArtists));
      throw Exception('Failed to load top artists: $e');
    }
  }

  // --- Audio Stream URL Fetching ---

  Future<String> getAudioStreamUrl(String videoId, int bitrate) async {
    print('ApiService: Fetching audio stream for video ID: $videoId with bitrate: $bitrate');
    try {
      // --- Cache Check ---
      if (_streamUrlCache.containsKey(videoId)) {
        final cachedData = _streamUrlCache[videoId]!;
        final expiryTime = cachedData['expiry'] as int? ?? 0;
        if (DateTime.now().millisecondsSinceEpoch < expiryTime) {
          final streamUrl = cachedData['url'] as String? ?? '';
          if (streamUrl.isNotEmpty) {
            print('ApiService: Using cached stream URL.');
            return streamUrl; // Assuming cached URL is likely still valid
          }
        } else { _streamUrlCache.remove(videoId); print('Cached URL expired.'); }
      }

      // --- ID Conversion ---
      if (!isValidYoutubeID(videoId)) {
        print('ApiService: Non-YouTube ID ($videoId), attempting conversion...');
        final searchQuery = await getSearchQueryForTrack(videoId);
        final searchResults = await _yt.search.search(searchQuery);
        if (searchResults.isEmpty) throw Exception('No YouTube results found for ID: $videoId');
        videoId = searchResults.first.id.value;
        print('ApiService: Converted to YouTube ID: $videoId');
      }

      // --- Bitrate Adjustment (Optional) ---
      int adjustedBitrate = bitrate;

      // --- Retry Loop ---
      int attempts = 0;
      while (attempts < NetworkConfig.maxRetries) {
        try {
          final vidId = VideoId(videoId);
          final manifest = await _yt.videos.streamsClient.getManifest(vidId);
          final unmodifiableAudioStreams = manifest.audioOnly; // Original list
          if (unmodifiableAudioStreams.isEmpty) throw Exception('No audio streams found.');

          print('ApiService: Available audio streams (kbps): ${unmodifiableAudioStreams.map((s) => s.bitrate.bitsPerSecond ~/ 1000).toList()}');

          // Create a mutable copy before sorting
          final List<AudioOnlyStreamInfo> mutableAudioStreams = List.from(unmodifiableAudioStreams);

          // Sort the mutable copy
          mutableAudioStreams.sortBy<num>((s) => (s.bitrate.bitsPerSecond / 1000 - adjustedBitrate).abs());

          // Get the best match
          final streamInfo = mutableAudioStreams.first;

          final streamUrl = streamInfo.url.toString();
          print('ApiService: Selected stream URL (${streamInfo.bitrate.kiloBitsPerSecond.round()} kbps)');

          final expiryTime = DateTime.now().add(const Duration(hours: 5, minutes: 50)).millisecondsSinceEpoch;
          _streamUrlCache[videoId] = {'url': streamUrl, 'expiry': expiryTime, 'bitrate': streamInfo.bitrate.kiloBitsPerSecond.round() };

          return streamUrl; // Success

        } on SocketException catch (e) { // Network errors
          attempts++; print("Attempt $attempts failed (Network): $e");
          if (attempts >= NetworkConfig.maxRetries) rethrow;
          await _waitBeforeRetry(attempts);
          if (!_networkService.isConnected) throw Exception('Lost connection during retry.');
        } on Exception catch (e) { // Other API errors
          attempts++; print("Attempt $attempts failed (API/Manifest): $e");
          if (e.toString().contains("Video unavailable") || e.toString().contains("Private video")) throw Exception("Video unavailable: $videoId");
          if (attempts >= NetworkConfig.maxRetries) rethrow;
          await _waitBeforeRetry(attempts);
        }
      }
      throw Exception('Failed after max retries.'); // Should only be reached if loop somehow finishes without success/rethrow

    } catch (e) {
      print('ApiService: FINAL Error fetching audio stream for $videoId: $e');
      // Add to pending queue only for likely recoverable network errors
      if (_isNetworkError(e)) {
        _addToPendingOperations(_PendingOperation('Get stream: $videoId', () => getAudioStreamUrl(videoId, bitrate)));
      }
      // Rethrow a user-friendly error
      throw Exception('Failed to get audio stream: ${e.toString()}');
    }
  }

  // Helper for exponential backoff delay
  Future<void> _waitBeforeRetry(int attempt) async {
    final backoffSeconds = pow(2, attempt) + (Random().nextDouble() * 0.5); // Exponential + jitter
    print('ApiService: Retrying in ${backoffSeconds.toStringAsFixed(1)} seconds...');
    await Future.delayed(Duration(milliseconds: (backoffSeconds * 1000).round()));
  }

  // Helper to check if an error is likely network-related
  bool _isNetworkError(dynamic e) {
    if (e is SocketException) return true; // dart:io
    if (e is DioException && ( // package:dio/dio.dart
        e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.unknown)) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('network') || msg.contains('connection') || msg.contains('socket') || msg.contains('host lookup');
  }

  // Helper method to check if a string looks like a YouTube ID
  bool isValidYoutubeID(String id) {
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);
  }

  // Helper method to create a search query from a potentially non-YT track ID
  Future<String> getSearchQueryForTrack(String id) async {
    // Try fetching Track info (e.g., from Spotify import cache)
    final track = await _getTrackInfoFromCache(id); // Uses SharedPreferences cache
    if (track != null) {
      // Construct search query using known details
      return "${track.trackName} ${track.artistName} official audio";
    }
    // Fallback if track info not found - search using the ID itself
    return id;
  }

  // Helper to lookup track info from the shared prefs cache (used for ID conversion)
  Future<Track?> _getTrackInfoFromCache(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Assuming 'all_tracks_cache' stores JSON list of Tracks encountered
      final allTracksJson = prefs.getString('all_tracks_cache');
      if (allTracksJson != null) {
        final List<dynamic> allTracksList = jsonDecode(allTracksJson);
        // Use firstWhereOrNull from package:collection
        final trackData = allTracksList.firstWhereOrNull((t) => t is Map && t['id'] == id);
        if (trackData != null) {
          return Track.fromJson(Map<String, dynamic>.from(trackData));
        }
      }
    } catch (e) { print('Error reading all_tracks_cache: $e'); }
    return null;
  }


  // --- Artist/Album Methods (Placeholders - Replace with Real API Calls) ---

  Future<Artist> fetchArtistDetails(String artistName) async {
    print("ApiService: Fetching details for artist: $artistName");
    // ** TODO: Replace this entire block with your actual API call **
    await Future.delayed(const Duration(milliseconds: 700)); // Simulate network delay
    if (artistName.isEmpty || artistName == 'Unknown Artist') {
      throw Exception("Cannot fetch details for unknown artist.");
    }
    // --- Placeholder Logic ---
    String artistImageUrl = '';
    String bio = "Bio for $artistName currently unavailable."; // Default bio
    List<Track> topTracks = [];
    List<Album> topAlbums = [];
    try {
      // Fetch some tracks to simulate top tracks and get an image
      topTracks = (await fetchTracksByQuery("$artistName songs")).take(10).toList();
      if (topTracks.isNotEmpty && topTracks.first.albumArtUrl.isNotEmpty) {
        artistImageUrl = topTracks.first.albumArtUrl;
      }
      // Fetch simulated albums (using the updated placeholder logic below)
      topAlbums = await fetchArtistTopAlbums(artistName);
    } catch (e) {
      print("Error fetching artist sub-data (placeholder): $e");
      // Return partially filled data even if sub-fetches fail
    }
    // --- End Placeholder Logic ---
    return Artist(
      id: artistName.hashCode.toString(), // Placeholder ID
      name: artistName,
      imageUrl: artistImageUrl,
      bio: bio, // Use default bio
      topAlbums: topAlbums,
      topTracks: topTracks,
    );
  }

  // --- REVISED Placeholder for Artist Albums ---
  Future<List<Album>> fetchArtistTopAlbums(String artistName) async {
    print("ApiService: Fetching top albums for artist (Alternative Placeholder): $artistName");
    // ** TODO: Replace this entire block with your actual API call **
    await Future.delayed(const Duration(milliseconds: 200)); // Shorter delay simulation

    // --- Alternative Placeholder Logic ---
    try {
      // 1. Fetch a decent number of tracks associated with the artist
      final artistTracks = await fetchTracksByQuery("$artistName songs");

      if (artistTracks.isEmpty) {
        print("ApiService: No tracks found to derive albums for $artistName.");
        return []; // Return empty if no tracks found
      }

      // 2. Group these tracks by their 'albumName' property
      final albumsMap = <String, List<Track>>{};
      for (var track in artistTracks) {
        // Filter out clearly invalid or generic album names during grouping
        if (track.albumName.isNotEmpty &&
            track.albumName != 'YouTube' && // Keep this filter
            track.albumName != 'Unknown Album' && // Keep this filter
            !track.albumName.toLowerCase().contains("various artists") &&
            !track.albumName.toLowerCase().contains("greatest hits") && // Be stricter here maybe
            !track.albumName.toLowerCase().contains("top tracks") &&
            !track.albumName.toLowerCase().contains("playlist") )
        {
          albumsMap.putIfAbsent(track.albumName, () => []).add(track);
        }
      }

      if (albumsMap.isEmpty) {
        print("ApiService: No valid album groups found after filtering for $artistName.");
        return [];
      }

      print("ApiService: Found ${albumsMap.length} potential album groups for $artistName.");

      // 3. Create Album objects from the groups
      return albumsMap.entries
          .take(8) // Limit the number of albums shown
          .map((entry) {
        // Find the best image URL from the tracks in this album group
        String bestImageUrl = entry.value
            .firstWhereOrNull((t) => t.albumArtUrl.isNotEmpty)
            ?.albumArtUrl ?? ''; // Use first available art or empty

        return Album(
            id: entry.key.hashCode.toString() + artistName.hashCode.toString(), // Combined placeholder ID
            name: entry.key, // The grouped album name
            artistName: artistName, // Assume passed artist name is correct
            imageUrl: bestImageUrl,
            tracks: [], // IMPORTANT: Keep tracks empty. Fetch details on AlbumScreen.
            releaseDate: DateTime.now().subtract(Duration(days: Random().nextInt(1825))) // Dummy date
        );
      })
          .toList();
    } catch (e) {
      print("Error during alternative placeholder album fetch for $artistName: $e");
      return []; // Return empty list on error
    }
    // --- End Alternative Placeholder Logic ---
  }

  Future<Album> fetchAlbumDetails(String albumName, String artistName) async {
    print("ApiService: Fetching details for album: '$albumName' by $artistName");
    // Handle invalid/generic album names passed from YT tracks
    if (albumName.isEmpty || albumName == 'YouTube' || albumName == 'Unknown Album') {
      print("ApiService: Refusing to fetch details for generic album name '$albumName'.");
      throw Exception("Album details not available for this track.");
    }
    // ** TODO: Replace this entire block with your actual API call (might need album ID) **
    await Future.delayed(const Duration(milliseconds: 600)); // Simulate delay
    // --- Placeholder Logic ---
    try {
      // Try a query likely to get tracks from that specific album
      final tracks = await fetchTracksByQuery('"$albumName" "$artistName" album full');
      String imageUrl = '';
      String foundArtist = artistName; // Use passed name as default
      String foundAlbum = albumName; // Use passed name as default
      DateTime releaseDate = DateTime.now().subtract(Duration(days: Random().nextInt(3650))); // Dummy

      if (tracks.isNotEmpty) {
        // Try to get consistent metadata from the results
        final firstGoodTrack = tracks.firstWhereOrNull((t) => t.albumArtUrl.isNotEmpty);
        imageUrl = firstGoodTrack?.albumArtUrl ?? tracks.first.albumArtUrl; // Use best available art
        // It's often better *not* to override names based on search results unless API guarantees accuracy
        // foundArtist = tracks.first.artistName;
        // foundAlbum = tracks.first.albumName;
        // TODO: Attempt to parse release date from somewhere if possible
      } else {
        print("ApiService: No tracks found via YT search for album '$albumName'. Returning minimal data.");
      }

      return Album(
        id: albumName.hashCode.toString() + artistName.hashCode.toString(), // Placeholder ID
        name: foundAlbum,
        artistName: foundArtist,
        imageUrl: imageUrl,
        tracks: tracks, // Assign fetched tracks
        releaseDate: releaseDate,
      );
    } catch (e) {
      print("Error fetching album details placeholder for '$albumName': $e");
      throw Exception("Could not load album details."); // Throw clearer error
    }
    // --- End Placeholder Logic ---
  }


  // --- Caching Logic (SharedPreferences) ---
  Future<void> _cacheTracks(String key, List<Track> tracks, Duration expiry) async { if(tracks.isEmpty) return; try { final p=await SharedPreferences.getInstance(); final j=jsonEncode(tracks.map((t)=>t.toJson()).toList()); final t=DateTime.now().add(expiry).millisecondsSinceEpoch; await p.setString('tracks_$key',j); await p.setInt('tracks_expiry_$key',t); final aJ=p.getString('all_tracks_cache')??'[]'; final List<dynamic> aL=jsonDecode(aJ); final Set<String> eIds=aL.whereType<Map>().map((t)=>t['id'] as String? ?? '').toSet(); for(final tr in tracks){if(!eIds.contains(tr.id))aL.add(tr.toJson());} await p.setString('all_tracks_cache',jsonEncode(aL)); } catch(e){ print('Error caching tracks ($key): $e');}}
  Future<List<Track>?> _getCachedTracks(String key, {bool ignoreExpiry = false}) async { try { final p=await SharedPreferences.getInstance(); final j=p.getString('tracks_$key'); if(j==null)return null; final t=p.getInt('tracks_expiry_$key')??0; if(!ignoreExpiry && DateTime.now().millisecondsSinceEpoch>t){print("Cache expired for $key");return null;} final List<dynamic> l=jsonDecode(j); return l.map((t)=>Track.fromJson(Map<String,dynamic>.from(t))).toList(); } catch(e){ print('Error get cache ($key): $e'); return null;}}
  Future<void> _cacheArtists(String key, List<Map<String, String>> artists, Duration expiry) async { if(artists.isEmpty) return; try { final p=await SharedPreferences.getInstance(); final j=jsonEncode(artists); final t=DateTime.now().add(expiry).millisecondsSinceEpoch; await p.setString('artists_$key',j); await p.setInt('artists_expiry_$key',t); } catch(e){ print('Error caching artists ($key): $e');}}
  Future<List<Map<String, String>>?> _getCachedArtists(String key, {bool ignoreExpiry = false}) async { try { final p=await SharedPreferences.getInstance(); final j=p.getString('artists_$key'); if(j==null)return null; final t=p.getInt('artists_expiry_$key')??0; if(!ignoreExpiry && DateTime.now().millisecondsSinceEpoch>t){print("Cache expired for $key");return null;} final List<dynamic> l=jsonDecode(j); return l.map((a)=>Map<String,String>.from(a)).toList(); } catch(e){ print('Error get cache ($key): $e'); return null;}}

  // --- Pending Operations Queue ---
  void _addToPendingOperations(_PendingOperation operation) { if (!_pendingOperations.any((op) => op.description == operation.description)) { _pendingOperations.add(operation); print("Added to API pending queue: ${operation.description}"); if (!_isProcessingQueue && _networkService.isConnected) _processOperationsQueue(); } }
  Future<void> _processOperationsQueue() async { if (_pendingOperations.isEmpty || _isProcessingQueue) return; _isProcessingQueue = true; print("API Service: Processing pending queue..."); while (_pendingOperations.isNotEmpty && _networkService.isConnected) { final op = _pendingOperations.removeAt(0); try { await op.execute(); } catch (e) { if (op.attempts < 2) { op.attempts++; _pendingOperations.add(op); } await Future.delayed(const Duration(seconds: 5)); } } _isProcessingQueue = false; print("API Service: Finished queue."); }

  // --- Cache Management & Dispose ---
  Future<void> clearCache() async { try { final p=await SharedPreferences.getInstance(); final k=p.getKeys().where((k)=> k.startsWith('tracks_')||k.startsWith('artists_')||k.startsWith('all_tracks_cache')||k.startsWith('tracks_expiry_')||k.startsWith('artists_expiry_')).toList(); for(final key in k) await p.remove(key); _streamUrlCache.clear(); _inMemoryListCache.clear(); print("ApiService Cache Cleared (SharedPreferences & In-Memory)."); } catch(e){ print('Error clearing ApiService cache: $e');}}
  void dispose() { _yt.close(); _pendingOperations.clear(); _inMemoryListCache.clear(); print("ApiService disposed."); }
}

// Helper class for pending operations
class _PendingOperation {
  final String description; final Future<dynamic> Function() execute; int attempts = 1;
  _PendingOperation(this.description, this.execute);
}

// Private helper class for in-memory cache entries
class _CacheEntry<T> {
  final T data;
  final DateTime expiryTime;

  _CacheEntry(this.data, Duration duration)
      : expiryTime = DateTime.now().add(duration);

  bool get isExpired => DateTime.now().isAfter(expiryTime);
}