import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
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

    // 2. Official Music Video search via InnerTube
    // YouTube Music's track.id for songs is an Audio Track (ATV) whose video stream
    // is a static still JPEG of the album art. To get a real looping video canvas
    // (matching Spotify Canvas and Muzo discovery), we query YouTube for the
    // official music video (OMV / UGC) matching the track title and artist.
    // We prioritize official videos by the artist/label and reject secondary lyrical channels.
    if (track.trackName.isNotEmpty) {
      try {
        final query = '${track.trackName} ${track.artistName} Official Video'.trim();
        final videoResults = await InnerTubeService.instance
            .searchVideos(query, limit: 6)
            .timeout(const Duration(seconds: 4));
        if (videoResults.isNotEmpty) {
          // Score candidates to strictly prefer official artist/label videos and reject
          // lyrical, fan-made, or secondary channel uploads.
          final scored = videoResults
              .map((v) => (video: v, score: _scoreCandidate(v, track)))
              .where((e) => e.score >= 80 && e.video.id != track.id)
              .toList();

          scored.sort((a, b) => b.score.compareTo(a.score));

          for (final candidate in scored) {
            final cached = await _resolveAndCacheVideo(candidate.video.id);
            if (cached != null) {
              _cache[track.id] = cached;
              return cached;
            }
          }
        }
      } catch (e) {
        debugPrint('CanvasResolutionService: video search failed for ${track.trackName}: $e');
      }
    }

    // Graceful fallback: If no real official music video exists (or only secondary lyric videos exist),
    // do NOT return track.id (which is a static still picture) or a fan lyric video.
    // Returning null allows ExploreFeedCard to show the centered album artwork, ambient glow, and equalizer.
    _cache[track.id] = null;
    return null;
  }

  /// Evaluates video candidates to ensure genuine official artist/label uploads are preferred,
  /// heavily penalizing fan lyric videos, remixes, and secondary channels.
  static int _scoreCandidate(Track candidate, Track target) {
    final cTitle = candidate.trackName.toLowerCase();
    final cArtist = candidate.artistName.toLowerCase();
    final tArtist = target.artistName.toLowerCase();

    int score = 100;

    // Heavy penalties for non-official / secondary / lyric channels
    const penaltyKeywords = [
      'lyrics',
      'lyric',
      'lyrical',
      'audio',
      'visualizer',
      'karaoke',
      'cover',
      'remix',
      'synthwave',
      'slowed',
      'reverb',
      '8d',
      'bass boosted',
      'status',
      'reaction',
      'shorts',
      'fan made',
      'edit',
    ];

    for (final word in penaltyKeywords) {
      if (cTitle.contains(word)) score -= 150;
      if (cArtist.contains(word)) score -= 200;
    }

    // Major bonus for official music video markers
    if (cTitle.contains('official music video') ||
        cTitle.contains('official video')) {
      score += 80;
    } else if (cTitle.contains('official') ||
        cTitle.contains('music video') ||
        cTitle.contains('video')) {
      score += 40;
    }

    // Bonus for artist match in channel/byline name
    final primaryArtist = tArtist.split(',').first.split('&').first.trim();
    if (primaryArtist.isNotEmpty && cArtist.contains(primaryArtist)) {
      score += 60;
    }

    // Bonus for official label / vevo channels
    if (cArtist.contains('vevo') ||
        cArtist.contains('records') ||
        cArtist.contains('entertainment') ||
        cArtist.contains('t-series') ||
        cArtist.contains('sony music') ||
        cArtist.contains('zee music') ||
        cArtist.contains('yrf') ||
        cArtist.contains('speed records') ||
        cArtist.contains('tips') ||
        cArtist.contains('warner') ||
        cArtist.contains('universal')) {
      score += 40;
    }

    return score;
  }

  /// Resolves direct stream URL and fetches a clean ~500KB fMP4 loop segment
  /// aligned to MP4 frame boundaries with synchronized durations for seamless looping.
  Future<String?> _resolveAndCacheVideo(String videoId) async {
    try {
      final dir = await _getCacheDir();
      final targetFile = File('${dir.path}/canvas_v2_$videoId.mp4');
      if (await targetFile.exists() && (await targetFile.length()) > 50000) {
        return targetFile.path;
      }

      final directUrl = await InnerTubeService.instance
          .getDirectVideoStreamUrl(videoId, preferredHeight: 480)
          .timeout(const Duration(seconds: 5));
      if (directUrl == null || directUrl.isEmpty) return null;

      // Query ~500KB bounded chunk (approx 12-16 seconds of looping 360p/480p video)
      final rangeUrl = '$directUrl&range=0-500000';
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
      if (bytes.length < 32) return null;

      final sanitizedBytes = _sanitizeMp4Chunk(bytes);
      if (sanitizedBytes.length < 50000) {
        debugPrint('CanvasResolutionService: sanitized chunk too small (${sanitizedBytes.length} bytes) for $videoId');
        return null;
      }

      final tmpFile = File('${targetFile.path}.tmp');
      await tmpFile.writeAsBytes(sanitizedBytes);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tmpFile.rename(targetFile.path);
      return targetFile.path;
    } catch (e) {
      debugPrint('CanvasResolutionService: could not resolve canvas for $videoId: $e');
      return null;
    }
  }

  /// Sanitizes an fMP4 byte stream:
  /// 1. Locates complete movie fragments (`moof` + `mdat`) and discards any partial trailing box.
  /// 2. Omits the global `sidx` box (which indexes the full multi-minute video), preventing ExoPlayer
  ///    from reporting unexpected EOF / buffering stalls when reaching the end of the downloaded chunk.
  /// 3. Patches `mvhd`, `tkhd`, and `mdhd` inside `moov` to the exact duration of the downloaded fragments
  ///    so the media framework recognizes the end of file as `STATE_ENDED` and natively loops seamlessly.
  static Uint8List _sanitizeMp4Chunk(Uint8List bytes) {
    if (bytes.length < 32) return bytes;
    final bd = ByteData.sublistView(bytes);
    int offset = 0;
    int lastCompleteOffset = 0;
    int completeFragments = 0;
    int sidxOffset = -1;
    int sidxSize = 0;

    // First pass: locate atoms and find last complete mdat
    while (offset + 8 <= bytes.length) {
      final size = bd.getUint32(offset);
      if (size <= 0 || offset + size > bytes.length) break;
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      if (type == 'sidx' && sidxOffset < 0) {
        sidxOffset = offset;
        sidxSize = size;
      } else if (type == 'mdat') {
        completeFragments++;
        lastCompleteOffset = offset + size;
      }
      offset += size;
    }

    if (lastCompleteOffset <= 0 || completeFragments == 0) {
      return bytes;
    }

    // Calculate actual duration of completed fragments from sidx if present
    int actualDuration = 0;
    if (sidxOffset >= 0 && sidxSize >= 32) {
      final sidxBd = ByteData.sublistView(bytes, sidxOffset, sidxOffset + sidxSize);
      final ver = sidxBd.getUint8(8);
      int curr = 16;
      final timescale = sidxBd.getUint32(curr);
      curr += 4;
      if (ver == 0) {
        curr += 8; // earliest_presentation_time (4) + first_offset (4)
      } else {
        curr += 16; // earliest_presentation_time (8) + first_offset (8)
      }
      curr += 2; // reserved
      final refCount = sidxBd.getUint16(curr);
      curr += 2;

      int durSum = 0;
      final count = completeFragments < refCount ? completeFragments : refCount;
      for (int i = 0; i < count; i++) {
        if (curr + 12 > sidxSize) break;
        final subDur = sidxBd.getUint32(curr + 4);
        durSum += subDur;
        curr += 12;
      }
      actualDuration = durSum;
      if (kDebugMode) {
        final sec = timescale > 0 ? (actualDuration / timescale).toStringAsFixed(2) : '0';
        debugPrint('CanvasResolutionService: $completeFragments fragments, duration $sec sec');
      }
    }

    // Build sanitized bytes without sidx (treated as standalone complete stream)
    final builder = BytesBuilder(copy: false);

    offset = 0;
    while (offset + 8 <= lastCompleteOffset) {
      final size = bd.getUint32(offset);
      if (size <= 0 || offset + size > lastCompleteOffset) break;
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));

      if (type == 'sidx') {
        // Omit sidx so ExoPlayer treats this as a complete standalone stream
        offset += size;
        continue;
      }

      if (type == 'moov' && actualDuration > 0) {
        // Patch duration in mvhd, tkhd, mdhd inside moov
        final moovBytes = Uint8List.fromList(bytes.sublist(offset, offset + size));
        _patchMoovDurations(moovBytes, actualDuration);
        builder.add(moovBytes);
        offset += size;
        continue;
      }

      builder.add(bytes.sublist(offset, offset + size));
      offset += size;
    }

    return builder.takeBytes();
  }

  static void _patchMoovDurations(Uint8List moovBytes, int duration) {
    final bd = ByteData.sublistView(moovBytes);

    void walk(int start, int end) {
      int off = start;
      while (off + 8 <= end) {
        final sz = bd.getUint32(off);
        if (sz <= 0 || off + sz > end) break;
        final typ = String.fromCharCodes(moovBytes.sublist(off + 4, off + 8));

        if (typ == 'mvhd') {
          final ver = moovBytes[off + 8];
          if (ver == 0 && off + 8 + 20 <= end) {
            bd.setUint32(off + 8 + 16, duration);
          } else if (ver == 1 && off + 8 + 32 <= end) {
            bd.setUint64(off + 8 + 24, duration);
          }
        } else if (typ == 'tkhd') {
          final ver = moovBytes[off + 8];
          if (ver == 0 && off + 8 + 24 <= end) {
            bd.setUint32(off + 8 + 20, duration);
          } else if (ver == 1 && off + 8 + 36 <= end) {
            bd.setUint64(off + 8 + 28, duration);
          }
        } else if (typ == 'mdhd') {
          final ver = moovBytes[off + 8];
          if (ver == 0 && off + 8 + 20 <= end) {
            bd.setUint32(off + 8 + 16, duration);
          } else if (ver == 1 && off + 8 + 32 <= end) {
            bd.setUint64(off + 8 + 24, duration);
          }
        } else if (typ == 'moov' || typ == 'trak' || typ == 'mdia' || typ == 'minf') {
          walk(off + 8, off + sz);
        }

        off += sz;
      }
    }

    walk(0, moovBytes.length);
  }
}
