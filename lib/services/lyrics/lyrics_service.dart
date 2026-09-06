// lib/services/lyrics/lyrics_service.dart
// BitChord-matching multi-source lyrics service with syllable/word-first priority,
// tiered fallbacks, two-tier caching, deduplication, and instrumental gap synthesis.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'better_lyrics_provider.dart';
import 'simp_music_provider.dart';
import 'kugou_provider.dart';
import 'lrclib_provider.dart';
import 'lyrics_cache_db.dart';
import '../innertube/innertube_service.dart';
import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';

/// Provider types for lyrics matching BitChord LyricsSource
enum LyricsProvider {
  betterLyrics,
  simpMusic,
  kugou,
  lrclib,
  youtubeTranscript,
}

/// Main lyrics service that orchestrates multiple providers
/// with syllable-first priority, two-tier caching, and instrumental gap handling
class LyricsService {
  final BetterLyricsProvider _betterLyricsProvider = BetterLyricsProvider();
  final SimpMusicProvider _simpMusicProvider = SimpMusicProvider();
  final KuGouProvider _kugouProvider = KuGouProvider();
  final LrcLibProvider _lrcLibProvider = LrcLibProvider();
  final InnerTubeService _innerTubeService = InnerTubeService();
  final LyricsCacheDb _diskCache = LyricsCacheDb();

  // Memory cache for raw results
  final Map<String, LyricsResult> _memCache = {};
  // Memory cache for parsed entries (including word-level timing)
  final Map<String, List<LyricsEntry>> _parsedCache = {};
  static const int _maxMemCacheSize = 100;

  // In-flight request deduplication
  final Map<String, Future<List<LyricsEntry>>> _inFlightRequests = {};

  // Prefetch queue
  final List<_PrefetchTask> _prefetchQueue = [];
  bool _isPrefetching = false;

  bool _isInitialized = false;

  /// Initialize the service (call once on app start)
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _diskCache.initialize();
    _isInitialized = true;
    if (kDebugMode) debugPrint('LyricsService: Initialized with disk cache');
  }

  /// Get parsed lyrics entries with BitChord's syllable/word-first prioritization
  Future<List<LyricsEntry>> getParsedLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? videoId,
    String? album,
  }) async {
    final cacheKey = _buildCacheKey(title, artist);

    // 1. Check memory parsed cache
    if (_parsedCache.containsKey(cacheKey)) {
      if (kDebugMode) debugPrint('LyricsService: Parsed cache hit for "$title"');
      return _parsedCache[cacheKey]!;
    }

    // 2. Check disk cache
    final diskEntry = await _diskCache.get(cacheKey);
    if (diskEntry != null && diskEntry.lyrics.isNotEmpty) {
      final entries = diskEntry.isSynced
          ? LyricsUtils.parseLrc(diskEntry.lyrics)
          : LyricsUtils.parsePlainText(diskEntry.lyrics);

      // Invalidate if contaminated by legacy BetterLyrics unspaced bug
      final isContaminated = diskEntry.provider == LyricsProvider.betterLyrics.name &&
          entries.any((e) =>
              e.text.length >= 18 &&
              !e.text.contains(' ') &&
              RegExp(r'^[a-zA-Z0-9\x27\x22\.,!?\-]+$').hasMatch(e.text));

      if (isContaminated) {
        if (kDebugMode) {
          debugPrint('LyricsService: Invalidating unspaced legacy disk cache for "$title"');
        }
      } else {
        if (kDebugMode) debugPrint('LyricsService: Disk cache hit for "$title"');
        final withGaps = withInstrumentalGaps(entries);
        _parsedCache[cacheKey] = withGaps;
        return withGaps;
      }
    }

    // 3. Deduplicate in-flight requests
    if (_inFlightRequests.containsKey(cacheKey)) {
      if (kDebugMode) debugPrint('LyricsService: Deduplicating request for "$title"');
      return _inFlightRequests[cacheKey]!;
    }

    final future = _fetchWithSyllablePriority(
      cacheKey: cacheKey,
      title: title,
      artist: artist,
      durationMs: durationMs,
      videoId: videoId,
      album: album,
    );

    _inFlightRequests[cacheKey] = future;
    try {
      final result = await future;
      return result;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  /// Fetches lyrics trying word/syllable-level sources first, then line-synced fallbacks
  Future<List<LyricsEntry>> _fetchWithSyllablePriority({
    required String cacheKey,
    required String title,
    required String artist,
    int? durationMs,
    String? videoId,
    String? album,
  }) async {
    // ── TIER 1: Word / Syllable-synced sources (highest priority) ────────
    // 1a. BetterLyrics (Apple Music TTML per-syllable timing)
    try {
      final betterEntries = await _betterLyricsProvider.getLyrics(
        title: title,
        artist: artist,
        durationMs: durationMs,
        album: album,
      );
      if (betterEntries != null && betterEntries.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('LyricsService: BetterLyrics word-synced hit (${betterEntries.length} lines)');
        }
        final withGaps = withInstrumentalGaps(betterEntries);
        _cacheParsed(cacheKey, withGaps, LyricsProvider.betterLyrics);
        return withGaps;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsService: BetterLyrics failed: $e');
    }

    // 1b. SimpMusic (matched on video ID, richSync word-timing)
    if (videoId != null && videoId.isNotEmpty) {
      try {
        final simpEntries = await _simpMusicProvider.getLyrics(
          videoId: videoId,
          durationMs: durationMs,
        );
        if (simpEntries != null && simpEntries.isNotEmpty) {
          if (simpEntries.any((e) => e.isWordSynced)) {
            if (kDebugMode) {
              debugPrint('LyricsService: SimpMusic richSync word-synced hit (${simpEntries.length} lines)');
            }
            final withGaps = withInstrumentalGaps(simpEntries);
            _cacheParsed(cacheKey, withGaps, LyricsProvider.simpMusic);
            return withGaps;
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('LyricsService: SimpMusic failed: $e');
      }
    }

    // ── TIER 2: Line-synced fallbacks ────────────────────────────────────
    // 2a. KuGou (massive catalogue)
    try {
      final kugouEntries = await _kugouProvider.getLyrics(
        title: title,
        artist: artist,
        durationMs: durationMs,
      );
      if (kugouEntries != null && kugouEntries.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('LyricsService: KuGou line-synced hit (${kugouEntries.length} lines)');
        }
        final withGaps = withInstrumentalGaps(kugouEntries);
        _cacheParsed(cacheKey, withGaps, LyricsProvider.kugou);
        return withGaps;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsService: KuGou failed: $e');
    }

    // 2b. LrcLib (free community database)
    try {
      final lrcResult = await _tryLrcLib(title, artist, durationMs);
      if (lrcResult != null && lrcResult.lyrics.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('LyricsService: LrcLib line-synced hit');
        }
        final entries = LyricsUtils.parseLrc(lrcResult.lyrics);
        if (entries.isNotEmpty) {
          final withGaps = withInstrumentalGaps(entries);
          _cacheParsed(cacheKey, withGaps, LyricsProvider.lrclib);
          return withGaps;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsService: LrcLib failed: $e');
    }

    // ── TIER 3: Plaintext / Transcript fallbacks ─────────────────────────
    if (videoId != null && videoId.isNotEmpty) {
      try {
        final ytResult = await _tryYouTubeTranscript(videoId);
        if (ytResult != null && ytResult.lyrics.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('LyricsService: YouTube transcript hit');
          }
          final entries = LyricsUtils.parseLrc(ytResult.lyrics);
          if (entries.isNotEmpty) {
            final withGaps = withInstrumentalGaps(entries);
            _cacheParsed(cacheKey, withGaps, LyricsProvider.youtubeTranscript);
            return withGaps;
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('LyricsService: YouTube transcript failed: $e');
      }
    }

    if (kDebugMode) debugPrint('LyricsService: No lyrics found for "$title"');
    return [];
  }

  /// Synthesizes musical breaks / instrumental pauses between distant timestamps (BitChord LyricGaps parity)
  static List<LyricsEntry> withInstrumentalGaps(List<LyricsEntry> entries) {
    if (entries.isEmpty) return entries;
    const minGapMs = 3800;
    final out = <LyricsEntry>[];

    // Find the first actual sung lyric entry (skipping empty headEntry)
    final firstVocalIdx = entries.indexWhere(
      (e) => e.text.trim().isNotEmpty && !e.isMusicalBreak,
    );

    // If first vocal line starts after intro gap (>= 3.5s), insert intro break
    if (firstVocalIdx >= 0 && entries[firstVocalIdx].timeMs >= 3500) {
      out.add(const LyricsEntry(timeMs: 0, text: '• • •'));
    }

    for (int i = 0; i < entries.length; i++) {
      final line = entries[i];
      // Avoid duplicate empty head entries at 0ms if we inserted an intro break
      if (line.text.trim().isEmpty && out.isNotEmpty) continue;
      out.add(line);

      if (i + 1 < entries.length) {
        final next = entries[i + 1];
        if (next.text.trim().isEmpty) continue;
        final lineEnd = line.endMs ?? (line.timeMs + 3200);
        final silence = next.timeMs - lineEnd;
        if (silence >= minGapMs && lineEnd > line.timeMs) {
          out.add(LyricsEntry(timeMs: lineEnd, text: '• • •'));
        }
      }
    }
    return out;
  }

  void _cacheParsed(
      String cacheKey, List<LyricsEntry> entries, LyricsProvider provider) {
    if (_parsedCache.length >= _maxMemCacheSize) {
      _parsedCache.remove(_parsedCache.keys.first);
    }
    _parsedCache[cacheKey] = entries;

    // Convert to LRC text for disk persistence
    final buffer = StringBuffer();
    for (final e in entries) {
      final m = (e.timeMs ~/ 60000).toString().padLeft(2, '0');
      final s = ((e.timeMs % 60000) / 1000).toStringAsFixed(2).padLeft(5, '0');
      buffer.writeln('[$m:$s]${e.text}');
    }
    _diskCache.put(cacheKey, buffer.toString(), true, provider.name);
  }

  /// Backward-compatible getLyrics method
  Future<LyricsResult?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? videoId,
    List<LyricsProvider> providerOrder = const [
      LyricsProvider.betterLyrics,
      LyricsProvider.simpMusic,
      LyricsProvider.kugou,
      LyricsProvider.lrclib,
      LyricsProvider.youtubeTranscript,
    ],
  }) async {
    final entries = await getParsedLyrics(
      title: title,
      artist: artist,
      durationMs: durationMs,
      videoId: videoId,
    );
    if (entries.isEmpty) return null;

    final buffer = StringBuffer();
    for (final e in entries) {
      final m = (e.timeMs ~/ 60000).toString().padLeft(2, '0');
      final s = ((e.timeMs % 60000) / 1000).toStringAsFixed(2).padLeft(5, '0');
      buffer.writeln('[$m:$s]${e.text}');
    }
    return LyricsResult(
      lyrics: buffer.toString(),
      isSynced: true,
      provider: LyricsProvider.betterLyrics,
    );
  }

  /// Try to get lyrics from LrcLib with enhanced metadata normalization
  Future<LyricsResult?> _tryLrcLib(
      String title, String artist, int? durationMs) async {
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
    variants.add(_SearchVariant(title, artist));

    final cleanTitle = _cleanTitle(title);
    final cleanArtist = _cleanArtist(artist);

    if (cleanTitle != title || cleanArtist != artist) {
      variants.add(_SearchVariant(cleanTitle, cleanArtist));
    }
    if (cleanTitle != title) {
      variants.add(_SearchVariant(cleanTitle, artist));
    }
    if (cleanArtist != artist) {
      variants.add(_SearchVariant(title, cleanArtist));
    }

    return variants;
  }

  String _cleanTitle(String title) {
    return title
        .replaceAll(
            RegExp(r'[\(\[].*?feat.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[].*?ft\.?.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'[\(\[].*?remaster.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'[\(\[].*?remix.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[].*?mix.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'[\(\[].*?live.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'[\(\[].*?version.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'[\(\[].*?edit.*?[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'-\s*live.*', caseSensitive: false), '')
        .trim();
  }

  String _cleanArtist(String artist) {
    var cleaned = artist.replaceAll(' - Topic', '').trim();
    if (cleaned.contains(',')) {
      cleaned = cleaned.split(',').first.trim();
    }
    cleaned = cleaned.replaceAll(RegExp(r'\s*VEVO', caseSensitive: false), '');
    return cleaned.trim();
  }

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

  String _buildCacheKey(String title, String artist) {
    return '${title.toLowerCase().trim()}_${artist.toLowerCase().trim()}';
  }

  /// Prefetch lyrics for upcoming tracks
  void prefetchLyrics(List<Map<String, String>> tracks) {
    for (final track in tracks) {
      final title = track['title'] ?? '';
      final artist = track['artist'] ?? '';
      final videoId = track['videoId'];

      if (title.isEmpty || artist.isEmpty) continue;
      final cacheKey = _buildCacheKey(title, artist);

      if (_parsedCache.containsKey(cacheKey)) continue;
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

  Future<void> _processPrefetchQueue() async {
    if (_isPrefetching || _prefetchQueue.isEmpty) return;
    _isPrefetching = true;

    while (_prefetchQueue.isNotEmpty) {
      final task = _prefetchQueue.removeAt(0);
      try {
        final diskEntry = await _diskCache.get(task.cacheKey);
        if (diskEntry != null) continue;

        await Future.delayed(const Duration(milliseconds: 100));
        await getParsedLyrics(
          title: task.title,
          artist: task.artist,
          videoId: task.videoId,
        );
      } catch (_) {}
    }
    _isPrefetching = false;
  }

  Future<void> clearCache() async {
    _memCache.clear();
    _parsedCache.clear();
    await _diskCache.clear();
    if (kDebugMode) debugPrint('LyricsService: All caches cleared');
  }

  void dispose() {
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

class _SearchVariant {
  final String title;
  final String artist;

  _SearchVariant(this.title, this.artist);
}
