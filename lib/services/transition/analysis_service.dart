// lib/services/transition/analysis_service.dart
//
// Finds out what AutoMix needs to know about a song, once, and remembers it.
//
//   request(id) -> [already known?] -> [saved?] -> get the audio -> decode ->
//   analyse (isolate) -> save -> tell the engine
//
// ONE AT A TIME, at the pace of a background job: a decode is a few hundred ms
// of CPU and an analysis another 200 ms, and nothing here is worth a dropped
// frame in the animation the listener is looking at.
//
// WHAT IT WILL NOT DO, by default
//   * spend mobile data - a song is a few MB, so over cellular it waits for the
//     listener to allow it (TransitionSettings.analyzeOnCellular)
//   * run offline, in low-data mode, or when AutoMix is off
//   * retry a song that failed, for ten minutes (a region-locked or damaged
//     file would otherwise be fetched on every tick of the engine)
//
// Everything platform-shaped (the decoder, the download, the isolate, the
// database) is injected, so the logic is tested without a device.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'audio_analyzer.dart';
import 'track_analysis.dart';

/// Where the audio of a song can be read from.
class AnalysisSource {
  const AnalysisSource.file(String this.path)
      : url = null,
        headers = null,
        cacheTo = null;
  const AnalysisSource.network(String this.url, {this.headers, this.cacheTo})
      : path = null;

  final String? path;
  final String? url;
  final Map<String, String>? headers;

  /// Where the player keeps a finished copy of this song. If the analysis has
  /// to download the song anyway, it downloads it THERE - when nothing else is
  /// writing that file and the download is provably whole - and the player then
  /// plays that copy instead of fetching the song a second time.
  final String? cacheTo;

  bool get isLocal => path != null;
}

typedef AnalysisLocator = Future<AnalysisSource?> Function(String trackId);

/// The decoded audio the analyser works on: the mid ((L+R)/2) that beats and
/// levels are read from, and the side ((L-R)/2) the loudness meter needs.
class DecodedAudio {
  const DecodedAudio(this.mid, [this.side]);
  final Int16List mid;
  final Int16List? side;
}

/// The audio of the file at [path], or null if it cannot be decoded.
typedef AnalysisDecoder = Future<DecodedAudio?> Function(String path, int rate);

/// Copies [source] to a local file and returns its path (the caller deletes it).
typedef AnalysisFetcher = Future<String?> Function(AnalysisSource source);

typedef AnalysisRunner = Future<TrackAnalysis> Function(AnalysisInput input);

/// Whether this device may spend mobile data on analysis right now.
typedef NetworkPolicy = Future<bool> Function({required bool allowCellular});

// ── Storage ─────────────────────────────────────────────────────────────────

abstract class AnalysisStore {
  Future<TrackAnalysis?> read(String trackId);
  Future<void> write(TrackAnalysis analysis);
}

class MemoryAnalysisStore implements AnalysisStore {
  final Map<String, TrackAnalysis> _rows = <String, TrackAnalysis>{};

  @override
  Future<TrackAnalysis?> read(String trackId) async => _rows[trackId];

  @override
  Future<void> write(TrackAnalysis analysis) async =>
      _rows[analysis.trackId] = analysis;
}

/// One row per song, newest kept. A result is ~3 KB (the beat list dominates),
/// so a thousand songs are a few MB.
class SqfliteAnalysisStore implements AnalysisStore {
  SqfliteAnalysisStore({this.maxRows = 1000});

  final int maxRows;
  static const String _file = 'track_analysis_v1.db';
  static const String _table = 'track_analysis';

  Future<Database>? _db;
  int _writes = 0;

  Future<Database> _open() => _db ??= () async {
        final dir = await getDatabasesPath();
        return openDatabase(
          p.join(dir, _file),
          version: 1,
          onCreate: (db, _) => db.execute('CREATE TABLE $_table('
              'track_id TEXT PRIMARY KEY, duration_ms INTEGER NOT NULL, '
              'json TEXT NOT NULL, updated INTEGER NOT NULL)'),
        );
      }();

  @override
  Future<TrackAnalysis?> read(String trackId) async {
    try {
      final db = await _open();
      final rows = await db.query(_table,
          columns: ['json'], where: 'track_id = ?', whereArgs: [trackId], limit: 1);
      if (rows.isEmpty) return null;
      return TrackAnalysis.decode(rows.first['json']! as String);
    } catch (e) {
      if (kDebugMode) debugPrint('AnalysisStore: read failed: $e');
      return null;
    }
  }

  @override
  Future<void> write(TrackAnalysis analysis) async {
    try {
      final db = await _open();
      await db.insert(
        _table,
        {
          'track_id': analysis.trackId,
          'duration_ms': analysis.durationMs,
          'json': analysis.encode(),
          'updated': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (++_writes % 50 == 0) {
        await db.execute('DELETE FROM $_table WHERE track_id NOT IN '
            '(SELECT track_id FROM $_table ORDER BY updated DESC LIMIT $maxRows)');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AnalysisStore: write failed: $e');
    }
  }
}

// ── Platform pieces ─────────────────────────────────────────────────────────

class AnalysisPlatform {
  const AnalysisPlatform._();

  static const MethodChannel _channel = MethodChannel('mine_music/audio_decode');

  /// Only Android has a decoder wired up so far.
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<DecodedAudio?> decode(String path, int rate) async {
    if (!supported) return null;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('decode', {
        'path': path,
        'rate': rate,
        'maxSeconds': AnalysisService.maxSongMs ~/ 1000,
        'channels': 2,
      });
      if (bytes == null || bytes.lengthInBytes < 2) return null;
      // Interleaved little-endian 16-bit left/right; every platform Flutter runs
      // on is little-endian, so the bytes ARE the samples. The channel hands back
      // a view that may start on an odd offset, which an Int16List cannot sit on,
      // so take one copy to a fresh, aligned buffer.
      final aligned = Uint8List.fromList(bytes);
      final st = Int16List.view(aligned.buffer, 0, aligned.lengthInBytes ~/ 2);
      final frames = st.length ~/ 2;
      final mid = Int16List(frames);
      final side = Int16List(frames);
      for (var i = 0; i < frames; i++) {
        final l = st[2 * i];
        final r = st[2 * i + 1];
        mid[i] = (l + r) >> 1;
        side[i] = (l - r) >> 1;
      }
      return DecodedAudio(mid, side);    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('AnalysisPlatform: decode failed: ${e.message}');
      return null;
    }
  }

  /// A song is 3-6 MB; anything past this is not a song.
  static const int maxBytes = 48 * 1024 * 1024;

  static Future<String?> fetch(AnalysisSource source) async {
    final url = source.url;
    if (url == null) return source.path;

    final shared = source.cacheTo;
    final shareable = shared != null &&
        !File(shared).existsSync() &&
        !File('$shared.part').existsSync();
    final dir = await getTemporaryDirectory();
    final target = shareable
        ? '$shared.analysis'
        : p.join(dir.path, 'automix_${DateTime.now().microsecondsSinceEpoch}.audio');
    final cancel = CancelToken();
    try {
      final response = await Dio().download(
        url,
        target,
        cancelToken: cancel,
        options: Options(
          // The stream servers expect a range request, as the player makes.
          headers: <String, String>{'Range': 'bytes=0-', ...?source.headers},
          receiveTimeout: const Duration(seconds: 40),
          sendTimeout: const Duration(seconds: 15),
        ),
        onReceiveProgress: (received, total) {
          if (received > maxBytes || total > maxBytes) cancel.cancel('too large');
        },
      );
      if (shareable) {
        // Promote it to the player's cache only if it is provably the whole
        // song: the server said how long the body was and that is what arrived.
        // A truncated file under the cache's final name would play as a song
        // that ends early.
        final expected =
            int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '');
        final got = await File(target).length();
        if (expected != null &&
            expected == got &&
            got > 100000 &&
            !File(shared).existsSync() &&
            !File('$shared.part').existsSync()) {
          await File(target).rename(shared);
          return shared;
        }
      }
      return target;
    } catch (e) {
      if (kDebugMode) debugPrint('AnalysisPlatform: fetch failed: $e');
      await _delete(target);
      return null;
    }
  }
  static Future<void> _delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<bool> networkAllowed({required bool allowCellular}) async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        return true;
      }
      return allowCellular && results.contains(ConnectivityResult.mobile);
    } catch (_) {
      return false;
    }
  }
}

// ── The service ─────────────────────────────────────────────────────────────

class AnalysisService {
  AnalysisService({
    required this.locate,
    required this.isEnabled,
    required this.allowCellular,
    required this.onResult,
    AnalysisStore? store,
    AnalysisDecoder? decode,
    AnalysisFetcher? fetch,
    AnalysisRunner? run,
    NetworkPolicy? network,
    bool? supported,
    DateTime Function()? now,
    this.cooldown = const Duration(minutes: 10),
    this.maxKnown = 200,
  })  : store = store ?? SqfliteAnalysisStore(),
        _decode = decode ?? AnalysisPlatform.decode,
        _fetch = fetch ?? AnalysisPlatform.fetch,
        _run = run ?? ((input) => compute(analyzeInput, input)),
        _network = network ?? AnalysisPlatform.networkAllowed,
        _supported = supported ?? AnalysisPlatform.supported,
        _now = now ?? DateTime.now;

  final AnalysisLocator locate;
  final bool Function() isEnabled;
  final bool Function() allowCellular;

  /// A result landed (the engine re-plans).
  final void Function() onResult;

  final AnalysisStore store;
  final AnalysisDecoder _decode;
  final AnalysisFetcher _fetch;
  final AnalysisRunner _run;
  final NetworkPolicy _network;
  final bool _supported;
  final DateTime Function() _now;
  final Duration cooldown;
  final int maxKnown;

  /// Longer than this is not a song (a DJ set, a podcast, an audiobook chapter):
  /// the decode alone would hold ~90 MB of samples, and there is no transition
  /// to plan into the end of one.
  static const int maxSongMs = 12 * 60 * 1000;

  // Insertion-ordered: the oldest is first.
  final LinkedHashMap<String, TrackAnalysis> _known =
      LinkedHashMap<String, TrackAnalysis>();
  final Map<String, DateTime> _failed = <String, DateTime>{};
  final Queue<_Job> _queue = Queue<_Job>();
  final Set<String> _pending = <String>{};
  bool _running = false;
  bool _disposed = false;

  /// Songs analysed in this session (for tests and diagnostics).
  int analysed = 0;

  /// What is known about [trackId], right now, without waiting for anything.
  TrackAnalysis? lookup(String trackId, int durationMs) {
    final a = _known[trackId];
    if (a == null || !a.isUsable || !a.matchesDuration(durationMs)) return null;
    return a;
  }

  /// Ask for [trackId] to be analysed. Cheap and idempotent: the engine calls
  /// it on every tick.
  void request(String trackId, {int durationMs = 0}) {
    if (_disposed || !_supported || !isEnabled()) return;
    if (lookup(trackId, durationMs) != null) return;
    if (_pending.contains(trackId)) return;
    final failedAt = _failed[trackId];
    if (failedAt != null && _now().difference(failedAt) < cooldown) return;
    _pending.add(trackId);
    _queue.add(_Job(trackId, durationMs));
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final job = _queue.removeFirst();
        try {
          await _work(job);
        } catch (e) {
          _fail(job.id, 'unexpected: $e');
        } finally {
          _pending.remove(job.id);
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _work(_Job job) async {
    if (!isEnabled()) return; // switched off while it waited

    // Saved from an earlier session.
    final saved = await store.read(job.id);
    if (saved != null && saved.isUsable && saved.matchesDuration(job.durationMs)) {
      _remember(saved);
      onResult();
      return;
    }

    if (job.durationMs > maxSongMs) return _fail(job.id, 'too long to be a song');

    final source = await locate(job.id);
    if (source == null) return; // not known right now; the engine will ask again
    if (!source.isLocal &&
        !await _network(allowCellular: allowCellular())) {
      return; // metered or offline: wait, do not remember it as a failure
    }
    if (!isEnabled() || _disposed) return;

    String? path;
    var temporary = false;
    try {
      if (source.isLocal) {
        path = source.path;
      } else {
        path = await _fetch(source);
        // Anything but the player's own cache copy is ours to delete.
        temporary = path != source.cacheTo;
      }
      if (path == null) return _fail(job.id, 'no audio');

      final audio = await _decode(path, AudioAnalyzer.sampleRate);
      if (audio == null || audio.mid.isEmpty) {
        return _fail(job.id, 'undecodable');
      }

      final decodedMs = audio.mid.length * 1000 ~/ AudioAnalyzer.sampleRate;
      final analysis = await _run(AnalysisInput(
        pcm: audio.mid,
        side: audio.side,
        trackId: job.id,
        durationMs: job.durationMs > 0 ? job.durationMs : decodedMs,
      ));
      if (_disposed) return;
      analysed++;
      _failed.remove(job.id);
      _remember(analysis);
      await store.write(analysis);
      onResult();
    } finally {
      if (temporary && path != null) await AnalysisPlatform._delete(path);
    }
  }

  void _remember(TrackAnalysis a) {
    _known.remove(a.trackId);
    _known[a.trackId] = a;
    while (_known.length > maxKnown) {
      _known.remove(_known.keys.first);
    }
  }

  void _fail(String id, String why) {
    _failed[id] = _now();
    if (kDebugMode) debugPrint('AnalysisService: $id: $why');
  }

  void dispose() {
    _disposed = true;
    _queue.clear();
  }
}

class _Job {
  const _Job(this.id, this.durationMs);
  final String id;
  final int durationMs;
}
