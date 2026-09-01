import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/track.dart';

String _jsonEncodeData(Object data) => jsonEncode(data);
List<dynamic> _jsonDecodeData(String s) => jsonDecode(s) as List<dynamic>;

/// Owns the download engine: file IO, metadata persistence, progress,
/// concurrency limit, queue and cancellation.
///
/// The [MusicProvider] remains the façade the UI talks to; this manager holds
/// the state. Business hooks are injected so the manager never reaches into
/// playback or network internals:
///  - [resolveStreamForTrack] converts + resolves a playable URL.
///  - [onMessage] reports user-facing status strings.
///  - [onTransientFailure] lets the provider enqueue its generic retry op.
///  - [isOffline] / [isConnected] gate when downloads may run.
///  - [stopActiveTrack] is invoked before deleting a currently playing file.
///  - [removeLocalTrackByPath] keeps the local-music list in sync when a
///    downloaded file disappears on disk.
///  - [artworkRecoveryPath] lets the palette engine recover legacy artwork.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.resolveStreamForTrack,
    required this.onMessage,
    required this.onTransientFailure,
    required this.isOffline,
    required this.isConnected,
    required this.stopActiveTrack,
    required this.removeLocalTrackByPath,
  });

  static const String _metadataKey = 'downloadedTracks';
  static const int _maxConcurrent = 6;
  static const int _minValidFileBytes = 50 * 1024;
  static const Duration _progressThrottle = Duration(milliseconds: 250);

  final Future<ResolvedDownload?> Function(Track track) resolveStreamForTrack;
  final void Function(String message) onMessage;
  final void Function(String description, Future<void> Function() retry)
      onTransientFailure;
  final bool Function() isOffline;
  final bool Function() isConnected;
  final Future<void> Function(String trackId) stopActiveTrack;
  final void Function(String expectedPath) removeLocalTrackByPath;

  final Map<String, double> _downloadProgress = {};
  final Map<String, DateTime> _lastProgressNotify = {};
  final Map<String, bool> _isDownloading = {};
  final List<Track> _currentlyDownloadingTracks = [];
  final Map<String, CancelToken> _downloadCancelTokens = {};
  int _concurrentDownloads = 0;
  final List<Track> _downloadQueue = [];
  Map<String, Map<String, dynamic>> _metadata = {};
  List<Track>? _downloadedTracksCache;

  Map<String, double> get downloadProgress => Map.unmodifiable(_downloadProgress);
  Map<String, bool> get isDownloading => Map.unmodifiable(_isDownloading);
  List<Track> get currentlyDownloadingTracks =>
      List.unmodifiable(_currentlyDownloadingTracks);
  List<Track> get downloadQueue => List.unmodifiable(_downloadQueue);
  Map<String, Map<String, dynamic>> get metadata => _metadata;
  bool isDownloadingSync(String trackId) => _isDownloading[trackId] == true;
  bool isDownloadedMetadataSync(String trackId) =>
      _metadata.containsKey(trackId);

  // --- Directory layout -----------------------------------------------------

  Future<Directory> getDownloadsDirectory() async {
    final d = await getApplicationSupportDirectory();
    final dl = Directory('${d.path}/offline_music');
    if (!await dl.exists()) await dl.create(recursive: true);
    return dl;
  }

  Future<String> _buildDownloadFilePath(String trackId) async =>
      '${(await getDownloadsDirectory()).path}/$trackId.mp3';

  Future<String> _buildArtDownloadPath(String trackId) async =>
      '${(await getDownloadsDirectory()).path}/$trackId.jpg';

  // --- Persistence ----------------------------------------------------------

  Future<void> loadMetadata() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_metadataKey);
      if (s != null) {
        final l = await compute(_jsonDecodeData, s);
        final dDir = await getDownloadsDirectory();

        _metadata = {};
        for (var i in l) {
          if (i['id'] != null && i['filePath'] != null && i['track'] != null) {
            String storedPath = i['filePath'];
            String id = i['id'];

            // Normalize path if it doesn't exist at stored location but exists
            // in the current downloads directory.
            String finalPath = storedPath;
            if (!await File(storedPath).exists()) {
              final filename = storedPath.split('/').last;
              final currentPath = '${dDir.path}/$filename';
              if (await File(currentPath).exists()) {
                if (kDebugMode) {
                  debugPrint("DownloadManager: Corrected path for $id: $storedPath -> $currentPath");
                }
                finalPath = currentPath;
              }
            }

            _metadata[id] = {
              'track': Track.fromJson(Map<String, dynamic>.from(i['track'] as Map)),
              'filePath': finalPath,
              'artPath': i['artPath'] as String?,
              'downloadDate': i['downloadDate'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(i['downloadDate'])
                  : null
            };
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("DownloadManager: Error loading download metadata: $e");
      _metadata = {};
    }
  }

  Future<void> saveMetadata() => _saveMetadataInternal();

  Future<void> _saveMetadataInternal() async {
    final l = _metadata.values
        .map((m) => {
              'id': (m['track'] as Track).id,
              'filePath': m['filePath'],
              'artPath': m['artPath'],
              'downloadDate':
                  (m['downloadDate'] as DateTime?)?.millisecondsSinceEpoch,
              'track': (m['track'] as Track).toJson()
            })
        .toList();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_metadataKey, await compute(_jsonEncodeData, l));
    } catch (e) {
      onTransientFailure('Save dl meta', _saveMetadataInternal);
    }
  }

  void _invalidateCache() => _downloadedTracksCache = null;

  // --- Core operations ------------------------------------------------------

  Future<void> downloadTrack(Track track) async {
    final id = track.id;
    if (await isTrackDownloaded(id)) {
      onMessage("${track.trackName} downloaded.");
      return;
    }
    if (_isDownloading[id] == true) {
      onMessage("${track.trackName} downloading.");
      return;
    }
    if (track.source == 'local') {
      onMessage("Cannot download local files.");
      return;
    }
    if (isOffline() || !isConnected()) {
      onMessage('Offline: Cannot download.');
      return;
    }
    if (_concurrentDownloads >= _maxConcurrent) {
      _addToQueue(track);
      return;
    }
    await _runDownload(track);
  }

  Future<void> _runDownload(Track track) async {
    final id = track.id;
    CancelToken cT = CancelToken();
    _isDownloading[id] = true;
    _downloadProgress[id] = 0.0;
    _downloadCancelTokens[id] = cT;
    _concurrentDownloads++;
    if (!_currentlyDownloadingTracks.any((t) => t.id == id)) {
      _currentlyDownloadingTracks.add(track);
    }
    notifyListeners();

    String fP = '';
    try {
      final resolved = await resolveStreamForTrack(track);
      final sUrl = resolved?.url;
      if (sUrl == null) throw Exception('No downloadable stream found.');

      fP = await _buildDownloadFilePath(id);

      // Download artwork simultaneously (if available)
      String aP = '';
      if (track.albumArtUrl.isNotEmpty) {
        aP = await _buildArtDownloadPath(id);
        try {
          await _downloadWithProgress(track.albumArtUrl, aP, cT, id);
        } catch (e) {
          if (kDebugMode) debugPrint('DownloadManager: Art download failed: $e');
          aP = ''; // Fallback to network if local art fails
        }
      }

      await _downloadWithProgress(sUrl, fP, cT, id);

      if (!cT.isCancelled) {
        // Validate file size before saving metadata
        final file = File(fP);
        if (await file.exists() && await file.length() > _minValidFileBytes) {
          _metadata[id] = {
            'track': track,
            'filePath': fP,
            'artPath': aP,
            'downloadDate': DateTime.now()
          };
          await saveMetadata();
          _invalidateCache();
          onMessage("${track.trackName} downloaded.");
        } else {
          // File too small or missing - likely an error page or empty
          if (await file.exists()) await file.delete();
          throw Exception("Download failed: File corrupt or too small.");
        }
      } else {
        onMessage("${track.trackName} cancelled.");
        if (fP.isNotEmpty) {
          try {
            final f = File(fP);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      if (!cT.isCancelled) {
        onMessage('Download failed: ${track.trackName}');
        if (fP.isNotEmpty) {
          try {
            final f = File(fP);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
        bool retry = e is DioException &&
            [
              DioExceptionType.connectionTimeout,
              DioExceptionType.sendTimeout,
              DioExceptionType.receiveTimeout,
              DioExceptionType.connectionError,
              DioExceptionType.unknown
            ].contains(e.type);
        if (retry) {
          onTransientFailure('Download: ${track.trackName}',
              () => downloadTrack(track));
        }
      }
    } finally {
      if (_isDownloading.containsKey(id)) {
        _isDownloading.remove(id);
        _downloadProgress.remove(id);
        _downloadCancelTokens.remove(id);
        _currentlyDownloadingTracks.removeWhere((t) => t.id == id);
        _concurrentDownloads = max(0, _concurrentDownloads - 1);
      }
      notifyListeners();
      _processQueue();
    }
  }

  Future<void> _downloadWithProgress(
      String url, String savePath, CancelToken cT, String id) {
    return _dio.download(url, savePath, cancelToken: cT,
        onReceiveProgress: (received, total) {
      if (total > 0 && _isDownloading[id] == true) {
        _downloadProgress[id] = received / total;
        final now = DateTime.now();
        if (!_lastProgressNotify.containsKey(id) ||
            now.difference(_lastProgressNotify[id]!) >= _progressThrottle) {
          _lastProgressNotify[id] = now;
          notifyListeners();
        }
      }
    });
  }

  void cancelDownload(String trackId) {
    _downloadQueue.removeWhere((t) => t.id == trackId);
    _downloadCancelTokens[trackId]?.cancel('Cancelled by user.');
  }

  Future<void> deleteDownloadedTrack(String trackId) async {
    final meta = _metadata[trackId];
    if (meta == null) {
      onMessage("Not downloaded.");
      return;
    }
    final fp = meta['filePath'] as String?;
    final ap = meta['artPath'] as String?;
    final tn = (meta['track'] as Track?)?.trackName ?? '?';
    try {
      await stopActiveTrack(trackId);
      if (fp != null) {
        final f = File(fp);
        if (await f.exists()) await f.delete();
      }
      if (ap != null) {
        final af = File(ap);
        if (await af.exists()) await af.delete();
      }
      _metadata.remove(trackId);
      await saveMetadata();
      _invalidateCache();
      onMessage("Removed $tn.");
    } catch (_) {
      onMessage('Failed to delete $tn.');
    } finally {
      notifyListeners();
    }
  }

  Future<bool> isTrackDownloaded(String trackId) async {
    final meta = _metadata[trackId];
    if (meta != null) {
      final p = meta['filePath'] as String?;
      if (p != null && p.isNotEmpty) {
        if (await File(p).exists()) {
          // Also check file size to ensure it's not a corrupt/empty file
          if (await File(p).length() > _minValidFileBytes) {
            return true;
          } else {
            if (kDebugMode) {
              debugPrint("DownloadManager: Found downloaded file for $trackId but it's too small. Treating as missing.");
            }
            await handleMissingFile(trackId, p);
            return false;
          }
        } else {
          await handleMissingFile(trackId, p);
          return false;
        }
      }
    }
    return false;
  }

  Future<String?> getDownloadedTrackPath(String trackId) async {
    if (await isTrackDownloaded(trackId)) {
      return _metadata[trackId]?['filePath'] as String?;
    }
    return null;
  }

  Future<List<Track>> getDownloadedTracks() async {
    // Cached: FutureBuilders call this on every tab re-entry; each uncached
    // call costs one disk stat per downloaded track.
    final cached = _downloadedTracksCache;
    if (cached != null) return cached;
    List<String> missing = [];
    for (var e in _metadata.entries) {
      final p = e.value['filePath'] as String?;
      if (p == null || !(await File(p).exists())) missing.add(e.key);
    }
    if (missing.isNotEmpty) {
      for (var id in missing) {
        _metadata.remove(id);
      }
      await _saveMetadataInternal();
      _invalidateCache();
      notifyListeners();
    }
    final result = _metadata.values
        .where((m) => m['track'] is Track)
        .map((m) => m['track'] as Track)
        .toList();
    _downloadedTracksCache = result;
    return result;
  }

  Future<void> handleMissingFile(String trackId, String expectedPath) async {
    bool mRem = _metadata.remove(trackId) != null;
    if (mRem) await _saveMetadataInternal();
    _invalidateCache();
    removeLocalTrackByPath(expectedPath);
    if (mRem) notifyListeners();
  }

  void _addToQueue(Track track) {
    if (_isDownloading[track.id] == true ||
        _downloadQueue.any((t) => t.id == track.id) ||
        _metadata.containsKey(track.id)) {
      return;
    }
    _downloadQueue.add(track);
    onMessage('${track.trackName} queued.');
    notifyListeners();
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_downloadQueue.isEmpty ||
        isOffline() ||
        !isConnected() ||
        _concurrentDownloads >= _maxConcurrent) {
      return;
    }
    final t = _downloadQueue.removeAt(0);
    notifyListeners();
    await downloadTrack(t);
  }

  /// Kick the queue after connectivity/offline state changes.
  void processQueue() => _processQueue();

  void pauseAllDownloads({bool clearQueue = false}) {
    final ids = List<String>.from(_downloadCancelTokens.keys);
    int c = 0;
    for (final id in ids) {
      _downloadCancelTokens[id]?.cancel("Downloads paused");
      c++;
    }
    if (c > 0) debugPrint("Paused $c downloads.");
    if (clearQueue && _downloadQueue.isNotEmpty) {
      _downloadQueue.clear();
      notifyListeners();
    }
  }

  /// Network downloader — kept internal to the manager. Retries live at the
  /// call sites via [onTransientFailure]; a plain single-pass download with
  /// progress + cancellation is sufficient here because resumable retry is
  /// handled by re-invoking [downloadTrack].
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(seconds: 30),
    ),
  );
}

/// Resolved stream for a download job.
class ResolvedDownload {
  final String url;
  final String? userAgent;
  const ResolvedDownload({required this.url, this.userAgent});
}
