import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/downloads/chunked_downloader.dart';
import 'package:music_streaming_app/services/downloads/download_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DOWNLOADS: ranged and parallel (googlevideo paces big unranged GETs to
/// about playback speed), resumable, verified, and honest about expired URLs.

/// A local file server with Range support and knobs for misbehaving.
class _Server {
  _Server(this.body);

  final Uint8List body;
  late HttpServer _server;
  final List<String?> ranges = [];
  final List<String?> agents = [];
  bool supportRange = true;
  int status = 200;

  /// Ranges (by start offset) that drop the connection halfway, once each.
  final Set<int> breakOnce = {};

  /// Ranges that stall until the test lets go.
  Completer<void>? stall;

  Future<Uri> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
    return Uri.parse('http://127.0.0.1:${_server.port}/audio');
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final range = req.headers.value(HttpHeaders.rangeHeader);
    ranges.add(range);
    agents.add(req.headers.value(HttpHeaders.userAgentHeader));
    final res = req.response;
    if (status != 200) {
      res.statusCode = status;
      await res.close();
      return;
    }
    if (!supportRange || range == null) {
      res.contentLength = body.length;
      res.add(body);
      await res.close();
      return;
    }
    final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
    final from = int.parse(m.group(1)!);
    final to = min(int.parse(m.group(2)!), body.length - 1);
    res.statusCode = 206;
    res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $from-$to/${body.length}');
    res.contentLength = to - from + 1;
    final slice = body.sublist(from, to + 1);
    if (stall != null && from > 0) await stall!.future;
    if (breakOnce.remove(from)) {
      final socket = await res.detachSocket(writeHeaders: true);
      socket.add(slice.sublist(0, slice.length ~/ 2));
      await socket.flush();
      socket.destroy();
      return;
    }
    res.add(slice);
    await res.close();
  }
}

Uint8List _bytes(int n) {
  final r = Random(7);
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

void main() {
  late Directory dir;
  late _Server server;
  late Uri url;
  final body = _bytes(1000 * 1000 + 123); // just under 1 MB, an odd size

  ChunkedDownloader dl({int chunk = 128 * 1024}) => ChunkedDownloader(
        chunkBytes: chunk,
        connections: 4,
        retryDelay: const Duration(milliseconds: 5),
        stallTimeout: const Duration(seconds: 5),
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dl_test');
    server = _Server(body);
    url = await server.start();
  });

  tearDown(() async {
    await server.stop();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('ranges in parallel, every byte right, with the signing client\'s UA', () async {
    final path = '${dir.path}/a.mp3';
    final progress = <int>[];
    await dl().download(
      url: url.replace(queryParameters: {'clen': '${body.length}'}),
      path: path,
      userAgent: 'com.google.ios.youtube/20',
      onProgress: (r, t) => progress.add(r),
    );
    expect(await File(path).readAsBytes(), body);
    final ranged = server.ranges.whereType<String>().toList();
    expect(ranged.length, (body.length / (128 * 1024)).ceil(), reason: 'one request per range, no probe with clen');
    expect(ranged.every((r) => r.startsWith('bytes=')), isTrue);
    expect(server.agents.toSet(), {'com.google.ios.youtube/20'});
    expect(progress.last, body.length);
    expect(ChunkedDownloader.partialFiles(path), isEmpty, reason: 'pieces cleaned up');
  });

  test('without clen the size comes from a 1-byte probe', () async {
    final path = '${dir.path}/b.mp3';
    await dl().download(url: url, path: path);
    expect(await File(path).readAsBytes(), body);
    expect(server.ranges.first, 'bytes=0-0');
  });

  test('a dropped range is retried; the rest are not fetched twice', () async {
    final path = '${dir.path}/c.mp3';
    server.breakOnce.add(256 * 1024);
    await dl().download(url: url.replace(queryParameters: {'clen': '${body.length}'}), path: path);
    expect(await File(path).readAsBytes(), body);
    final starts = server.ranges.map((r) => r!.split('=')[1].split('-').first).toList();
    expect(starts.where((s) => s == '${256 * 1024}').length, 2);
    expect(starts.where((s) => s == '0').length, 1);
  });

  test('cancel keeps finished ranges; the retry resumes instead of starting over', () async {
    final path = '${dir.path}/d.mp3';
    final u = url.replace(queryParameters: {'clen': '${body.length}'});
    server.stall = Completer<void>();
    var cancel = false;
    final first = dl().download(url: u, path: path, isCancelled: () => cancel);
    // Range 0 completes; the others stall. Then cancel.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    cancel = true;
    server.stall!.complete();
    await expectLater(first, throwsA(isA<DownloadCancelled>()));
    expect(File('$path.part0').existsSync(), isTrue);
    server.ranges.clear();
    server.stall = null;

    await dl().download(url: u, path: path);
    expect(await File(path).readAsBytes(), body);
    expect(server.ranges, isNot(contains('bytes=0-${128 * 1024 - 1}')), reason: 'range 0 was kept');
  });

  test('a server without Range support still works (one GET)', () async {
    server.supportRange = false;
    final path = '${dir.path}/e.mp3';
    await dl().download(url: url, path: path);
    expect(await File(path).readAsBytes(), body);
  });

  test('an expired URL says so and is not retried', () async {
    server.status = 403;
    final path = '${dir.path}/f.mp3';
    await expectLater(
      dl().download(url: url.replace(queryParameters: {'clen': '${body.length}'}), path: path),
      throwsA(isA<DownloadHttpException>().having((e) => e.expired, 'expired', isTrue)),
    );
    expect(server.ranges.length, lessThanOrEqualTo(4), reason: 'one attempt per connection, no retry storm');
    expect(File(path).existsSync(), isFalse);
  });

  test('a different file at the same path is not spliced into an old partial', () async {
    final path = '${dir.path}/g.mp3';
    File('$path.part.size').writeAsStringSync('999');
    File('$path.part0').writeAsBytesSync(List.filled(128 * 1024, 0));
    await dl().download(url: url.replace(queryParameters: {'clen': '${body.length}'}), path: path);
    expect(await File(path).readAsBytes(), body);
  });

  group('manager', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Track t(String id) => Track(id: id, trackName: 'Song $id', artistName: 'A', albumName: '', previewUrl: '');

    DownloadManager manager({
      required Future<ResolvedDownload?> Function(Track) resolve,
      Future<String?> Function(String)? cached,
      void Function(String)? stale,
      bool Function()? connected,
    }) =>
        DownloadManager(
          resolveStreamForTrack: resolve,
          onMessage: (_) {},
          onTransientFailure: (_, __) {},
          isOffline: () => false,
          isConnected: connected ?? () => true,
          stopActiveTrack: (_) async {},
          removeLocalTrackByPath: (_) {},
          cachedStreamFile: cached,
          onStaleStream: stale,
          downloader: dl(),
          baseDirectory: () async => dir,
        );

    test('downloads, registers, and reports progress to the end', () async {
      final m = manager(resolve: (_) async => ResolvedDownload(url: '$url?clen=${body.length}', userAgent: 'UA'));
      final seen = <double>[];
      m.addListener(() => seen.addAll(m.downloadProgress.values));
      await m.downloadTrack(t('song1'));
      expect(await m.isTrackDownloaded('song1'), isTrue);
      expect(await File('${dir.path}/offline_music/song1.mp3').readAsBytes(), body);
      expect(seen, isNotEmpty);
    });

    test('a song already played through is copied from the stream cache, not fetched', () async {
      final cache = File('${dir.path}/cache.m4a')..writeAsBytesSync(body);
      var resolved = 0;
      final m = manager(
        resolve: (_) async {
          resolved++;
          return ResolvedDownload(url: '$url');
        },
        cached: (id) async => cache.path,
      );
      await m.downloadTrack(t('song2'));
      expect(resolved, 0);
      expect(server.ranges, isEmpty);
      expect(await File('${dir.path}/offline_music/song2.mp3').readAsBytes(), body);
    });

    test('an expired URL is forgotten and resolved once more', () async {
      final staleIds = <String>[];
      var calls = 0;
      final m = manager(
        resolve: (_) async {
          calls++;
          server.status = calls == 1 ? 403 : 200;
          return ResolvedDownload(url: '$url?clen=${body.length}', streamId: 'yt123');
        },
        stale: staleIds.add,
      );
      await m.downloadTrack(t('song3'));
      expect(staleIds, ['yt123']);
      expect(calls, 2);
      expect(await m.isTrackDownloaded('song3'), isTrue);
    });

    test('a batch never runs more than 3 at once; the rest queue and all finish', () async {
      server.stall = Completer<void>();
      final m = manager(resolve: (_) async => ResolvedDownload(url: '$url?clen=${body.length}'));
      final all = [for (var i = 0; i < 5; i++) m.downloadTrack(t('b$i'))];
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(m.currentlyDownloadingTracks.length, 3);
      expect(m.downloadQueue.length, 2);
      server.stall!.complete();
      await Future.wait(all);
      for (var i = 0; i < 50 && m.currentlyDownloadingTracks.isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      for (var i = 0; i < 5; i++) {
        expect(await m.isTrackDownloaded('b$i'), isTrue, reason: 'b$i');
      }
    });

    test('a dropped connection pauses: pieces kept, back at the front of the queue', () async {
      server.stall = Completer<void>();
      var online = true;
      final m = manager(
          resolve: (_) async => ResolvedDownload(url: '$url?clen=${body.length}'), connected: () => online);
      final f = m.downloadTrack(t('p1'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      online = false;
      m.pauseAllDownloads();
      await f.timeout(const Duration(seconds: 2), onTimeout: () => fail('pause waited for the stalled connection'));
      server.stall!.complete();
      expect(m.downloadQueue.map((x) => x.id), ['p1']);
      expect(File('${dir.path}/offline_music/p1.mp3.part0').existsSync(), isTrue);

      online = true;
      m.processQueue();
      for (var i = 0; i < 60 && !(await m.isTrackDownloaded('p1')); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(await m.isTrackDownloaded('p1'), isTrue, reason: 'resumed when back online');
    });

    test('a user cancel discards the pieces', () async {
      server.stall = Completer<void>();
      final m = manager(resolve: (_) async => ResolvedDownload(url: '$url?clen=${body.length}'));
      final f = m.downloadTrack(t('c1'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      m.cancelDownload('c1');
      await f.timeout(const Duration(seconds: 2), onTimeout: () => fail('cancel waited for the stalled connection'));
      server.stall!.complete();
      expect(m.downloadQueue, isEmpty);
      expect(ChunkedDownloader.partialFiles('${dir.path}/offline_music/c1.mp3'), isEmpty);
      expect(await m.isTrackDownloaded('c1'), isFalse);
    });
  });
}
