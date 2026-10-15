import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/transition/analysis_service.dart';
import 'package:music_streaming_app/services/transition/audio_analyzer.dart';
import 'package:music_streaming_app/services/transition/track_analysis.dart';

/// THE ANALYSIS JOB THIS FILE PINS.
///
/// The decoder, the download, the isolate and the database are replaced with
/// fakes, so what is under test is the policy: what is analysed, when, how
/// often, and what is remembered.

class _Rig {
  _Rig({
    this.enabled = true,
    bool network = true,
    bool supported = true,
    this.source,
    this.pcm,
    AnalysisStore? store,
  })  : networkUp = network,
        store = store ?? MemoryAnalysisStore() {
    service = AnalysisService(
      locate: (id) async {
        located.add(id);
        return source ?? const AnalysisSource.file('/songs/a.m4a');
      },
      isEnabled: () => enabled,
      allowCellular: () => cellular,
      onResult: () => results++,
      store: this.store,
      supported: supported,
      now: () => clock,
      decode: (path, rate) async {
        decoded.add(path);
        return DecodedAudio(pcm ?? Int16List(rate * 3));
      },
      fetch: (s) async {
        fetched.add(s.url!);
        return '/tmp/fetched.audio';
      },
      run: (input) async => TrackAnalysis(
        trackId: input.trackId,
        durationMs: input.durationMs,
        bpm: 120,
        beatConfidence: 0.9,
      ),
      network: ({required bool allowCellular}) async {
        networkAsked++;
        return networkUp || (allowCellular && cellularUp);
      },
    );
  }

  late final AnalysisService service;
  final AnalysisStore store;
  AnalysisSource? source;
  final Int16List? pcm;
  bool enabled;
  bool cellular = false;
  bool networkUp;
  bool cellularUp = true;
  int results = 0;
  int networkAsked = 0;
  DateTime clock = DateTime(2026, 1, 1);
  final List<String> located = <String>[];
  final List<String> decoded = <String>[];
  final List<String> fetched = <String>[];

  /// Lets the one-at-a-time worker run to the end of its queue.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  test('analyses a local file once and answers from memory after', () async {
    final r = _Rig();
    r.service.request('a', durationMs: 200000);
    await r.settle();

    expect(r.decoded, ['/songs/a.m4a']);
    expect(r.results, 1);
    final got = r.service.lookup('a', 200000);
    expect(got, isNotNull);
    expect(got!.bpm, 120);

    r.service.request('a', durationMs: 200000);
    await r.settle();
    expect(r.decoded, hasLength(1), reason: 'known songs are not read again');
  });

  test('uses the song duration it was given, else the decoded length', () async {
    final r = _Rig();
    r.service.request('a', durationMs: 123456);
    r.service.request('b');
    await r.settle();
    expect(r.service.lookup('a', 123456)!.durationMs, 123456);
    // 3 s of silence at the analysis rate.
    expect(r.service.lookup('b', 0)!.durationMs, 3000);
  });

  test('a result for another cut of the song is not used', () async {
    final r = _Rig();
    r.service.request('a', durationMs: 200000);
    await r.settle();
    expect(r.service.lookup('a', 200800), isNotNull, reason: 'within 1.5 s');
    expect(r.service.lookup('a', 231000), isNull, reason: 'a different cut');
  });

  test('a saved result is loaded without touching the audio', () async {
    final store = MemoryAnalysisStore();
    await store.write(const TrackAnalysis(
        trackId: 'a', durationMs: 200000, bpm: 98, beatConfidence: 0.8));
    final r = _Rig(store: store);
    r.service.request('a', durationMs: 200000);
    await r.settle();

    expect(r.decoded, isEmpty);
    expect(r.located, isEmpty);
    expect(r.service.lookup('a', 200000)!.bpm, 98);
    expect(r.results, 1);
  });

  test('a saved result from an older analyser is redone', () async {
    final store = MemoryAnalysisStore();
    await store.write(const TrackAnalysis(
        trackId: 'a', durationMs: 200000, bpm: 98, version: 0));
    final r = _Rig(store: store);
    r.service.request('a', durationMs: 200000);
    await r.settle();
    expect(r.decoded, hasLength(1));
    expect(r.service.lookup('a', 200000)!.bpm, 120);
  });

  test('results are written for the next session', () async {
    final r = _Rig();
    r.service.request('a', durationMs: 200000);
    await r.settle();
    expect((await r.store.read('a'))?.bpm, 120);
  });

  test('does nothing unless AutoMix is on', () async {
    final r = _Rig(enabled: false);
    r.service.request('a', durationMs: 200000);
    await r.settle();
    expect(r.located, isEmpty);
    expect(r.decoded, isEmpty);
  });

  test('does nothing on a platform without a decoder', () async {
    final r = _Rig(supported: false);
    r.service.request('a', durationMs: 200000);
    await r.settle();
    expect(r.located, isEmpty);
  });

  test('a request that waited while AutoMix was switched off is dropped', () async {
    final r = _Rig();
    r.service.request('a', durationMs: 1);
    r.enabled = false; // before the worker gets to it
    await r.settle();
    expect(r.decoded, isEmpty);
  });

  test('requests are deduplicated while one is pending', () async {
    final r = _Rig();
    r.service.request('a', durationMs: 1);
    r.service.request('a', durationMs: 1);
    r.service.request('a', durationMs: 1);
    await r.settle();
    expect(r.decoded, hasLength(1));
  });

  test('songs are analysed one at a time, in the order asked', () async {
    final gate = Completer<DecodedAudio?>();
    var inFlight = 0;
    var peak = 0;
    final order = <String>[];
    final service = AnalysisService(
      locate: (id) async {
        order.add(id);
        return const AnalysisSource.file('/x');
      },
      isEnabled: () => true,
      allowCellular: () => false,
      onResult: () {},
      store: MemoryAnalysisStore(),
      supported: true,
      decode: (path, rate) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        if (!gate.isCompleted) await gate.future;
        inFlight--;
        return DecodedAudio(Int16List(rate * 3));
      },
      run: (input) async =>
          TrackAnalysis(trackId: input.trackId, durationMs: input.durationMs),
    );
    service.request('a');
    service.request('b');
    service.request('c');
    await Future<void>.delayed(Duration.zero);
    gate.complete(null);
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(order, ['a', 'b', 'c']);
    expect(peak, 1);
  });

  group('the network', () {
    const stream = AnalysisSource.network('https://x/y',
        headers: {'User-Agent': 'ua'});

    test('a stream is fetched, decoded and analysed on Wi-Fi', () async {
      final r = _Rig(source: stream, pcm: Int16List(11025 * 3));
      r.service.request('a', durationMs: 5000);
      await r.settle();
      expect(r.fetched, ['https://x/y']);
      expect(r.decoded, ['/tmp/fetched.audio']);
      expect(r.service.lookup('a', 5000), isNotNull);
    });

    test('mobile data waits for permission', () async {
      final r = _Rig(source: stream, network: false);
      r.service.request('a', durationMs: 5000);
      await r.settle();
      expect(r.fetched, isEmpty);
      expect(r.networkAsked, 1);
      expect(r.service.lookup('a', 5000), isNull);

      // Not a failure: it may be asked again at once, and works once allowed.
      r.cellular = true;
      r.service.request('a', durationMs: 5000);
      await r.settle();
      expect(r.fetched, hasLength(1));
    });

    test('a temporary download is deleted once it has been analysed', () async {
      final dir = Directory.systemTemp.createTempSync('analysis_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final temp = File('${dir.path}/automix_1.audio')..writeAsBytesSync([1, 2, 3]);
      final service = AnalysisService(
        locate: (id) async => const AnalysisSource.network('https://x/y'),
        isEnabled: () => true,
        allowCellular: () => false,
        onResult: () {},
        store: MemoryAnalysisStore(),
        supported: true,
        network: ({required bool allowCellular}) async => true,
        fetch: (s) async => temp.path,
        decode: (path, rate) async => DecodedAudio(Int16List(rate * 3)),
        run: (input) async =>
            TrackAnalysis(trackId: input.trackId, durationMs: input.durationMs),
      );
      service.request('a');
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(service.lookup('a', 0), isNotNull);
      expect(temp.existsSync(), isFalse);
    });

    test('a download that landed in the player\'s cache is kept for the player',
        () async {
      final dir = Directory.systemTemp.createTempSync('analysis_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final shared = File('${dir.path}/audio_a.m4a')..writeAsBytesSync([1, 2, 3]);
      final service = AnalysisService(
        locate: (id) async =>
            AnalysisSource.network('https://x/y', cacheTo: shared.path),
        isEnabled: () => true,
        allowCellular: () => false,
        onResult: () {},
        store: MemoryAnalysisStore(),
        supported: true,
        network: ({required bool allowCellular}) async => true,
        fetch: (s) async => s.cacheTo,
        decode: (path, rate) async {
          expect(path, shared.path);
          return DecodedAudio(Int16List(rate * 3));
        },
        run: (input) async =>
            TrackAnalysis(trackId: input.trackId, durationMs: input.durationMs),
      );
      service.request('a');
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(service.lookup('a', 0), isNotNull);
      expect(shared.existsSync(), isTrue, reason: 'the player will play from it');
    });

    test('a download that could not be shared is still only a temporary one',
        () async {
      final dir = Directory.systemTemp.createTempSync('analysis_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final shared = File('${dir.path}/audio_a.m4a');
      final temp = File('${dir.path}/audio_a.m4a.analysis')..writeAsBytesSync([9]);
      final service = AnalysisService(
        locate: (id) async =>
            AnalysisSource.network('https://x/y', cacheTo: shared.path),
        isEnabled: () => true,
        allowCellular: () => false,
        onResult: () {},
        store: MemoryAnalysisStore(),
        supported: true,
        network: ({required bool allowCellular}) async => true,
        fetch: (s) async => temp.path, // not provably whole: not promoted
        decode: (path, rate) async => DecodedAudio(Int16List(rate * 3)),
        run: (input) async =>
            TrackAnalysis(trackId: input.trackId, durationMs: input.durationMs),
      );
      service.request('a');
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(temp.existsSync(), isFalse);
      expect(shared.existsSync(), isFalse,
          reason: 'a truncated file must never wear the cache\'s final name');
    });
    test('a local file never asks the network', () async {
      final r = _Rig(network: false);
      r.service.request('a', durationMs: 5000);
      await r.settle();
      expect(r.networkAsked, 0);
      expect(r.decoded, hasLength(1));
    });
  });

  group('failures', () {
    test('an undecodable file is not retried for ten minutes', () async {
      var decodes = 0;
      var clock = DateTime(2026, 1, 1);
      final service = AnalysisService(
        locate: (id) async => const AnalysisSource.file('/bad'),
        isEnabled: () => true,
        allowCellular: () => false,
        onResult: () {},
        store: MemoryAnalysisStore(),
        supported: true,
        now: () => clock,
        decode: (path, rate) async {
          decodes++;
          return null;
        },
        run: (input) async =>
            TrackAnalysis(trackId: input.trackId, durationMs: input.durationMs),
      );
      service.request('a');
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(decodes, 1);

      service.request('a');
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(decodes, 1, reason: 'still cooling down');

      clock = clock.add(const Duration(minutes: 11));
      service.request('a');
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(decodes, 2, reason: 'and tried again afterwards');
    });

    test('a song the app cannot locate right now is not held against it',
        () async {
      var found = false;
      final service = AnalysisService(
        locate: (id) async => found ? const AnalysisSource.file('/x') : null,
        isEnabled: () => true,
        allowCellular: () => false,
        onResult: () {},
        store: MemoryAnalysisStore(),
        supported: true,
        decode: (path, rate) async => DecodedAudio(Int16List(rate * 3)),
        run: (input) async =>
            TrackAnalysis(trackId: input.trackId, durationMs: input.durationMs),
      );
      service.request('a');
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(service.lookup('a', 0), isNull);

      found = true;
      service.request('a');
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(service.lookup('a', 0), isNotNull);
    });

    test('an exception in any stage is contained', () async {
      final service = AnalysisService(
        locate: (id) async => const AnalysisSource.file('/x'),
        isEnabled: () => true,
        allowCellular: () => false,
        onResult: () {},
        store: MemoryAnalysisStore(),
        supported: true,
        decode: (path, rate) async => throw StateError('codec exploded'),
        run: (input) async =>
            TrackAnalysis(trackId: input.trackId, durationMs: input.durationMs),
      );
      service.request('a');
      service.request('b');
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      // Both were attempted (the worker survived the first), neither is known.
      expect(service.lookup('a', 0), isNull);
      expect(service.lookup('b', 0), isNull);
    });
  });

  test('memory keeps the most recent songs only', () async {
    final service = AnalysisService(
      locate: (id) async => const AnalysisSource.file('/x'),
      isEnabled: () => true,
      allowCellular: () => false,
      onResult: () {},
      store: MemoryAnalysisStore(),
      supported: true,
      maxKnown: 3,
      decode: (path, rate) async => DecodedAudio(Int16List(rate * 3)),
      run: (input) async =>
          TrackAnalysis(trackId: input.trackId, durationMs: input.durationMs),
    );
    for (final id in ['a', 'b', 'c', 'd']) {
      service.request(id);
    }
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(service.lookup('a', 0), isNull, reason: 'the oldest left');
    expect(service.lookup('d', 0), isNotNull);
  });

  test('a disposed service ignores everything', () async {
    final r = _Rig();
    r.service.dispose();
    r.service.request('a');
    await r.settle();
    expect(r.decoded, isEmpty);
  });

  test('through the real analyser entry point, the result carries the duration',
      () async {
    // End to end through analyzeInput, minus the platform.
    final n = 30 * AudioAnalyzer.sampleRate;
    final pcm = Int16List(n);
    final period = (AudioAnalyzer.sampleRate * 60 / 120).round();
    for (var t = 0; t < n; t += period) {
      for (var j = 0; j < 400 && t + j < n; j++) {
        pcm[t + j] = ((j.isEven ? 1 : -1) * 20000 * (1 - j / 400)).round();
      }
    }
    final service = AnalysisService(
      locate: (id) async => const AnalysisSource.file('/x'),
      isEnabled: () => true,
      allowCellular: () => false,
      onResult: () {},
      store: MemoryAnalysisStore(),
      supported: true,
      decode: (path, rate) async => DecodedAudio(pcm),
      run: (input) async => analyzeInput(input),
    );
    service.request('click', durationMs: 30000);
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final a = service.lookup('click', 30000);
    expect(a, isNotNull);
    expect(a!.durationMs, 30000);
  });
}
