import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/update/update_downloader.dart';
import 'package:music_streaming_app/services/update/update_http.dart';
import 'package:music_streaming_app/services/update/update_models.dart';

/// UPDATES: getting the APK onto disk. Streamed, resumable, verified by
/// SHA-256 without loading the file, and honest about every way it can go
/// wrong. The "network" is a MockClient.streaming that speaks Range.

Uint8List _bytes(int n, {int seed = 7}) {
  final r = Random(seed);
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

String _hex(List<int> b) => crypto.sha256.convert(b).toString();

const _name = 'MineMusic-1.1.0-b142.apk';
const _url = 'https://example.com/dl/MineMusic-1.1.0-b142.apk';

ReleaseAsset _assetFor(
  Uint8List body, {
  String name = _name,
  String url = _url,
  bool sha = true,
  bool size = true,
}) =>
    ReleaseAsset(
      name: name,
      url: url,
      size: size ? body.length : 0,
      sha256: sha ? _hex(body) : '',
    );

/// A file server with Range support and knobs for misbehaving.
class _Server {
  _Server(this.body);

  final Uint8List body;
  final List<http.BaseRequest> requests = [];
  int chunkSize = 16 * 1024;

  /// Always answer 200 with the whole body (the server ignored Range).
  bool ignoreRange = false;

  /// Answer 416 to any Range request.
  bool refuseRange = false;

  /// Answer 206 but from the wrong offset.
  bool wrongOffset = false;

  /// Force this status for every request.
  int? status;

  /// Throw this from `send` (connection failure).
  Object? connectError;

  /// Send this many bytes, then fail the stream with [streamError].
  int? failAfter;
  Object streamError = const SocketException('Connection reset by peer');

  /// Serve this controller's stream for a request without Range.
  StreamController<List<int>>? live;

  Stream<List<int>> _chunks(Uint8List data) async* {
    for (var i = 0; i < data.length; i += chunkSize) {
      yield data.sublist(i, min(i + chunkSize, data.length));
    }
  }

  String? rangeOf(int i) => requests[i].headers['range'];

  late final http.Client client = MockClient.streaming((request, _) async {
    requests.add(request);
    final err = connectError;
    if (err != null) throw err;
    final forced = status;
    if (forced != null) {
      return http.StreamedResponse(const Stream<List<int>>.empty(), forced);
    }
    final range = request.headers['range'];
    if (range != null && refuseRange) {
      return http.StreamedResponse(const Stream<List<int>>.empty(), 416);
    }
    if (range != null && !ignoreRange) {
      final start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      final from = wrongOffset ? 0 : start;
      final slice = Uint8List.sublistView(body, from);
      return http.StreamedResponse(
        _chunks(slice),
        206,
        contentLength: slice.length,
        headers: {'content-range': 'bytes $from-${body.length - 1}/${body.length}'},
      );
    }
    final controller = live;
    if (controller != null) {
      return http.StreamedResponse(controller.stream, 200, contentLength: body.length);
    }
    final failing = failAfter;
    if (failing != null) {
      Stream<List<int>> broken() async* {
        yield* _chunks(Uint8List.sublistView(body, 0, failing));
        throw streamError;
      }

      return http.StreamedResponse(broken(), 200, contentLength: body.length);
    }
    return http.StreamedResponse(_chunks(body), 200, contentLength: body.length);
  });
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('update_dl_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  File finalFile([String name = _name]) => File(joinPath(tmp, name));
  File partFile([String name = _name]) => File('${joinPath(tmp, name)}.part');

  /// A clock that advances 100 ms every time it is read.
  DateTime Function() fakeClock() {
    var t = DateTime.utc(2026);
    return () => t = t.add(const Duration(milliseconds: 100));
  }

  group('a clean download', () {
    test('streams, verifies, and only then takes its final name', () async {
      final body = _bytes(200 * 1024);
      final server = _Server(body);
      final events = <String>[];
      final progress = <DownloadProgress>[];

      final out = await UpdateDownloader(client: server.client).download(
        _assetFor(body),
        dir: tmp,
        onProgress: (p) {
          progress.add(p);
          events.add('progress');
        },
        onVerifying: () => events.add('verifying'),
      );

      expect(out, isA<DownloadCompleted>());
      final file = (out as DownloadCompleted).file;
      expect(file.path, finalFile().path);
      expect(file.readAsBytesSync(), body);
      expect(partFile().existsSync(), isFalse);

      // One GET, no Range, with our identity.
      expect(server.requests, hasLength(1));
      expect(server.requests.single.url.toString(), _url);
      expect(server.requests.single.headers['range'], isNull);
      expect(server.requests.single.headers['user-agent'], 'MineMusic-Updater');

      // Progress only goes forward, ends whole, and "verifying" comes last.
      expect(progress, isNotEmpty);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].received, greaterThanOrEqualTo(progress[i - 1].received));
      }
      expect(progress.first.received, 0);
      expect(progress.last.received, body.length);
      expect(progress.every((p) => p.total == body.length), isTrue);
      expect(progress.every((p) => p.fraction >= 0 && p.fraction <= 1), isTrue);
      expect(progress.last.fraction, 1.0);
      expect(events.where((e) => e == 'verifying'), hasLength(1));
      expect(events.last, 'verifying');
      expect(events.indexOf('verifying'), events.length - 1);
    });

    test('reports a speed and an ETA while it runs', () async {
      final body = _bytes(160 * 1024);
      final progress = <DownloadProgress>[];
      await UpdateDownloader(client: _Server(body).client, now: fakeClock()).download(
        _assetFor(body),
        dir: tmp,
        onProgress: progress.add,
      );
      final running = progress.where((p) => p.received > 0 && p.received < body.length);
      expect(running, isNotEmpty);
      expect(running.every((p) => p.bytesPerSecond > 0), isTrue);
      expect(running.every((p) => p.etaSeconds != null && p.etaSeconds! > 0), isTrue);
      // ETA shrinks as the transfer nears the end.
      expect(running.last.etaSeconds, lessThanOrEqualTo(running.first.etaSeconds!));
      expect(progress.last.etaSeconds, 0);
    });

    test('a large file is streamed and hashed correctly', () async {
      final body = _bytes(5 * 1024 * 1024, seed: 99);
      final server = _Server(body)..chunkSize = 64 * 1024;
      final out = await UpdateDownloader(client: server.client).download(_assetFor(body), dir: tmp);
      expect(out, isA<DownloadCompleted>());
      expect(finalFile().lengthSync(), body.length);
      expect(_hex(finalFile().readAsBytesSync()), _hex(body));
    });

    test('creates the folder if it does not exist', () async {
      final body = _bytes(1000);
      final nested = Directory(joinPath(tmp, 'a${Platform.pathSeparator}b'));
      final out = await UpdateDownloader(client: _Server(body).client).download(_assetFor(body), dir: nested);
      expect(out, isA<DownloadCompleted>());
      expect(File(joinPath(nested, _name)).existsSync(), isTrue);
    });

    test('with neither a checksum nor a size it still completes (nothing to check against)', () async {
      final body = _bytes(5000);
      final out = await UpdateDownloader(client: _Server(body).client)
          .download(_assetFor(body, sha: false, size: false), dir: tmp);
      expect(out, isA<DownloadCompleted>());
    });

    test('a declared size alone is enforced', () async {
      final body = _bytes(5000);
      final out = await UpdateDownloader(client: _Server(body).client)
          .download(_assetFor(body, sha: false), dir: tmp);
      expect(out, isA<DownloadCompleted>());
    });

    test('the checksum may be written in upper case', () async {
      final body = _bytes(5000);
      final asset = ReleaseAsset(name: _name, url: _url, size: body.length, sha256: _hex(body).toUpperCase());
      final out = await UpdateDownloader(client: _Server(body).client).download(asset, dir: tmp);
      expect(out, isA<DownloadCompleted>());
    });
  });

  group('resuming', () {
    test('continues a .part with a Range request and appends', () async {
      final body = _bytes(200 * 1024);
      partFile().writeAsBytesSync(body.sublist(0, 70000));
      final server = _Server(body);
      final progress = <DownloadProgress>[];

      final out = await UpdateDownloader(client: server.client)
          .download(_assetFor(body), dir: tmp, onProgress: progress.add);

      expect(out, isA<DownloadCompleted>());
      expect(server.requests, hasLength(1));
      expect(server.rangeOf(0), 'bytes=70000-');
      expect(finalFile().readAsBytesSync(), body);
      expect(partFile().existsSync(), isFalse);
      // Progress starts where the old attempt stopped, not at zero.
      expect(progress.first.received, 70000);
      expect(progress.last.received, body.length);
    });

    test('a server that ignores Range (200) restarts from zero without duplicating bytes', () async {
      final body = _bytes(100 * 1024);
      partFile().writeAsBytesSync(body.sublist(0, 30000));
      final server = _Server(body)..ignoreRange = true;
      final progress = <DownloadProgress>[];

      final out = await UpdateDownloader(client: server.client)
          .download(_assetFor(body), dir: tmp, onProgress: progress.add);

      expect(out, isA<DownloadCompleted>());
      expect(server.requests, hasLength(1));
      expect(server.rangeOf(0), 'bytes=30000-'); // asked, but was not honoured
      expect(finalFile().readAsBytesSync(), body);
      expect(progress.first.received, 0);
    });

    test('416 discards the .part and restarts from zero', () async {
      final body = _bytes(100 * 1024);
      partFile().writeAsBytesSync(Uint8List(30000)); // garbage prefix
      final server = _Server(body)..refuseRange = true;

      final out = await UpdateDownloader(client: server.client).download(_assetFor(body), dir: tmp);

      expect(out, isA<DownloadCompleted>());
      expect(server.requests, hasLength(2));
      expect(server.rangeOf(0), 'bytes=30000-');
      expect(server.rangeOf(1), isNull);
      expect(finalFile().readAsBytesSync(), body);
    });

    test('a 206 from the wrong offset also restarts from zero', () async {
      final body = _bytes(100 * 1024);
      partFile().writeAsBytesSync(body.sublist(0, 30000));
      final server = _Server(body)..wrongOffset = true;

      final out = await UpdateDownloader(client: server.client).download(_assetFor(body), dir: tmp);

      expect(out, isA<DownloadCompleted>());
      expect(server.requests, hasLength(2));
      expect(server.rangeOf(1), isNull);
      expect(finalFile().readAsBytesSync(), body);
    });

    test('a .part longer than the whole file is thrown away, not resumed', () async {
      final body = _bytes(50 * 1024);
      partFile().writeAsBytesSync(Uint8List(body.length + 10));
      final server = _Server(body);

      final out = await UpdateDownloader(client: server.client).download(_assetFor(body), dir: tmp);

      expect(out, isA<DownloadCompleted>());
      expect(server.rangeOf(0), isNull);
      expect(finalFile().readAsBytesSync(), body);
    });

    test('a .part that is already whole is only verified - no network', () async {
      final body = _bytes(50 * 1024);
      partFile().writeAsBytesSync(body);
      final server = _Server(body);

      final out = await UpdateDownloader(client: server.client).download(_assetFor(body), dir: tmp);

      expect(out, isA<DownloadCompleted>());
      expect(server.requests, isEmpty);
      expect(finalFile().readAsBytesSync(), body);
      expect(partFile().existsSync(), isFalse);
    });

    test('a resumed file that turns out wrong is corrupt and deleted', () async {
      final body = _bytes(100 * 1024);
      final stale = Uint8List.fromList(_bytes(30000, seed: 1234)); // not a prefix of body
      partFile().writeAsBytesSync(stale);

      final out = await UpdateDownloader(client: _Server(body).client).download(_assetFor(body), dir: tmp);

      expect(out, isA<DownloadCorrupt>());
      expect(partFile().existsSync(), isFalse);
      expect(finalFile().existsSync(), isFalse);
    });

    test('a dropped connection keeps the .part, and the next attempt finishes the job', () async {
      final body = _bytes(100 * 1024);
      final server = _Server(body)..failAfter = 40 * 1024;
      final dl = UpdateDownloader(client: server.client);

      final first = await dl.download(_assetFor(body), dir: tmp);
      expect(first, isA<DownloadFailed>());
      expect((first as DownloadFailed).message, 'You appear to be offline.');
      expect(partFile().lengthSync(), 40 * 1024);
      expect(finalFile().existsSync(), isFalse);

      server.failAfter = null;
      final second = await dl.download(_assetFor(body), dir: tmp);
      expect(second, isA<DownloadCompleted>());
      expect(server.rangeOf(1), 'bytes=${40 * 1024}-');
      expect(finalFile().readAsBytesSync(), body);
    });
  });

  group('verification', () {
    test('a checksum mismatch deletes everything and is reported as corrupt', () async {
      final body = _bytes(50 * 1024);
      final wrong = ReleaseAsset(name: _name, url: _url, size: body.length, sha256: _hex(_bytes(10)));

      final out = await UpdateDownloader(client: _Server(body).client).download(wrong, dir: tmp);

      expect(out, same(DownloadOutcome.corrupt));
      expect(finalFile().existsSync(), isFalse);
      expect(partFile().existsSync(), isFalse);
    });

    test('too few bytes for the declared size is corrupt', () async {
      final body = _bytes(50 * 1024);
      final asset = ReleaseAsset(name: _name, url: _url, size: body.length + 5, sha256: _hex(body));
      final out = await UpdateDownloader(client: _Server(body).client).download(asset, dir: tmp);
      expect(out, isA<DownloadCorrupt>());
      expect(partFile().existsSync(), isFalse);
      expect(finalFile().existsSync(), isFalse);
    });

    test('too many bytes for the declared size is corrupt', () async {
      final body = _bytes(50 * 1024);
      final asset = ReleaseAsset(name: _name, url: _url, size: body.length - 5);
      final out = await UpdateDownloader(client: _Server(body).client).download(asset, dir: tmp);
      expect(out, isA<DownloadCorrupt>());
      expect(finalFile().existsSync(), isFalse);
    });

    test('"verifying" is announced before the hash, and not at all when the size already failed', () async {
      final body = _bytes(10 * 1024);
      var verifying = 0;
      final asset = ReleaseAsset(name: _name, url: _url, size: body.length + 1);
      await UpdateDownloader(client: _Server(body).client)
          .download(asset, dir: tmp, onVerifying: () => verifying++);
      expect(verifying, 0);
    });

    test('isVerified: size and checksum must both hold when both are declared', () async {
      final body = _bytes(8000);
      final dl = UpdateDownloader();
      final file = finalFile()..writeAsBytesSync(body);

      expect(await dl.isVerified(file, _assetFor(body)), isTrue);
      expect(await dl.isVerified(file, _assetFor(body, sha: false)), isTrue); // size only
      expect(await dl.isVerified(file, _assetFor(body, size: false)), isTrue); // checksum only
      expect(await dl.isVerified(file, _assetFor(body, sha: false, size: false)), isFalse); // nothing to check
      expect(await dl.isVerified(file, ReleaseAsset(name: _name, url: _url, size: body.length + 1, sha256: _hex(body))), isFalse);
      expect(await dl.isVerified(file, ReleaseAsset(name: _name, url: _url, size: body.length, sha256: _hex(_bytes(3)))), isFalse);
      expect(await dl.isVerified(File(joinPath(tmp, 'missing.apk')), _assetFor(body)), isFalse);
    });
  });

  group('a finished file already on disk', () {
    test('a verified file short-circuits: no request at all', () async {
      final body = _bytes(60 * 1024);
      finalFile().writeAsBytesSync(body);
      final server = _Server(body);
      final progress = <DownloadProgress>[];

      final out = await UpdateDownloader(client: server.client)
          .download(_assetFor(body), dir: tmp, onProgress: progress.add);

      expect(out, isA<DownloadCompleted>());
      expect((out as DownloadCompleted).file.path, finalFile().path);
      expect(server.requests, isEmpty);
      expect(progress.last.fraction, 1.0);
    });

    test('a damaged one is deleted and fetched again', () async {
      final body = _bytes(60 * 1024);
      final damaged = Uint8List.fromList(body)..[100] ^= 0xFF;
      finalFile().writeAsBytesSync(damaged);
      final server = _Server(body);

      final out = await UpdateDownloader(client: server.client).download(_assetFor(body), dir: tmp);

      expect(out, isA<DownloadCompleted>());
      expect(server.requests, hasLength(1));
      expect(finalFile().readAsBytesSync(), body);
    });
  });

  group('cancelling', () {
    test('keeps the .part, and a later download resumes from it', () async {
      final body = _bytes(100 * 1024);
      final live = StreamController<List<int>>();
      final server = _Server(body)..live = live;
      final token = CancelToken();
      final reached = Completer<void>();

      final running = UpdateDownloader(client: server.client).download(
        _assetFor(body),
        dir: tmp,
        cancel: token,
        onProgress: (p) {
          if (p.received >= 30000 && !reached.isCompleted) reached.complete();
        },
      );
      live
        ..add(body.sublist(0, 10000))
        ..add(body.sublist(10000, 20000))
        ..add(body.sublist(20000, 30000));
      await reached.future.timeout(const Duration(seconds: 5));
      token.cancel();

      final out = await running.timeout(const Duration(seconds: 5));
      expect(out, same(DownloadOutcome.cancelled));
      expect(partFile().lengthSync(), 30000);
      expect(finalFile().existsSync(), isFalse);
      unawaited(live.close());

      // Later: the same bytes, resumed.
      final server2 = _Server(body);
      final again = await UpdateDownloader(client: server2.client).download(_assetFor(body), dir: tmp);
      expect(again, isA<DownloadCompleted>());
      expect(server2.rangeOf(0), 'bytes=30000-');
      expect(finalFile().readAsBytesSync(), body);
    });

    test('unblocks a read that is waiting for the network', () async {
      final body = _bytes(100 * 1024);
      final live = StreamController<List<int>>();
      final server = _Server(body)..live = live;
      final token = CancelToken();
      final got = Completer<void>();

      final running = UpdateDownloader(client: server.client).download(
        _assetFor(body),
        dir: tmp,
        cancel: token,
        onProgress: (p) {
          if (p.received > 0 && !got.isCompleted) got.complete();
        },
      );
      live.add(body.sublist(0, 5000));
      await got.future.timeout(const Duration(seconds: 5));
      // ...and now the server says nothing more. Cancel must not wait for it.
      token.cancel();
      expect(await running.timeout(const Duration(seconds: 2)), isA<DownloadCancelled>());
      expect(partFile().lengthSync(), 5000);
      unawaited(live.close());
    });

    test('a token cancelled before the start does nothing at all', () async {
      final body = _bytes(1000);
      final server = _Server(body);
      final token = CancelToken()..cancel();
      final out = await UpdateDownloader(client: server.client).download(_assetFor(body), dir: tmp, cancel: token);
      expect(out, isA<DownloadCancelled>());
      expect(server.requests, isEmpty);
      expect(partFile().existsSync(), isFalse);
    });

    test('CancelToken is idempotent and observable', () async {
      final t = CancelToken();
      expect(t.isCancelled, isFalse);
      var fired = 0;
      unawaited(t.onCancel.then((_) => fired++));
      t
        ..cancel()
        ..cancel();
      await Future<void>.delayed(Duration.zero);
      expect(t.isCancelled, isTrue);
      expect(fired, 1);
    });
  });

  group('failing safely', () {
    test('refuses anything that is not https, before touching the network or disk', () async {
      final body = _bytes(100);
      final server = _Server(body);
      final dl = UpdateDownloader(client: server.client);
      for (final url in ['http://example.com/a.apk', 'ftp://example.com/a.apk', 'file:///sdcard/a.apk', '//example.com/a.apk', 'a.apk', '']) {
        final out = await dl.download(_assetFor(body, url: url), dir: tmp);
        expect(out, isA<DownloadFailed>(), reason: url);
      }
      expect(server.requests, isEmpty);
      expect(tmp.listSync(), isEmpty);
    });

    test('refuses file names that could escape the folder', () async {
      final body = _bytes(100);
      final server = _Server(body);
      final dl = UpdateDownloader(client: server.client);
      for (final name in ['../evil.apk', 'a/b.apk', r'a\b.apk', '.hidden.apk', 'a b.apk', '', '..']) {
        final out = await dl.download(_assetFor(body, name: name), dir: tmp);
        expect(out, isA<DownloadFailed>(), reason: name);
      }
      expect(server.requests, isEmpty);
      expect(File('${tmp.parent.path}${Platform.pathSeparator}evil.apk').existsSync(), isFalse);
    });

    final statuses = <int, String>{
      404: 'This update is no longer available.',
      410: 'This update is no longer available.',
      403: kDownloadInterruptedMessage,
      500: kDownloadInterruptedMessage,
      503: kDownloadInterruptedMessage,
      302: kDownloadInterruptedMessage,
    };
    statuses.forEach((code, message) {
      test('HTTP $code is a Failed("$message") and leaves no file', () async {
        final server = _Server(_bytes(10))..status = code;
        final out = await UpdateDownloader(client: server.client).download(_assetFor(_bytes(10)), dir: tmp);
        expect((out as DownloadFailed).message, message);
        expect(finalFile().existsSync(), isFalse);
      });
    });

    test('416 on a first attempt (nothing to resume) is a failure, not a loop', () async {
      final body = _bytes(100);
      final server = _Server(body)..status = 416;
      final out = await UpdateDownloader(client: server.client).download(_assetFor(body), dir: tmp);
      expect(out, isA<DownloadFailed>());
      expect(server.requests, hasLength(1));
    });

    test('no connection is "offline"; any other transport error is "interrupted"', () async {
      final body = _bytes(100);
      final server = _Server(body)..connectError = const SocketException('Network is unreachable');
      final dl = UpdateDownloader(client: server.client);
      expect(((await dl.download(_assetFor(body), dir: tmp)) as DownloadFailed).message, kOfflineMessage);

      server.connectError = http.ClientException('SocketException: Failed host lookup');
      expect(((await dl.download(_assetFor(body), dir: tmp)) as DownloadFailed).message, kOfflineMessage);

      server.connectError = const HandshakeException('bad certificate');
      expect(((await dl.download(_assetFor(body), dir: tmp)) as DownloadFailed).message, kDownloadInterruptedMessage);

      server.connectError = StateError('a bug');
      expect(((await dl.download(_assetFor(body), dir: tmp)) as DownloadFailed).message, kDownloadInterruptedMessage);
    });

    test('a stalled transfer gives up after the idle timeout and keeps what it has', () async {
      final body = _bytes(100 * 1024);
      final live = StreamController<List<int>>();
      final server = _Server(body)..live = live;
      final got = Completer<void>();
      live.add(body.sublist(0, 4000));

      final out = await UpdateDownloader(client: server.client, idleTimeout: const Duration(milliseconds: 150))
          .download(
            _assetFor(body),
            dir: tmp,
            onProgress: (p) {
              if (p.received > 0 && !got.isCompleted) got.complete();
            },
          )
          .timeout(const Duration(seconds: 5));

      expect(got.isCompleted, isTrue);
      expect(out, isA<DownloadFailed>());
      expect(partFile().lengthSync(), 4000);
      unawaited(live.close());
    });

    test('a folder that cannot be created is a Failed, never an exception', () async {
      final blocker = File(joinPath(tmp, 'blocker'))..writeAsStringSync('i am a file');
      final out = await UpdateDownloader(client: _Server(_bytes(10)).client)
          .download(_assetFor(_bytes(10)), dir: Directory('${blocker.path}${Platform.pathSeparator}sub'));
      expect(out, isA<DownloadFailed>());
    });
  });

  group('SpeedMeter', () {
    final t0 = DateTime.utc(2026);

    test('measures over a sliding two-second window', () {
      final m = SpeedMeter();
      expect(m.add(t0, 0), 0);
      expect(m.add(t0.add(const Duration(seconds: 1)), 1000), closeTo(1000, 0.01));
      expect(m.add(t0.add(const Duration(seconds: 2)), 3000), closeTo(1500, 0.01));
      // The first sample is now older than the window and is forgotten.
      expect(m.add(t0.add(const Duration(seconds: 3)), 6000), closeTo(2500, 0.01));
    });

    test('a burst in the first instant is damped by a 250 ms floor', () {
      final m = SpeedMeter()..add(t0, 0);
      expect(m.add(t0.add(const Duration(milliseconds: 10)), 100000), closeTo(400000, 1));
    });

    test('does not divide by zero when time stands still', () {
      final m = SpeedMeter()..add(t0, 0);
      expect(m.add(t0, 500), 0);
      expect(m.add(t0.subtract(const Duration(seconds: 1)), 900), 0); // clock went backwards
    });
  });

  group('DownloadProgress', () {
    test('fraction is 0 with no total and never above 1', () {
      expect(const DownloadProgress(received: 50, total: 0).fraction, 0);
      expect(const DownloadProgress(received: 50, total: 100).fraction, 0.5);
      expect(const DownloadProgress(received: 150, total: 100).fraction, 1);
    });
  });

  test('close() leaves a borrowed client open and is safe on an owned one', () {
    final borrowed = _Server(_bytes(1)).client;
    UpdateDownloader(client: borrowed).close();
    expect(() => UpdateDownloader().close(), returnsNormally);
  });
}
