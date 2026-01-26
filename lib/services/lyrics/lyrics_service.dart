// lib/services/lyrics/lyrics_service.dart

// Supports: LrcLib, YouTube Transcripts

import 'package:flutter/foundation.dart';
import 'lrclib_provider.dart';
import '../innertube/innertube_service.dart';
import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';

/// Provider types for lyrics
enum LyricsProvider {
  lrclib,
  youtubeTranscript,
}

/// Main lyrics service that orchestrates multiple providers

class LyricsService {
  final LrcLibProvider _lrcLibProvider = LrcLibProvider();
  final InnerTubeService _innerTubeService = InnerTubeService();
  
  // LRU-style cache for lyrics
  final Map<String, CachedLyrics> _cache = {};
  static const int _maxCacheSize = 50;
  
  /// Get lyrics with fallback through multiple providers
  /// Returns raw lyrics string (LRC format for synced, plain text otherwise)
  Future<LyricsResult?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? videoId,
    List<LyricsProvider> providerOrder = const [
      LyricsProvider.lrclib,
      LyricsProvider.youtubeTranscript,
    ],
  }) async {
    // Check cache first
    final cacheKey = _buildCacheKey(title, artist);
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (!cached.isExpired) {
        if (kDebugMode) {
          print('LyricsService: Cache hit for "$title"');
        }
        return cached.result;
      } else {
        _cache.remove(cacheKey);
      }
    }
    
    // Try each provider in order
    for (final provider in providerOrder) {
      try {
        LyricsResult? result;
        
        switch (provider) {
          case LyricsProvider.lrclib:
            result = await _tryLrcLib(title, artist, durationMs);
            break;
          case LyricsProvider.youtubeTranscript:
            if (videoId != null) {
              result = await _tryYouTubeTranscript(videoId);
            }
            break;
        }
        
        if (result != null && result.lyrics.isNotEmpty) {
          if (kDebugMode) {
            print('LyricsService: Found lyrics via ${provider.name} for "$title"');
          }
          
          // Cache the result
          _addToCache(cacheKey, result);
          
          return result;
        }
      } catch (e) {
        if (kDebugMode) {
          print('LyricsService: ${provider.name} failed: $e');
        }
        // Continue to next provider
      }
    }
    
    if (kDebugMode) {
      print('LyricsService: No lyrics found for "$title"');
    }
    return null;
  }
  
  /// Get parsed lyrics entries (with timestamps)
  Future<List<LyricsEntry>> getParsedLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? videoId,
  }) async {
    final result = await getLyrics(
      title: title,
      artist: artist,
      durationMs: durationMs,
      videoId: videoId,
    );
    
    if (result == null) return [];
    
    if (result.isSynced) {
      return LyricsUtils.parseLrc(result.lyrics);
    } else {
      // Convert plain lyrics to entries without timestamps
      return result.lyrics
          .split('\n')
          .asMap()
          .entries
          .map((e) => LyricsEntry(
                timeMs: e.key * 5000, // 5 second intervals for unsync'd
                text: e.value,
              ))
          .toList();
    }
  }
  
  /// Try to get lyrics from LrcLib
  Future<LyricsResult?> _tryLrcLib(String title, String artist, int? durationMs) async {
    // 1. Try exact match
    var result = await _lrcLibProvider.getLyrics(
      title: title,
      artist: artist,
      durationSeconds: durationMs != null ? durationMs ~/ 1000 : null,
    );
    
    // 2. If not found, try varying title and artist cleaning
    if (result == null) {
       final cleanTitle = _cleanTitle(title);
       final cleanArtist = _cleanArtist(artist);
       
       // Try Clean Title + Clean Artist (Best Chance)
       if (cleanTitle != title || cleanArtist != artist) {
         if (kDebugMode) print('LyricsService: Retrying with cleaned metadata: "$cleanTitle" by "$cleanArtist"');
         result = await _lrcLibProvider.getLyrics(
            title: cleanTitle,
            artist: cleanArtist,
            durationSeconds: durationMs != null ? durationMs ~/ 1000 : null,
         );
       }
       
       // Try Original Title + Clean Artist (Check if Artist was the issue)
       if (result == null && cleanArtist != artist) {
          if (kDebugMode) print('LyricsService: Retrying with clean artist only: "$title" by "$cleanArtist"');
          result = await _lrcLibProvider.getLyrics(
            title: title,
            artist: cleanArtist,
            durationSeconds: durationMs != null ? durationMs ~/ 1000 : null,
         );
       }
    }

    if (result != null) {
      // Check if it's synced (starts with [)
      final isSynced = result.trimLeft().startsWith('[');
      return LyricsResult(
        lyrics: result,
        isSynced: isSynced,
        provider: LyricsProvider.lrclib,
      );
    }
    
    return null;
  }

  String _cleanTitle(String title) {
    // Remove (feat. ...), [feat. ...], (ft. ...), [ft. ...]
    // Remove (Remastered...), [Remastered...]
    // Remove - Live, (Live)
    return title
        .replaceAll(RegExp(r'[\(\[]\s*(feat|ft|featuring)\.?\s+.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[]\s*(remaster|remastered|mix|remix).*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[]\s*live.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'-\s*live.*', caseSensitive: false), '')
        .trim();
  }
  
  String _cleanArtist(String artist) {
    // 1. Remove " - Topic" (YouTube auto-generated)
    var cleaned = artist.replaceAll(' - Topic', '').trim();
    
    // 2. If valid comma exists (e.g. "Ed Sheeran, Shape of You, 3:54"), take first part
    // But be careful of "Earth, Wind & Fire" -> check if 2nd part looks like a song title matching our title?
    // Heuristic: If comma exists, and the string is long/complex, try taking the first chunk.
    if (cleaned.contains(',')) {
       final parts = cleaned.split(',');
       if (parts.isNotEmpty) {
         cleaned = parts.first.trim();
       }
    }
    
    // 3. Remove "Vevo" etc.
    cleaned = cleaned.replaceAll(RegExp(r'\s*VEVO', caseSensitive: false), '');
    
    return cleaned.trim();
  }
  
  /// Try to get lyrics from YouTube transcript
  Future<LyricsResult?> _tryYouTubeTranscript(String videoId) async {
    final transcript = await _innerTubeService.getTranscript(videoId);
    
    if (transcript != null && transcript.isNotEmpty) {
      return LyricsResult(
        lyrics: transcript,
        isSynced: true, // Transcripts are always synced
        provider: LyricsProvider.youtubeTranscript,
      );
    }
    
    return null;
  }
  
  /// Build cache key from title and artist
  String _buildCacheKey(String title, String artist) {
    return '${title.toLowerCase().trim()}_${artist.toLowerCase().trim()}';
  }
  
  /// Add result to cache with LRU eviction
  void _addToCache(String key, LyricsResult result) {
    // Evict oldest if at capacity
    if (_cache.length >= _maxCacheSize) {
      final oldest = _cache.entries
          .reduce((a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b);
      _cache.remove(oldest.key);
    }
    
    _cache[key] = CachedLyrics(result);
  }
  
  /// Clear the lyrics cache
  void clearCache() {
    _cache.clear();
  }
  
  void dispose() {
    _innerTubeService.dispose();
  }
}

/// Result from lyrics lookup
class LyricsResult {
  final String lyrics;
  final bool isSynced;
  final LyricsProvider provider;
  
  const LyricsResult({
    required this.lyrics,
    required this.isSynced,
    required this.provider,
  });
}

/// Cached lyrics with expiration
class CachedLyrics {
  final LyricsResult result;
  final DateTime timestamp;
  
  CachedLyrics(this.result) : timestamp = DateTime.now();
  
  // Cache for 1 hour
  bool get isExpired => 
      DateTime.now().difference(timestamp) > const Duration(hours: 1);
}
