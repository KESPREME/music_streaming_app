import 'dart:async';
import 'package:flutter/widgets.dart';

import '../models/track.dart';
import 'innertube/innertube_service.dart';

/// Service that resolves looping video canvas streams for tracks
/// (matching Spotify Canvas and Muzo Video discovery).
class CanvasResolutionService {
  CanvasResolutionService._();
  static final CanvasResolutionService instance = CanvasResolutionService._();

  final Map<String, String?> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};

  /// Check if canvas is already resolved in memory.
  String? cachedCanvas(String trackId) => _cache[trackId];

  /// Resolves a video stream URL for [track].
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

    // 2. YouTube tracks (11 character IDs): fetch lightweight MP4 video stream via InnerTube iOS client
    if (track.id.length == 11 && !track.id.startsWith('MPREb')) {
      try {
        final videoUrl = await InnerTubeService.instance
            .getDirectVideoStreamUrl(track.id, preferredHeight: 480)
            .timeout(const Duration(seconds: 5));
        if (videoUrl != null && videoUrl.isNotEmpty) {
          _cache[track.id] = videoUrl;
          return videoUrl;
        }
      } catch (e) {
        debugPrint('CanvasResolutionService: could not resolve canvas for ${track.id}: $e');
      }
    } else if (track.trackName.isNotEmpty) {
      // 3. Non-11-character tracks: quick search fallback via InnerTube
      try {
        final query = '${track.trackName} ${track.artistName}'.trim();
        final searchResults = await InnerTubeService.instance
            .searchSongs(query, limit: 3)
            .timeout(const Duration(seconds: 4));
        if (searchResults.isNotEmpty && searchResults.first.id.isNotEmpty) {
          final videoUrl = await InnerTubeService.instance
              .getDirectVideoStreamUrl(searchResults.first.id, preferredHeight: 480)
              .timeout(const Duration(seconds: 5));
          if (videoUrl != null && videoUrl.isNotEmpty) {
            _cache[track.id] = videoUrl;
            return videoUrl;
          }
        }
      } catch (e) {
        debugPrint('CanvasResolutionService search fallback failed for ${track.trackName}: $e');
      }
    }

    _cache[track.id] = null;
    return null;
  }
}
