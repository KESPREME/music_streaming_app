// lib/services/downloads/chunked_downloader.dart
//
// Fast, resumable file downloads. Plan: docs/PLAN-motion-perf-downloads.md (P2).
//
// WHY
//
// googlevideo serves ranged requests of up to ~10 MB at full speed and paces
// larger or unranged ones to roughly playback speed (yt-dlp FAQ: "YouTube
// throttles any request with an http chunk size of > 10MB"). The old download
// was one plain GET with no User-Agent, so a 4-minute song took about as long
// to download as to play, and a dropped connection started it over.
//
// HOW
//
//   * Size from the URL's `clen=` (googlevideo always carries it), else a
//     1-byte `Range: bytes=0-0` probe.
//   * Split into [chunkBytes] (1 MB) ranges, fetched [connections] at a time,
//     each with the User-Agent of the client that signed the URL.
//   * Each range streams into its own `<path>.part<i>` file, renamed from
//     `.tmp` only once it has every byte, so a finished range survives a crash
//     and a retry fetches only what is missing (resume).
//   * When every range is in, they are joined into `<path>.tmp`, the size is
//     checked, and it is renamed over [path] in one step.
//   * A server that ignores Range, or a file of unknown size, falls back to
//     one streamed GET (still `.tmp` + rename).
//   * Each range is retried [maxRetries] times with backoff. 403/410 is not
//     retried here: the URL has expired, and only the caller can get a new one
//     ([DownloadHttpException.expired]).

import 'dart:async';
import 'dart:io';
import 'dart:math';

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => 'Download cancelled';
}

class DownloadHttpException implements Exception {
  const DownloadHttpException(this.status);
  final int status;

  /// The URL is no longer valid; resolve a fresh one.
  bool get expired => status == 403 || status == 410;

  @override
  String toString() => 'Download failed: HTTP $status';
}

class ChunkedDownloader {
  ChunkedDownloader({
    HttpClient Function()? clientFactory,
    // 1 MB: a 4-minute song (4-8 MB) becomes 4-8 ranges, enough to keep all
    // [connections] busy, and far under the ~10 MB pacing threshold.
    this.chunkBytes = 1024 * 1024,
    this.connections = 4,
    this.maxRetries = 3,
    this.stallTimeout = const Duration(seconds: 20),
    this.retryDelay = const Duration(milliseconds: 600),
  }) : _clientFactory = clientFactory ?? _defaultClient;

  final HttpClient Function() _clientFactory;
  final int chunkBytes;
  final int connections;
  final int maxRetries;

  /// No byte for this long on an open response counts as a failure.
  final Duration stallTimeout;
  final Duration retryDelay;

  static HttpClient _defaultClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 15)
    ..maxConnectionsPerHost = 8;

  /// The total size googlevideo writes into its URLs, or null.
  static int? contentLengthFromUrl(Uri url) {
    final v = int.tryParse(url.queryParameters['clen'] ?? '');
    return v != null && v > 0 ? v : null;
  }

  /// The pieces a partial download of [path] leaves behind.
  static Iterable<File> partialFiles(String path) sync* {
    final dir = File(path).parent;
    if (!dir.existsSync()) return;
    final name = File(path).uri.pathSegments.last;
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      final n = e.uri.pathSegments.last;
      if (n == '$name.tmp' || n.startsWith('$name.part')) yield e;
    }
  }

  /// Deletes what a cancelled download of [path] left behind.
  static Future<void> discardPartial(String path) async {
    for (final f in partialFiles(path).toList()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  /// Downloads [url] to [path]. Completes when [path] holds the whole file.
  ///
  /// [onProgress] reports bytes so far and the total (-1 when unknown).
  /// [isCancelled] is polled while bytes arrive; a cancel throws
  /// [DownloadCancelled] and keeps the finished ranges for a later resume.
  Future<void> download({
    required Uri url,
    required String path,
    String? userAgent,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final client = _clientFactory();
    try {
      var total = contentLengthFromUrl(url);
      var ranged = true;
      if (total == null) {
        final probe = await _probe(client, url, userAgent);
        total = probe.total;
        ranged = probe.ranged;
      }
      if (total == null || !ranged || total <= 0) {
        await _single(client, url, path, userAgent, onProgress, isCancelled);
        return;
      }
      await _chunked(client, url, path, total, userAgent, onProgress, isCancelled);
    } finally {
      client.close(force: true);
    }
  }

  Future<({int? total, bool ranged})> _probe(HttpClient client, Uri url, String? ua) async {
    final req = await client.getUrl(url);
    _headers(req, ua, range: 'bytes=0-0');
    final res = await req.close();
    if (res.statusCode == 206) {
      // One byte: drained, so the connection is kept for the ranges.
      await res.drain<void>().catchError((_) {});
      final cr = res.headers.value(HttpHeaders.contentRangeHeader) ?? '';
      final total = int.tryParse(cr.split('/').last.trim());
      return (total: total, ranged: total != null);
    }
    // No Range support: the body is the whole file. Abort it rather than pay
    // for it twice; the single-GET path fetches it properly.
    await res.listen((_) {}).cancel();
    if (res.statusCode == 200) return (total: res.contentLength > 0 ? res.contentLength : null, ranged: false);
    throw DownloadHttpException(res.statusCode);
  }

  void _headers(HttpClientRequest req, String? ua, {String? range}) {
    if (ua != null && ua.isNotEmpty) req.headers.set(HttpHeaders.userAgentHeader, ua);
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  }

  /// Sends a GET and waits for its headers, abandoning it as soon as
  /// [isCancelled] says so (a server that is not answering sends nothing to
  /// react to) or after [stallTimeout].
  Future<HttpClientResponse> _open(
    HttpClient client,
    Uri url,
    String? ua, {
    String? range,
    bool Function()? isCancelled,
  }) async {
    final req = await client.getUrl(url).timeout(stallTimeout);
    _headers(req, ua, range: range);
    final response = req.close();
    if (isCancelled == null) return response.timeout(stallTimeout);
    final done = Completer<HttpClientResponse>();
    final watch = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!done.isCompleted && isCancelled()) {
        req.abort(const DownloadCancelled());
        done.completeError(const DownloadCancelled());
      }
    });
    response.timeout(stallTimeout).then((r) {
      if (!done.isCompleted) {
        done.complete(r);
      } else {
        unawaited(r.listen((_) {}).cancel().catchError((_) {}));
      }
    }, onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    });
    try {
      return await done.future;
    } finally {
      watch.cancel();
    }
  }

  Future<void> _chunked(
    HttpClient client,
    Uri url,
    String path,
    int total,
    String? ua,
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
  ) async {
    final count = (total + chunkBytes - 1) ~/ chunkBytes;
    // A partial download of a different size (a re-resolved URL can be a
    // different format) cannot be resumed.
    final marker = File('$path.part.size');
    if (marker.existsSync() && marker.readAsStringSync().trim() != '$total') {
      await discardPartial(path);
    }
    marker.parent.createSync(recursive: true);
    marker.writeAsStringSync('$total');

    File part(int i) => File('$path.part$i');
    int start(int i) => i * chunkBytes;
    int end(int i) => min(total, (i + 1) * chunkBytes) - 1;

    final received = List<int>.filled(count, 0);
    final pending = <int>[];
    for (var i = 0; i < count; i++) {
      final f = part(i);
      if (f.existsSync() && f.lengthSync() == end(i) - start(i) + 1) {
        received[i] = end(i) - start(i) + 1;
      } else {
        pending.add(i);
      }
    }
    void report() => onProgress?.call(received.fold(0, (a, b) => a + b), total);
    report();

    Object? failure;
    var next = 0;
    Future<void> worker() async {
      while (failure == null && next < pending.length) {
        final i = pending[next++];
        for (var attempt = 0;; attempt++) {
          received[i] = 0;
          try {
            await _range(client, url, part(i), start(i), end(i), ua, (n) {
              received[i] = n;
              report();
            }, isCancelled);
            break;
          } on DownloadCancelled {
            rethrow;
          } on DownloadHttpException catch (e) {
            if (e.expired || attempt >= maxRetries) rethrow;
          } catch (_) {
            if (attempt >= maxRetries) rethrow;
          }
          if (isCancelled?.call() ?? false) throw const DownloadCancelled();
          await Future<void>.delayed(retryDelay * (1 << attempt));
        }
      }
    }

    final workers = [
      for (var w = 0; w < min(connections, max(1, pending.length)); w++)
        worker().catchError((Object e) {
          failure ??= e;
        }),
    ];
    await Future.wait(workers);
    if (failure != null) throw failure!;

    // Join, verify, swap in.
    final tmp = File('$path.tmp');
    final sink = tmp.openWrite();
    try {
      for (var i = 0; i < count; i++) {
        await sink.addStream(part(i).openRead());
      }
    } finally {
      await sink.close();
    }
    final size = tmp.lengthSync();
    if (size != total) {
      await discardPartial(path);
      throw StateError('Downloaded $size of $total bytes');
    }
    await _swapIn(tmp, path);
    for (var i = 0; i < count; i++) {
      try {
        part(i).deleteSync();
      } catch (_) {}
    }
    try {
      marker.deleteSync();
    } catch (_) {}
  }

  Future<void> _range(
    HttpClient client,
    Uri url,
    File out,
    int from,
    int to,
    String? ua,
    void Function(int received) onBytes,
    bool Function()? isCancelled,
  ) async {
    final res = await _open(client, url, ua, range: 'bytes=$from-$to', isCancelled: isCancelled);
    final expected = to - from + 1;
    // A server may answer a range that covers the whole file with 200.
    final okWhole = res.statusCode == 200 && from == 0 && res.contentLength == expected;
    if (res.statusCode != 206 && !okWhole) {
      await res.listen((_) {}).cancel();
      throw DownloadHttpException(res.statusCode);
    }
    final tmp = File('${out.path}.tmp');
    final sink = tmp.openWrite();
    int n;
    try {
      n = await _pipe(res, sink, limit: expected, onBytes: onBytes, isCancelled: isCancelled);
    } finally {
      await sink.close();
    }
    if (n != expected) {
      try {
        tmp.deleteSync();
      } catch (_) {}
      throw StateError('Range $from-$to ended at $n of $expected bytes');
    }
    if (out.existsSync()) out.deleteSync();
    tmp.renameSync(out.path);
  }

  /// Streams [src] into [sink]; the byte count when it ends.
  ///
  /// Cancel is also checked on a timer, not only when bytes arrive: a stalled
  /// connection (the network just dropped) sends none, and the pause must not
  /// wait for [stallTimeout] to take effect.
  Future<int> _pipe(
    Stream<List<int>> src,
    IOSink sink, {
    int? limit,
    void Function(int received)? onBytes,
    bool Function()? isCancelled,
  }) {
    final done = Completer<int>();
    var n = 0;
    Timer? watch;
    late final StreamSubscription<List<int>> sub;
    void fail(Object e) {
      if (done.isCompleted) return;
      watch?.cancel();
      unawaited(sub.cancel().catchError((_) {}));
      done.completeError(e);
    }

    sub = src.timeout(stallTimeout).listen(
      (bytes) {
        if (isCancelled?.call() ?? false) return fail(const DownloadCancelled());
        sink.add(bytes);
        n += bytes.length;
        if (limit != null && n > limit) return fail(StateError('More bytes than asked for'));
        onBytes?.call(n);
      },
      onError: fail,
      onDone: () {
        watch?.cancel();
        if (!done.isCompleted) done.complete(n);
      },
      cancelOnError: true,
    );
    if (isCancelled != null) {
      watch = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (isCancelled()) fail(const DownloadCancelled());
      });
    }
    return done.future;
  }

  Future<void> _single(
    HttpClient client,
    Uri url,
    String path,
    String? ua,
    void Function(int, int)? onProgress,
    bool Function()? isCancelled,
  ) async {
    for (var attempt = 0;; attempt++) {
      try {
        final res = await _open(client, url, ua, isCancelled: isCancelled);
        if (res.statusCode != 200) {
          await res.listen((_) {}).cancel();
          throw DownloadHttpException(res.statusCode);
        }
        final total = res.contentLength;
        final tmp = File('$path.tmp');
        tmp.parent.createSync(recursive: true);
        final sink = tmp.openWrite();
        int n;
        try {
          n = await _pipe(res, sink,
              onBytes: (got) => onProgress?.call(got, total), isCancelled: isCancelled);
        } finally {
          await sink.close();
        }
        if (total > 0 && n != total) throw StateError('Downloaded $n of $total bytes');
        await _swapIn(tmp, path);
        return;
      } on DownloadCancelled {
        rethrow;
      } on DownloadHttpException catch (e) {
        if (e.expired || attempt >= maxRetries) rethrow;
      } catch (_) {
        if (attempt >= maxRetries) rethrow;
      }
      if (isCancelled?.call() ?? false) throw const DownloadCancelled();
      await Future<void>.delayed(retryDelay * (1 << attempt));
    }
  }

  static Future<void> _swapIn(File tmp, String path) async {
    final dest = File(path);
    if (dest.existsSync()) dest.deleteSync();
    tmp.renameSync(path);
  }
}
