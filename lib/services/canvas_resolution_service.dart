import 'dart:async';
import 'dart:convert';
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

  Future<void> _concurrencyLock = Future.value();

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

    final future = _queueResolve(track).whenComplete(() {
      _inFlight.remove(trackId);
    });

    _inFlight[trackId] = future;
    return future;
  }

  Future<String?> _queueResolve(Track track) async {
    final prev = _concurrencyLock;
    final completer = Completer<void>();
    _concurrencyLock = completer.future;
    try {
      await prev.timeout(const Duration(seconds: 4), onTimeout: () {});
      return await _resolveUncached(track);
    } finally {
      completer.complete();
    }
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

    // Check if target file for track.id already exists on disk (instant 0-network hit)
    try {
      final dir = await _getCacheDir();
      final trackFile = File('${dir.path}/canvas_track_${track.id}.mp4');
      if (await trackFile.exists() && (await trackFile.length()) > 50000) {
        _cache[track.id] = trackFile.path;
        return trackFile.path;
      }
    } catch (_) {}

    // 2. Apple Music Motion Artwork (BitChord AppleMusicCanvas parity)
    if (track.trackName.isNotEmpty) {
      try {
        final appleVideo = await _resolveAppleMusic(track);
        if (appleVideo != null && appleVideo.isNotEmpty) {
          final localPath = await _cacheRemoteFile(
            appleVideo,
            'canvas_apple_${track.id}.mp4',
          );
          _cache[track.id] = localPath;
          return localPath;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('CanvasResolutionService: Apple Music check failed: $e');
      }
    }

    // 3. Tidal Video Cover (BitChord TidalCanvas parity: square 1280x1280 looping clips)
    if (track.trackName.isNotEmpty) {
      try {
        final tidalCover = await _resolveTidalVideo(track);
        if (tidalCover != null && tidalCover.isNotEmpty) {
          final localPath = await _cacheRemoteFile(
            tidalCover,
            'canvas_tidal_${track.id}.mp4',
          );
          _cache[track.id] = localPath;
          return localPath;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('CanvasResolutionService: Tidal check failed: $e');
      }
    }

    // 4. Community Canvas Manifest (BitChord CommunityCanvas parity: back-catalogue loops)
    if (track.trackName.isNotEmpty) {
      try {
        final communityVideo = await _resolveCommunityCanvas(track);
        if (communityVideo != null && communityVideo.isNotEmpty) {
          final localPath = await _cacheRemoteFile(
            communityVideo,
            'canvas_comm_${track.id}.mp4',
          );
          _cache[track.id] = localPath;
          return localPath;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('CanvasResolutionService: Community check failed: $e');
      }
    }

    // 5. Official Music Video search via InnerTube
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
          // Score candidates to prioritize official artist/label videos
          final scored = videoResults
              .map((v) => (video: v, score: _scoreCandidate(v, track)))
              .where((e) => e.score >= 50)
              .toList();

          scored.sort((a, b) => b.score.compareTo(a.score));

          // Try up to top 3 highest-confidence official video candidates
          for (final candidate in scored.take(3)) {
            // First: attempt to fetch, sanitize, and cache bounded clip to local disk (0 network on loops)
            final cached = await _resolveAndCacheVideo(candidate.video.id);
            if (cached != null) {
              try {
                final dir = await _getCacheDir();
                final trackFile = File('${dir.path}/canvas_track_${track.id}.mp4');
                if (!await trackFile.exists() && cached != trackFile.path) {
                  await File(cached).copy(trackFile.path);
                }
                final finalPath = trackFile.existsSync() ? trackFile.path : cached;
                _cache[track.id] = finalPath;
                unawaited(_pruneCacheIfNeeded());
                return finalPath;
              } catch (_) {
                _cache[track.id] = cached;
                return cached;
              }
            }

            // Fallback: direct stream URL if chunk caching failed
            final directStream = await InnerTubeService.instance
                .getDirectVideoStreamUrl(candidate.video.id, preferredHeight: 360)
                .timeout(const Duration(seconds: 5));
            if (directStream != null && directStream.isNotEmpty) {
              _cache[track.id] = directStream;
              return directStream;
            }
          }
        }
      } catch (e) {
        debugPrint('CanvasResolutionService: video search failed for ${track.trackName}: $e');
      }
    }

    _cache[track.id] = null;
    return null;
  }

  @visibleForTesting
  static int scoreCandidateForTest(Track candidate, Track target) =>
      _scoreCandidate(candidate, target);

  /// Evaluates video candidates to ensure genuine official artist/label uploads are preferred,
  /// strictly disqualifying any lyric videos, karaoke, remixes, and secondary channels.
  static int _scoreCandidate(Track candidate, Track target) {
    final cTitle = candidate.trackName.toLowerCase();
    final cArtist = candidate.artistName.toLowerCase();
    final tArtist = target.artistName.toLowerCase();

    // 1. ABSOLUTE DISQUALIFICATION: Reject any video with lyric, lyrical, karaoke,
    // subtitles, visualizer, cover, fan made, reaction, slowed, reverb, etc.
    const disqualifiedKeywords = [
      'lyrics',
      'lyric',
      'lyrical',
      'karaoke',
      'with lyrics',
      'subtitles',
      'instrumental',
      'visualizer',
      'fan made',
      'cover',
      'slowed',
      'reverb',
      'reaction',
      'shorts',
      'status',
      'full album',
      'extended',
      '8d audio',
      'bass boosted',
      'audio only',
      'official audio', // Still audio track uploads must not be used as video canvas
    ];

    for (final word in disqualifiedKeywords) {
      if (cTitle.contains(word) || cArtist.contains(word)) {
        return 0; // Outright rejection
      }
    }

    // 2. Strict title matching requirement (BitChord CanvasArtwork parity).
    final normCTitle = _normalizeForMatch(candidate.trackName);
    final normTTitle = _normalizeForMatch(target.trackName);
    if (normCTitle.isEmpty || normTTitle.isEmpty) return 0;
    final titleMatches = normCTitle == normTTitle ||
        normCTitle.contains(normTTitle) ||
        normTTitle.contains(normCTitle);
    if (!titleMatches) return 0;

    // 3. Duration check (if available): Reject extreme outliers
    if (candidate.duration != null && target.duration != null && target.duration!.inSeconds > 30) {
      final diff = (candidate.duration!.inSeconds - target.duration!.inSeconds).abs();
      // Music videos can have intro/outro skits, but should not exceed +100s or be under 25s
      if (diff > 100 || candidate.duration!.inSeconds < 25) {
        return 0;
      }
    }

    int score = 100;

    // 4. Heavy bonus for genuine official music video markers
    if (cTitle.contains('official music video')) {
      score += 120;
    } else if (cTitle.contains('official video')) {
      score += 90;
    } else if (cTitle.contains('music video')) {
      score += 50;
    }

    // 5. Strong bonus for artist match in channel name (primary artist upload)
    final primaryArtist = tArtist.split(',').first.split('&').first.trim();
    if (primaryArtist.isNotEmpty && cArtist.contains(primaryArtist)) {
      score += 80;
    }

    // 6. Bonus for verified artist / VEVO / official topic channels
    if (cArtist.endsWith(' - topic') || cArtist.contains('vevo')) {
      score += 60;
    }

    // 7. Bonus for official label channels
    if (cArtist.contains('records') ||
        cArtist.contains('entertainment') ||
        cArtist.contains('t-series') ||
        cArtist.contains('sony music') ||
        cArtist.contains('zee music') ||
        cArtist.contains('yrf') ||
        cArtist.contains('speed records') ||
        cArtist.contains('tips') ||
        cArtist.contains('warner') ||
        cArtist.contains('universal') ||
        cArtist.contains('interscope') ||
        cArtist.contains('def jam') ||
        cArtist.contains('atlantic') ||
        cArtist.contains('columbia')) {
      score += 45;
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
          .getDirectVideoStreamUrl(videoId, preferredHeight: 360)
          .timeout(const Duration(seconds: 5));
      if (directUrl == null || directUrl.isEmpty) return null;

      // Query ~400KB bounded chunk (approx 12-16 seconds of looping 360p video)
      final rangeUrl = '$directUrl&range=0-400000';
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

  Future<String> _cacheRemoteFile(String url, String targetName) async {
    try {
      final dir = await _getCacheDir();
      final targetFile = File('${dir.path}/$targetName');
      if (await targetFile.exists() && (await targetFile.length()) > 30000) {
        return targetFile.path;
      }
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200 && resp.bodyBytes.length > 30000) {
        final tmp = File('${targetFile.path}.tmp');
        await tmp.writeAsBytes(resp.bodyBytes);
        if (await targetFile.exists()) await targetFile.delete();
        await tmp.rename(targetFile.path);
        unawaited(_pruneCacheIfNeeded());
        return targetFile.path;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CanvasResolutionService: remote cache failed for $url: $e');
    }
    return url;
  }

  DateTime? _lastPruneTime;
  Future<void> _pruneCacheIfNeeded() async {
    final now = DateTime.now();
    if (_lastPruneTime != null &&
        now.difference(_lastPruneTime!) < const Duration(minutes: 5)) {
      return;
    }
    _lastPruneTime = now;
    try {
      final dir = await _getCacheDir();
      if (!await dir.exists()) return;
      final entities = await dir.list().toList();
      final files = entities.whereType<File>().toList();
      int totalBytes = 0;
      final fileStats = <File, DateTime>{};
      for (final f in files) {
        try {
          final stat = await f.stat();
          totalBytes += stat.size;
          fileStats[f] = stat.modified;
        } catch (_) {}
      }
      // 150 MB maximum disk budget
      const maxBudget = 150 * 1024 * 1024;
      if (totalBytes > maxBudget) {
        files.sort((a, b) =>
            (fileStats[a] ?? DateTime(2000)).compareTo(fileStats[b] ?? DateTime(2000)));
        for (final f in files) {
          if (totalBytes <= 100 * 1024 * 1024) break;
          try {
            final len = await f.length();
            await f.delete();
            totalBytes -= len;
          } catch (_) {}
        }
      }
    } catch (_) {}
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

  // ── BitChord Canvas Multi-Source Providers ──────────────────────────

  static String _normalizeForMatch(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> _splitArtists(String raw) {
    final sep = RegExp(
      r'(?:\s*,\s*|\s*&\s*|\s+×\s+|\s+x\s+|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bwith\b)',
      caseSensitive: false,
    );
    return raw
        .split(sep)
        .map((a) => _normalizeForMatch(a))
        .where((a) => a.isNotEmpty)
        .toList();
  }

  static bool _matchesTrack(
    String title,
    List<String> artists,
    String wantTitle,
    String wantArtist,
  ) {
    final normTitle = _normalizeForMatch(title);
    final normWantTitle = _normalizeForMatch(wantTitle);
    if (normTitle.isEmpty || normWantTitle.isEmpty) return false;
    final titleOk = normTitle == normWantTitle ||
        normTitle.contains(normWantTitle) ||
        normWantTitle.contains(normTitle);

    final wantArtists = _splitArtists(wantArtist);
    final artistOk = wantArtists.isEmpty ||
        artists.isEmpty ||
        wantArtists.any((w) => artists.any((a) => a.contains(w) || w.contains(a)));

    return titleOk && artistOk;
  }

  // Tidal Video Covers (Square 1280x1280 looping clips)
  static const String _tidalEmbedToken = 'vNVdglQOjFJJGG2U';

  Future<String?> _resolveTidalVideo(Track track) async {
    final query = '${track.artistName} ${track.trackName}'.trim();
    final url = Uri.parse(
      'https://api.tidal.com/v1/search?query=${Uri.encodeComponent(query)}&limit=10&types=TRACKS&countryCode=US',
    );
    final response = await http.get(url, headers: {
      'X-Tidal-Token': _tidalEmbedToken,
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    }).timeout(const Duration(seconds: 3));

    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tracksObj = json['tracks'] as Map<String, dynamic>?;
    final items = tracksObj?['items'] as List<dynamic>?;
    if (items == null) return null;

    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final tTitle = item['title'] as String? ?? '';
      final artistsList = (item['artists'] as List<dynamic>?)
              ?.map((a) => (a is Map<String, dynamic> ? a['name'] as String? : null) ?? '')
              .where((s) => s.isNotEmpty)
              .toList() ??
          [];

      if (!_matchesTrack(tTitle, artistsList, track.trackName, track.artistName)) {
        continue;
      }

      final albumObj = item['album'] as Map<String, dynamic>?;
      final videoCover = albumObj?['videoCover'] as String?;
      if (videoCover != null && videoCover.isNotEmpty) {
        final videoUrl =
            'https://resources.tidal.com/videos/${videoCover.replaceAll('-', '/')}/1280x1280.mp4';
        return videoUrl;
      }
    }
    return null;
  }

  // Community Canvas Manifest Cache (30 min TTL)
  static List<Map<String, dynamic>>? _communityManifest;
  static DateTime? _communityFetchedAt;

  Future<String?> _resolveCommunityCanvas(Track track) async {
    final now = DateTime.now();
    if (_communityManifest == null ||
        _communityFetchedAt == null ||
        now.difference(_communityFetchedAt!).inMinutes > 30) {
      try {
        final res = await http
            .get(Uri.parse('https://vivimusicanvas.mkmdevilmi.workers.dev/canvas.json'))
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          final items = (decoded is Map ? decoded['items'] : decoded) as List?;
          if (items != null) {
            _communityManifest = items.cast<Map<String, dynamic>>();
            _communityFetchedAt = now;
          }
        }
      } catch (_) {}
    }

    final manifest = _communityManifest;
    if (manifest == null || manifest.isEmpty) return null;

    final wantTitle = _normalizeForMatch(track.trackName);
    final wantArtist = _normalizeForMatch(track.artistName);
    if (wantTitle.isEmpty) return null;

    for (final entry in manifest) {
      final s = _normalizeForMatch(entry['song']?.toString() ?? '');
      final a = _normalizeForMatch(entry['artist']?.toString() ?? '');
      final url = entry['url']?.toString();
      if (url == null || url.isEmpty) continue;

      final titleOk = s.isNotEmpty &&
          (wantTitle == s || wantTitle.contains(s) || s.contains(wantTitle));
      final artistOk = a.isEmpty ||
          wantArtist.isEmpty ||
          wantArtist.contains(a) ||
          a.contains(wantArtist);

      if (titleOk && artistOk) {
        return url;
      }
    }
    return null;
  }

  // ── Apple Music Motion Artwork (BitChord AppleMusicCanvas parity) ──
  static String? _appleToken;
  static DateTime? _appleTokenExpiresAt;
  static DateTime? _appleRetryAfter;
  static final Set<String> _appleRejectedTokens = {};
  static const String _canvasUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  Future<String?> _getAppleToken() async {
    final now = DateTime.now();
    if (_appleToken != null &&
        _appleTokenExpiresAt != null &&
        now.isBefore(_appleTokenExpiresAt!.subtract(const Duration(minutes: 1)))) {
      return _appleToken;
    }
    if (_appleRetryAfter != null && now.isBefore(_appleRetryAfter!)) {
      return null;
    }

    try {
      final browseRes = await http.get(
        Uri.parse('https://music.apple.com/us/browse'),
        headers: {'User-Agent': _canvasUa},
      ).timeout(const Duration(seconds: 4));
      if (browseRes.statusCode != 200) return null;

      final scriptMatches = RegExp(r'/assets/index(?:-legacy)?[~-][A-Za-z0-9_-]+\.js')
          .allMatches(browseRes.body)
          .map((m) => m.group(0)!)
          .toSet();

      for (final path in scriptMatches) {
        final jsRes = await http.get(
          Uri.parse('https://music.apple.com$path'),
          headers: {'User-Agent': _canvasUa},
        ).timeout(const Duration(seconds: 4));
        if (jsRes.statusCode != 200) continue;

        final jwtMatches = RegExp(r'ey[A-Za-z0-9_-]+\.ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')
            .allMatches(jsRes.body)
            .map((m) => m.group(0)!)
            .toSet();

        String? bestToken;
        DateTime? bestExp;

        for (final jwt in jwtMatches) {
          if (_appleRejectedTokens.contains(jwt)) continue;
          try {
            final parts = jwt.split('.');
            if (parts.length != 3) continue;
            final header = utf8.decode(base64Url.decode(base64Url.normalize(parts[0])));
            final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
            final isWebPlay = header.contains('WebPlayKid') || payload.contains('AMPWebPlay');

            final expMatch = RegExp(r'"exp"\s*:\s*(\d+)').firstMatch(payload);
            final expSeconds = expMatch != null ? int.tryParse(expMatch.group(1)!) : null;
            final expDate = expSeconds != null
                ? DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000)
                : now.add(const Duration(hours: 2));

            if (expDate.isAfter(now)) {
              if (isWebPlay) {
                bestToken = jwt;
                bestExp = expDate;
                break;
              } else if (bestToken == null) {
                bestToken = jwt;
                bestExp = expDate;
              }
            }
          } catch (_) {}
        }

        if (bestToken != null) {
          _appleToken = bestToken;
          _appleTokenExpiresAt = bestExp ?? now.add(const Duration(hours: 2));
          return bestToken;
        }
      }
    } catch (_) {
      _appleRetryAfter = now.add(const Duration(minutes: 15));
    }
    return null;
  }

  Future<String?> _resolveAppleMusic(Track track) async {
    final token = await _getAppleToken();
    if (token == null) return null;

    final query = '${track.artistName} ${track.trackName}'.trim();
    final searchUrl = Uri.parse(
      'https://amp-api.music.apple.com/v1/catalog/us/search?term=${Uri.encodeComponent(query)}&types=songs&limit=5&extend=editorialVideo&include=albums',
    );

    final res = await http.get(searchUrl, headers: {
      'Authorization': 'Bearer $token',
      'Origin': 'https://music.apple.com',
      'Referer': 'https://music.apple.com/',
      'User-Agent': _canvasUa,
    }).timeout(const Duration(seconds: 4));

    if (res.statusCode == 401) {
      _appleRejectedTokens.add(token);
      _appleToken = null;
      return null;
    }
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final songs = json['results']?['songs']?['data'] as List<dynamic>?;
    if (songs == null || songs.isEmpty) return null;

    for (final song in songs) {
      if (song is! Map<String, dynamic>) continue;
      final attrs = song['attributes'] as Map<String, dynamic>?;
      if (attrs == null) continue;

      final sName = attrs['name'] as String? ?? '';
      final normSName = _normalizeForMatch(sName);
      final normWantName = _normalizeForMatch(track.trackName);
      if (normSName.isEmpty || normWantName.isEmpty) continue;
      if (normSName != normWantName &&
          !normSName.contains(normWantName) &&
          !normWantName.contains(normSName)) {
        continue;
      }

      // Check inline editorialVideo
      final inlineVideo = attrs['editorialVideo'] as Map<String, dynamic>?;
      if (inlineVideo != null) {
        final url = _extractMotionUrl(inlineVideo);
        if (url != null) return url;
      }

      // Resolve album
      String? albumId;
      final albums = song['relationships']?['albums']?['data'] as List<dynamic>?;
      if (albums != null && albums.isNotEmpty) {
        albumId = (albums.first as Map<String, dynamic>?)?['id']?.toString();
      }
      if (albumId == null && attrs['url'] != null) {
        final match = RegExp(r'/album/(?:[^/]+/)?(\d+)').firstMatch(attrs['url'].toString());
        albumId = match?.group(1);
      }

      if (albumId != null && !albumId.startsWith('pl.')) {
        final albumUrl = Uri.parse(
          'https://amp-api.music.apple.com/v1/catalog/us/albums/$albumId?extend=editorialVideo',
        );
        final aRes = await http.get(albumUrl, headers: {
          'Authorization': 'Bearer $token',
          'Origin': 'https://music.apple.com',
          'Referer': 'https://music.apple.com/',
          'User-Agent': _canvasUa,
        }).timeout(const Duration(seconds: 4));

        if (aRes.statusCode == 200) {
          final aJson = jsonDecode(aRes.body) as Map<String, dynamic>;
          final aData = (aJson['data'] as List<dynamic>?)?.firstOrNull as Map<String, dynamic>?;
          final aAttrs = aData?['attributes'] as Map<String, dynamic>?;
          final aVideo = aAttrs?['editorialVideo'] as Map<String, dynamic>?;
          if (aVideo != null) {
            final url = _extractMotionUrl(aVideo);
            if (url != null) return url;
          }
        }
      }
    }
    return null;
  }

  static String? _extractMotionUrl(Map<String, dynamic> video) {
    String? link(String key) {
      final asset = video[key] as Map<String, dynamic>?;
      if (asset == null) return null;
      return (asset['video'] ?? asset['videoUrl'] ?? asset['hlsUrl'] ?? asset['url'])?.toString();
    }

    final square = link('motionDetailSquare') ?? link('motionSquareVideo1x1');
    final raw = link('motionDetailRaw');
    final tall = link('motionDetailTall') ?? link('motionTallVideo3x4');
    return square ?? raw ?? tall;
  }

  final Map<String, String?> _albumCache = {};

  /// Resolves an animated cover video for an album release (BitChord CanvasRepository.canvasForAlbum parity).
  Future<String?> resolveAlbumCanvas(
    String albumName,
    String artistName,
  ) async {
    final cleanAlbum = albumName.trim();
    final cleanArtist = artistName.trim();
    if (cleanAlbum.isEmpty) return null;

    final key = '$cleanAlbum|$cleanArtist'.toLowerCase();
    if (_albumCache.containsKey(key)) {
      return _albumCache[key];
    }

    final isTesting =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTesting) return null;

    // 1. Tidal Video Cover for Album (Square 1280x1280 looping MP4)
    try {
      final tidal = await _resolveTidalAlbum(cleanAlbum, cleanArtist);
      if (tidal != null && tidal.isNotEmpty) {
        _albumCache[key] = tidal;
        return tidal;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CanvasResolutionService: Tidal album canvas failed: $e');
    }

    // 2. Apple Music Editorial Video for Album (BitChord AppleMusicCanvas.searchAlbum)
    try {
      final apple = await _resolveAppleMusicAlbum(cleanAlbum, cleanArtist);
      if (apple != null && apple.isNotEmpty) {
        _albumCache[key] = apple;
        return apple;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CanvasResolutionService: Apple Music album canvas failed: $e');
    }

    _albumCache[key] = null;
    return null;
  }

  Future<String?> _resolveTidalAlbum(String albumName, String artistName) async {
    final query = cleanSearchQuery('$albumName $artistName');
    final url = Uri.parse(
      'https://api.tidal.com/v1/search?query=${Uri.encodeComponent(query)}&limit=10&types=ALBUMS&countryCode=US',
    );
    final response = await http.get(url, headers: {
      'X-Tidal-Token': _tidalEmbedToken,
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    }).timeout(const Duration(seconds: 4));

    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final albumsObj = json['albums'] as Map<String, dynamic>?;
    final items = albumsObj?['items'] as List<dynamic>?;
    if (items == null || items.isEmpty) return null;

    final normAlbum = _normalizeForMatch(albumName);
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final title = item['title'] as String? ?? '';
      final normTitle = _normalizeForMatch(title);
      if (normTitle.isEmpty) continue;
      if (normTitle != normAlbum &&
          !normTitle.contains(normAlbum) &&
          !normAlbum.contains(normTitle)) {
        continue;
      }

      final videoCover = item['videoCover'] as String?;
      if (videoCover != null && videoCover.isNotEmpty) {
        return 'https://resources.tidal.com/videos/${videoCover.replaceAll('-', '/')}/1280x1280.mp4';
      }
    }
    return null;
  }

  Future<String?> _resolveAppleMusicAlbum(String albumName, String artistName) async {
    final token = await _getAppleToken();
    if (token == null) return null;

    final term = albumName.toLowerCase().contains(artistName.toLowerCase())
        ? albumName
        : '$artistName $albumName';
    final searchUrl = Uri.parse(
      'https://amp-api.music.apple.com/v1/catalog/us/search?term=${Uri.encodeComponent(term.trim())}&types=albums&limit=10&extend=editorialVideo',
    );

    final res = await http.get(searchUrl, headers: {
      'Authorization': 'Bearer $token',
      'Origin': 'https://music.apple.com',
      'Referer': 'https://music.apple.com/',
      'User-Agent': _canvasUa,
    }).timeout(const Duration(seconds: 4));

    if (res.statusCode == 401) {
      _appleRejectedTokens.add(token);
      _appleToken = null;
      return null;
    }
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final albums = json['results']?['albums']?['data'] as List<dynamic>?;
    if (albums == null || albums.isEmpty) return null;

    final normAlbum = _normalizeForMatch(albumName);
    for (final record in albums) {
      if (record is! Map<String, dynamic>) continue;
      final attrs = record['attributes'] as Map<String, dynamic>?;
      if (attrs == null) continue;

      final name = attrs['name'] as String? ?? '';
      final normName = _normalizeForMatch(name);
      if (normName.isEmpty) continue;
      if (normName != normAlbum &&
          !normName.contains(normAlbum) &&
          !normAlbum.contains(normName)) {
        continue;
      }

      final video = attrs['editorialVideo'] as Map<String, dynamic>?;
      if (video != null) {
        final url = _extractMotionUrl(video);
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  static String cleanSearchQuery(String raw) {
    return raw.replaceAll(RegExp(r'[^\w\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
