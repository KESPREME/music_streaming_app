// lib/services/update/update_downloader.dart
//
// Gets the APK onto disk, safely.
//
//   * Streams to `<dir>/<name>.part` and renames to `<dir>/<name>` only after
//     the bytes check out, so a file with the final name is always a complete,
//     verified one.
//   * Resumes. A `.part` left by a dropped connection (or a cancel) continues
//     with `Range: bytes=N-`. A server that answers 200 ignored the Range, and
//     a 416 means our offset is no good - both restart from zero.
//   * Verifies SHA-256 by streaming the file through `package:crypto`, never
//     loading it, and checks the size when the release declares one. A bad
//     file is deleted, not kept "just in case".
//   * Refuses anything that is not https.
//
// Failure is a value ([DownloadOutcome]); [UpdateDownloader.download] never
// throws.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'update_http.dart';
import 'update_models.dart';

/// A tiny cancellation handle. Cancelling unblocks a stalled read at once.
class CancelToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get onCancel => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// How far a download is. [received] includes bytes a resumed download already
/// had.
@immutable
class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    this.bytesPerSecond = 0,
    this.etaSeconds,
  });

  final int received;

  /// 0 when neither the release nor the server said.
  final int total;

  /// Smoothed over about two seconds.
  final double bytesPerSecond;
  final int? etaSeconds;

  double get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : 0;
}

/// How a download ended.
sealed class DownloadOutcome {
  const DownloadOutcome();

  /// The verified file, under its final name.
  factory DownloadOutcome.completed(File file) = DownloadCompleted;

  /// A transport or storage problem; [message] is for a person. The `.part`
  /// is kept so the next attempt resumes.
  factory DownloadOutcome.failed(String message) = DownloadFailed;

  /// The caller cancelled; the `.part` is kept.
  static const DownloadOutcome cancelled = DownloadCancelled();

  /// The bytes were wrong (checksum or size). The file was deleted.
  static const DownloadOutcome corrupt = DownloadCorrupt();
}

final class DownloadCompleted extends DownloadOutcome {
  const DownloadCompleted(this.file);
  final File file;
}

final class DownloadCancelled extends DownloadOutcome {
  const DownloadCancelled();
}

final class DownloadCorrupt extends DownloadOutcome {
  const DownloadCorrupt();
}

final class DownloadFailed extends DownloadOutcome {
  const DownloadFailed(this.message);
  final String message;
}

/// Bytes per second over a sliding [window]. Pure; time is passed in.
class SpeedMeter {
  SpeedMeter({this.window = const Duration(seconds: 2)});

  final Duration window;
  final ListQueue<(DateTime, int)> _samples = ListQueue();
  double _last = 0;

  /// Records that [received] bytes had arrived at [at]; returns the speed.
  ///
  /// Spans shorter than a quarter second are treated as a quarter second, so
  /// the first chunk of a download does not report an absurd burst rate.
  double add(DateTime at, int received) {
    _samples.addLast((at, received));
    while (_samples.length > 2 && at.difference(_samples.first.$1) > window) {
      _samples.removeFirst();
    }
    final first = _samples.first;
    final micros = at.difference(first.$1).inMicroseconds;
    if (micros <= 0) return _last;
    final span = math.max(micros, 250000);
    return _last = (received - first.$2) / (span / 1e6);
  }
}

enum _Step { done, cancelled, restart, failed }

class _Transfer {
  const _Transfer(this.step, [this.message]);
  final _Step step;
  final String? message;
}

final RegExp _contentRange = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$', caseSensitive: false);
final RegExp _safeFileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+\-]*$');

class UpdateDownloader {
  UpdateDownloader({
    http.Client? client,
    DateTime Function()? now,
    this.idleTimeout = const Duration(seconds: 30),
    this.connectTimeout = const Duration(seconds: 20),
  })  : _client = client,
        _ownsClient = client == null,
        _now = now ?? DateTime.now;

  /// A transfer that delivers nothing for this long is treated as dead.
  final Duration idleTimeout;

  /// Time to receive the response headers.
  final Duration connectTimeout;

  http.Client? _client;
  final bool _ownsClient;
  final DateTime Function() _now;

  http.Client get _http => _client ??= http.Client();

  /// Closes the HTTP client only if this downloader created it.
  void close() {
    if (_ownsClient) {
      _client?.close();
      _client = null;
    }
  }

  /// Downloads [asset] into [dir] and returns how it went. Never throws.
  ///
  /// [onVerifying] fires once the last byte is on disk, just before hashing.
  Future<DownloadOutcome> download(
    ReleaseAsset asset, {
    required Directory dir,
    void Function(DownloadProgress)? onProgress,
    void Function()? onVerifying,
    CancelToken? cancel,
  }) async {
    try {
      return await _download(asset, dir, onProgress, onVerifying, cancel);
    } catch (e) {
      logUpdate('download crashed: $e');
      return DownloadOutcome.failed(looksOffline(e) ? kOfflineMessage : kDownloadInterruptedMessage);
    }
  }

  /// True when [file] is exactly [asset]: the declared size (if any) matches
  /// and the SHA-256 (if any) matches. With neither declared there is nothing
  /// to verify against, so a file is never trusted. Never throws.
  Future<bool> isVerified(File file, ReleaseAsset asset) async {
    try {
      if (!await file.exists()) return false;
      if (asset.size > 0 && await file.length() != asset.size) return false;
      if (asset.sha256.isNotEmpty) {
        return await sha256Of(file) == asset.sha256.toLowerCase();
      }
      return asset.size > 0;
    } catch (_) {
      return false;
    }
  }

  /// Hex SHA-256 of [file], streamed - the file is never held in memory.
  Future<String> sha256Of(File file) async =>
      (await crypto.sha256.bind(file.openRead()).first).toString();

  // ---------------------------------------------------------------------------

  Future<DownloadOutcome> _download(
    ReleaseAsset asset,
    Directory dir,
    void Function(DownloadProgress)? onProgress,
    void Function()? onVerifying,
    CancelToken? cancel,
  ) async {
    final uri = Uri.tryParse(asset.url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return DownloadOutcome.failed('The update link is not secure, so it was not downloaded.');
    }
    if (!_safeFileName.hasMatch(asset.name) || asset.name.contains('..')) {
      return DownloadOutcome.failed('The update file has an unusable name.');
    }

    await dir.create(recursive: true);
    final target = File(joinPath(dir, asset.name));
    final part = File('${target.path}.part');

    // A verified file from an earlier run needs no network at all.
    if (await target.exists()) {
      if (await isVerified(target, asset)) {
        onProgress?.call(DownloadProgress(
          received: asset.size,
          total: asset.size,
        ));
        return DownloadOutcome.completed(target);
      }
      await _tryDelete(target);
    }
    if (cancel?.isCancelled ?? false) return DownloadOutcome.cancelled;

    var have = await part.exists() ? await part.length() : 0;
    if (asset.size > 0 && have > asset.size) {
      await _tryDelete(part);
      have = 0;
    }

    // A .part that is already the full size only needs verifying.
    final alreadyWhole = asset.size > 0 && have == asset.size;
    if (!alreadyWhole) {
      var restarted = false;
      while (true) {
        final t = await _transfer(
          uri: uri,
          part: part,
          have: have,
          asset: asset,
          onProgress: onProgress,
          cancel: cancel,
        );
        if (t.step == _Step.done) break;
        if (t.step == _Step.cancelled) return DownloadOutcome.cancelled;
        if (t.step == _Step.failed) {
          return DownloadOutcome.failed(t.message ?? kDownloadInterruptedMessage);
        }
        // restart: the offset was refused. Once, from zero.
        if (restarted) return DownloadOutcome.failed(kDownloadInterruptedMessage);
        restarted = true;
        await _tryDelete(part);
        have = 0;
      }
    }

    if (cancel?.isCancelled ?? false) return DownloadOutcome.cancelled;

    final length = await part.length();
    if (asset.size > 0 && length != asset.size) {
      logUpdate('size mismatch: got $length, expected ${asset.size}');
      await _tryDelete(part);
      return DownloadOutcome.corrupt;
    }

    onVerifying?.call();
    if (asset.sha256.isNotEmpty) {
      final actual = await sha256Of(part);
      if (actual != asset.sha256.toLowerCase()) {
        logUpdate('checksum mismatch: $actual');
        await _tryDelete(part);
        return DownloadOutcome.corrupt;
      }
    }

    try {
      await part.rename(target.path);
    } catch (e) {
      logUpdate('rename failed: $e');
      return DownloadOutcome.failed('The update could not be saved on this phone.');
    }
    return DownloadOutcome.completed(target);
  }

  Future<_Transfer> _transfer({
    required Uri uri,
    required File part,
    required int have,
    required ReleaseAsset asset,
    required void Function(DownloadProgress)? onProgress,
    required CancelToken? cancel,
  }) async {
    final request = http.Request('GET', uri)
      ..headers.addAll({
        'User-Agent': kUpdateUserAgent,
        'Accept': 'application/octet-stream',
        'Accept-Encoding': 'identity',
        if (have > 0) 'Range': 'bytes=$have-',
      });

    final http.StreamedResponse res;
    try {
      res = await _http.send(request).timeout(connectTimeout);
    } catch (e) {
      logUpdate('connect failed: $e');
      return _Transfer(_Step.failed, looksOffline(e) ? kOfflineMessage : kDownloadInterruptedMessage);
    }

    if (cancel?.isCancelled ?? false) {
      await _drain(res);
      return const _Transfer(_Step.cancelled);
    }

    var start = have;
    var append = false;
    var serverTotal = 0;
    switch (res.statusCode) {
      case 206:
        final range = _header(res.headers, 'content-range');
        final m = range == null ? null : _contentRange.firstMatch(range.trim());
        if (m != null) {
          if (int.parse(m.group(1)!) != have) {
            await _drain(res);
            return const _Transfer(_Step.restart);
          }
          final t = m.group(3)!;
          if (t != '*') serverTotal = int.parse(t);
        } else if (res.contentLength != null) {
          serverTotal = have + res.contentLength!;
        }
        append = have > 0;
      case 200:
        // The whole file from byte 0: either a first download, or a server
        // that ignored our Range. Either way the old bytes are not wanted.
        start = 0;
        serverTotal = res.contentLength ?? 0;
      case 416:
        await _drain(res);
        return have > 0
            ? const _Transfer(_Step.restart)
            : const _Transfer(_Step.failed, kDownloadInterruptedMessage);
      case 404 || 410:
        await _drain(res);
        return const _Transfer(_Step.failed, 'This update is no longer available.');
      default:
        await _drain(res);
        return const _Transfer(_Step.failed, kDownloadInterruptedMessage);
    }

    final total = asset.size > 0 ? asset.size : serverTotal;
    final meter = SpeedMeter()..add(_now(), start);
    void emit(int received) {
      if (onProgress == null) return;
      final speed = meter.add(_now(), received);
      final remaining = total > received ? total - received : 0;
      onProgress(DownloadProgress(
        received: received,
        total: total,
        bytesPerSecond: speed,
        etaSeconds: speed > 0 && total > 0 ? (remaining / speed).ceil() : null,
      ));
    }

    RandomAccessFile? raf;
    final it = StreamIterator<List<int>>(res.stream);
    if (cancel != null) unawaited(cancel.onCancel.then((_) => it.cancel()));
    var received = start;
    _Transfer result = const _Transfer(_Step.done);
    try {
      raf = await part.open(mode: append ? FileMode.append : FileMode.write);
      emit(received);
      while (!(cancel?.isCancelled ?? false)) {
        final bool more;
        try {
          more = await it.moveNext().timeout(idleTimeout);
        } on TimeoutException {
          result = const _Transfer(_Step.failed, kDownloadInterruptedMessage);
          break;
        }
        if (!more) break;
        if (cancel?.isCancelled ?? false) break;
        final chunk = it.current;
        await raf.writeFrom(chunk);
        received += chunk.length;
        emit(received);
      }
      if (result.step == _Step.done && (cancel?.isCancelled ?? false)) {
        result = const _Transfer(_Step.cancelled);
      }
    } catch (e) {
      logUpdate('transfer interrupted: $e');
      result = _Transfer(
        _Step.failed,
        looksOffline(e) ? kOfflineMessage : kDownloadInterruptedMessage,
      );
    } finally {
      try {
        await it.cancel();
      } catch (_) {}
      try {
        await raf?.flush();
        await raf?.close();
      } catch (_) {}
    }
    return result;
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name) return e.value;
    }
    return null;
  }

  /// Reads and discards a response body so its connection can be reused.
  Future<void> _drain(http.StreamedResponse res) async {
    try {
      await res.stream.drain<void>().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> _tryDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
