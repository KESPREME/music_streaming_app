import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/track.dart';

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

    // 2. YouTube tracks (11 character IDs): fetch lightweight 360p video stream for looping
    if (track.id.length == 11 && !track.id.startsWith('MPREb')) {
      try {
        final yt = YoutubeExplode();
        final manifest = await yt.videos.streamsClient
            .getManifest(track.id)
            .timeout(const Duration(seconds: 4));
        yt.close();

        // Muxed 360p / 480p format loads instantly and loops smoothly without buffering
        final muxed = manifest.muxed.sortByVideoQuality();
        if (muxed.isNotEmpty) {
          final chosen = muxed.firstWhere(
            (s) =>
                s.qualityLabel == '360p' ||
                s.qualityLabel == '480p' ||
                s.qualityLabel == '240p',
            orElse: () => muxed.first,
          );
          final videoUrl = chosen.url.toString();
          _cache[track.id] = videoUrl;
          return videoUrl;
        }
      } catch (e) {
        debugPrint('CanvasResolutionService: could not resolve canvas for ${track.id}: $e');
      }
    }

    _cache[track.id] = null;
    return null;
  }
}
