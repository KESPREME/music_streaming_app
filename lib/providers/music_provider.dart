// lib/providers/music_provider.dart

// Dart Core Libraries
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:just_audio/just_audio.dart'; // Import for PlayerState
import 'dart:math';

// Flutter Foundation & Material
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Flutter Packages
import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:device_info_plus/device_info_plus.dart'; // Commented out: Unused
import 'package:dio/dio.dart'; // Used by NetworkService for downloads
import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart'; // Commented out: Unused
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http; // For network diagnostics
import 'package:collection/collection.dart'; // For firstWhereOrNull

// Your Project Model Imports
import '../models/track.dart';
import '../models/playlist.dart'; // Ensure this has fromJson, toJson, and copyWith methods
import '../models/artist.dart';  // Import new model
import '../models/album.dart';   // Import new model
// import '../models/friend_listening.dart'; // Uncomment if FriendListening model and FirestoreService are used

// Your Project Service Imports
import '../services/api_service.dart';
import '../services/audio_service.dart'; // Your audio player wrapper
import '../services/spotify_service.dart';
import '../services/local_music_service.dart'; // Updated service using on_audio_query
import '../services/network_service.dart';
// import '../services/firestore_service.dart'; // Uncomment if used

// Your Project Utility Imports
import '../utils/network_config.dart';

// Enums
enum RepeatMode { off, all, one }
// SortCriteria enum is imported from local_music_service.dart

// Helper function for list comparison (can be moved to a utils file)
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (int i = 0; i < a.length; i++) {
    // Assumes Track model has a correct == operator override
    if (a[i] != b[i]) return false;
  }
  return true;
}

class MusicProvider with ChangeNotifier {
  // --- State Properties ---
  List<Track> _tracks = [];
  List<Track> _trendingTracks = [];
  List<Track> _fullTrendingTracks = [];
  List<Track> _recentlyPlayed = [];
  List<Track> _likedSongs = [];
  List<Track> _searchedTracks = []; // For generic track search results
  List<Track> _artistTracks = [];
  List<Track> _genreTracks = [];
  List<Playlist> _userPlaylists = [];
  List<Track> _localTracks = [];
  SortCriteria _localTracksSortCriteria = SortCriteria.nameAsc;
  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isOfflineTrack = false;
  bool _shuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.off;
  String? _currentPlaylistId;
  List<Track>? _currentPlayingTracks;
  List<Track> _shuffledPlaylist = [];
  int _currentIndex = -1;
  final List<Track> _queue = []; // Added queue
  int _queueIndex = -1; // Added queue index tracking
  int _wifiBitrate = NetworkConfig.goodNetworkBitrate;
  int _cellularBitrate = NetworkConfig.moderateNetworkBitrate;
  bool _isOfflineMode = false;
  bool _userManuallySetOffline = false;
  bool _isLowDataMode = false;
  bool _isReconnecting = false;
  Timer? _reconnectionTimer;
  String? _errorMessage;
  bool _isLoadingLocal = false;
  Artist? _currentArtistDetails; // Added state for artist screen
  Album? _currentAlbumDetails; // Added state for album screen
  bool _isLoadingArtist = false; // Loading state for artist screen
  bool _isLoadingAlbum = false; // Loading state for album screen
  Map<String, double> _downloadProgress = {};
  Map<String, bool> _isDownloading = {};
  List<Track> _currentlyDownloadingTracks = [];
  final Map<String, CancelToken> _downloadCancelTokens = {};
  int _concurrentDownloads = 0;
  final List<Track> _downloadQueue = [];
  Map<String, Map<String, dynamic>> _downloadedTracksMetadata = {};
  Map<String, List<Track>> _cachedTracks = {};
  final ApiService _apiService = ApiService();
  final AudioService _audioService = AudioService();
  late final SpotifyService _spotifyService;
  final LocalMusicService _localMusicService = LocalMusicService();
  final NetworkService _networkService = NetworkService();
  final List<_RetryOperation> _retryQueue = [];
  Timer? _retryTimer;
  static const int _maxRetryAttempts = 3;
  StreamSubscription? _networkQualitySubscription;
  StreamSubscription? _connectivityStatusSubscription;

  // --- Getters ---
  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Track> get trendingTracks => List.unmodifiable(_trendingTracks);
  List<Track> get fullTrendingTracks => List.unmodifiable(_fullTrendingTracks);
  List<Track> get searchedTracks => List.unmodifiable(_searchedTracks); // Getter for searched tracks
  List<Track> get recentlyPlayed => List.unmodifiable(_recentlyPlayed);
  List<Track> get likedSongs => List.unmodifiable(_likedSongs);
  List<Track> get artistTracks => List.unmodifiable(_artistTracks);
  List<Track> get genreTracks => List.unmodifiable(_genreTracks);
  List<Playlist> get userPlaylists => List.unmodifiable(_userPlaylists);
  List<Track> get localTracks => List.unmodifiable(_localTracks);
  SortCriteria get localTracksSortCriteria => _localTracksSortCriteria;
  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isOfflineTrackPlaying => _isOfflineTrack;
  String? get errorMessage => _errorMessage;
  bool get isLoadingLocal => _isLoadingLocal;
  Artist? get currentArtistDetails => _currentArtistDetails; // Added getter
  Album? get currentAlbumDetails => _currentAlbumDetails; // Added getter
  bool get isLoadingArtist => _isLoadingArtist; // Added getter
  bool get isLoadingAlbum => _isLoadingAlbum; // Added getter
  int get wifiBitrate => _wifiBitrate;
  int get cellularBitrate => _cellularBitrate;
  bool get isOfflineMode => _isOfflineMode;
  bool get isLowDataMode => _isLowDataMode;
  bool get shuffleEnabled => _shuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  String? get currentPlaylistId => _currentPlaylistId;
  NetworkQuality get networkQuality => _networkService.networkQuality;
  Map<String, double> get downloadProgress => Map.unmodifiable(_downloadProgress);
  Map<String, bool> get isDownloading => Map.unmodifiable(_isDownloading);
  List<Track> get currentlyDownloadingTracks => List.unmodifiable(_currentlyDownloadingTracks);
  List<Track> get downloadQueue => List.unmodifiable(_downloadQueue);
  List<Track> get queue => List.unmodifiable(_queue); // Added queue getter
  Stream<Duration> get positionStream => _audioService.onPositionChanged;
  Stream<Duration> get durationStream => _audioService.onDurationChanged;
  Stream<bool> get playbackStateStream => _audioService.onPlaybackStateChanged;
  Stream<PlayerState> get playerStateStream => _audioService.playerStateStream;
  Stream<bool> get playbackCompleteStream => _audioService.onPlaybackComplete;

  // --- Initialization & Setup ---
  MusicProvider() { _spotifyService = SpotifyService(_apiService); _initialize(); }
  Future<void> _initialize() async { print('Initializing...'); await _loadSettings(); await _loadLikedSongs(); await _loadRecentlyPlayed(); await loadUserPlaylists(); await _loadDownloadedTracksMetadata(); _setupAudioListeners(); _startRetryTimer(); _setupConnectivityMonitoring(); final isConnected = _networkService.isConnected; if (isConnected && !_isOfflineMode) { try { await Future.wait([ fetchTracks(), fetchTrendingTracks() ]); } catch (e) { _errorMessage = 'Could not load initial content.'; } } else { _errorMessage = _isOfflineMode ? (_userManuallySetOffline ? 'Currently in offline mode.' : 'No internet connection.') : 'No internet connection.'; } unawaited(loadLocalMusicFiles()); print('Initialization complete.'); }
  void _setupAudioListeners() { _audioService.onPositionChanged.listen((pos) { if (_position != pos) { _position = pos; notifyListeners(); } }, onError: (e) => print("Pos stream error: $e")); _audioService.onDurationChanged.listen((dur) { if ((_duration - dur).abs() > const Duration(milliseconds: 500) && dur > Duration.zero) { _duration = dur; notifyListeners(); } }, onError: (e) => print("Dur stream error: $e")); _audioService.onPlaybackStateChanged.listen((playing) { if (_isPlaying != playing) { _isPlaying = playing; notifyListeners(); } }, onError: (e) => print("State stream error: $e")); _audioService.onPlaybackComplete.listen((completed) { if (completed) _onTrackComplete(); }, onError: (e) => print("Complete stream error: $e")); }

  // --- Settings Persistence ---
  Future<void> _loadSettings() async { try { final p = await SharedPreferences.getInstance(); _wifiBitrate = p.getInt('wifiBitrate') ?? NetworkConfig.goodNetworkBitrate; _cellularBitrate = p.getInt('cellularBitrate') ?? NetworkConfig.moderateNetworkBitrate; _isOfflineMode = p.getBool('offlineMode') ?? false; _userManuallySetOffline = p.getBool('userManuallySetOffline') ?? false; _isLowDataMode = p.getBool('lowDataMode') ?? false; _shuffleEnabled = p.getBool('shuffleEnabled') ?? false; try { _repeatMode = RepeatMode.values[p.getInt('repeatMode') ?? RepeatMode.off.index]; } catch (_) { _repeatMode = RepeatMode.off; } try { _localTracksSortCriteria = SortCriteria.values[p.getInt('localSortCriteria') ?? SortCriteria.nameAsc.index]; } catch (_) { _localTracksSortCriteria = SortCriteria.nameAsc; } print('Settings loaded.'); } catch (e) { print("Error loading settings: $e"); } }
  Future<void> _saveSettings() async { try { final p = await SharedPreferences.getInstance(); await p.setInt('wifiBitrate', _wifiBitrate); await p.setInt('cellularBitrate', _cellularBitrate); await p.setBool('offlineMode', _isOfflineMode); await p.setBool('userManuallySetOffline', _userManuallySetOffline); await p.setBool('lowDataMode', _isLowDataMode); await p.setBool('shuffleEnabled', _shuffleEnabled); await p.setInt('repeatMode', _repeatMode.index); await p.setInt('localSortCriteria', _localTracksSortCriteria.index); print('Settings saved.'); } catch (e) { _errorMessage = "Failed to save settings."; notifyListeners(); } }

  // --- Playback Control & Context ---
  void toggleShuffle() { _shuffleEnabled = !_shuffleEnabled; if (_shuffleEnabled && _currentPlayingTracks != null) { _shufflePlaylist(); } else { _updateCurrentIndex(); } _saveSettings(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void cycleRepeatMode() { _repeatMode = RepeatMode.values[(_repeatMode.index + 1) % RepeatMode.values.length]; _saveSettings(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void _shufflePlaylist() { if (_currentPlayingTracks == null || _currentPlayingTracks!.isEmpty) { _shuffledPlaylist = []; _currentIndex = -1; return; } _shuffledPlaylist = List.from(_currentPlayingTracks!)..shuffle(Random()); _updateCurrentIndex(); /* Preload handled by toggleShuffle or setPlaybackContext */ }
  List<Track> _getActivePlaylist() => _shuffleEnabled ? _shuffledPlaylist : (_currentPlayingTracks ?? []);
  void _updateCurrentIndex() { final list = _getActivePlaylist(); _currentIndex = (_currentTrack != null && list.isNotEmpty) ? list.indexWhere((t) => t.id == _currentTrack!.id) : -1; }
  void _setPlaybackContext(List<Track>? tracks, {String? playlistId, bool clearQueue = true}) { if (!listEquals(_currentPlayingTracks, tracks) || _currentPlaylistId != playlistId) { print("Setting playback context. ID: $playlistId, Tracks: ${tracks?.length ?? 0}, ClearQueue: $clearQueue"); _currentPlayingTracks = tracks != null ? List.from(tracks) : null; _currentPlaylistId = playlistId; if (clearQueue && _queue.isNotEmpty) { _queue.clear(); print("Playback context changed, queue cleared."); } if (_shuffleEnabled && _currentPlayingTracks != null) _shufflePlaylist(); else _updateCurrentIndex(); _handlePlaybackOrContextChangeForPreloading();} else { _updateCurrentIndex(); } _updateCombinedQueueIndex();  }
  void _onTrackComplete() { print('Track completion: ${_currentTrack?.trackName}'); if (_currentTrack == null) { stopTrack(); return; } if (_repeatMode == RepeatMode.one) { seekTo(Duration.zero); if(!_isPlaying) resumeTrack(); _handlePlaybackOrContextChangeForPreloading(); return; } if (_queue.isNotEmpty) { final next = _queue.removeAt(0); print("Playing next from queue: ${next.trackName}"); _playTrackInternal(next, setContext: false, clearQueue: false); notifyListeners(); /* Preload handled by playTrackInternal -> playTrack */ return; } final list = _getActivePlaylist(); if (list.isEmpty) { stopTrack(); return; } _updateCurrentIndex(); int nextIdx = _currentIndex + 1; if (nextIdx < list.length) { print('Playing next from context index $nextIdx'); _playTrackInternal(list[nextIdx], setContext: true, clearQueue: false); } else { if (_repeatMode == RepeatMode.all) { print('Looping context to start.'); _playTrackInternal(list[0], setContext: true, clearQueue: false); } else { print('End of context, Repeat off, stopping.'); stopTrack(); } } /* Preload handled by playTrackInternal if it plays */ }
  Future<void> _playTrackInternal(Track track, {bool setContext = true, bool clearQueue = true}) async { if (setContext) _setPlaybackContext(_currentPlayingTracks, playlistId: _currentPlaylistId, clearQueue: clearQueue); else { _currentTrack = track; _updateCurrentIndex(); /* _currentTrack = null; */ } bool offline = await _shouldPlayOffline(track); try { if (offline) await playOfflineTrack(track, setContext: setContext, clearQueue: clearQueue); else await playTrack(track, playlistTracks: _currentPlayingTracks, playlistId: _currentPlaylistId, setContext: setContext, clearQueue: clearQueue); } catch(e) { print("Error in _playTrackInternal: $e"); } _updateCombinedQueueIndex(); /* Preload handled by playTrack/playOfflineTrack */ }
  Future<bool> _shouldPlayOffline(Track track) async => track.source == 'local' || await isTrackDownloaded(track.id);
  Future<void> skipToNext() async { print('SkipNext requested.'); if (_currentTrack == null) return; if (_queue.isNotEmpty) { final next = _queue.removeAt(0); print("Skipping to next from queue: ${next.trackName}"); await _playTrackInternal(next, setContext: false, clearQueue: false); notifyListeners(); return; } final list = _getActivePlaylist(); if (list.isEmpty) return; _updateCurrentIndex(); if (_currentIndex == -1 && list.isNotEmpty) { await _playTrackInternal(list[0]); return; } int next = _currentIndex + 1; if (next < list.length) { await _playTrackInternal(list[next]); } else { if (_repeatMode != RepeatMode.off) await _playTrackInternal(list[0]); else await stopTrack(); } _updateCombinedQueueIndex(); /* Preload handled by playTrackInternal if it plays */ }
  Future<void> skipToPrevious() async { print('SkipPrevious requested.'); if (_currentTrack == null) return; if (_position > const Duration(seconds: 3)) { await seekTo(Duration.zero); if (!_isPlaying) await resumeTrack(); _handlePlaybackOrContextChangeForPreloading(); return; } final list = _getActivePlaylist(); if (list.isEmpty) return; _updateCurrentIndex(); if (_currentIndex == -1 && list.isNotEmpty) { await _playTrackInternal(list.last); return; } int prev = _currentIndex - 1; if (prev >= 0) { await _playTrackInternal(list[prev]); } else { if (_repeatMode != RepeatMode.off) await _playTrackInternal(list.last); else { await seekTo(Duration.zero); if (!_isPlaying) await resumeTrack(); _handlePlaybackOrContextChangeForPreloading(); } } _updateCombinedQueueIndex(); /* Preload handled by playTrackInternal if it plays */ }

  // --- Core Playback Methods ---
  Future<void> playTrack(Track track, {String? playlistId, List<Track>? playlistTracks, bool setContext = true, bool clearQueue = true}) async { print('Request playTrack: ${track.trackName} (SetContext: $setContext, ClearQueue: $clearQueue)'); if (_currentTrack?.id == track.id && _isPlaying) { await pauseTrack(); return; } if (_currentTrack?.id == track.id && !_isPlaying && _currentTrack != null) { await resumeTrack(); return; } _clearError(); try { if (_isPlaying) await _audioService.stop(); _isPlaying = false; if (setContext) _setPlaybackContext(playlistTracks, playlistId: playlistId, clearQueue: clearQueue); else { _currentTrack = track; _updateCurrentIndex(); _currentTrack = null; } bool playOffline = await _shouldPlayOffline(track); if (playOffline) { await playOfflineTrack(track, setContext: setContext, clearQueue: clearQueue); return; } if (_isOfflineMode) throw Exception('Offline Mode: Track not available.'); if (!_networkService.isConnected) throw Exception('No internet connection.'); _currentTrack = track; _isOfflineTrack = false; notifyListeners(); String playableId = track.id; Track effectiveTrack = track; if (track.source == 'spotify') { final yt = await _spotifyService.findYouTubeTrack(track); if (yt != null) { playableId = yt.id; effectiveTrack = track.copyWith(id: playableId, source: 'youtube', previewUrl: yt.previewUrl); _currentTrack = effectiveTrack; notifyListeners(); } else throw Exception("No playable version for '${track.trackName}'."); } final bitrate = await _getBitrate(); if (bitrate == 0 && !_isOfflineMode && !_networkService.isConnected) throw Exception('Connection lost.');
      _handleNetworkQualityChange(_networkService.networkQuality);
      final url = await _apiService.getAudioStreamUrl(playableId, bitrate); await _audioService.play(url); _currentTrack = effectiveTrack; _isPlaying = true; _updateRecentlyPlayed(effectiveTrack); _updateCurrentIndex(); _updateCombinedQueueIndex(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); } catch (e, s) { print('--- ERROR PLAYING TRACK ---\nTrack: ${track.trackName}\nError: $e\n$s\n--- END ---'); await _handlePlaybackError('Error playing track: ${e.toString()}'); } }
  Future<void> playOfflineTrack(Track track, {bool setContext = true, bool clearQueue = true}) async { bool knownOffline = track.source == 'local' || _downloadedTracksMetadata.containsKey(track.id); if (!knownOffline) { await playTrack(track, playlistTracks: _currentPlayingTracks, playlistId: _currentPlaylistId, setContext: setContext, clearQueue: clearQueue); return; } if (_currentTrack?.id == track.id && _isPlaying) { await pauseTrack(); return; } if (_currentTrack?.id == track.id && !_isPlaying && _currentTrack != null) { await resumeTrack(); return; } _clearError(); try { if (_isPlaying) await _audioService.stop(); _isPlaying = false; String filePath; bool isDownloaded = _downloadedTracksMetadata.containsKey(track.id); if (track.source == 'local') filePath = track.previewUrl; else if (isDownloaded) { final meta = _downloadedTracksMetadata[track.id]; filePath = meta?['filePath'] as String? ?? ''; } else throw Exception('Source not local/downloaded.'); if (filePath.isEmpty) throw Exception('File path empty.'); final file = File(filePath); if (!await file.exists()) { await _handleMissingOfflineFile(track.id, filePath); throw Exception('File missing.'); } _currentTrack = track; _isOfflineTrack = true; if (setContext) { List<Track> contextTracks; String contextDesc; if (isDownloaded) { contextTracks = await getDownloadedTracks(); contextDesc = "Downloads"; } else { contextTracks = _localTracks; contextDesc = "Local Tracks"; } _setPlaybackContext(contextTracks, clearQueue: clearQueue); print("Set playback context to $contextDesc"); } else _updateCurrentIndex();

      notifyListeners(); await _audioService.playLocalFile(filePath); _isPlaying = true; _updateRecentlyPlayed(track); _updateCombinedQueueIndex(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); } catch (e, s) { print('--- ERROR PLAYING OFFLINE ---\nTrack: ${track.trackName}\nError: $e\n$s\n--- END ---'); await _handlePlaybackError('Error playing offline track: ${e.toString()}'); } }
  Future<void> pauseTrack() async { if (!_isPlaying) return; try { await _audioService.pause(); /* No preload on pause */ } catch (e) { await _handlePlaybackError('Error pausing: $e'); } }
  Future<void> resumeTrack() async { if (_isPlaying || _currentTrack == null) return; _clearError(); try { await _audioService.resume(); } catch (e) { await _handlePlaybackError('Error resuming: $e'); } }
  Future<void> seekTo(Duration position) async { if (_currentTrack == null) return; final dur = _duration; final clamped = position.isNegative ? Duration.zero : (dur > Duration.zero && position > dur ? dur : position); try { await _audioService.seekTo(clamped); _position = clamped; notifyListeners(); } catch (e) { _errorMessage = 'Error seeking.'; notifyListeners(); } }
  Future<void> stopTrack() async { try { await _audioService.stop(); } catch (e) { print('Error stopping service: $e'); } finally { _isPlaying = false; _currentTrack = null; _isOfflineTrack = false; _position = Duration.zero; _duration = Duration.zero; _currentIndex = -1; _currentPlayingTracks = null; _currentPlaylistId = null; _shuffledPlaylist = []; _queue.clear(); _queueIndex = -1; notifyListeners(); } }

  // --- Error Handling ---
  void _clearError() { if (_errorMessage != null) { _errorMessage = null; notifyListeners(); } }
  Future<void> _handlePlaybackError(String message) async { print("Playback Error: $message"); _errorMessage = message.length > 150 ? '${message.substring(0, 147)}...' : message; await stopTrack(); }

  // --- Queue Management ---
  void addToQueue(Track track) { _queue.add(track); print("Added to queue: ${track.trackName}. Size: ${_queue.length}"); _updateCombinedQueueIndex(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void addListToQueue(List<Track> tracks) { _queue.addAll(tracks); print("Added ${tracks.length} to queue. Size: ${_queue.length}"); _updateCombinedQueueIndex(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void playNext(Track track) { _queue.insert(0, track); print("Play next: ${track.trackName}. Size: ${_queue.length}"); _updateCombinedQueueIndex(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void reorderQueueItem(int oldIndex, int newIndex) { if (oldIndex < 0 || oldIndex >= _queue.length || newIndex < 0) return; final int iIdx = newIndex > oldIndex ? newIndex - 1 : newIndex; final tr = _queue.removeAt(oldIndex); _queue.insert(iIdx.clamp(0, _queue.length), tr); _updateCombinedQueueIndex(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }

  // Updated to accept Track object or index
  void removeFromQueue(dynamic item) {
    bool removed = false;
    if (item is int && item >= 0 && item < _queue.length) {
      final rTr = _queue.removeAt(item);
      print("Removed from queue by index: ${rTr.trackName}. Size: ${_queue.length}");
      removed = true;
    } else if (item is Track) {
      final initialLength = _queue.length;
      _queue.removeWhere((t) => t.id == item.id);
      if (_queue.length < initialLength) {
        print("Removed from queue by track: ${item.trackName}. Size: ${_queue.length}");
        removed = true;
      }
    } else if (item is String) { // Remove by track ID
       final initialLength = _queue.length;
      _queue.removeWhere((t) => t.id == item);
      if (_queue.length < initialLength) {
        print("Removed from queue by track ID: $item. Size: ${_queue.length}");
        removed = true;
      }
    }

    if (removed) {
      _updateCombinedQueueIndex();
      notifyListeners();
      _handlePlaybackOrContextChangeForPreloading(); // Also call after removing from queue
    }
  }

  void clearQueue() { if (_queue.isEmpty) return; _queue.clear(); print("Queue cleared."); _updateCombinedQueueIndex(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void _updateCombinedQueueIndex() { if (_currentTrack == null) { _queueIndex = -1; return; } int indexInQueue = _queue.indexWhere((t) => t.id == _currentTrack!.id); if (indexInQueue != -1) _queueIndex = indexInQueue; else _queueIndex = -1; }

  // --- Preloading Logic ---
  Track? _getActualNextTrack() {
    if (_queue.isNotEmpty) {
      return _queue.first; // Next in queue always takes precedence
    }
    final activePlaylist = _getActivePlaylist();
    if (activePlaylist.isEmpty || _currentIndex < 0) return null;

    if (_repeatMode == RepeatMode.one) {
      return _currentTrack; // If repeat one, next is current (it will restart)
    }

    int nextIndex = _currentIndex + 1;
    if (nextIndex < activePlaylist.length) {
      return activePlaylist[nextIndex];
    } else if (_repeatMode == RepeatMode.all) {
      return activePlaylist.first; // Loop back to start
    }
    return null; // End of playlist, no repeat all
  }

  Future<void> _preloadNextTrack() async {
    final nextTrack = _getActualNextTrack();
    if (nextTrack != null && nextTrack.id != _currentTrack?.id && nextTrack.source != 'local' && !(await isTrackDownloaded(nextTrack.id))) {
      try {
        if (kDebugMode) print("MusicProvider: Attempting to preload ${nextTrack.trackName}");
        String playableId = nextTrack.id;
        if (nextTrack.source == 'spotify') {
          final ytEquivalent = await _spotifyService.findYouTubeTrack(nextTrack);
          if (ytEquivalent != null) playableId = ytEquivalent.id;
          else {
            if (kDebugMode) print("MusicProvider: Could not find YouTube equivalent for Spotify track ${nextTrack.trackName} for preloading.");
            return;
          }
        }
        final bitrate = await _getBitrate(); // Use current adaptive bitrate for preloading
        final url = await _apiService.getAudioStreamUrl(playableId, bitrate);
        await _audioService.preloadTrack(url);
      } catch (e) {
        if (kDebugMode) print("MusicProvider: Error preloading next track ${nextTrack.trackName}: $e");
      }
    } else {
      if (kDebugMode) print("MusicProvider: No suitable next track to preload or next is same as current/local/downloaded.");
    }
  }

  // Call _preloadNextTrack after a track starts playing or context changes
  void _handlePlaybackOrContextChangeForPreloading() {
    // Clear any existing preloaded track if context changes significantly
    // This is implicitly handled by AudioService if a different track is played.
    // Explicitly: _audioService.cancelPreload(); (if such method existed)

    // Then try to preload the new next track
    _preloadNextTrack();
  }


  // --- Placeholder Navigation Methods ---
  Future<void> navigateToArtist(String artistName) async { print("PROVIDER ACTION: Navigate to Artist: $artistName"); _isLoadingArtist = true; _currentArtistDetails = null; _errorMessage = null; notifyListeners(); try { _currentArtistDetails = await _apiService.fetchArtistDetails(artistName); print("PROVIDER: Artist details fetched for $artistName"); } catch (e) { _errorMessage = "Could not load artist details."; _currentArtistDetails = null; } finally { _isLoadingArtist = false; notifyListeners(); } }
  Future<void> navigateToAlbum(String albumName, String artistName) async { print("PROVIDER ACTION: Navigate to Album: $albumName by $artistName"); _isLoadingAlbum = true; _currentAlbumDetails = null; _errorMessage = null; notifyListeners(); try { _currentAlbumDetails = await _apiService.fetchAlbumDetails(albumName, artistName); print("PROVIDER: Album details fetched for $albumName"); } catch (e) { _errorMessage = "Could not load album details."; _currentAlbumDetails = null; } finally { _isLoadingAlbum = false; notifyListeners(); } }

  // --- Network & Mode Management ---
  void _setupConnectivityMonitoring() { _networkQualitySubscription = _networkService.onNetworkQualityChanged.listen((q) => _handleNetworkQualityChange(q), onError: (e) => print("NetQual stream error: $e")); _connectivityStatusSubscription = _networkService.onConnectivityChanged.listen((c) => _handleConnectivityChange(c), onError: (e) => print("Connect stream error: $e")); _networkService.checkNetworkQualityNow().then((q) { _handleNetworkQualityChange(q); _handleConnectivityChange(q != NetworkQuality.offline); }); }

  void _handleNetworkQualityChange(NetworkQuality quality) {
    // Adjust bitrates based on network quality (existing logic)
    if (!_isLowDataMode) {
      int nW = _wifiBitrate, nC = _cellularBitrate;
      switch (quality) {
        case NetworkQuality.poor: nW = nC = NetworkConfig.poorNetworkBitrate; break;
        case NetworkQuality.moderate: nW = NetworkConfig.moderateNetworkBitrate; nC = NetworkConfig.poorNetworkBitrate; break;
        case NetworkQuality.good: nW = NetworkConfig.goodNetworkBitrate; nC = NetworkConfig.moderateNetworkBitrate; break;
        case NetworkQuality.excellent: nW = NetworkConfig.excellentNetworkBitrate; nC = NetworkConfig.goodNetworkBitrate; break;
        default: break;
      }
      if (nW != _wifiBitrate || nC != _cellularBitrate) {
        _wifiBitrate = nW;
        _cellularBitrate = nC;
        _saveSettings(); // Save bitrate settings
        // notifyListeners(); // Notifying for bitrate change might be too frequent if UI doesn't directly show it
      }
    }

    // Adjust audio buffer settings based on network quality
    Duration bufferDuration, minBufferDuration, maxBufferDuration;
    switch (quality) {
      case NetworkQuality.offline: // Should not happen if playing online content
      case NetworkQuality.poor:
        minBufferDuration = const Duration(seconds: 15); // Start playback after 15s buffered
        bufferDuration = const Duration(seconds: 60);    // Try to keep 60s buffered ahead
        maxBufferDuration = const Duration(seconds: 120); // Max buffer size
        break;
      case NetworkQuality.moderate:
        minBufferDuration = const Duration(seconds: 8);
        bufferDuration = const Duration(seconds: 45);
        maxBufferDuration = const Duration(seconds: 90);
        break;
      case NetworkQuality.good:
        minBufferDuration = const Duration(seconds: 5);
        bufferDuration = const Duration(seconds: 30);
        maxBufferDuration = const Duration(seconds: 60);
        break;
      case NetworkQuality.excellent:
        minBufferDuration = const Duration(seconds: 2);
        bufferDuration = const Duration(seconds: 20);
        maxBufferDuration = const Duration(seconds: 40);
        break;
    }
    // Only configure if playing online content

    // No need to notifyListeners() here as this primarily affects background player behavior
  }

  void _handleConnectivityChange(bool isConnected) { if (!isConnected && !_isOfflineMode) { _isOfflineMode = true; _userManuallySetOffline = false; _saveSettings(); _showOfflineModeNotification('Connection lost.'); _switchToOfflineVersionIfAvailable(); pauseAllDownloads(); notifyListeners(); } else if (isConnected && _isOfflineMode && !_userManuallySetOffline) { goOnline(); } else if (isConnected && _isOfflineMode && _userManuallySetOffline) { if (!_isReconnecting) _showReconnectionPrompt(); _processRetryQueue(); _processDownloadQueue(); } else if (isConnected && !_isOfflineMode) { if (_isReconnecting) { _isReconnecting = false; _reconnectionTimer?.cancel(); _errorMessage = null; notifyListeners(); } _processRetryQueue(); _processDownloadQueue(); } }
  void goOnline() { if (_isOfflineMode) { bool wasOffline = _isOfflineMode; _isOfflineMode = false; _userManuallySetOffline = false; _isReconnecting = false; _reconnectionTimer?.cancel(); _saveSettings(); _errorMessage = 'You are now online.'; notifyListeners(); if (wasOffline) _refreshDataOnReconnect(); _processRetryQueue(); _processDownloadQueue(); } }
  void goOffline() { if (!_isOfflineMode) { _isOfflineMode = true; _userManuallySetOffline = true; _isReconnecting = false; _reconnectionTimer?.cancel(); _saveSettings(); _showOfflineModeNotification('Offline mode enabled.'); _switchToOfflineVersionIfAvailable(); pauseAllDownloads(); notifyListeners(); } }
  void toggleOfflineMode() => _isOfflineMode ? goOnline() : goOffline();
  void toggleLowDataMode() { _isLowDataMode = !_isLowDataMode; if (_isLowDataMode) { _wifiBitrate = NetworkConfig.moderateNetworkBitrate; _cellularBitrate = NetworkConfig.poorNetworkBitrate; _errorMessage = "Low data mode enabled."; } else { _handleNetworkQualityChange(_networkService.networkQuality); _errorMessage = "Low data mode disabled."; } _saveSettings(); notifyListeners(); }
  void _showReconnectionPrompt() { if (_isReconnecting) return; _isReconnecting = true; _errorMessage = 'Internet available. Tap to go online.'; notifyListeners(); }
  void _showOfflineModeNotification(String message) { _errorMessage = message; notifyListeners(); }
  Future<void> _refreshDataOnReconnect() async { try { await fetchTracks(forceRefresh: true); } catch (_) {} try { await fetchTrendingTracks(forceRefresh: true); } catch (_) {} }
  Future<bool> _switchToOfflineVersionIfAvailable() async { if (_currentTrack == null || _isOfflineTrack) return false; final downloadedPath = await getDownloadedTrackPath(_currentTrack!.id); final isLocalSource = _currentTrack!.source == 'local'; final String? offlinePath = isLocalSource ? _currentTrack!.previewUrl : downloadedPath; if (offlinePath != null && offlinePath.isNotEmpty) { try { final currentPosition = _position; await _audioService.stop(); await _audioService.playLocalFile(offlinePath); _isOfflineTrack = true; _isPlaying = true; if (currentPosition > Duration.zero && _duration > Duration.zero && currentPosition < _duration) await _audioService.seekTo(currentPosition); notifyListeners(); return true; } catch (e) { await _handlePlaybackError("Error playing offline file."); return true; } } else { await pauseTrack(); _errorMessage = "Playback paused: Offline & not downloaded."; notifyListeners(); return true; } }

  // --- Liked Songs ---
  bool isSongLiked(String trackId) => _likedSongs.any((t) => t.id == trackId);
  void likeSong(Track track) { if (!isSongLiked(track.id)) { _likedSongs.insert(0, track); _saveLikedSongs(); notifyListeners(); } }
  void unlikeSong(String trackId) { int count = _likedSongs.length; _likedSongs.removeWhere((t) => t.id == trackId); if (_likedSongs.length < count) { _saveLikedSongs(); notifyListeners(); } }
  void toggleLike(Track track) => isSongLiked(track.id) ? unlikeSong(track.id) : likeSong(track);
  Future<void> _loadLikedSongs() async { try { final p = await SharedPreferences.getInstance(); final s = p.getString('likedSongs'); if (s != null) _likedSongs = List<Map<String, dynamic>>.from(jsonDecode(s)).map((j) => Track.fromJson(j)).toList(); } catch (_) { _likedSongs = []; } }
  Future<void> _saveLikedSongs() async { try { final p = await SharedPreferences.getInstance(); await p.setString('likedSongs', jsonEncode(_likedSongs.map((t) => t.toJson()).toList())); } catch (e) { _addToRetryQueue(_RetryOperation('Save liked', _saveLikedSongs)); } }

  // --- Recently Played ---
  Future<void> _updateRecentlyPlayed(Track track) async { _recentlyPlayed.removeWhere((t) => t.id == track.id); _recentlyPlayed.insert(0, track); if (_recentlyPlayed.length > 20) _recentlyPlayed = _recentlyPlayed.take(20).toList(); await _saveRecentlyPlayed(); }
  void removeFromRecentlyPlayed(String trackId) { int count = _recentlyPlayed.length; _recentlyPlayed.removeWhere((t) => t.id == trackId); if (_recentlyPlayed.length < count) { _saveRecentlyPlayed(); notifyListeners(); } }
  Future<void> _loadRecentlyPlayed() async { try { final p = await SharedPreferences.getInstance(); final s = p.getString('recentlyPlayed'); if (s != null) _recentlyPlayed = List<Map<String, dynamic>>.from(jsonDecode(s)).map((j) => Track.fromJson(j)).toList(); } catch (_) { _recentlyPlayed = []; } }
  Future<void> _saveRecentlyPlayed() async { try { final p = await SharedPreferences.getInstance(); await p.setString('recentlyPlayed', jsonEncode(_recentlyPlayed.map((t) => t.toJson()).toList())); } catch (e) { _addToRetryQueue(_RetryOperation('Save recent', _saveRecentlyPlayed)); } }

  // --- Bitrate Settings ---
  void setWifiBitrate(int bitrate) { if (_wifiBitrate != bitrate) { _wifiBitrate = bitrate; _saveSettings(); notifyListeners(); } }
  void setCellularBitrate(int bitrate) { if (_cellularBitrate != bitrate) { _cellularBitrate = bitrate; _saveSettings(); notifyListeners(); } }
  Future<int> _getBitrate() async { if (_isOfflineMode || !_networkService.isConnected) return 0; if (_isLowDataMode) return min(_cellularBitrate, _wifiBitrate); final type = await _networkService.getConnectionType(); return (type == ConnectivityResult.wifi) ? _wifiBitrate : _cellularBitrate; }

  // --- Local Music ---
  Future<void> loadLocalMusicFiles({bool forceRescan = false}) async { if (_isLoadingLocal && !forceRescan) return; _isLoadingLocal = true; notifyListeners(); try { _localTracks = await _localMusicService.fetchLocalMusicFromMediaStore(); _localTracks = LocalMusicService.sortTracks(_localTracks, _localTracksSortCriteria); _errorMessage = null; } catch (e) { _errorMessage = 'Failed to load local files: ${e.toString()}'; _localTracks = []; } finally { _isLoadingLocal = false; notifyListeners(); } }
  void sortLocalTracks(SortCriteria criteria) { if (_localTracksSortCriteria == criteria && _localTracks.isNotEmpty) return; _localTracksSortCriteria = criteria; _localTracks = LocalMusicService.sortTracks(_localTracks, criteria); _saveSettings(); notifyListeners(); }
  Future<void> addLocalMusicFolder() async { String? iMsg="Adding folder..."; _errorMessage=iMsg; notifyListeners(); try { final String? p = await _localMusicService.pickDirectory(); if(p!=null){await loadLocalMusicFiles(forceRescan:true); if(_errorMessage==iMsg) _errorMessage="Local music refreshed.";} else if(_errorMessage==iMsg) _errorMessage=null;} catch(e) {_errorMessage='Failed to add folder: ${e.toString()}';} finally {notifyListeners();} }
  Future<void> pickAndPlayLocalFile() async { try { final t = await _localMusicService.pickMusicFile(); if (t != null) { if (!_localTracks.any((tr) => tr.id == t.id)) { _localTracks.add(t); sortLocalTracks(_localTracksSortCriteria); } await playOfflineTrack(t); } } catch (e) { _errorMessage = 'Failed to pick file: ${e.toString()}'; notifyListeners(); } }
  Future<void> playAllLocalTracks({int startIndex = 0, bool? shuffle}) async { if (_localTracks.isEmpty) { _errorMessage = 'No local music found.'; notifyListeners(); return; } try { _setPlaybackContext(_localTracks); if (shuffle != null && shuffle != _shuffleEnabled) { _shuffleEnabled = shuffle; _saveSettings(); } Track t; if (_shuffleEnabled) t = _shuffledPlaylist.isNotEmpty ? _shuffledPlaylist[0] : _localTracks[0]; else t = _localTracks[startIndex.clamp(0, _localTracks.length - 1)]; await playOfflineTrack(t); } catch (e) { await _handlePlaybackError('Failed to play local tracks.'); } }

  // --- Playlist Management ---
  Future<void> loadUserPlaylists() async { try { final p = await SharedPreferences.getInstance(); final s = p.getString('userPlaylists'); if (s != null) _userPlaylists = List<Map<String, dynamic>>.from(jsonDecode(s)).map((j) => Playlist.fromJson(j)).toList(); } catch (_) { _userPlaylists = []; } }
  Future<void> saveUserPlaylists() async { try { final p = await SharedPreferences.getInstance(); await p.setString('userPlaylists', jsonEncode(_userPlaylists.map((pl) => pl.toJson()).toList())); } catch (e) { _addToRetryQueue(_RetryOperation('Save playlists', saveUserPlaylists)); } }
  Future<void> createPlaylist(String name, {List<Track>? initialTracks, String? imageUrl}) async { if (name.trim().isEmpty) { _errorMessage = "Name empty."; notifyListeners(); return; } try { final pl = Playlist(id: 'pl_${DateTime.now().millisecondsSinceEpoch}', name: name.trim(), imageUrl: imageUrl ?? '', tracks: initialTracks ?? []); _userPlaylists.add(pl); await saveUserPlaylists(); _errorMessage = "Playlist created."; notifyListeners(); } catch (_) { _errorMessage = 'Failed to create.'; notifyListeners(); } }
  Future<void> deletePlaylist(String playlistId) async { final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) return; try { _userPlaylists.removeAt(i); await saveUserPlaylists(); if (_currentPlaylistId == playlistId) await stopTrack(); _errorMessage = "Playlist deleted."; notifyListeners(); } catch (_) { _errorMessage = 'Failed to delete.'; notifyListeners(); } }
  Future<void> renamePlaylist(String playlistId, String newName) async { if (newName.trim().isEmpty) { _errorMessage = "Name empty."; notifyListeners(); return; } final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) return; try { _userPlaylists[i] = _userPlaylists[i].copyWith(name: newName.trim()); await saveUserPlaylists(); _errorMessage = "Renamed."; notifyListeners(); } catch (_) { _errorMessage = "Failed to rename."; notifyListeners(); } }
  Future<void> addTrackToPlaylist(String playlistId, Track track) async { final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) return; final pl = _userPlaylists[i]; if (pl.tracks.any((t) => t.id == track.id)) { _errorMessage = "Already in playlist."; notifyListeners(); return; } try { _userPlaylists[i] = pl.copyWith(tracks: [...pl.tracks, track]); await saveUserPlaylists(); _errorMessage = "Added to ${pl.name}."; notifyListeners(); } catch (_) { _errorMessage = 'Failed to add track.'; notifyListeners(); } }
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async { final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) return; final pl = _userPlaylists[i]; final tN = pl.tracks.firstWhereOrNull((t) => t.id == trackId)?.trackName ?? '?'; try { final uT = pl.tracks.where((t) => t.id != trackId).toList(); if (uT.length < pl.tracks.length) { _userPlaylists[i] = pl.copyWith(tracks: uT); await saveUserPlaylists(); _errorMessage = "Removed '$tN'."; if (_currentPlaylistId == playlistId && _currentTrack?.id == trackId) await skipToNext(); notifyListeners(); } } catch (_) { _errorMessage = 'Failed to remove track.'; notifyListeners(); } }
  Future<void> reorderTrackInPlaylist(String playlistId, int oldIndex, int newIndex) async { final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) return; final pl = _userPlaylists[i]; if (oldIndex < 0 || oldIndex >= pl.tracks.length || newIndex < 0) return; try { final t = List<Track>.from(pl.tracks); final tr = t.removeAt(oldIndex); int iI = (newIndex > oldIndex) ? newIndex - 1 : newIndex; iI = iI.clamp(0, t.length); t.insert(iI, tr); _userPlaylists[i] = pl.copyWith(tracks: t); await saveUserPlaylists(); notifyListeners(); } catch (_) { _errorMessage = "Failed to reorder."; notifyListeners(); } }
  Future<void> playPlaylist(String playlistId, {int startIndex = 0, bool? shuffle}) async { final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) { _errorMessage = 'Playlist not found.'; notifyListeners(); return; } final pl = _userPlaylists[i]; if (pl.tracks.isEmpty) { _errorMessage = "'${pl.name}' empty."; notifyListeners(); return; } if (shuffle != null && shuffle != _shuffleEnabled) { _shuffleEnabled = shuffle; _saveSettings(); } _setPlaybackContext(pl.tracks, playlistId: playlistId); Track t; if (_shuffleEnabled) t = _shuffledPlaylist.isNotEmpty ? _shuffledPlaylist[0] : pl.tracks[0]; else t = pl.tracks[startIndex.clamp(0, pl.tracks.length - 1)]; await playTrack(t, playlistId: playlistId, playlistTracks: pl.tracks); }
  Future<void> importPlaylist(Playlist playlist) async { try { final i = _userPlaylists.indexWhere((p) => p.id == playlist.id); if (i >= 0) _userPlaylists[i] = playlist; else _userPlaylists.add(playlist); await saveUserPlaylists(); _errorMessage = "Imported '${playlist.name}'."; notifyListeners(); } catch (e) { _errorMessage = 'Failed to import playlist.'; _addToRetryQueue(_RetryOperation('Import: ${playlist.name}', () => importPlaylist(playlist))); notifyListeners(); } }

  // --- Downloading ---
  Future<Directory> _getDownloadsDirectory() async { try { final d = await getApplicationSupportDirectory(); final dl = Directory('${d.path}/offline_music'); if (!await dl.exists()) await dl.create(recursive: true); return dl; } catch (e) { throw Exception("Could not access downloads directory."); } }
  Future<String> _buildDownloadFilePath(String trackId) async { final d = await _getDownloadsDirectory(); return '${d.path}/${trackId}.mp3'; }
  Future<void> downloadTrack(Track track) async { final id = track.id; if (await isTrackDownloaded(id)) { _errorMessage = "${track.trackName} downloaded."; notifyListeners(); return; } if (_isDownloading[id] == true) { _errorMessage = "${track.trackName} downloading."; notifyListeners(); return; } if (track.source == 'local') { _errorMessage = "Cannot download local files."; notifyListeners(); return; } if (_isOfflineMode || !_networkService.isConnected) { _errorMessage = 'Offline: Cannot download.'; notifyListeners(); return; } if (_concurrentDownloads >= NetworkConfig.maxConcurrentDownloads) { _addToDownloadQueue(track); return; } CancelToken cT = CancelToken(); _isDownloading[id] = true; _downloadProgress[id] = 0.0; _downloadCancelTokens[id] = cT; _concurrentDownloads++; if (!_currentlyDownloadingTracks.any((t)=> t.id == id)) _currentlyDownloadingTracks.add(track); notifyListeners(); String fP = ''; try { String sId = id; if (track.source == 'spotify') { final yt = await _spotifyService.findYouTubeTrack(track); if (yt != null) sId = yt.id; else throw Exception("No playable version."); } final sUrl = await _apiService.getAudioStreamUrl(sId, NetworkConfig.excellentNetworkBitrate); fP = await _buildDownloadFilePath(id); await _networkService.downloadFile(sUrl, fP, cancelToken: cT, onProgress: (p) { if (_isDownloading[id] == true) { _downloadProgress[id] = p; notifyListeners(); } }); if (!cT.isCancelled) { _downloadedTracksMetadata[id] = { 'track': track, 'filePath': fP, 'downloadDate': DateTime.now() }; await saveDownloadedTracksMetadata(); _errorMessage = "${track.trackName} downloaded."; } else { _errorMessage = "${track.trackName} cancelled."; if (fP.isNotEmpty) try { final f = File(fP); if (await f.exists()) await f.delete(); } catch (_) {} } } catch (e) { if (!cT.isCancelled) { _errorMessage = 'Download failed: ${track.trackName}'; if (fP.isNotEmpty) try { final f = File(fP); if (await f.exists()) await f.delete(); } catch (_) {} bool retry = e is DioException && [DioExceptionType.connectionTimeout, DioExceptionType.sendTimeout, DioExceptionType.receiveTimeout, DioExceptionType.connectionError, DioExceptionType.unknown].contains(e.type); if (retry) _addToRetryQueue(_RetryOperation('Download: ${track.trackName}', () => downloadTrack(track))); } } finally { if (_isDownloading.containsKey(id)) { _isDownloading.remove(id); _downloadProgress.remove(id); _downloadCancelTokens.remove(id); _currentlyDownloadingTracks.removeWhere((t) => t.id == id); _concurrentDownloads = max(0, _concurrentDownloads - 1); } notifyListeners(); _processDownloadQueue(); } }
  void cancelDownload(String trackId) { _downloadQueue.removeWhere((t) => t.id == trackId); _downloadCancelTokens[trackId]?.cancel('Cancelled by user.'); }
  Future<void> deleteDownloadedTrack(String trackId) async { final meta = _downloadedTracksMetadata[trackId]; if (meta == null) { _errorMessage = "Not downloaded."; notifyListeners(); return; } final fp = meta['filePath'] as String?; final tn = (meta['track'] as Track?)?.trackName ?? '?'; try { if (_isPlaying && _isOfflineTrack && _currentTrack?.id == trackId) await stopTrack(); if (fp != null) { final f = File(fp); if (await f.exists()) await f.delete(); } _downloadedTracksMetadata.remove(trackId); await saveDownloadedTracksMetadata(); _errorMessage = "Removed $tn."; } catch (_) { _errorMessage = 'Failed to delete $tn.'; } finally { notifyListeners(); } }
  Future<bool> isTrackDownloaded(String trackId) async { final meta = _downloadedTracksMetadata[trackId]; if (meta != null) { final p = meta['filePath'] as String?; if (p != null && p.isNotEmpty) { if (await File(p).exists()) return true; else { await _handleMissingOfflineFile(trackId, p); return false; } } } return false; }
  Future<String?> getDownloadedTrackPath(String trackId) async { if (await isTrackDownloaded(trackId)) return _downloadedTracksMetadata[trackId]?['filePath'] as String?; return null; }
  Future<List<Track>> getDownloadedTracks() async { List<String> r = []; for (var e in _downloadedTracksMetadata.entries) { final p = e.value['filePath'] as String?; if (p == null || !(await File(p).exists())) r.add(e.key); } if (r.isNotEmpty) { for (var id in r) _downloadedTracksMetadata.remove(id); await _saveDownloadedTracksMetadataInternal(); notifyListeners(); } return _downloadedTracksMetadata.values.where((m) => m['track'] is Track).map((m) => m['track'] as Track).toList(); }
  Future<void> _loadDownloadedTracksMetadata() async { try { final p = await SharedPreferences.getInstance(); final s = p.getString('downloadedTracks'); if (s != null) { final l = jsonDecode(s) as List; _downloadedTracksMetadata = { for (var i in l) if (i['id'] != null && i['filePath'] != null && i['track'] != null) i['id']: { 'track': Track.fromJson(i['track']), 'filePath': i['filePath'], 'downloadDate': i['downloadDate'] != null ? DateTime.fromMillisecondsSinceEpoch(i['downloadDate']) : null } }; } } catch (_) { _downloadedTracksMetadata = {}; } }
  Future<void> saveDownloadedTracksMetadata() async => await _saveDownloadedTracksMetadataInternal();
  Future<void> _saveDownloadedTracksMetadataInternal() async { final l = _downloadedTracksMetadata.values.map((m) => {'id': (m['track'] as Track).id, 'filePath': m['filePath'], 'downloadDate': (m['downloadDate'] as DateTime?)?.millisecondsSinceEpoch, 'track': (m['track'] as Track).toJson()}).toList(); try { final p = await SharedPreferences.getInstance(); await p.setString('downloadedTracks', jsonEncode(l)); } catch (e) { _addToRetryQueue(_RetryOperation('Save dl meta', _saveDownloadedTracksMetadataInternal)); } }
  Future<void> _handleMissingOfflineFile(String trackId, String expectedPath) async { bool mRem = _downloadedTracksMetadata.remove(trackId) != null; if (mRem) await _saveDownloadedTracksMetadataInternal(); int cB = _localTracks.length; _localTracks.removeWhere((t) => t.id == expectedPath); bool lRem = _localTracks.length < cB; if (mRem || lRem) notifyListeners(); }
  void _addToDownloadQueue(Track track) { if (_isDownloading[track.id]==true || _downloadQueue.any((t)=>t.id==track.id) || _downloadedTracksMetadata.containsKey(track.id)) return; _downloadQueue.add(track); _errorMessage = '${track.trackName} queued.'; notifyListeners(); _processDownloadQueue(); }
  Future<void> _processDownloadQueue() async { if (_downloadQueue.isEmpty || _isOfflineMode || !_networkService.isConnected || _concurrentDownloads >= NetworkConfig.maxConcurrentDownloads) return; final t = _downloadQueue.removeAt(0); notifyListeners(); await downloadTrack(t); }
  void pauseAllDownloads({bool clearQueue = false}) { final ids = List<String>.from(_downloadCancelTokens.keys); int c = 0; for (final id in ids) { _downloadCancelTokens[id]?.cancel("Downloads paused"); c++; } if (c > 0) print("Paused $c downloads."); if (clearQueue && _downloadQueue.isNotEmpty) { _downloadQueue.clear(); notifyListeners(); } }

  // --- Spotify Integration ---
  Future<void> importSpotifyPlaylist(String spotifyPlaylistId, String playlistName, String imageUrl) async { if (_isOfflineMode) { _errorMessage = 'Cannot import offline.'; notifyListeners(); return; } _errorMessage = 'Importing Spotify playlist...'; notifyListeners(); try { final playlist = await _spotifyService.getPlaylistWithTracks(spotifyPlaylistId, playlistName, imageUrl); await importPlaylist(playlist); _errorMessage = "Imported '${playlist.name}'."; } catch (e) { _errorMessage = 'Failed to import Spotify: ${e.toString()}'; _addToRetryQueue(_RetryOperation('Import Spotify: $playlistName', () => importSpotifyPlaylist(spotifyPlaylistId, playlistName, imageUrl))); } finally { notifyListeners(); } }

  // --- API Content Fetching ---
  Future<List<Track>> fetchTracks({bool forceRefresh = false}) async { const k = 'popular_music'; if (!forceRefresh && _cachedTracks.containsKey(k)) return _cachedTracks[k]!; if (_isOfflineMode) { _errorMessage = "Offline: No new tracks."; notifyListeners(); return _tracks; } try { _tracks = await _apiService.fetchTracks(); _cachedTracks[k] = _tracks; notifyListeners(); return _tracks; } catch (e) { _errorMessage = 'Failed to load tracks.'; _addToRetryQueue(_RetryOperation('Fetch tracks', () => fetchTracks(forceRefresh: true))); notifyListeners(); return _tracks; } }
  Future<List<Track>> fetchTrendingTracks({bool forceRefresh = false}) async { const k = 'trending_music'; if (!forceRefresh && _cachedTracks.containsKey(k)) { _fullTrendingTracks = _cachedTracks[k]!; _trendingTracks = _fullTrendingTracks.take(5).toList(); return _fullTrendingTracks;} if (_isOfflineMode) { _errorMessage = "Offline: No trending."; notifyListeners(); return _fullTrendingTracks; } try { _fullTrendingTracks = await _apiService.fetchTrendingTracks(); _cachedTracks[k] = _fullTrendingTracks; _trendingTracks = _fullTrendingTracks.take(5).toList(); notifyListeners(); return _fullTrendingTracks; } catch (e) { _errorMessage = 'Failed to load trending.'; _addToRetryQueue(_RetryOperation('Fetch trending', () => fetchTrendingTracks(forceRefresh: true))); notifyListeners(); return _fullTrendingTracks; } }

  // Method for generic track search, used by SearchTabContent
  Future<List<Track>> searchTracks(String query, {bool forceRefresh = false}) async {
    // Note: Caching for generic search results is handled by ApiService if implemented there.
    // This provider method primarily acts as a pass-through.
    if (_isOfflineMode && !_networkService.isConnected) {
      _errorMessage = "Offline: Cannot perform search.";
      notifyListeners();
      return []; // Return empty list in offline mode
    }
    try {
      _clearError(); // Clear previous errors before a new search
      _searchedTracks = await _apiService.fetchTracksByQuery(query);
      notifyListeners(); // Notify listeners that new search results are available
      return _searchedTracks;
    } catch (e) {
      _errorMessage = 'Search failed for "$query": ${e.toString()}';
      _searchedTracks = []; // Clear results on error
      _addToRetryQueue(_RetryOperation('Search tracks: $query', () => searchTracks(query, forceRefresh: true)));
      notifyListeners();
      return []; // Return empty list on error
    }
  }

  Future<void> fetchArtistTracks(String artistName, {bool forceRefresh = false}) async { final k = 'artist_$artistName'; if (!forceRefresh && _cachedTracks.containsKey(k)) { _artistTracks = _cachedTracks[k]!; notifyListeners(); return; } if (_isOfflineMode) { _errorMessage = "Offline: No artist tracks."; notifyListeners(); return; } try { _artistTracks = await _apiService.fetchTracksByQuery('$artistName top tracks'); _cachedTracks[k] = _artistTracks; notifyListeners(); } catch (e) { _errorMessage = 'Failed for $artistName.'; _addToRetryQueue(_RetryOperation('Fetch artist: $artistName', () => fetchArtistTracks(artistName, forceRefresh: true))); notifyListeners(); } }
  Future<void> fetchGenreTracks(String genre, {bool forceRefresh = false}) async { final k = 'genre_$genre'; if (!forceRefresh && _cachedTracks.containsKey(k)) { _genreTracks = _cachedTracks[k]!; notifyListeners(); return; } if (_isOfflineMode) { _errorMessage = "Offline: No genre tracks."; notifyListeners(); return; } try { _genreTracks = await _apiService.fetchTracksByQuery('$genre music'); _cachedTracks[k] = _genreTracks; notifyListeners(); } catch (e) { _errorMessage = 'Failed for $genre.'; _addToRetryQueue(_RetryOperation('Fetch genre: $genre', () => fetchGenreTracks(genre, forceRefresh: true))); notifyListeners(); } }

  // --- Retry Queue ---
  void _startRetryTimer() { _retryTimer?.cancel(); _retryTimer = Timer.periodic(const Duration(seconds: 45), (t) { if (_networkService.isConnected && !_isOfflineMode && _retryQueue.isNotEmpty) _processRetryQueue(); }); }
  void _addToRetryQueue(_RetryOperation operation) { if (!_retryQueue.any((op) => op.description == operation.description)) { _retryQueue.add(operation); if (_networkService.isConnected && !_isOfflineMode) _processRetryQueue(); } }
  Future<void> _processRetryQueue() async { if (_retryQueue.isEmpty || _isOfflineMode || !_networkService.isConnected) return; final op = _retryQueue.removeAt(0); try { await op.execute(); if (_retryQueue.isNotEmpty) Future.delayed(const Duration(seconds: 2), _processRetryQueue); } catch (e) { if (op.attempts < _maxRetryAttempts) { op.attempts++; _retryQueue.add(op); } else { _errorMessage = "Failed ${op.description}."; notifyListeners(); } if (_retryQueue.isNotEmpty) Future.delayed(const Duration(seconds: 5), _processRetryQueue); } }

  void clearSearchResults() {
    _searchedTracks.clear();
    _artistTracks.clear();
    // Potentially clear other search-related lists here if they exist
    notifyListeners();
  }

  // --- Utility & Diagnostics ---
  Track? getTrackById(String id) { if (_currentTrack?.id == id) return _currentTrack; Track? find(List<Track> l, String i) { try { return l.firstWhere((t) => t.id == i); } catch (_) { return null; } } Track? f; f = find(_localTracks, id); if (f != null) return f; f = find(_likedSongs, id); if (f != null) return f; if (_downloadedTracksMetadata.containsKey(id)) { final d = _downloadedTracksMetadata[id]?['track']; if (d is Track) return d; } f = find(_recentlyPlayed, id); if (f != null) return f; f = find(_tracks, id); if (f != null) return f; f = find(_fullTrendingTracks, id); if (f != null) return f; for (final p in _userPlaylists) { f = find(p.tracks, id); if (f != null) return f; } f = find(_artistTracks, id); if (f != null) return f; f = find(_genreTracks, id); if (f != null) return f; return null; }
  Future<Map<String, dynamic>> runNetworkDiagnostics() async { final d=<String, dynamic>{}; try { d['OfflineMode']=_isOfflineMode; d['ManualOffline']=_userManuallySetOffline; d['NetSvc Conn']=_networkService.isConnected; d['NetQual']=_networkService.networkQuality.toString(); d['ConnType']=(await _networkService.getConnectionType()).toString(); if(_networkService.isConnected){try{final r=await http.get(Uri.parse('https://www.google.com/favicon.ico')).timeout(const Duration(seconds:5));d['PingTest']='${r.statusCode}(${r.contentLength}b)';}catch(e){d['PingTest']='Failed($e)';}} d['LowData']=_isLowDataMode; d['WiFi BR'] = _wifiBitrate; d['Cell BR'] = _cellularBitrate; d['Est BR'] = await _getBitrate(); d['Shuffle']=_shuffleEnabled; d['Repeat']=_repeatMode.toString(); d['DLQ']=_downloadQueue.length; d['RetryQ']=_retryQueue.length; d['ConcDL']=_concurrentDownloads; return d; } catch (e) { d['Error']=e.toString(); return d; } }
  Future<void> clearAllCaches() async { try { await _apiService.clearCache(); _cachedTracks.clear(); _tracks = []; _trendingTracks = []; _fullTrendingTracks = []; _artistTracks = []; _genreTracks = []; _retryQueue.clear(); _errorMessage = 'Caches cleared.'; notifyListeners(); if (_networkService.isConnected && !_isOfflineMode) { await fetchTracks(); await fetchTrendingTracks(); } } catch (_) { _errorMessage = 'Failed cache clear.'; notifyListeners(); } }

  // --- Dispose ---
  @override
  void dispose() {
    print('MusicProvider: Disposing...');
    _audioService.dispose();
    _retryTimer?.cancel();
    _networkQualitySubscription?.cancel();
    _connectivityStatusSubscription?.cancel();
    _reconnectionTimer?.cancel();
    _downloadCancelTokens.forEach((_, token) { if (!token.isCancelled) token.cancel("Provider disposed"); });
    _downloadCancelTokens.clear();
    print('MusicProvider: Disposed.');
    super.dispose();
  }

} // End of MusicProvider class

// Helper class for retry operations (Keep as is)
class _RetryOperation {
  final String description;
  final Future<dynamic> Function() execute;
  int attempts = 1;
  _RetryOperation(this.description, this.execute);
}