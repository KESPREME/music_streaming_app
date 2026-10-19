// lib/services/local_music_service.dart
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart'; // Import device_info_plus
import '../models/track.dart';

class LocalMusicService {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  // MediaStore id of every scanned file, by path. Artwork is looked up by id.
  //
  // NEVER pass a `path:` to on_audio_query's song query: it pastes the path into
  // the SQL selection unescaped (`_data like '%<path>/%'`), so a file
  // named "Don't Stop.mp3" throws "Invalid token" inside a Kotlin coroutine
  // the Dart side cannot catch, and the app dies. (It also only matches
  // folders, so it never found the file anyway.)
  final Map<String, int> _idByPath = {};
  Future<void>? _indexing;

  // Thumbnail decoding is IO + bitmap work on the platform side: a screen full
  // of rows must not start 40 at once.
  static const int _maxArtworkJobs = 4;
  int _artworkJobs = 0;
  final List<Completer<void>> _artworkWaiters = [];

  void _remember(List<SongModel> songs) {
    for (final s in songs) {
      _idByPath[s.data] = s.id;
    }
  }

  /// Fills [_idByPath] from one unfiltered query (no SQL built from strings).
  Future<void> _ensureIndex() {
    if (_idByPath.isNotEmpty) return Future.value();
    return _indexing ??= _audioQuery
        .querySongs(uriType: UriType.EXTERNAL, ignoreCase: true)
        .then(_remember)
        .catchError((Object e) {
      if (kDebugMode) debugPrint('LocalMusicService: index failed: $e');
    }).whenComplete(() => _indexing = null);
  }

  Future<int?> _idFor(String path) async {
    final known = _idByPath[path];
    if (known != null) return known;
    await _ensureIndex();
    return _idByPath[path];
  }

  Future<bool> _requestPermissions() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      // Permissions likely not applicable or handled differently on web/desktop
      return true;
    }

    PermissionStatus status;
    List<Permission> permissionsToRequest = [];

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) { // Android 13+
        status = await Permission.audio.status;
        if (!status.isGranted) permissionsToRequest.add(Permission.audio);
      } else { // Android < 13
        status = await Permission.storage.status; // READ_EXTERNAL_STORAGE is implied
        if (!status.isGranted) permissionsToRequest.add(Permission.storage);
      }
    } else if (Platform.isIOS) {
      // For iOS, accessing media library (if needed beyond app's sandbox)
      status = await Permission.mediaLibrary.status;
      if(!status.isGranted) permissionsToRequest.add(Permission.mediaLibrary);
    }

    if (permissionsToRequest.isEmpty) {
      debugPrint("LocalMusicService: All necessary permissions already granted.");
      return true; // Already granted
    }

    debugPrint("LocalMusicService: Requesting permissions: ${permissionsToRequest.map((p) => p.toString()).toList()}");
    Map<Permission, PermissionStatus> statuses = await permissionsToRequest.request();

    // Check if all requested permissions were granted
    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!allGranted) {
      debugPrint("LocalMusicService: Permissions not granted. Statuses: $statuses");
      // Optionally open app settings if permanently denied
      statuses.forEach((permission, status) {
        if (status.isPermanentlyDenied) {
          // openAppSettings(); // Consider prompting user
          debugPrint("LocalMusicService: Permission ${permission.toString()} permanently denied.");
        }
      });
    } else {
      debugPrint("LocalMusicService: Permissions granted successfully.");
    }

    return allGranted;
  }

  // Fetch all local music using on_audio_query
  Future<List<Track>> fetchLocalMusicFromMediaStore() async {
    if (!await _requestPermissions()) {
      throw Exception('Storage/Media permission denied');
    }

    try {
      // Query songs, sorting by title by default
      List<SongModel> songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      debugPrint('LocalMusicService: Found ${songs.length} songs via MediaStore.');
      _idByPath.clear();
      _remember(songs);

      // Map SongModel to Track model
      List<Track> tracks = songs
          .where((song) =>
      song.isMusic == true && // Ensure it's marked as music
          song.duration != null && song.duration! > 10000 && // Filter out short sounds (e.g., > 10 seconds)
          (song.title.isNotEmpty && song.title != '<unknown>')) // Filter invalid titles
          .map((song) {
        return Track(
          id: song.data, // Use file path as unique ID for local files
          trackName: song.title,
          artistName: song.artist ?? 'Unknown Artist',
          albumName: song.album ?? 'Unknown Album',
          previewUrl: song.data, // Store file path for playback
          albumArtUrl: '', // Leave empty, artwork needs specific handling
          source: 'local',
          duration: Duration(milliseconds: song.duration ?? 0), // Map duration
        );
      }).toList();

      debugPrint('LocalMusicService: Mapped ${tracks.length} valid music tracks.');
      return tracks;

    } catch (e) {
      debugPrint('Error fetching local music from MediaStore: $e');
      rethrow; // Rethrow to allow provider/UI to handle
    }
  }

  // Pick a folder using file_picker
  Future<String?> pickDirectory() async {
    try {
      // Request permissions before picking if needed (though picker might also prompt)
      if (!await _requestPermissions()) return null;

      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        debugPrint("LocalMusicService: User selected directory: $selectedDirectory");
        // Inform the caller that a directory was selected.
        // On Android, MediaStore needs time or a trigger to index new files.
        // Returning the path allows the caller (MusicProvider) to trigger a rescan.
      }
      return selectedDirectory;
    } catch (e) {
      debugPrint('Error picking directory: $e');
      return null; // Return null on error
    }
  }

  // Pick a single music file using file picker
  Future<Track?> pickMusicFile() async {
    if (!await _requestPermissions()) return null;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
      );

      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        final file = File(result.files.first.path!);
        final path = file.path;

        // Metadata from MediaStore when the file is indexed (matched by path in
        // Dart; see the note on _idByPath for why never by `path:`).
        SongModel? song;
        try {
          final all = await _audioQuery.querySongs(uriType: UriType.EXTERNAL, ignoreCase: true);
          _remember(all);
          song = all.where((s) => s.data == path).firstOrNull;
        } catch (e) {
          debugPrint('LocalMusicService: metadata lookup failed: $e');
        }

        if (song != null) {
          return Track(
            id: path,
            trackName: song.title,
            artistName: song.artist ?? 'Unknown Artist',
            albumName: song.album ?? 'Unknown Album',
            previewUrl: path,
            albumArtUrl: '', // Placeholder
            source: 'local',
            duration: Duration(milliseconds: song.duration ?? 0),
          );
        } else {
          // Fallback: Basic info if metadata query fails
          debugPrint("LocalMusicService: Metadata query failed for picked file, using filename.");
          final fileName = result.files.first.name;
          final trackName = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
          return Track(
            id: path,
            trackName: trackName,
            artistName: 'Local File', // Indicate it's just from file
            albumName: 'Unknown Album',
            previewUrl: path,
            albumArtUrl: '',
            source: 'local',
            duration: null, // Duration unknown here
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error picking music file: $e');
      rethrow;
    }
  }

  // --- Static Helpers for Grouping and Sorting ---

  static Map<String, List<Track>> groupTracksByFolder(List<Track> tracks) {
    final Map<String, List<Track>> musicByFolder = {};
    for (final track in tracks) {
      try {
        // track.previewUrl holds the full path for local files
        final file = File(track.previewUrl);
        // Ensure parent directory exists before accessing path
        if (file.parent.existsSync()) {
          final folderPath = file.parent.path;
          final folderName = folderPath.split(Platform.pathSeparator).last;

          if (!musicByFolder.containsKey(folderName)) {
            musicByFolder[folderName] = [];
          }
          musicByFolder[folderName]!.add(track);
        } else {
          debugPrint("Warning: Parent directory not found for ${track.previewUrl}");
        }
      } catch (e) {
        // Catch potential file system errors
        debugPrint("Error grouping track ${track.id} by folder: $e");
      }
    }
    return musicByFolder;
  }

  static List<Track> sortTracks(List<Track> tracks, SortCriteria criteria) {
    final sortedTracks = List<Track>.from(tracks); // Work on a copy

    int compareStrings(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    int compareDurations(Duration? a, Duration? b) => (a ?? Duration.zero).compareTo(b ?? Duration.zero);

    switch (criteria) {
      case SortCriteria.nameAsc:
        sortedTracks.sort((a, b) => compareStrings(a.trackName, b.trackName));
        break;
      case SortCriteria.nameDesc:
        sortedTracks.sort((a, b) => compareStrings(b.trackName, a.trackName));
        break;
      case SortCriteria.artistAsc:
        sortedTracks.sort((a, b) => compareStrings(a.artistName, b.artistName));
        break;
      case SortCriteria.artistDesc:
        sortedTracks.sort((a, b) => compareStrings(b.artistName, a.artistName));
        break;
      case SortCriteria.albumAsc:
        sortedTracks.sort((a, b) => compareStrings(a.albumName, b.albumName));
        break;
      case SortCriteria.albumDesc:
        sortedTracks.sort((a, b) => compareStrings(b.albumName, a.albumName));
        break;
      case SortCriteria.durationAsc: // Added Duration sort
        sortedTracks.sort((a, b) => compareDurations(a.duration, b.duration));
        break;
      case SortCriteria.durationDesc: // Added Duration sort
        sortedTracks.sort((a, b) => compareDurations(b.duration, a.duration));
        break;
      case SortCriteria.folderAsc:
        sortedTracks.sort((a, b) {
          try {
            final folderA = File(a.previewUrl).parent.path.split(Platform.pathSeparator).last;
            final folderB = File(b.previewUrl).parent.path.split(Platform.pathSeparator).last;
            return compareStrings(folderA, folderB);
          } catch(_) { return 0; }
        });
        break;
      case SortCriteria.folderDesc:
        sortedTracks.sort((a, b) {
          try {
            final folderA = File(a.previewUrl).parent.path.split(Platform.pathSeparator).last;
            final folderB = File(b.previewUrl).parent.path.split(Platform.pathSeparator).last;
            return compareStrings(folderB, folderA);
          } catch(_) { return 0; }
        });
        break;
    // Note: Sorting by 'Date Added' from file system (lastModified) can be unreliable.
    // MediaStore often provides a DATE_ADDED column which might be better if accessible.
    // Keeping file system sort for now.
      case SortCriteria.dateAddedAsc:
        sortedTracks.sort((a, b) {
          try {
            return File(a.previewUrl).lastModifiedSync().compareTo(File(b.previewUrl).lastModifiedSync());
          } catch(_) { return 0; }
        });
        break;
      case SortCriteria.dateAddedDesc:
        sortedTracks.sort((a, b) {
          try {
            return File(b.previewUrl).lastModifiedSync().compareTo(File(a.previewUrl).lastModifiedSync());
          } catch(_) { return 0; }
        });
        break;
    }
    return sortedTracks;
  }

  // --- Artwork Resolution ---

  /// The embedded cover of the file at [path], or null. Looked up by MediaStore
  /// id; at most [_maxArtworkJobs] run at once.
  Future<Uint8List?> getTrackArtwork(String path) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
    try {
      final id = await _idFor(path);
      if (id == null) return null;
      while (_artworkJobs >= _maxArtworkJobs) {
        final w = Completer<void>();
        _artworkWaiters.add(w);
        await w.future;
      }
      _artworkJobs++;
      try {
        final bytes = await _audioQuery.queryArtwork(
          id,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: 200, // a 56 dp row at 3x, and enough for palette generation
        );
        return bytes == null || bytes.isEmpty ? null : bytes;
      } finally {
        _artworkJobs--;
        if (_artworkWaiters.isNotEmpty) _artworkWaiters.removeAt(0).complete();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LocalMusicService: Error fetching artwork for $path: $e');
    }
    return null;
  }
}

// Update SortCriteria Enum to include new options
enum SortCriteria {
  nameAsc, nameDesc,
  artistAsc, artistDesc,
  albumAsc, albumDesc,
  durationAsc, durationDesc, // Added
  folderAsc, folderDesc,
  dateAddedAsc, dateAddedDesc,
}

