// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../utils/network_config.dart';
import 'network_service.dart';

class ApiService {
  final YoutubeExplode _yt = YoutubeExplode();
  final NetworkService _networkService = NetworkService();

  final Map<String, _CacheEntry> _inMemoryListCache = {};
  static const int _maxInMemoryCacheEntries = 5;
  static const Duration _inMemoryCacheDuration = Duration(minutes: 5);

  final Map<String, Map<String, dynamic>> _streamUrlCache = {};

  final List<_PendingOperation> _pendingOperations = [];
  bool _isProcessingQueue = false;

  T? _getInMemoryCache<T>(String key) {
    final entry = _inMemoryListCache[key];
    if (entry != null && !entry.isExpired && entry.data is T) {
      print("ApiService: Returning from in-memory cache for key $key");
      return entry.data as T;
    }
    _inMemoryListCache.remove(key);
    return null;
  }

  void _setInMemoryCache<T>(String key, T data) {
    if (_inMemoryListCache.length >= _maxInMemoryCacheEntries) {
      _inMemoryListCache.remove(_inMemoryListCache.keys.first);
    }
    _inMemoryListCache[key] = _CacheEntry(data, _inMemoryCacheDuration);
    print("ApiService: Set in-memory cache for key $key");
  }

  Future<List<Track>> fetchTracks() async {
    const cacheKey = 'popular_music_tracks';
    final cachedMemory = _getInMemoryCache<List<Track>>(cacheKey);
    if (cachedMemory != null) return cachedMemory;

    try {
      final cached = await _getCachedTracks(cacheKey);
      if (cached != null) {
        _setInMemoryCache(cacheKey, cached);
        return cached;
      }

      if (!_networkService.isConnected) throw Exception('No internet');

      final results = await _yt.search.search('popular music');
      final tracks = _mapVideoResultsToTracks(results.take(15).toList());

      await _cacheTracks(cacheKey, tracks, NetworkConfig.longCacheValidity);
      _setInMemoryCache(cacheKey, tracks);
      return tracks;
    } on SocketException catch (_) {
      final fallback = await _getCachedTracks(cacheKey, ignoreExpiry: true);
      return fallback ?? [];
    } on Exception catch (e) {
      final fallback = await _getCachedTracks(cacheKey, ignoreExpiry: true);
      if (fallback != null) return fallback;
      if (_isNetworkError(e)) {
        _addToPendingOperations(_PendingOperation('Fetch popular', fetchTracks));
      }
      throw Exception("Failed to fetch tracks: $e");
    }
  }

  Future<List<Track>> fetchTrendingTracks() async {
    const cacheKey = 'trending_music_tracks';
    final cachedMemory = _getInMemoryCache<List<Track>>(cacheKey);
    if (cachedMemory != null) return cachedMemory;

    try {
      final cached = await _getCachedTracks(cacheKey);
      if (cached != null) {
        _setInMemoryCache(cacheKey, cached);
        return cached;
      }

      if (!_networkService.isConnected) throw Exception('No internet');

      final results = await _yt.search.search('top new music videos this week');
      final tracks = _mapVideoResultsToTracks(results.take(20).toList());

      await _cacheTracks(cacheKey, tracks, NetworkConfig.shortCacheValidity);
      _setInMemoryCache(cacheKey, tracks);
      return tracks;
    } on SocketException catch (_) {
      final fallback = await _getCachedTracks(cacheKey, ignoreExpiry: true);
      return fallback ?? [];
    } on Exception catch (e) {
      final fallback = await _getCachedTracks(cacheKey, ignoreExpiry: true);
      if (fallback != null) return fallback;
      if (_isNetworkError(e)) {
        _addToPendingOperations(_PendingOperation('Fetch trending', fetchTrendingTracks));
      }
      throw Exception("Failed to fetch trending tracks: $e");
    }
  }

  Future<List<Track>> fetchTracksByQuery(String query) async {
    final cacheKey = 'search_${query.hashCode}';
    final cachedMemory = _getInMemoryCache<List<Track>>(cacheKey);
    if (cachedMemory != null) return cachedMemory;

    try {
      final cached = await _getCachedTracks(cacheKey);
      if (cached != null) {
        _setInMemoryCache(cacheKey, cached);
        return cached;
      }

      if (!_networkService.isConnected) throw Exception('No internet');

      final results = await _yt.search.search(query);
      final tracks = _mapVideoResultsToTracks(results.toList()).take(20).toList();

      await _cacheTracks(cacheKey, tracks, NetworkConfig.shortCacheValidity);
      _setInMemoryCache(cacheKey, tracks);
      return tracks;
    } on SocketException catch (_) {
      final fallback = await _getCachedTracks(cacheKey, ignoreExpiry: true);
      return fallback ?? [];
    } on Exception catch (e) {
      final fallback = await _getCachedTracks(cacheKey, ignoreExpiry: true);
      if (fallback != null) return fallback;
      throw Exception("Search failed for '$query': $e");
    }
  }

  Future<List<Map<String, String>>> fetchTopArtists() async {
    const cacheKey = 'top_artists';
    final cachedMemory = _getInMemoryCache<List<Map<String, String>>>(cacheKey);
    if (cachedMemory != null) return cachedMemory;

    try {
      final cached = await _getCachedArtists(cacheKey);
      if (cached != null) {
        _setInMemoryCache(cacheKey, cached);
        return cached;
      }

      if (!_networkService.isConnected) throw Exception('No internet');

      final results = await _yt.search.search('top music artists 2024');
      final artistMap = <String, String>{};
      results.take(20).forEach((video) {
        if (video.author.isNotEmpty && !artistMap.containsKey(video.author)) {
          artistMap[video.author] = video.thumbnails.highResUrl;
        }
      });

      final artists = artistMap.entries.take(10).map((entry) {
        return {'name': entry.key, 'image': entry.value};
      }).toList();

      await _cacheArtists(cacheKey, artists, NetworkConfig.longCacheValidity);
      _setInMemoryCache(cacheKey, artists);
      return artists;
    } on SocketException catch (_) {
      final fallback = await _getCachedArtists(cacheKey, ignoreExpiry: true);
      return fallback ?? [];
    } on Exception catch (e) {
      final fallback = await _getCachedArtists(cacheKey, ignoreExpiry: true);
      if (fallback != null) return fallback;
      if (_isNetworkError(e)) {
        _addToPendingOperations(_PendingOperation('Fetch top artists', fetchTopArtists));
      }
      throw Exception("Failed to fetch top artists: $e");
    }
  }

  List<Track> _mapVideoResultsToTracks(List<Video> videos) {
    return videos
        .where((video) =>
    video.duration != null &&
        video.duration! > const Duration(seconds: 30) &&
        !video.isLive)
        .map((video) => Track(
      id: video.id.value,
      trackName: video.title.isEmpty ? "Unknown Title" : video.title,
      artistName: video.author.isEmpty ? "Unknown Artist" : video.author,
      albumName: "YouTube",
      previewUrl: video.url,
      albumArtUrl: video.thumbnails.highResUrl,
      source: 'youtube',
      duration: video.duration,
    ))
        .toList();
  }
  // -- AUDIO STREAM URL LOGIC --
  Future<String> getAudioStreamUrl(String videoId, int bitrate) async {
    print('ApiService: Fetching audio stream for video ID: $videoId with bitrate: $bitrate');
    try {
      // In-memory stream URL cache
      if (_streamUrlCache.containsKey(videoId)) {
        final cachedData = _streamUrlCache[videoId]!;
        final expiryTime = cachedData['expiry'] as int? ?? 0;
        if (DateTime.now().millisecondsSinceEpoch < expiryTime) {
          final streamUrl = cachedData['url'] as String? ?? '';
          if (streamUrl.isNotEmpty) return streamUrl;
        } else {
          _streamUrlCache.remove(videoId);
        }
      }

      // Validate/convert ID
      if (!isValidYoutubeID(videoId)) {
        print('ApiService: Non-YouTube ID ($videoId), attempting conversion...');
        final searchQuery = await getSearchQueryForTrack(videoId);
        final searchResults = await _yt.search.search(searchQuery);
        if (searchResults.isEmpty) throw Exception('No YouTube results found for ID: $videoId');
        videoId = searchResults.first.id.value;
      }

      int adjustedBitrate = bitrate;
      int attempts = 0;
      while (attempts < NetworkConfig.maxRetries) {
        try {
          final vidId = VideoId(videoId);
          final manifest = await _yt.videos.streamsClient.getManifest(vidId);
          final unmodifiableAudioStreams = manifest.audioOnly;
          if (unmodifiableAudioStreams.isEmpty) throw Exception('No audio streams found.');

          // sort by closest bitrate
          final List<AudioOnlyStreamInfo> mutableAudioStreams = List.from(unmodifiableAudioStreams);
          mutableAudioStreams.sortBy<num>(
                  (s) => (s.bitrate.bitsPerSecond / 1000 - adjustedBitrate).abs());

          final streamInfo = mutableAudioStreams.first;
          final streamUrl = streamInfo.url.toString();
          final expiryTime = DateTime.now().add(const Duration(hours: 5, minutes: 50)).millisecondsSinceEpoch;
          _streamUrlCache[videoId] = {
            'url': streamUrl,
            'expiry': expiryTime,
            'bitrate': streamInfo.bitrate.kiloBitsPerSecond.round()
          };
          return streamUrl;
        } on SocketException catch (_) {
          attempts++;
          if (attempts >= NetworkConfig.maxRetries) rethrow;
          await _waitBeforeRetry(attempts);
          if (!_networkService.isConnected) throw Exception('Lost connection during retry.');
        } on YoutubeExplodeException catch (e) {
          attempts++;
          if (e.message.contains("Video unavailable") || e.message.contains("Private video")) {
            throw Exception("Video unavailable: $videoId");
          }
          if (attempts >= NetworkConfig.maxRetries) rethrow;
        } on Exception catch (e) {
          attempts++;
          if (e.toString().contains("Video unavailable") ||
              e.toString().contains("Private video")) throw Exception("Video unavailable: $videoId");
          if (attempts >= NetworkConfig.maxRetries) rethrow;
          await _waitBeforeRetry(attempts);
        }
      }
      throw Exception('Failed after max retries.');
    } catch (e) {
      if (_isNetworkError(e)) {
        _addToPendingOperations(_PendingOperation('Get stream: $videoId', () => getAudioStreamUrl(videoId, bitrate)));
      }
      throw Exception('Failed to get audio stream: ${e.toString()}');
    }
  }

  // -- WAIT/RETRY HELPERS --
  Future<void> _waitBeforeRetry(int attempt) async {
    final backoffSeconds = pow(2, attempt) + (Random().nextDouble() * 0.5);
    await Future.delayed(Duration(milliseconds: (backoffSeconds * 1000).round()));
  }

  bool _isNetworkError(dynamic e) {
    if (e is SocketException) return true;
    if (e is DioException &&
        (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.unknown)) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('network') || msg.contains('connection') || msg.contains('socket') || msg.contains('host lookup');
  }

  // -- ID & TRACK SEARCH HELPERS --
  bool isValidYoutubeID(String id) {
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);
  }

  Future<String> getSearchQueryForTrack(String id) async {
    final track = await _getTrackInfoFromCache(id);
    if (track != null) {
      return "${track.trackName} ${track.artistName} official audio";
    }
    return id;
  }

  Future<Track?> _getTrackInfoFromCache(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allTracksJson = prefs.getString('all_tracks_cache');
      if (allTracksJson != null) {
        final List<dynamic> allTracksList = jsonDecode(allTracksJson);
        final trackData = allTracksList.firstWhereOrNull((t) => t is Map && t['id'] == id);
        if (trackData != null) {
          return Track.fromJson(Map<String, dynamic>.from(trackData));
        }
      }
    } catch (_) {}
    return null;
  }

  // -- ARTIST AND ALBUM METHODS --

  Future<Artist> fetchArtistDetails(String artistName) async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (artistName.isEmpty || artistName == 'Unknown Artist') {
      throw Exception("Cannot fetch details for unknown artist.");
    }
    String artistImageUrl = '';
    String bio = "Bio for $artistName currently unavailable.";
    List<Track> topTracks = [];
    List<Album> topAlbums = [];
    try {
      topTracks = (await fetchTracksByQuery("$artistName songs")).take(10).toList();
      if (topTracks.isNotEmpty && topTracks.first.albumArtUrl.isNotEmpty) {
        artistImageUrl = topTracks.first.albumArtUrl;
      }
      topAlbums = await fetchArtistTopAlbums(artistName);
    } catch (_) {}
    return Artist(
      id: artistName.hashCode.toString(),
      name: artistName,
      imageUrl: artistImageUrl,
      bio: bio,
      topAlbums: topAlbums,
      topTracks: topTracks,
    );
  }

  Future<List<Album>> fetchArtistTopAlbums(String artistName) async {
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      final artistTracks = await fetchTracksByQuery("$artistName songs");
      if (artistTracks.isEmpty) return [];
      final albumsMap = <String, List<Track>>{};
      for (var track in artistTracks) {
        if (track.albumName.isNotEmpty &&
            track.albumName != 'YouTube' &&
            track.albumName != 'Unknown Album' &&
            !track.albumName.toLowerCase().contains("various artists") &&
            !track.albumName.toLowerCase().contains("greatest hits") &&
            !track.albumName.toLowerCase().contains("top tracks") &&
            !track.albumName.toLowerCase().contains("playlist")) {
          albumsMap.putIfAbsent(track.albumName, () => []).add(track);
        }
      }
      if (albumsMap.isEmpty) return [];
      return albumsMap.entries
          .take(8)
          .map((entry) {
        String bestImageUrl = entry.value
            .firstWhereOrNull((t) => t.albumArtUrl.isNotEmpty)
            ?.albumArtUrl ?? '';
        return Album(
          id: entry.key.hashCode.toString() + artistName.hashCode.toString(),
          name: entry.key,
          artistName: artistName,
          imageUrl: bestImageUrl,
          tracks: [],
          releaseDate: DateTime.now().subtract(Duration(days: Random().nextInt(1825))),
        );
      })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Album> fetchAlbumDetails(String albumName, String artistName) async {
    if (albumName.isEmpty || albumName == 'YouTube' || albumName == 'Unknown Album') {
      throw Exception("Album details not available for this track.");
    }
    await Future.delayed(const Duration(milliseconds: 600));
    try {
      final tracks = await fetchTracksByQuery('"$albumName" "$artistName" album full');
      String imageUrl = '';
      DateTime releaseDate = DateTime.now().subtract(Duration(days: Random().nextInt(3650)));
      if (tracks.isNotEmpty) {
        final firstGoodTrack = tracks.firstWhereOrNull((t) => t.albumArtUrl.isNotEmpty);
        imageUrl = firstGoodTrack?.albumArtUrl ?? tracks.first.albumArtUrl;
      }
      return Album(
        id: albumName.hashCode.toString() + artistName.hashCode.toString(),
        name: albumName,
        artistName: artistName,
        imageUrl: imageUrl,
        tracks: tracks,
        releaseDate: releaseDate,
      );
    } catch (_) {
      throw Exception("Could not load album details.");
    }
  }

  // -- CACHING LOGIC: SHARED PREFERENCES --
  Future<void> _cacheTracks(String key, List<Track> tracks, Duration expiry) async {
    if(tracks.isEmpty) return;
    try {
      final p=await SharedPreferences.getInstance();
      final j=jsonEncode(tracks.map((t)=>t.toJson()).toList());
      final t=DateTime.now().add(expiry).millisecondsSinceEpoch;
      await p.setString('tracks_$key',j);
      await p.setInt('tracks_expiry_$key',t);
      final aJ=p.getString('all_tracks_cache')??'[]';
      final List<dynamic> aL=jsonDecode(aJ);
      final Set<String> eIds=aL.whereType<Map>().map((t)=>t['id'] as String? ?? '').toSet();
      for(final tr in tracks){if(!eIds.contains(tr.id))aL.add(tr.toJson());}
      await p.setString('all_tracks_cache',jsonEncode(aL));
    } catch(_) {}
  }

  Future<List<Track>?> _getCachedTracks(String key, {bool ignoreExpiry = false}) async {
    try {
      final p=await SharedPreferences.getInstance();
      final j=p.getString('tracks_$key');
      if(j==null)return null;
      final t=p.getInt('tracks_expiry_$key')??0;
      if(!ignoreExpiry && DateTime.now().millisecondsSinceEpoch>t) return null;
      final List<dynamic> l=jsonDecode(j);
      return l.map((t)=>Track.fromJson(Map<String,dynamic>.from(t))).toList();
    } catch(_) { return null; }
  }

  Future<void> _cacheArtists(String key, List<Map<String, String>> artists, Duration expiry) async {
    if(artists.isEmpty) return;
    try {
      final p=await SharedPreferences.getInstance();
      final j=jsonEncode(artists);
      final t=DateTime.now().add(expiry).millisecondsSinceEpoch;
      await p.setString('artists_$key',j);
      await p.setInt('artists_expiry_$key',t);
    } catch(_) {}
  }

  Future<List<Map<String, String>>?> _getCachedArtists(String key, {bool ignoreExpiry = false}) async {
    try {
      final p=await SharedPreferences.getInstance();
      final j=p.getString('artists_$key');
      if(j==null)return null;
      final t=p.getInt('artists_expiry_$key')??0;
      if(!ignoreExpiry && DateTime.now().millisecondsSinceEpoch>t) return null;
      final List<dynamic> l=jsonDecode(j);
      return l.map((a)=>Map<String,String>.from(a)).toList();
    } catch(_) { return null; }
  }

  // -- PENDING OPERATIONS QUEUE --
  void _addToPendingOperations(_PendingOperation operation) {
    if (!_pendingOperations.any((op) => op.description == operation.description)) {
      _pendingOperations.add(operation);
      if (!_isProcessingQueue && _networkService.isConnected) {
        _processOperationsQueue();
      }
    }
  }

  Future<void> _processOperationsQueue() async {
    if (_pendingOperations.isEmpty || _isProcessingQueue) return;
    _isProcessingQueue = true;
    while (_pendingOperations.isNotEmpty && _networkService.isConnected) {
      final op = _pendingOperations.removeAt(0);
      try {
        await op.execute();
      } catch (_) {
        if (op.attempts < 2) {
          op.attempts++;
          _pendingOperations.add(op);
        }
        await Future.delayed(const Duration(seconds: 5));
      }
    }
    _isProcessingQueue = false;
  }

  // -- CACHE MANAGEMENT & DISPOSE --
  Future<void> clearCache() async {
    try {
      final p=await SharedPreferences.getInstance();
      final k=p.getKeys().where((k)=> k.startsWith('tracks_')||k.startsWith('artists_')||k.startsWith('all_tracks_cache')||k.startsWith('tracks_expiry_')||k.startsWith('artists_expiry_')).toList();
      for(final key in k) await p.remove(key);
      _streamUrlCache.clear();
      _inMemoryListCache.clear();
    } catch(_) {}
  }

  void dispose() {
    _yt.close();
    _pendingOperations.clear();
    _inMemoryListCache.clear();
  }
}

// -- HELPER CLASSES --

class _PendingOperation {
  final String description;
  final Future<dynamic> Function() execute;
  int attempts = 1;
  _PendingOperation(this.description, this.execute);
}

class _CacheEntry<T> {
  final T data;
  final DateTime expiryTime;
  _CacheEntry(this.data, Duration duration) : expiryTime = DateTime.now().add(duration);
  bool get isExpired => DateTime.now().isAfter(expiryTime);
}

