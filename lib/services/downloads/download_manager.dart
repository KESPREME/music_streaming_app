import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/track.dart';
import 'chunked_downloader.dart';

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
    this.cachedStreamFile,
    this.onStaleStream,
    ChunkedDownloader? downloader,
    Future<Directory> Function()? baseDirectory,
  })  : _downloader = downloader ?? ChunkedDownloader(),
        _baseDirectory = baseDirectory ?? getApplicationSupportDirectory;

  /// The finished streaming-cache file of a song, if it has been played
  /// through: copied instead of downloaded again.
  final Future<String?> Function(String trackId)? cachedStreamFile;

  /// A resolved URL turned out to be expired (403/410): forget it so the next
  /// resolve gets a fresh one.
  final void Function(String streamId)? onStaleStream;

  final ChunkedDownloader _downloader;
  final Future<Directory> Function() _baseDirectory;

  static const String _metadataKey = 'downloadedTracks';

  /// Files at once. Each one uses [ChunkedDownloader.connections] connections,
  /// so 3 is already 12 parallel ranges.
  static const int _maxConcurrent = 3;
  static const int _minValidFileBytes = 50 * 1024;
  static const Duration _progressThrottle = Duration(milliseconds: 200);

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
    final d = await _baseDirectory();
    final dl = Directory('${d.path}/offline_music');
    if (!await dl.exists()) await dl.create(recursive: true);
    return dl;
  }

  Future<String> _buildDownloadFilePath(String trackId) async =>
      // `.mp3` whatever the container (it is usually m4a/opus): kept because
      // existing downloads and the legacy artwork lookup rely on the name, and
      // the player identifies the format from the bytes, not the extension.
      '${(await getDownloadsDirectory()).path}/$trackId.mp3';

  Future<String> _buildArtDownloadPath(String trackId) async =>
      '${(await getDownloadsDirectory()).path}/$trackId.jpg';

  // --- Persistence ----------------------------------------------------------

  Future<void> loadMetadata() async {
    unawaited(_sweepStalePartials());
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

  /// Pieces of downloads that never finished (the app was closed and the song
  /// was not downloaded again) are kept for a resume, but not forever.
  Future<void> _sweepStalePartials() async {
    try {
      final dir = await getDownloadsDirectory();
      final cutoff = DateTime.now().subtract(const Duration(days: 3));
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.contains('.part') && !name.endsWith('.tmp')) continue;
        if ((await e.stat()).modified.isBefore(cutoff)) await e.delete();
      }
    } catch (_) {}
  }

  // --- Core operations ------------------------------------------------------

  Future<void> downloadTrack(Track track) async {
    final id = track.id;
    if (_isDownloading[id] == true) {
      onMessage("${track.trackName} downloading.");
      return;
    }
    if (track.source == 'local') {
      onMessage("Cannot download local files.");
      return;
    }
    // Only a song with metadata can already be downloaded; checking its file
    // is the one await, and it is skipped for new songs so the slot below is
    // taken in the same turn (a batch never overfills the limit).
    if (_metadata.containsKey(id)) {
      if (await isTrackDownloaded(id)) {
        onMessage("${track.trackName} downloaded.");
        return;
      }
      if (_isDownloading[id] == true) return;
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

  /// Downloads paused by a dropped connection: their finished ranges are kept
  /// and they go back to the front of the queue (a user cancel discards).
  final Set<String> _pausedIds = {};

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
      fP = await _buildDownloadFilePath(id);

      // Artwork in parallel and off the progress bar: it is a few KB and must
      // never hold up, or be mistaken for, the song.
      final art = _downloadArtwork(track, cT);

      // Played all the way through already: the streaming cache has every
      // byte. Copy it instead of fetching the song again.
      final cached = await cachedStreamFile?.call(id);
      if (cached != null && await File(cached).exists()) {
        await File(cached).copy('$fP.tmp');
        if (await File(fP).exists()) await File(fP).delete();
        await File('$fP.tmp').rename(fP);
        _setProgress(id, 1);
      } else {
        await _transfer(track, fP, cT);
      }

      final aP = await art;
      if (cT.isCancelled) throw const DownloadCancelled();

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
    } catch (e) {
      final paused = _pausedIds.remove(id);
      if (paused) {
        // Connection dropped: keep the finished ranges, resume first.
        if (!_downloadQueue.any((t) => t.id == id)) _downloadQueue.insert(0, track);
      } else if (cT.isCancelled || e is DownloadCancelled) {
        onMessage("${track.trackName} cancelled.");
        if (fP.isNotEmpty) await ChunkedDownloader.discardPartial(fP);
      } else {
        onMessage('Download failed: ${track.trackName}');
        final transient = e is SocketException ||
            e is TimeoutException ||
            e is HttpException ||
            (e is DownloadHttpException && (e.status >= 500 || e.status == 429)) ||
            (e is DioException &&
                [
                  DioExceptionType.connectionTimeout,
                  DioExceptionType.sendTimeout,
                  DioExceptionType.receiveTimeout,
                  DioExceptionType.connectionError,
                  DioExceptionType.unknown
                ].contains(e.type));
        if (transient) {
          // Finished ranges stay on disk: the retry resumes, it does not
          // start over.
          onTransientFailure('Download: ${track.trackName}', () => downloadTrack(track));
        } else if (fP.isNotEmpty) {
          await ChunkedDownloader.discardPartial(fP);
        }
      }
    } finally {
      if (_isDownloading.containsKey(id)) {
        _isDownloading.remove(id);
        _downloadProgress.remove(id);
        _downloadCancelTokens.remove(id);
        _lastProgressNotify.remove(id);
        _currentlyDownloadingTracks.removeWhere((t) => t.id == id);
        _concurrentDownloads = max(0, _concurrentDownloads - 1);
      }
      notifyListeners();
      _processQueue();
    }
  }

  /// Resolves and fetches the song. An expired URL (403/410) is forgotten and
  /// resolved once more; the finished ranges are reused if the new URL is the
  /// same file.
  Future<void> _transfer(Track track, String path, CancelToken cT) async {
    for (var attempt = 0;; attempt++) {
      final resolved = await resolveStreamForTrack(track);
      final url = resolved?.url;
      if (url == null) throw Exception('No downloadable stream found.');
      if (cT.isCancelled) throw const DownloadCancelled();
      try {
        await _downloader.download(
          url: Uri.parse(url),
          path: path,
          userAgent: resolved!.userAgent,
          isCancelled: () => cT.isCancelled,
          onProgress: (received, total) {
            if (total > 0) _setProgress(track.id, received / total);
          },
        );
        return;
      } on DownloadHttpException catch (e) {
        if (!e.expired || attempt >= 1) rethrow;
        onStaleStream?.call(resolved!.streamId ?? track.id);
      }
    }
  }

  Future<String> _downloadArtwork(Track track, CancelToken cT) async {
    if (track.albumArtUrl.isEmpty || !track.albumArtUrl.contains('://')) return '';
    try {
      final aP = await _buildArtDownloadPath(track.id);
      await _dio.download(track.albumArtUrl, aP, cancelToken: cT);
      return aP;
    } catch (e) {
      if (kDebugMode) debugPrint('DownloadManager: Art download failed: $e');
      return ''; // the network artwork is used instead
    }
  }

  void _setProgress(String id, double value) {
    if (_isDownloading[id] != true) return;
    _downloadProgress[id] = value.clamp(0.0, 1.0);
    final now = DateTime.now();
    final last = _lastProgressNotify[id];
    if (last == null || now.difference(last) >= _progressThrottle || value >= 1) {
      _lastProgressNotify[id] = now;
      notifyListeners();
    }
  }

  void cancelDownload(String trackId) {
    _downloadQueue.removeWhere((t) => t.id == trackId);
    _pausedIds.remove(trackId);
    _downloadCancelTokens[trackId]?.cancel('Cancelled by user.');
    notifyListeners();
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
    // Fill every free slot, not one per finished download.
    while (_downloadQueue.isNotEmpty &&
        !isOffline() &&
        isConnected() &&
        _concurrentDownloads < _maxConcurrent) {
      final t = _downloadQueue.removeAt(0);
      notifyListeners();
      final before = _concurrentDownloads;
      unawaited(downloadTrack(t));
      // downloadTrack takes its slot only after an await (the downloaded
      // check); stop here rather than overfill, the finishing download calls
      // back in.
      if (_concurrentDownloads == before) break;
    }
  }

  /// Kick the queue after connectivity/offline state changes.
  void processQueue() => _processQueue();

  void pauseAllDownloads({bool clearQueue = false}) {
    final ids = List<String>.from(_downloadCancelTokens.keys);
    for (final id in ids) {
      // Not a user cancel: keep what has been fetched and resume it first.
      if (!clearQueue) _pausedIds.add(id);
      _downloadCancelTokens[id]?.cancel("Downloads paused");
    }
    if (ids.isNotEmpty && kDebugMode) debugPrint("Paused ${ids.length} downloads.");
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

  /// The id the URL was resolved for (a Spotify song resolves to a YouTube
  /// id), so an expired URL can be forgotten.
  final String? streamId;
  const ResolvedDownload({required this.url, this.userAgent, this.streamId});
}
