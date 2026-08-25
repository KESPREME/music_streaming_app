import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/services/stream_resolution_service.dart';

void main() {
  group('StreamResolutionService', () {
    test('returns first valid leg result (race winner)', () async {
      final slowLegCalls = <String>[];
      final service = StreamResolutionService(
        legs: [
          (request) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return LegResult(url: 'https://fast.example/${request.videoId}', source: 'a');
          },
          (request) async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return LegResult(url: 'https://slow.example/${request.videoId}', source: 'b');
          },
        ],
        validate: (url, ua) async => true,
      );

      final result = await service.resolve(const ResolveRequest(videoId: 'v1'));
      expect(result, isNotNull);
      expect(result!.url, 'https://fast.example/v1');
      expect(result.source, 'a');
      // Slow leg may still be running, but winner is leg A. Give it a moment
      // and ensure service did not accidentally return the slow leg instead.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(service.cachedUrlFor('v1')!.url, 'https://fast.example/v1');
      slowLegCalls.clear();
    });

    test('falls back to second leg when first returns null', () async {
      final service = StreamResolutionService(
        legs: [
          (request) async => null,
          (request) async =>
              LegResult(url: 'https://b.example/${request.videoId}', source: 'b'),
        ],
        validate: (url, ua) async => true,
      );

      final result = await service.resolve(const ResolveRequest(videoId: 'v2'));
      expect(result, isNotNull);
      expect(result!.url, 'https://b.example/v2');
    });

    test('invalid URL from winner falls through to next leg', () async {
      final service = StreamResolutionService(
        legs: [
          (request) async =>
              LegResult(url: 'https://dead.example/${request.videoId}', source: 'a'),
          (request) async =>
              LegResult(url: 'https://ok.example/${request.videoId}', source: 'b'),
        ],
        validate: (url, ua) async => !url.contains('dead.'),
      );

      final result = await service.resolve(const ResolveRequest(videoId: 'v3'));
      expect(result, isNotNull);
      expect(result!.url, 'https://ok.example/v3');
      expect(result.source, 'b');
    });

    test('coalesces concurrent resolves for same videoId into one leg call',
        () async {
      var legCalls = 0;
      final service = StreamResolutionService(
        legs: [
          (request) async {
            legCalls++;
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return LegResult(url: 'https://x.example/${request.videoId}', source: 'a');
          },
        ],
        validate: (url, ua) async => true,
      );

      final results = await Future.wait([
        service.resolve(const ResolveRequest(videoId: 'same')),
        service.resolve(const ResolveRequest(videoId: 'same')),
        service.resolve(const ResolveRequest(videoId: 'same')),
      ]);

      expect(legCalls, 1);
      expect(results.every((r) => r!.url == 'https://x.example/same'), isTrue);
    });

    test('caches result and skips legs on cache hit', () async {
      var legCalls = 0;
      final service = StreamResolutionService(
        legs: [
          (request) async {
            legCalls++;
            return LegResult(url: 'https://c.example/${request.videoId}', source: 'a');
          },
        ],
        validate: (url, ua) async => true,
      );

      await service.resolve(const ResolveRequest(videoId: 'cached'));
      final second = await service.resolve(const ResolveRequest(videoId: 'cached'));

      expect(legCalls, 1);
      expect(second!.url, 'https://c.example/cached');
    });

    test('cache entry expires after TTL', () async {
      var legCalls = 0;
      final service = StreamResolutionService(
        legs: [
          (request) async {
            legCalls++;
            return LegResult(url: 'https://t.example/${request.videoId}?v=$legCalls',
                source: 'a');
          },
        ],
        validate: (url, ua) async => true,
        cacheTtl: const Duration(milliseconds: 1),
      );

      await service.resolve(const ResolveRequest(videoId: 'ttl'));
      // TTL is 1ms — a real wall-clock sleep guarantees expiry even when the
      // first resolve completed within the same millisecond.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = await service.resolve(const ResolveRequest(videoId: 'ttl'));

      expect(legCalls, 2);
      expect(second!.url, 'https://t.example/ttl?v=2');
    });

    test('demotes leg after consecutive failures for cooldown window',
        () async {
      var aCalls = 0;
      var bCalls = 0;
      final service = StreamResolutionService(
        legs: [
          (request) async {
            aCalls++;
            throw Exception('leg a down');
          },
          (request) async {
            bCalls++;
            return LegResult(url: 'https://b.example/${request.videoId}', source: 'b');
          },
        ],
        validate: (url, ua) async => true,
        failureThreshold: 2,
        cooldown: const Duration(minutes: 10),
      );

      // Two failures demote leg A.
      await service.resolve(const ResolveRequest(videoId: 'd1'));
      await service.resolve(const ResolveRequest(videoId: 'd2'));
      final aCallsAfterDemotion = aCalls;
      expect(aCallsAfterDemotion, 2);

      // Third resolve must skip leg A entirely.
      await service.resolve(const ResolveRequest(videoId: 'd3'));
      expect(aCalls, 2, reason: 'demoted leg must not be called');
      expect(bCalls, 3);
    });

    test('returns null when all legs fail or are demoted', () async {
      final service = StreamResolutionService(
        legs: [
          (request) async => null,
          (request) async => null,
        ],
        validate: (url, ua) async => true,
      );

      final result = await service.resolve(const ResolveRequest(videoId: 'none'));
      expect(result, isNull);
    });

    test('cache is bounded to maxEntries (oldest evicted)', () async {
      final service = StreamResolutionService(
        legs: [
          (request) async =>
              LegResult(url: 'https://e.example/${request.videoId}', source: 'a'),
        ],
        validate: (url, ua) async => true,
        maxCacheEntries: 2,
      );

      await service.resolve(const ResolveRequest(videoId: 'e1'));
      await service.resolve(const ResolveRequest(videoId: 'e2'));
      await service.resolve(const ResolveRequest(videoId: 'e3')); // evicts e1

      expect(service.cachedUrlFor('e1'), isNull);
      expect(service.cachedUrlFor('e2'), isNotNull);
      expect(service.cachedUrlFor('e3'), isNotNull);
    });
  });
}
