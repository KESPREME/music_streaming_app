// lib/services/lyrics/lyrics_service.dart
// Enhanced lyrics service with disk caching, deduplication, and prefetching

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'lrclib_provider.dart';
import 'lyrics_cache_db.dart';
import '../innertube/innertube_service.dart';
import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';

/// Provider types for lyrics
enum LyricsProvider {
  lrclib,
  youtubeTranscript,
}

/// Main lyrics service that orchestrates multiple providers
/// with two-tier caching (memory + disk), deduplication, and prefetching
class LyricsService {
  final LrcLibProvider _lrcLibProvider = LrcLibProvider();
  final InnerTubeService _innerTubeService = InnerTubeService();
  final LyricsCacheDb _diskCache = LyricsCacheDb();
  
  // Memory cache (session-based, no expiry during session)
  final Map<String, LyricsResult> _memCache = {};
  static const int _maxMemCacheSize = 100;
  
  // In-flight request deduplication
  final Map<String, Future<LyricsResult?>> _inFlightRequests = {};
  
  // Prefetch queue
  final List<_PrefetchTask> _prefetchQueue = [];
  bool _isPrefetching = false;
  
  bool _isInitialized = false;
  
  /// Initialize the service (call once on app start)
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _diskCache.initialize();
    _isInitialized = true;
    if (kDebugMode) print('LyricsService: Initialized with disk cache');
  }
  
  /// Get lyrics with two-tier cache and deduplication
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
    final cacheKey = _buildCacheKey(title, artist);
    
    // 1. Check memory cache (fastest)
    if (_memCache.containsKey(cacheKey)) {
      if (kDebugMode) print('LyricsService: Memory cache hit for "$title"');
      return _memCache[cacheKey];
    }
    
    // 2. Check disk cache
    final diskEntry = await _diskCache.get(cacheKey);
    if (diskEntry != null) {
      if (kDebugMode) print('LyricsService: Disk cache hit for "$title"');
      final result = LyricsResult(
        lyrics: diskEntry.lyrics,
        isSynced: diskEntry.isSynced,
        provider: LyricsProvider.values.firstWhere(
          (p) => p.name == diskEntry.provider,
          orElse: () => LyricsProvider.lrclib,
        ),
      );
      _addToMemCache(cacheKey, result);
      return result;
    }
    
    // 3. Deduplicate in-flight requests
    if (_inFlightRequests.containsKey(cacheKey)) {
      if (kDebugMode) print('LyricsService: Deduplicating request for "$title"');
      return _inFlightRequests[cacheKey];
    }
    
    // 4. Fetch from providers
    _inFlightRequests[cacheKey] = _fetchFromProviders(
      cacheKey, title, artist, durationMs, videoId, providerOrder,
    );
    
    try {
      final result = await _inFlightRequests[cacheKey];
      return result;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }
  
  /// Internal fetch with fallback chain
  Future<LyricsResult?> _fetchFromProviders(
    String cacheKey,
    String title,
    String artist,
    int? durationMs,
    String? videoId,
    List<LyricsProvider> providerOrder,
  ) async {
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
          
          // Cache in memory
          _addToMemCache(cacheKey, result);
          
          // Cache to disk (fire and forget)
          _diskCache.put(cacheKey, result.lyrics, result.isSynced, provider.name);
          
          return result;
        }
      } catch (e) {
        if (kDebugMode) {
          print('LyricsService: ${provider.name} failed: $e');
        }
      }
    }
    
    if (kDebugMode) print('LyricsService: No lyrics found for "$title"');
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
      // Parse in isolate for performance
      return compute(_parseLrcInIsolate, result.lyrics);
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
  
  /// Static function for isolate parsing
  static List<LyricsEntry> _parseLrcInIsolate(String lrcContent) {
    return LyricsUtils.parseLrc(lrcContent);
  }
  
  /// Prefetch lyrics for upcoming tracks (call with next 3 tracks)
  void prefetchLyrics(List<Map<String, String>> tracks) {
    for (final track in tracks) {
      final title = track['title'] ?? '';
      final artist = track['artist'] ?? '';
      final videoId = track['videoId'];
      
      if (title.isEmpty || artist.isEmpty) continue;
      
      final cacheKey = _buildCacheKey(title, artist);
      
      // Skip if already cached or in queue
      if (_memCache.containsKey(cacheKey)) continue;
      if (_prefetchQueue.any((t) => t.cacheKey == cacheKey)) continue;
      
      _prefetchQueue.add(_PrefetchTask(
        cacheKey: cacheKey,
        title: title,
        artist: artist,
        videoId: videoId,
      ));
    }
    
    _processPrefetchQueue();
  }
  
  /// Process prefetch queue in background
  Future<void> _processPrefetchQueue() async {
    if (_isPrefetching || _prefetchQueue.isEmpty) return;
    
    _isPrefetching = true;
    
    while (_prefetchQueue.isNotEmpty) {
      final task = _prefetchQueue.removeAt(0);
      
      try {
        // Check if already cached (may have been fetched while in queue)
        final diskEntry = await _diskCache.get(task.cacheKey);
        if (diskEntry != null) continue;
        
        // Low-priority fetch (don't block UI)
        await Future.delayed(const Duration(milliseconds: 100));
        
        await getLyrics(
          title: task.title,
          artist: task.artist,
          videoId: task.videoId,
        );
        
        if (kDebugMode) print('LyricsService: Prefetched lyrics for "${task.title}"');
      } catch (e) {
        if (kDebugMode) print('LyricsService: Prefetch failed for "${task.title}": $e');
      }
    }
    
    _isPrefetching = false;
  }
  
  /// Try to get lyrics from LrcLib with enhanced metadata normalization
  Future<LyricsResult?> _tryLrcLib(String title, String artist, int? durationMs) async {
    // Strategy: Try multiple normalized variants
    final variants = _generateSearchVariants(title, artist);
    
    for (final variant in variants) {
      final result = await _lrcLibProvider.getLyrics(
        title: variant.title,
        artist: variant.artist,
        durationSeconds: durationMs != null ? durationMs ~/ 1000 : null,
      );
      
      if (result != null) {
        final isSynced = result.trimLeft().startsWith('[');
        return LyricsResult(
          lyrics: result,
          isSynced: isSynced,
          provider: LyricsProvider.lrclib,
        );
      }
    }
    
    return null;
  }
  
  /// Generate search variants for better matching
  List<_SearchVariant> _generateSearchVariants(String title, String artist) {
    final variants = <_SearchVariant>[];
    
    // Original
    variants.add(_SearchVariant(title, artist));
    
    // Clean both
    final cleanTitle = _cleanTitle(title);
    final cleanArtist = _cleanArtist(artist);
    
    if (cleanTitle != title || cleanArtist != artist) {
      variants.add(_SearchVariant(cleanTitle, cleanArtist));
    }
    
    // Clean title only
    if (cleanTitle != title) {
      variants.add(_SearchVariant(cleanTitle, artist));
    }
    
    // Clean artist only
    if (cleanArtist != artist) {
      variants.add(_SearchVariant(title, cleanArtist));
    }
    
    // Aggressive clean (remove more patterns)
    final aggressiveTitle = _aggressiveCleanTitle(title);
    final aggressiveArtist = _aggressiveCleanArtist(artist);
    
    if (aggressiveTitle != cleanTitle || aggressiveArtist != cleanArtist) {
      variants.add(_SearchVariant(aggressiveTitle, aggressiveArtist));
    }
    
    return variants;
  }
  
  /// Standard title cleaning
  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'[\(\[].*?feat.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[].*?ft\.?.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[].*?remaster.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[].*?remix.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[].*?mix.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[].*?live.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[].*?version.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[].*?edit.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'-\s*live.*', caseSensitive: false), '')
        .trim();
  }
  
  /// Aggressive title cleaning
  String _aggressiveCleanTitle(String title) {
    return _cleanTitle(title)
        .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), '') // Remove all parentheticals
        .replaceAll(RegExp(r'\s*-\s*[^-]+$'), '') // Remove trailing " - ..." 
        .replaceAll(RegExp(r"[''`]"), "'") // Normalize quotes
        .replaceAll(RegExp(r'[""❝❞]'), '"')
        .trim();
  }
  
  /// Standard artist cleaning  
  String _cleanArtist(String artist) {
    var cleaned = artist.replaceAll(' - Topic', '').trim();
    
    // Take first artist if multiple
    if (cleaned.contains(',')) {
      cleaned = cleaned.split(',').first.trim();
    }
    
    // Remove VEVO
    cleaned = cleaned.replaceAll(RegExp(r'\s*VEVO', caseSensitive: false), '');
    
    return cleaned.trim();
  }
  
  /// Aggressive artist cleaning
  String _aggressiveCleanArtist(String artist) {
    var cleaned = _cleanArtist(artist);
    
    // Handle common separators for collaborations
    final separators = [' & ', ' x ', ' X ', ' and ', ' with ', ' feat ', ' ft '];
    for (final sep in separators) {
      if (cleaned.contains(sep)) {
        cleaned = cleaned.split(sep).first.trim();
        break;
      }
    }
    
    return cleaned;
  }
  
  /// Try to get lyrics from YouTube transcript
  Future<LyricsResult?> _tryYouTubeTranscript(String videoId) async {
    final transcript = await _innerTubeService.getTranscript(videoId);
    
    if (transcript != null && transcript.isNotEmpty) {
      return LyricsResult(
        lyrics: transcript,
        isSynced: true,
        provider: LyricsProvider.youtubeTranscript,
      );
    }
    
    return null;
  }
  
  /// Build cache key from title and artist
  String _buildCacheKey(String title, String artist) {
    return '${title.toLowerCase().trim()}_${artist.toLowerCase().trim()}';
  }
  
  /// Add result to memory cache with LRU eviction
  void _addToMemCache(String key, LyricsResult result) {
    if (_memCache.length >= _maxMemCacheSize) {
      // Remove first (oldest) entry
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[key] = result;
  }
  
  /// Clear all caches
  Future<void> clearCache() async {
    _memCache.clear();
    await _diskCache.clear();
    if (kDebugMode) print('LyricsService: All caches cleared');
  }
  
  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    final diskStats = await _diskCache.getStats();
    return {
      'memoryCount': _memCache.length,
      'diskCount': diskStats['count'],
      'inFlightCount': _inFlightRequests.length,
      'prefetchQueueLength': _prefetchQueue.length,
    };
  }
  
  void dispose() {
    _innerTubeService.dispose();
    _diskCache.close();
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

/// Internal prefetch task
class _PrefetchTask {
  final String cacheKey;
  final String title;
  final String artist;
  final String? videoId;
  
  _PrefetchTask({
    required this.cacheKey,
    required this.title,
    required this.artist,
    this.videoId,
  });
}

/// Internal search variant
class _SearchVariant {
  final String title;
  final String artist;
  
  _SearchVariant(this.title, this.artist);
}
