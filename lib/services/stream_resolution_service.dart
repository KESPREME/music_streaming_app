import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'innertube/innertube_service.dart';
import 'saavn_service.dart';

/// A resolved, playable stream URL plus metadata needed to play it.
@immutable
class ResolvedStream {
  final String url;
  final String source; // 'innertube' | 'saavn' | 'youtube_explode'
  final String? userAgent;

  const ResolvedStream({
    required this.url,
    required this.source,
    this.userAgent,
  });
}

/// Result produced by a single resolution leg.
@immutable
class LegResult {
  final String url;
  final String source;
  final String? userAgent;

  const LegResult({required this.url, required this.source, this.userAgent});
}

/// Everything a resolution leg may need.
@immutable
class ResolveRequest {
  final String videoId;
  final String title;
  final String artist;
  final int? durationMs;

  const ResolveRequest({
    required this.videoId,
    this.title = '',
    this.artist = '',
    this.durationMs,
  });
}

typedef ResolutionLeg = Future<LegResult?> Function(ResolveRequest request);

typedef UrlValidator = Future<bool> Function(String url, String? userAgent);

/// Orchestrates parallel racing of stream-resolution legs (InnerTube direct,
/// Saavn 320kbps, …), validates winners, coalesces duplicate requests,
/// caches results, and self-heals by demoting failing legs.
///
/// Design notes:
/// - ANDROID_VR stream URLs are short-lived; cache TTL is deliberately
///   conservative (30 min) and callers re-resolve once on 403.
/// - Concurrent resolves for the same videoId share one in-flight future
///   (request coalescing) to prevent duplicate network stampedes.
/// - A leg with [failureThreshold] consecutive failures is skipped for
///   [cooldown], then given one clean retry window — a dead upstream never
///   blocks the race, and a recovered upstream rejoins automatically.
class StreamResolutionService {
  StreamResolutionService({
    List<ResolutionLeg>? legs,
    UrlValidator? validate,
    this.cacheTtl = const Duration(minutes: 30),
    this.maxCacheEntries = 200,
    this.failureThreshold = 3,
    this.cooldown = const Duration(minutes: 10),
  })  : _legs = legs ?? _defaultLegs(),
        _validate = validate ?? _defaultValidator;

  final List<ResolutionLeg> _legs;
  final UrlValidator _validate;
  final Duration cacheTtl;
  final int maxCacheEntries;
  final int failureThreshold;
  final Duration cooldown;

  static final StreamResolutionService instance = StreamResolutionService();

  // --- Cache (insertion-ordered for LRU-style eviction) ---
  final LinkedHashMap<String, (ResolvedStream, DateTime)> _cache =
      LinkedHashMap();

  // --- In-flight coalescing ---
  final Map<String, Future<ResolvedStream?>> _inFlight = {};

  // --- Health tracking (parallel to _legs) ---
  final List<int> _failures = [];
  final List<DateTime?> _demotedAt = [];

  /// Default legs: direct InnerTube ANDROID_VR (~200ms, no cipher, no PO
  /// token) raced against Saavn 320kbps AAC (client-side DES decrypt —
  /// no third-party proxy instance involved).
  static List<ResolutionLeg> _defaultLegs() {
    final saavn = SaavnService();
    final innertube = InnerTubeService.instance;
    return [
      (request) async {
        final url = await innertube.getDirectAudioStreamUrl(request.videoId);
        if (url == null) return null;
        // The URL's `c=` param names the client that signed it — googlevideo
        // rejects full playback when the UA doesn't match (Range probes pass
        // regardless, which is why validation alone can't catch this).
        return LegResult(
          url: url,
          source: 'innertube',
          userAgent: InnerTubeService.userAgentForStreamUrl(url),
        );
      },
      (request) async {
        final url = await saavn.resolveStreamUrl(
          title: request.title,
          artist: request.artist,
          targetDurationMs: request.durationMs,
        );
        if (url == null) return null;
        return LegResult(url: url, source: 'saavn');
      },
    ];
  }

  /// Resolve a playable URL for [request.videoId].
  ///
  /// [ResolveRequest.title]/[artist]/[durationMs] feed the Saavn matcher
  /// (duration guard prevents wrong-song matches).
  Future<ResolvedStream?> resolve(ResolveRequest request) {
    final cached = cachedUrlFor(request.videoId);
    if (cached != null) return Future.value(cached);

    final inFlight = _inFlight[request.videoId];
    if (inFlight != null) return inFlight;

    final future = _resolveUncached(request)
        // NOTE: block body on purpose — an expression body would return the
        // removed in-flight future and whenComplete would await itself.
        .whenComplete(() {
          _inFlight.remove(request.videoId);
        });
    _inFlight[request.videoId] = future;
    return future;
  }

  Future<ResolvedStream?> _resolveUncached(ResolveRequest request) async {
    final healthy = <int, ResolutionLeg>{};
    for (var i = 0; i < _legs.length; i++) {
      if (!_isDemoted(i)) healthy[i] = _legs[i];
    }
    if (healthy.isEmpty) return null;

    ResolvedStream? winner;
    var outstanding = healthy.length;
    final raceDone = Completer<void>();

    Future<void> settleLeg(int index, Future<LegResult?> fut) async {
      LegResult? legResult;
      try {
        legResult = await fut;
      } catch (e) {
        debugPrint(
            'StreamResolution: leg $index threw: $e');
        legResult = null;
      }
      try {
        if (winner == null) {
          if (legResult == null) {
            debugPrint(
                'StreamResolution: leg $index returned null');
            _recordFailure(index);
          } else {
            final valid =
                await _validate(legResult.url, legResult.userAgent);
            if (winner == null) {
              if (valid) {
                debugPrint(
                    'StreamResolution: leg $index WON');
                _recordSuccess(index);
                winner = ResolvedStream(
                  url: legResult.url,
                  source: legResult.source,
                  userAgent: legResult.userAgent,
                );
              } else {
                debugPrint(
                    'StreamResolution: leg $index failed validation');
                _recordFailure(index);
              }
            }
          }
        }
      } finally {
        outstanding--;
        if ((winner != null || outstanding == 0) && !raceDone.isCompleted) {
          raceDone.complete();
        }
      }
    }

    healthy.forEach((index, leg) {
      // Fire without awaiting — errors handled inside settleLeg.
      leg(request).then(
        (result) => settleLeg(index, Future.value(result)),
        onError: (Object e) => settleLeg(index, Future.error(e)),
      );
    });

    await raceDone.future;

    if (winner != null) {
      _cache[request.videoId] = (winner!, DateTime.now());
      _evictIfNeeded();
    }
    return winner;
  }

  bool _isDemoted(int index) {
    if (index >= _failures.length) return false;
    if (_failures[index] < failureThreshold) return false;
    final at = _demotedAt[index];
    if (at == null) return false;
    if (DateTime.now().difference(at) >= cooldown) {
      // Cooldown elapsed — give the leg a clean retry window.
      _failures[index] = 0;
      _demotedAt[index] = null;
      return false;
    }
    return true;
  }

  void _recordSuccess(int index) {
    _ensureHealthLists();
    _failures[index] = 0;
    _demotedAt[index] = null;
  }

  void _recordFailure(int index) {
    _ensureHealthLists();
    _failures[index]++;
    if (_failures[index] >= failureThreshold) {
      _demotedAt[index] = DateTime.now();
    }
  }

  void _ensureHealthLists() {
    while (_failures.length < _legs.length) {
      _failures.add(0);
      _demotedAt.add(null);
    }
  }

  ResolvedStream? cachedUrlFor(String videoId) {
    final entry = _cache[videoId];
    if (entry == null) return null;
    final (stream, timestamp) = entry;
    if (DateTime.now().difference(timestamp) > cacheTtl) {
      _cache.remove(videoId);
      return null;
    }
    return stream;
  }

  /// Drop a bad cached URL (e.g. after a 403 mid-playback).
  void invalidate(String videoId) => _cache.remove(videoId);

  void _evictIfNeeded() {
    while (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  void clearCache() => _cache.clear();

  /// Range-GET validation (2 bytes) — HEAD is rejected by some CDNs.
  static Future<bool> _defaultValidator(String url, String? userAgent) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2500);
      final request = await client
          .openUrl('GET', Uri.parse(url))
          .timeout(const Duration(milliseconds: 2500));
      request.headers.set('Range', 'bytes=0-1');
      if (userAgent != null) request.headers.set('User-Agent', userAgent);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == 200 || response.statusCode == 206;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }
}