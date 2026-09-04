import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import 'innertube/innertube_service.dart';

/// Service that resolves looping video canvas streams for tracks
/// (matching Spotify Canvas and Muzo Video discovery).
class CanvasResolutionService {
  CanvasResolutionService._();
  static final CanvasResolutionService instance = CanvasResolutionService._();

  final Map<String, String?> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};
  Directory? _cacheDir;

  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/explore_canvas');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Check if canvas is already resolved in memory.
  String? cachedCanvas(String trackId) => _cache[trackId];

  /// Resolves a video stream URL or local cached MP4 for [track].
  Future<String?> resolveCanvas(Track track) async {
    final trackId = track.id;
    if (trackId.isEmpty) return null;
    final isTesting =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTesting) return null;

    if (_cache.containsKey(trackId)) {
      return _cache[trackId];
    }

    if (_inFlight.containsKey(trackId)) {
      return _inFlight[trackId];
    }

    final future = _resolveUncached(track).whenComplete(() {
      _inFlight.remove(trackId);
    });

    _inFlight[trackId] = future;
    return future;
  }

  Future<String?> _resolveUncached(Track track) async {
    // 1. Direct video URL in previewUrl (local file, MP4, HLS)
    final preview = track.previewUrl.trim();
    if (preview.isNotEmpty) {
      final lower = preview.toLowerCase();
      if (lower.endsWith('.mp4') ||
          lower.endsWith('.m3u8') ||
          lower.endsWith('.webm') ||
          lower.contains('/canvas') ||
          lower.contains('video')) {
        _cache[track.id] = preview;
        return preview;
      }
    }

    // 2. YouTube tracks (11 character IDs)
    if (track.id.length == 11 && !track.id.startsWith('MPREb')) {
      final cached = await _resolveAndCacheVideo(track.id);
      if (cached != null) {
        _cache[track.id] = cached;
        return cached;
      }
    } else if (track.trackName.isNotEmpty) {
      // 3. Non-11-character tracks: quick search fallback via InnerTube
      try {
        final query = '${track.trackName} ${track.artistName}'.trim();
        final searchResults = await InnerTubeService.instance
            .searchSongs(query, limit: 3)
            .timeout(const Duration(seconds: 4));
        if (searchResults.isNotEmpty && searchResults.first.id.isNotEmpty) {
          final cached = await _resolveAndCacheVideo(searchResults.first.id);
          if (cached != null) {
            _cache[track.id] = cached;
            return cached;
          }
        }
      } catch (e) {
        debugPrint('CanvasResolutionService search fallback failed for ${track.trackName}: $e');
      }
    }

    _cache[track.id] = null;
    return null;
  }

  /// Resolves direct stream URL and fetches a clean ~320KB fMP4 loop segment
  /// aligned to MP4 frame boundaries, cached locally to prevent YouTube 403 blocks.
  Future<String?> _resolveAndCacheVideo(String videoId) async {
    try {
      final dir = await _getCacheDir();
      final targetFile = File('${dir.path}/canvas_$videoId.mp4');
      if (await targetFile.exists() && (await targetFile.length()) > 30000) {
        return targetFile.path;
      }

      final directUrl = await InnerTubeService.instance
          .getDirectVideoStreamUrl(videoId, preferredHeight: 480)
          .timeout(const Duration(seconds: 5));
      if (directUrl == null || directUrl.isEmpty) return null;

      // Query ~320KB bounded chunk (approx 8-12 seconds of looping 360p/480p video)
      final rangeUrl = '$directUrl&range=0-320000';
      final ua = InnerTubeService.userAgentForStreamUrl(directUrl) ??
          'com.google.ios.youtube/20.51.39 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)';
      final resp = await http.get(
        Uri.parse(rangeUrl),
        headers: {'User-Agent': ua},
      ).timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200 && resp.statusCode != 206) {
        debugPrint('CanvasResolutionService: chunk fetch status ${resp.statusCode} for $videoId');
        return null;
      }

      final bytes = resp.bodyBytes;
      if (bytes.length < 8) return null;

      // Ensure clean fragmented MP4 boundary: truncate cleanly after the last complete mdat box
      int lastCompleteOffset = 0;
      int offset = 0;
      while (offset + 8 <= bytes.length) {
        final size = (bytes[offset] << 24) |
            (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3];
        if (size <= 0 || offset + size > bytes.length) break;
        final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
        offset += size;
        if (type == 'mdat') {
          lastCompleteOffset = offset;
        }
      }

      final validBytes = lastCompleteOffset > 0
          ? bytes.sublist(0, lastCompleteOffset)
          : bytes;

      await targetFile.writeAsBytes(validBytes);
      return targetFile.path;
    } catch (e) {
      debugPrint('CanvasResolutionService: could not resolve canvas for $videoId: $e');
      return null;
    }
  }
}
