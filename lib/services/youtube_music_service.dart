// lib/services/youtube_music_service.dart
// Fast YouTube Music service using youtube_explode_dart
// Optimized for speed and reliability

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';

/// Fast YouTube Music service for international songs
/// Uses youtube_explode_dart for direct YouTube access
class YouTubeMusicService {
  final YoutubeExplode _yt = YoutubeExplode();
  
  // Cache for stream URLs (YouTube URLs expire after ~6 hours)
  final Map<String, _StreamCache> _streamCache = {};
  static const Duration _streamCacheDuration = Duration(hours: 5, minutes: 50);
  
  // Cache for search results
  final Map<String, _SearchCache> _searchCache = {};
  static const Duration _searchCacheDuration = Duration(minutes: 10);
  
  /// Search for songs on YouTube Music
  Future<List<Track>> searchSongs(String query, {int limit = 100}) async {
    try {
      if (query.trim().isEmpty) return [];
      
      // Check cache first
      final cacheKey = '${query}_$limit';
      if (_searchCache.containsKey(cacheKey)) {
        final cached = _searchCache[cacheKey]!;
        if (!cached.isExpired) {
          if (kDebugMode) {
            print('YouTubeMusicService: Returning cached results for "$query"');
          }
          return cached.tracks;
        }
        _searchCache.remove(cacheKey);
      }
      
      if (kDebugMode) {
        print('YouTubeMusicService: Searching for "$query" (limit: $limit)');
      }
      
      // Search YouTube
      final searchQuery = '$query music';
      final results = await _yt.search.search(searchQuery);
      
      // Convert to tracks
      final tracks = results
          .where((video) =>
              video.duration != null &&
              video.duration! > const Duration(seconds: 30) &&
              video.duration! < const Duration(hours: 1) && // Filter out long videos
              !video.isLive)
          .take(limit)
          .map((video) => Track(
                id: video.id.value,
                trackName: _cleanTitle(video.title),
                artistName: video.author.isEmpty ? 'Unknown Artist' : video.author,
                albumName: 'YouTube Music',
                previewUrl: video.url,
                albumArtUrl: video.thumbnails.highResUrl,
                source: 'youtube',
                duration: video.duration,
              ))
          .toList();
      
      // Cache results
      _searchCache[cacheKey] = _SearchCache(tracks);
      
      if (kDebugMode) {
        print('YouTubeMusicService: Found ${tracks.length} songs');
      }
      
      return tracks;
    } catch (e) {
      if (kDebugMode) {
        print('YouTubeMusicService: Search error: $e');
      }
      return [];
    }
  }
  
  /// Get songs by artist
  Future<List<Track>> getArtistSongs(String artistName, {int limit = 100}) async {
    try {
      if (artistName.trim().isEmpty) return [];
      
      if (kDebugMode) {
        print('YouTubeMusicService: Getting songs for artist: "$artistName"');
      }
      
      // Search for artist's top songs
      final query = '$artistName top songs';
      final results = await searchSongs(query, limit: limit);
      
      // Filter by artist name
      final filtered = results.where((track) {
        return track.artistName.toLowerCase().contains(artistName.toLowerCase()) ||
               track.trackName.toLowerCase().contains(artistName.toLowerCase());
      }).toList();
      
      if (kDebugMode) {
        print('YouTubeMusicService: Found ${filtered.length} songs for artist');
      }
      
      return filtered;
    } catch (e) {
      if (kDebugMode) {
        print('YouTubeMusicService: Get artist songs error: $e');
      }
      return [];
    }
  }
  
  /// Get audio stream URL for a video
  Future<String> getAudioStreamUrl(String videoId, {int preferredBitrate = 128}) async {
    try {
      // Check cache first
      if (_streamCache.containsKey(videoId)) {
        final cached = _streamCache[videoId]!;
        if (!cached.isExpired) {
          if (kDebugMode) {
            print('YouTubeMusicService: Returning cached stream URL for $videoId');
          }
          return cached.url;
        }
        _streamCache.remove(videoId);
      }
      
      if (kDebugMode) {
        print('YouTubeMusicService: Fetching stream URL for $videoId');
      }
      
      // Get stream manifest
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreams = manifest.audioOnly;
      
      if (audioStreams.isEmpty) {
        throw Exception('No audio streams available for $videoId');
      }
      
      // Select best stream based on preferred bitrate
      final stream = _selectBestStream(audioStreams, preferredBitrate);
      final streamUrl = stream.url.toString();
      
      // Cache the URL
      _streamCache[videoId] = _StreamCache(streamUrl);
      
      if (kDebugMode) {
        print('YouTubeMusicService: Stream URL obtained - ${stream.bitrate.kiloBitsPerSecond.round()} kbps');
      }
      
      return streamUrl;
    } catch (e) {
      if (kDebugMode) {
        print('YouTubeMusicService: Get stream URL error: $e');
      }
      rethrow;
    }
  }
  
  /// Get trending/popular songs
  Future<List<Track>> getTrendingTracks({int limit = 50}) async {
    try {
      if (kDebugMode) {
        print('YouTubeMusicService: Getting trending tracks');
      }
      
      final results = await searchSongs('top songs 2025', limit: limit);
      return results;
    } catch (e) {
      if (kDebugMode) {
        print('YouTubeMusicService: Get trending error: $e');
      }
      return [];
    }
  }
  
  /// Clean video title to extract song name
  String _cleanTitle(String title) {
    // Remove common patterns
    final patterns = [
      RegExp(r'\(Official.*?\)', caseSensitive: false),
      RegExp(r'\[Official.*?\]', caseSensitive: false),
      RegExp(r'\(Audio\)', caseSensitive: false),
      RegExp(r'\[Audio\]', caseSensitive: false),
      RegExp(r'\(Lyrics?\)', caseSensitive: false),
      RegExp(r'\[Lyrics?\]', caseSensitive: false),
      RegExp(r'\(HD\)', caseSensitive: false),
      RegExp(r'\[HD\]', caseSensitive: false),
      RegExp(r'\(4K\)', caseSensitive: false),
      RegExp(r'\[4K\]', caseSensitive: false),
    ];
    
    String cleaned = title;
    for (final pattern in patterns) {
      cleaned = cleaned.replaceAll(pattern, '');
    }
    
    return cleaned.trim();
  }
  
  /// Select best audio stream based on bitrate preference
  AudioOnlyStreamInfo _selectBestStream(List<AudioOnlyStreamInfo> streams, int preferredBitrate) {
    if (streams.isEmpty) {
      throw Exception('No streams available');
    }
    
    if (streams.length == 1) {
      return streams.first;
    }
    
    // Find stream closest to preferred bitrate
    AudioOnlyStreamInfo? bestStream;
    int minDiff = double.maxFinite.toInt();
    
    for (final stream in streams) {
      final streamBitrate = stream.bitrate.kiloBitsPerSecond.round();
      final diff = (streamBitrate - preferredBitrate).abs();
      
      if (diff < minDiff) {
        bestStream = stream;
        minDiff = diff;
      }
    }
    
    return bestStream ?? streams.first;
  }
  
  /// Clear all caches
  void clearCache() {
    _streamCache.clear();
    _searchCache.clear();
    if (kDebugMode) {
      print('YouTubeMusicService: Cache cleared');
    }
  }
  
  /// Dispose resources
  void dispose() {
    _yt.close();
    clearCache();
  }
}

/// Cache entry for stream URLs
class _StreamCache {
  final String url;
  final DateTime expiryTime;
  
  _StreamCache(this.url)
      : expiryTime = DateTime.now().add(YouTubeMusicService._streamCacheDuration);
  
  bool get isExpired => DateTime.now().isAfter(expiryTime);
}

/// Cache entry for search results
class _SearchCache {
  final List<Track> tracks;
  final DateTime expiryTime;
  
  _SearchCache(this.tracks)
      : expiryTime = DateTime.now().add(YouTubeMusicService._searchCacheDuration);
  
  bool get isExpired => DateTime.now().isAfter(expiryTime);
}
