// lib/providers/music_provider.dart

// Dart Core Libraries
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:just_audio/just_audio.dart'; // Import for PlayerState
import 'dart:math';

// Flutter Foundation & Material
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // Added for NetworkImage

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
import '../services/audio_service.dart'; // Your audio player wrapper
import '../services/spotify_service.dart';
import '../services/local_music_service.dart'; 
import '../services/network_service.dart';
import '../services/innertube/innertube_service.dart';
import '../services/cast_service.dart'; // Cast Service
import 'package:cast/cast.dart'; // Cast Models
import '../services/lyrics/lyrics_service.dart'; // Multi-provider lyrics service
import '../models/lyrics_entry.dart'; // Lyrics data model
// import '../services/firestore_service.dart'; // Uncomment if used

// Your Project Utility Imports
import '../utils/network_config.dart';

// Your Project Model Imports (Music Source)
// Your Project Model Imports (Music Source)
import '../models/music_source.dart'; // Music source enum
import 'package:palette_generator/palette_generator.dart'; // Dynamic colors

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
  final GlobalKey<NavigatorState> playerNavigatorKey = GlobalKey<NavigatorState>();
  // --- State Properties ---
  List<Track> _tracks = [];
  List<Track> _trendingTracks = [];
  List<Track> _fullTrendingTracks = [];
  List<Track> _recentlyPlayed = [];
  List<Track> _likedSongs = [];
  List<Track> _searchedTracks = []; // For generic track search results
  List<Track> _artistTracks = [];
  List<Track> _genreTracks = [];
  List<Track> _recommendedTracks = []; // New field for "For You"
  List<Playlist> _userPlaylists = [];
  List<Track> _localTracks = [];
  SortCriteria _localTracksSortCriteria = SortCriteria.nameAsc;
  
  bool _isOfflineContext = false; // Explicit flag for offline playback context

  // Search State
  List<Track> _playlistSearchResults = []; 
  List<Track> get playlistSearchResults => List.unmodifiable(_playlistSearchResults);
  
  // Getters
  
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
  int _wifiBitrate = NetworkConfig.goodNetworkBitrate;
  int _cellularBitrate = NetworkConfig.moderateNetworkBitrate;
  bool _isOfflineMode = false;

  // Navigation State
  bool _isPlayerExpanded = false;
  bool get isPlayerExpanded => _isPlayerExpanded;
  
  void setPlayerExpanded(bool expanded) {
    if (_isPlayerExpanded != expanded) {
      _isPlayerExpanded = expanded;
      notifyListeners();
    }
  }

  // Mini player visibility (for bottom sheets)
  bool _hideMiniPlayer = false;
  bool get hideMiniPlayer => _hideMiniPlayer;
  
  void setHideMiniPlayer(bool hide) {
    if (_hideMiniPlayer != hide) {
      _hideMiniPlayer = hide;
      notifyListeners();
    }
  }

  bool _userManuallySetOffline = false;
  bool _isLowDataMode = false;
  bool _isAutoBitrate = true; // Default to Auto
  bool _isReconnecting = false;
  Timer? _reconnectionTimer;
  String? _errorMessage;
  bool _isLoadingLocal = false;
  Artist? _currentArtistDetails; // Added state for artist screen
  Album? _currentAlbumDetails; // Added state for album screen
  bool _isLoadingArtist = false; // Loading state for artist screen
  bool _isLoadingAlbum = false; // Loading state for album screen
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _isDownloading = {};
  final List<Track> _currentlyDownloadingTracks = [];
  final Map<String, CancelToken> _downloadCancelTokens = {};
  int _concurrentDownloads = 0;
  final List<Track> _downloadQueue = [];
  Map<String, Map<String, dynamic>> _downloadedTracksMetadata = {};
  final Map<String, List<Track>> _cachedTracks = {};
  
  // FIX: Audio subscription management for proper cleanup
  final List<StreamSubscription> _audioSubscriptions = [];
  Timer? _notifyDebouncer;
  bool _notifyPending = false;
  bool _isStopping = false; // Flag to prevent redundant stopTrack calls
  
  // Error Tracking for auto-failover
  int _consecutiveErrors = 0;
  
  // Discovery Caching (TTL based)
  final Map<String, DateTime> _discoveryCacheTimes = {};
  static const Duration _discoveryCacheTTL = Duration(minutes: 30);
  
  // Search Caching (Speed up back/forth)
  final Map<String, List<Track>> _searchCache = {};
  
  // Download file validity cache to avoid repeated I/O
  final Map<String, bool> _downloadedFileCache = {};
  DateTime? _lastCacheRefresh;

  // Services
  final AudioService _audioService = AudioService();
  final SpotifyService _spotifyService = SpotifyService();
  final LocalMusicService _localMusicService = LocalMusicService();
  final NetworkService _networkService = NetworkService();
  final InnerTubeService _innerTubeService = InnerTubeService();
  final CastService _castService = CastService(); // Cast Service Instance

  // Cast State
  bool _isCasting = false;
  bool _isSearchingDevices = false;
  List<CastDevice> _castDevices = [];
  
  // Palette State
  PaletteGenerator? _paletteGenerator;
  PaletteGenerator? get paletteGenerator => _paletteGenerator;
  final Map<String, PaletteGenerator> _paletteCache = {}; // Cache for fast transitions

  // Cast Getters
  bool get isCasting => _isCasting;
  bool get isSearchingDevices => _isSearchingDevices;
  List<CastDevice> get castDevices => _castDevices;
  CastService get castService => _castService;
  
  // Audio Service getter (for equalizer access)
  AudioService get audioService => _audioService;
  
  // Download Status Check (sync for UI)
  bool isTrackDownloadedSync(String trackId) => _downloadedTracksMetadata.containsKey(trackId);

  // Audio State // YouTube Music InnerTube API
  final LyricsService _lyricsService = LyricsService(); // Multi-provider lyrics service
  MusicSource _currentMusicSource = MusicSource.youtube; // Default to YouTube (InnerTube)
  
  // Lyrics state
  List<LyricsEntry>? _currentLyrics;
  bool _isLoadingLyrics = false;
  String? _lyricsError;
  String? _lyricsTrackId; // To verify if cached lyrics belong to current track
  
  // Getters
  List<LyricsEntry>? get currentLyrics => _currentLyrics;
  bool get isLoadingLyrics => _isLoadingLyrics;
  String? get lyricsError => _lyricsError;
  bool get hasSyncedLyrics => _currentLyrics != null && _currentLyrics!.isNotEmpty;
  
  // Method to fetch lyrics
  Future<void> fetchLyrics({bool forceRefresh = false}) async {
    if (_currentTrack == null) return;
    
    // Return if already loaded for this track AND not forcing refresh
    if (!forceRefresh && _lyricsTrackId == _currentTrack!.id && _currentLyrics != null) {
      if (kDebugMode) print("MusicProvider: Using cached lyrics for ${_currentTrack!.trackName}");
      return; 
    }
    
    _isLoadingLyrics = true;
    _lyricsError = null;
    _currentLyrics = null;
    _lyricsTrackId = _currentTrack!.id;
    notifyListeners();
    
    try {
      if (kDebugMode) print("MusicProvider: Fetching lyrics for ${_currentTrack!.trackName} (Force: $forceRefresh)");
      final entries = await _lyricsService.getParsedLyrics(
        title: _currentTrack!.trackName,
        artist: _currentTrack!.artistName,
        durationMs: _currentTrack!.durationMs ?? _duration.inMilliseconds,
        videoId: _currentTrack!.source == 'youtube' ? _currentTrack!.id : null,
      );
      
      // Ensure we haven't changed tracks while fetching
      if (_lyricsTrackId == _currentTrack!.id) {
        _currentLyrics = entries;
        if (entries.isEmpty) {
          _lyricsError = "No lyrics found";
        }
      }
    } catch (e) {
      // FIX: Use null-safe check to prevent crash if currentTrack becomes null
      if (_currentTrack != null && _lyricsTrackId == _currentTrack!.id) {
        _lyricsError = "Failed to load lyrics";
        print("Lyrics Fetch Error: $e");
      }
    } finally {
      // FIX: Use null-safe check to prevent crash if currentTrack becomes null
      if (_currentTrack != null && _lyricsTrackId == _currentTrack!.id) {
        _isLoadingLyrics = false;
        notifyListeners();
      }
    }
  }
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
  List<Track> get recommendedTracks => List.unmodifiable(_recommendedTracks); // Getter
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
  bool get isAutoBitrate => _isAutoBitrate;
  bool get shuffleEnabled => _shuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  String? get currentPlaylistId => _currentPlaylistId;
  MusicSource get currentMusicSource => _currentMusicSource; // Music source getter
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
  DateTime? _lastPositionNotify;
  MusicProvider() { _initialize(); }
  
  Future<void> _initialize() async {
    if (kDebugMode) print('MusicProvider: Initializing...');
    
    await _loadSettings();
    await _loadLikedSongs();
    await _loadRecentlyPlayed();
    await loadUserPlaylists();
    await _loadDownloadedTracksMetadata();
    
    _setupAudioListeners();
    _startRetryTimer();
    _setupConnectivityMonitoring();
    
    final isConnected = _networkService.isConnected;
    if (isConnected && !_isOfflineMode) {
      try {
        await Future.wait([
          fetchTracks(),
          fetchTrendingTracks()
        ]);
      } catch (e) {
        _errorMessage = 'Could not load initial content.';
        if (kDebugMode) print('MusicProvider: Error loading initial content: $e');
      }
    } else {
      _errorMessage = _isOfflineMode
          ? (_userManuallySetOffline ? 'Currently in offline mode.' : 'No internet connection.')
          : 'No internet connection.';
    }
    
    unawaited(loadLocalMusicFiles());
    if (kDebugMode) print('MusicProvider: Initialization complete.');
  }
  
  // FIX: Debounced notification to avoid excessive UI rebuilds
  void _debouncedNotify() {
    if (_notifyPending) return;
    _notifyPending = true;
    _notifyDebouncer?.cancel();
    _notifyDebouncer = Timer(const Duration(milliseconds: 50), () {
      _notifyPending = false;
      notifyListeners();
    });
  }
  
  void _setupAudioListeners() {
    if (kDebugMode) print('MusicProvider: Setting up audio listeners...');
    
    // FIX: Store all subscriptions for proper cleanup
    // Position stream
    _audioSubscriptions.add(_audioService.onPositionChanged.listen((pos) {
      // FIX: Skip position updates when not playing to save battery
      if (!_isPlaying) return;
      
      if (_position != pos) {
        _position = pos;
        // THROTTLE: Only notify at most every 1000ms to save battery/UI
        final now = DateTime.now();
        if (_lastPositionNotify == null || now.difference(_lastPositionNotify!) > const Duration(milliseconds: 1000)) {
             _debouncedNotify();
             _lastPositionNotify = now;
        }
      }
    }, onError: (e) {
      if (kDebugMode) print("MusicProvider: Position stream error: $e");
    }));
    
    // Duration stream
    _audioSubscriptions.add(_audioService.onDurationChanged.listen((dur) {
      if ((_duration - dur).abs() > const Duration(milliseconds: 500) && dur > Duration.zero) {
        if (kDebugMode) print('MusicProvider: Duration updated: $dur');
        _duration = dur;
        _debouncedNotify();
      }
    }, onError: (e) {
      if (kDebugMode) print("MusicProvider: Duration stream error: $e");
    }));
    
    // Playback state stream - THIS IS CRITICAL
    _audioSubscriptions.add(_audioService.onPlaybackStateChanged.listen((playing) {
      if (kDebugMode) {
        print('MusicProvider: Playback state changed: $playing (was: $_isPlaying)');
        if (_currentTrack != null) {
          print('MusicProvider: Current track: ${_currentTrack!.trackName}');
        }
      }
      
      if (_isPlaying != playing) {
        _isPlaying = playing;
        
        if (!playing && _currentTrack != null) {
          if (kDebugMode) print('MusicProvider: ⚠️ Playback stopped unexpectedly!');
        }
        
        notifyListeners(); // Immediate notify for play/pause
      }
    }, onError: (e) {
      if (kDebugMode) print("MusicProvider: Playback state stream error: $e");
    }));
    
    // FIX: Restore track completion handling via playerStateStream
    // This listener handles both debugging AND track completion detection
    _audioSubscriptions.add(_audioService.playerStateStream.listen((state) {
      if (kDebugMode) {
        print('MusicProvider: Player state: ${state.playing ? "PLAYING" : "PAUSED"}, '
              'Processing: ${state.processingState}');
      }
      
      // FIX: Detect track completion and advance to next track
      // ProcessingState.completed means the current track finished playing
      if (state.processingState == ProcessingState.completed && 
          _currentTrack != null && 
          !_isStopping) {
        if (kDebugMode) print('MusicProvider: Track completed naturally, calling _onTrackComplete');
        _onTrackComplete();
      }
    }, onError: (e) {
      if (kDebugMode) print("MusicProvider: Player state stream error: $e");
    }));
    
    if (kDebugMode) print('MusicProvider: Audio listeners set up complete');
    
    // --- Navigation Listeners ---
    _audioSubscriptions.add(_audioService.onSkipToNext.listen((_) {
      if (kDebugMode) print("MusicProvider: External SkipNext triggered (Notification/LockScreen)");
      skipToNext();
    }));
    
    _audioSubscriptions.add(_audioService.onSkipToPrevious.listen((_) {
      if (kDebugMode) print("MusicProvider: External SkipPrevious triggered (Notification/LockScreen)");
      skipToPrevious();
    }));
    
    // Listen for Critical Playback Errors (Corrupt Files)
    _audioSubscriptions.add(_audioService.onPlaybackError.listen((error) async {
       if (error == "Source error" && _currentTrack != null) {
           if (kDebugMode) print("MusicProvider: Source error detected for ${_currentTrack!.trackName}");
           final id = _currentTrack!.id;
           final isDownloaded = _downloadedTracksMetadata.containsKey(id);
           
           if (isDownloaded || _currentTrack!.source == 'local') {
               final path = _currentTrack!.source == 'local' ? _currentTrack!.previewUrl : 
                            (_downloadedTracksMetadata[id]?['filePath'] ?? '');
                            
               if (path.isNotEmpty) {
                  await _handleMissingOfflineFile(id, path);
                  if (!_isOfflineMode && _networkService.isConnected) {
                       playTrack(_currentTrack!); 
                  } else {
                       await stopTrack(); 
                  }
               }
           } else {
              _handlePlaybackError("Source error: Stream unrecognized.");
           }
        } else {
           _handlePlaybackError(error);
        }
     }));
  }

  // --- Settings Persistence ---
  Future<void> _loadSettings() async { 
    try { 
      final p = await SharedPreferences.getInstance(); 
      _wifiBitrate = p.getInt('wifiBitrate') ?? NetworkConfig.goodNetworkBitrate; 
      _cellularBitrate = p.getInt('cellularBitrate') ?? NetworkConfig.moderateNetworkBitrate; 
      _isOfflineMode = p.getBool('offlineMode') ?? false; 
      _userManuallySetOffline = p.getBool('userManuallySetOffline') ?? false; 
      _isLowDataMode = p.getBool('lowDataMode') ?? false; 
      _isAutoBitrate = p.getBool('isAutoBitrate') ?? true;
      _shuffleEnabled = p.getBool('shuffleEnabled') ?? false; 
      
      final sourceValue = p.getString('musicSource') ?? 'youtube'; 
      _currentMusicSource = MusicSource.fromString(sourceValue); 
      
      if (kDebugMode) {
        print('Settings: Loaded music source = "$sourceValue" → ${_currentMusicSource.displayName}');
      }
      
      try { 
        _repeatMode = RepeatMode.values[p.getInt('repeatMode') ?? RepeatMode.off.index]; 
      } catch (_) { 
        _repeatMode = RepeatMode.off; 
      } 
      try { 
        _localTracksSortCriteria = SortCriteria.values[p.getInt('localSortCriteria') ?? SortCriteria.nameAsc.index]; 
      } catch (_) { 
        _localTracksSortCriteria = SortCriteria.nameAsc; 
      } 
      
      if (kDebugMode) {
        print('Settings loaded successfully.');
      }
    } catch (e) { 
      if (kDebugMode) {
        print("Error loading settings: $e"); 
      }
    } 
  }
  Future<void> _saveSettings() async { 
    try { 
      final p = await SharedPreferences.getInstance(); 
      await p.setInt('wifiBitrate', _wifiBitrate); 
      await p.setInt('cellularBitrate', _cellularBitrate); 
      await p.setBool('offlineMode', _isOfflineMode); 
      await p.setBool('userManuallySetOffline', _userManuallySetOffline); 
      await p.setBool('lowDataMode', _isLowDataMode); 
      await p.setBool('isAutoBitrate', _isAutoBitrate);
      await p.setBool('shuffleEnabled', _shuffleEnabled); 
      await p.setString('musicSource', _currentMusicSource.value); 
      await p.setInt('repeatMode', _repeatMode.index); 
      await p.setInt('localSortCriteria', _localTracksSortCriteria.index); 
      
      if (kDebugMode) {
        print('Settings: Saved music source = "${_currentMusicSource.value}" (${_currentMusicSource.displayName})');
        print('Settings saved successfully.');
      }
    } catch (e) { 
      _errorMessage = "Failed to save settings."; 
      if (kDebugMode) {
        print('Settings: Error saving - $e');
      }
      notifyListeners(); 
    } 
  }

  // --- Playback Control & Context ---
  void toggleShuffle() { _shuffleEnabled = !_shuffleEnabled; if (_shuffleEnabled && _currentPlayingTracks != null) { _shufflePlaylist(); } else { _updateCurrentIndex(); } _saveSettings(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void cycleRepeatMode() { _repeatMode = RepeatMode.values[(_repeatMode.index + 1) % RepeatMode.values.length]; _saveSettings(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void _shufflePlaylist() { if (_currentPlayingTracks == null || _currentPlayingTracks!.isEmpty) { _shuffledPlaylist = []; _currentIndex = -1; return; } _shuffledPlaylist = List.from(_currentPlayingTracks!)..shuffle(Random()); _updateCurrentIndex(); /* Preload handled by toggleShuffle or setPlaybackContext */ }
  List<Track> _getActivePlaylist() => _shuffleEnabled ? _shuffledPlaylist : (_currentPlayingTracks ?? []);
  void _updateCurrentIndex() { final list = _getActivePlaylist(); _currentIndex = (_currentTrack != null && list.isNotEmpty) ? list.indexWhere((t) => t.id == _currentTrack!.id) : -1; }
  void _setPlaybackContext(List<Track>? tracks, {String? playlistId, bool clearQueue = true}) { if (!listEquals(_currentPlayingTracks, tracks) || _currentPlaylistId != playlistId) { print("Setting playback context. ID: $playlistId, Tracks: ${tracks?.length ?? 0}, ClearQueue: $clearQueue"); _currentPlayingTracks = tracks != null ? List.from(tracks) : null; _currentPlaylistId = playlistId; if (clearQueue && _queue.isNotEmpty) { _queue.clear(); print("Playback context changed, queue cleared."); } if (_shuffleEnabled && _currentPlayingTracks != null) {
    _shufflePlaylist();
  } else {
    _updateCurrentIndex();
  } _handlePlaybackOrContextChangeForPreloading();} else { _updateCurrentIndex(); }  }
  void _onTrackComplete() {
    if (kDebugMode) print('MusicProvider: _onTrackComplete event for ${_currentTrack?.trackName}');
    
    if (_stopAfterCurrentTrack) {
      _stopAfterCurrentTrack = false;
      stopTrack();
      return;
    }

    if (_repeatMode == RepeatMode.one) {
       seekTo(Duration.zero);
       if(!_isPlaying) resumeTrack();
       _handlePlaybackOrContextChangeForPreloading();
       return;
    }

    _updateCurrentIndex();
    
    // 1. Check Queue
    if (_queue.isNotEmpty) {
       final next = _queue.removeAt(0);
       if (kDebugMode) print("MusicProvider: Playing next from queue: ${next.trackName}");
       _playTrackInternal(next, setContext: false, clearQueue: false);
       notifyListeners(); 
       return;
    }

    // 2. Standard Playlist Path
    final list = _getActivePlaylist();
    if (list.isEmpty) {
       stopTrack();
       return;
    }

    int nextIdx = _currentIndex + 1;
    if (nextIdx < list.length) {
       if (kDebugMode) print('MusicProvider: Advancing to index $nextIdx');
       _playTrackInternal(list[nextIdx], setContext: false, clearQueue: false);
    } else {
       _handleEndOfPlaylist();
    }
  }

  /// Unified logic for when a playlist reaches the end (completion or SkipNext)
  void _handleEndOfPlaylist() {
    final list = _getActivePlaylist();
    if (list.isEmpty) {
       stopTrack();
       return;
    }

    if (_repeatMode == RepeatMode.all) {
       if (kDebugMode) print('MusicProvider: Looping context to start.');
       _playTrackInternal(list[0], setContext: false, clearQueue: false);
    } else {
       // FIX: Smart Autoplay - Loop back to start for ANY playlist context
       // This ensures artist tracks, album tracks, search results all loop
       // instead of abruptly stopping (which disrupts UI/UX)
       bool isListNotEmpty = list.isNotEmpty;
       bool isFirstLocal = isListNotEmpty && list.first.source == 'local';
       bool isFirstDownloaded = isListNotEmpty && _downloadedTracksMetadata.containsKey(list.first.id);
       bool isOfflineContext = isListNotEmpty && (isFirstLocal || isFirstDownloaded || _isOfflineTrack || _isOfflineContext);
       
       if (isOfflineContext) {
           if (kDebugMode) print('MusicProvider: End of Downloaded List -> Looping to start (Smart Autoplay)');
           _playOfflineTrackInternal(list[0], setContext: false, clearQueue: false);
       } else if (isListNotEmpty && _currentPlayingTracks != null && _currentPlayingTracks!.length > 1) {
           // FIX: For online playlists (artist, album, etc.), loop to start for seamless experience
           if (kDebugMode) print('MusicProvider: End of Online Playlist -> Looping to start (Smart Autoplay)');
           _playTrackInternal(list[0], setContext: false, clearQueue: false);
       } else {
           if (kDebugMode) print('MusicProvider: End of context, Repeat off, stopping.');
           stopTrack();
       }
    }
  }
  Future<void> _playTrackInternal(Track track, {bool setContext = true, bool clearQueue = true}) async { 
    if (setContext) {
      _setPlaybackContext(_currentPlayingTracks, playlistId: _currentPlaylistId, clearQueue: clearQueue);
    } else { 
      // Do NOT update _currentTrack here. playTrack() handles it.
      // Updating it here causes playTrack to think we are toggling the current song.
      // _currentTrack = track; 
      _updateCurrentIndex(); 
    } 
    
    // Check offline status
    bool offline = await _shouldPlayOffline(track); 
    
    try { 
      if (offline) {
        await playOfflineTrack(track, setContext: setContext, clearQueue: clearQueue);
      } else {
        await playTrack(track, playlistTracks: _currentPlayingTracks, playlistId: _currentPlaylistId, setContext: setContext, clearQueue: clearQueue);
      } 
    } catch(e) { 
      print("Error in _playTrackInternal: $e"); 
    } 
  }
  Future<bool> _shouldPlayOffline(Track track) async => track.source == 'local' || await isTrackDownloaded(track.id);
  Future<void> skipToNext() async { 
    print('MusicProvider: SkipNext requested.'); 
    if (_currentTrack == null) return; 
    if (_queue.isNotEmpty) { 
      final next = _queue.removeAt(0); 
      print("MusicProvider: Skipping to next from queue: ${next.trackName}"); 
      await _playTrackInternal(next, setContext: false, clearQueue: false); 
      notifyListeners(); 
      return; 
    } 
    final list = _getActivePlaylist(); 
    if (list.isEmpty) return; 
    _updateCurrentIndex(); 
    if (_currentIndex == -1 && list.isNotEmpty) { 
      await _playTrackInternal(list[0]); 
      return; 
    } 
    int next = _currentIndex + 1; 
    if (next < list.length) { 
      await _playTrackInternal(list[next]); 
    } else { 
      _handleEndOfPlaylist(); // Unified logic
    } 
  }
  Future<void> skipToPrevious() async { print('SkipPrevious requested.'); if (_currentTrack == null) return; if (_position > const Duration(seconds: 3)) { await seekTo(Duration.zero); if (!_isPlaying) await resumeTrack(); _handlePlaybackOrContextChangeForPreloading(); return; } final list = _getActivePlaylist(); if (list.isEmpty) return; _updateCurrentIndex(); if (_currentIndex == -1 && list.isNotEmpty) { await _playTrackInternal(list.last); return; } int prev = _currentIndex - 1; if (prev >= 0) { await _playTrackInternal(list[prev]); } else { if (_repeatMode != RepeatMode.off) {
    await _playTrackInternal(list.last);
  } else { await seekTo(Duration.zero); if (!_isPlaying) await resumeTrack(); _handlePlaybackOrContextChangeForPreloading(); } } /* Preload handled by playTrackInternal if it plays */ }

  // --- Helper Methods for Navigation State ---
  bool _hasNext() {
    if (_queue.isNotEmpty) return true;
    final list = _getActivePlaylist();
    if (list.isEmpty) return false;
    if (_repeatMode != RepeatMode.off) return true; 
    return _currentIndex < list.length - 1;
  }
  
  bool _hasPrevious() {
    // If repeat is one or all, we can technically go back (restarts or wraps)
    if (_repeatMode != RepeatMode.off) return true;
    final list = _getActivePlaylist();
    if (list.isEmpty) return false;
    return _currentIndex > 0;
  }

  // --- Core Playback Methods ---
  Future<void> playTrack(
      Track track, {
        String? playlistId,
        List<Track>? playlistTracks,
        bool setContext = true,
        bool clearQueue = true,
      }) async {
    if (kDebugMode) {
      print('MusicProvider: Request playTrack: ${track.trackName} (ID: ${track.id})');
    }

    // If currently playing same track, pause (toggle)
    if (_currentTrack?.id == track.id && _isPlaying) {
      await pauseTrack();
      return;
    }

    // If currently loaded but paused, resume
    if (_currentTrack?.id == track.id && !_isPlaying && _currentTrack != null) {
      await resumeTrack();
      return;
    }

    _isOfflineContext = false; // Reset offline flag for online playback
    
    // Resume audio service if it was stopped
    // await _audioService.resume(); // (Not needed, play() handles it)
    
    _clearError();
    
    // FIX: Early validation for non-playable track IDs
    // Playlist/Album/Channel IDs cannot be streamed - they need to be browsed first
    final trackId = track.id;
    if (trackId.startsWith('UC') ||     // Artist/Channel
        trackId.startsWith('VL') ||     // Playlist
        trackId.startsWith('PL') ||     // Playlist
        trackId.startsWith('OLAK') ||   // Album
        trackId.startsWith('MPREb')) {  // Album browse ID
      if (kDebugMode) print('MusicProvider: Skipping non-playable track: ${track.trackName} (ID: $trackId)');
      _errorMessage = 'Cannot play ${track.trackName} - it is a ${trackId.startsWith("UC") ? "channel" : "playlist/album"}, not a song.';
      notifyListeners();
      return; // Don't try to play, don't skip - just return early
    }    
    try {
      // Stop current playback if any
      if (_isPlaying) {
        await _audioService.stop();
      }
      
      // Set context before attempting playback
      if (setContext) {
        _setPlaybackContext(playlistTracks, playlistId: playlistId, clearQueue: clearQueue);
      }

      // Check if should play offline version
      bool playOffline = await _shouldPlayOffline(track);
      if (playOffline) {
        await playOfflineTrack(track, setContext: setContext, clearQueue: clearQueue);
        return;
      }

      // Check network availability for online playback
      if (_isOfflineMode) {
        throw Exception('Offline mode enabled. Track not available offline.');
      }
      
      if (!_networkService.isConnected) {
        throw Exception('No internet connection available.');
      }

      // Update current track state
      _currentTrack = track;
      _paletteGenerator = null; // Reset palette immediately
      _isOfflineTrack = false;
      _updateCurrentIndex();
      notifyListeners();
      
      // Start generating palette in parallel (don't await)
      updatePalette();

      String playableId = track.id;
      Track effectiveTrack = track; // Restored
      // Start bitrate check early (parallelize with other work)
      final bitrateFuture = _getBitrate();

      // Handle Spotify tracks - convert to YouTube
      if (track.source == 'spotify') {
        if (kDebugMode) {
          print('MusicProvider: Converting Spotify track to YouTube: ${track.trackName}');
        }
        final yt = await _spotifyService.findYouTubeTrack(track);
        if (yt != null) {
          playableId = yt.id;
          effectiveTrack = track.copyWith(
            id: playableId,
            source: 'youtube',
            previewUrl: yt.previewUrl,
          );
          _currentTrack = effectiveTrack;
          notifyListeners();
        } else {
          throw Exception("Could not find playable version of '${track.trackName}'.");
        }
      }

      // Handle cross-source playback: If track source doesn't match current music source
      // Try to find equivalent track in current source or fall back to track's original source
      if (_shouldSearchForEquivalent(track)) {
        if (kDebugMode) {
          print('MusicProvider: Track source (${track.source}) differs from current source ($_currentMusicSource)');
          print('MusicProvider: Searching for equivalent track in ${_currentMusicSource.displayName}');
        }
        
        try {
          final equivalentTrack = await _findEquivalentTrack(track);
          if (equivalentTrack != null) {
            if (kDebugMode) {
              print('MusicProvider: Found equivalent: ${equivalentTrack.trackName} (${equivalentTrack.id})');
            }
            playableId = equivalentTrack.id;
            effectiveTrack = equivalentTrack;
            _currentTrack = effectiveTrack;
            notifyListeners();
          } else {
            // If no equivalent found, use the track's original source for this playback
            if (kDebugMode) {
              print('MusicProvider: No equivalent found, using original source for this track');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('MusicProvider: Error finding equivalent track: $e');
            print('MusicProvider: Falling back to original track source');
          }
        }
      }

      // Await the bitrate that was started earlier
      final bitrate = await bitrateFuture;
      if (bitrate == 0) {
        throw Exception('Cannot determine bitrate - check network connection.');
      }

      if (kDebugMode) {
        print('MusicProvider: Fetching stream URL for ${effectiveTrack.trackName} (bitrate: $bitrate kbps)');
      }


      // Get stream URL or Source using InnerTube service
      dynamic result;
      
      try {
        if (kDebugMode) {
          print('MusicProvider: Fetching stream via InnerTube for $playableId');
        }
        // Changed from getAudioStreamUrl to getAudioStream to support StreamProxy
        result = await _innerTubeService.getAudioStream(playableId, preferredBitrate: 128);
      } catch (e) {
        if (kDebugMode) {
          print('MusicProvider: InnerTube stream fetch failed: $e');
        }
        throw Exception('Failed to get stream: $e');
      }
      
      if (result == null) {
        throw Exception('Received empty stream result');
      }

      if (kDebugMode) {
        print('MusicProvider: Stream fetched. Type: ${result.runtimeType}');
      }

      // Play the audio based on result type
      try {
        if (result is AudioSource) {
           // Proxy Source (YoutubeExplode)
           await _audioService.play(null, 
             customSource: result,
             title: effectiveTrack.trackName,
             artist: effectiveTrack.artistName,
             artUri: effectiveTrack.albumArtUrl,
             id: effectiveTrack.id,
             hasNext: _hasNext(),
             hasPrevious: _hasPrevious(),
           );
        } else if (result is String) {
           // URL (Fallback)
           if (result.isEmpty) throw Exception('Empty URL received');
           await _audioService.play(result,
             title: effectiveTrack.trackName,
             artist: effectiveTrack.artistName,
             artUri: effectiveTrack.albumArtUrl,
             id: effectiveTrack.id,
             hasNext: _hasNext(),
             hasPrevious: _hasPrevious(),
           );
        } else {
           throw Exception('Unknown stream result type: ${result.runtimeType}');
        }
      } catch (e) {
        if (result is AudioSource) {
           // If Proxy failed, Try Fallback URL Method immediately
           if (kDebugMode) print('MusicProvider: Proxy playback failed ($e). Falling back to legacy URL method...');
           
           // Fetch URL using the Legacy/Fallback chain (Manual -> Cobalt -> Piped)
           // We explicitly use getAudioStreamUrl which returns a String
           final fallbackUrl = await _innerTubeService.getAudioStreamUrl(playableId, preferredBitrate: 128);
           
           if (kDebugMode) print('MusicProvider: Playing fallback URL...');
           await _audioService.play(fallbackUrl,
             title: effectiveTrack.trackName,
             artist: effectiveTrack.artistName,
             artUri: effectiveTrack.albumArtUrl,
             id: effectiveTrack.id,
             hasNext: _hasNext(),
             hasPrevious: _hasPrevious(),
           );
           
        } else {
           // If it was already a URL and failed, rethrow (or handle differently)
           rethrow;
        }
      }

      // Update state - Note: _isPlaying will be updated by the stream listener
      // Don't set _isPlaying = true here to avoid race condition
      _currentTrack = effectiveTrack;
      _updateRecentlyPlayed(effectiveTrack);
      _updateCurrentIndex();
      notifyListeners();
      
      // Start fetching lyrics in PARALLEL (don't wait)
      if (!_isOfflineMode) {
        unawaited(fetchLyrics()); 
      }
      
      // Preload next track (Audio + Lyrics)
      _prefetchNextTrack();

      // Prefetch Metadata (Artist & Album) for Instant Navigation
      prefetchMetadata(effectiveTrack);
      
      // Preload next track (Legacy call - can remove or keep for safety if it does something else)
      _handlePlaybackOrContextChangeForPreloading();
      
      // Palette updated earlier in parallel
      
      if (kDebugMode) {
        print('MusicProvider: Successfully started playback of ${effectiveTrack.trackName}');
      }
      _consecutiveErrors = 0; // Reset error count on success
      
    } catch (e, s) {
      if (kDebugMode) {
        print('MusicProvider: ERROR PLAYING TRACK');
        print('Track: ${track.trackName}');
        print('Error: $e');
        print('Stack trace: $s');
      }
      await _handlePlaybackError('Failed to play ${track.trackName}: ${e.toString()}');
    }
  }

  Future<void> playOfflineTrack(Track track, {bool setContext = true, bool clearQueue = true, List<Track>? contextList}) async {
    bool knownOffline = track.source == 'local' || _downloadedTracksMetadata.containsKey(track.id);
    
    if (!knownOffline) {
      await playTrack(track, playlistTracks: contextList ?? _currentPlayingTracks, playlistId: _currentPlaylistId, setContext: setContext, clearQueue: clearQueue);
      return;
    }
    
    if (_currentTrack?.id == track.id && _isPlaying) {
      await pauseTrack();
      return;
    }
    
    if (_currentTrack?.id == track.id && !_isPlaying && _currentTrack != null) {
      await resumeTrack();
      return;
    }
    
    _isOfflineContext = true; // Set explicit offline flag
    await _playOfflineTrackInternal(track, setContext: setContext, clearQueue: clearQueue);
    
    if (setContext && contextList != null) {
       _setPlaybackContext(contextList, clearQueue: clearQueue);
    }
  }

  Future<void> _playOfflineTrackInternal(Track track, {bool setContext = true, bool clearQueue = true}) async {
    _clearError();
    
    // Sync current track metadata immediately for UI consistency
    _currentTrack = track;
    _paletteGenerator = null;
    _isOfflineTrack = true;
    _updateCurrentIndex();
    notifyListeners();
    
    // Start palette generation in parallel
    updatePalette();

    try {
      if (_isPlaying) await _audioService.stop();
      
      String filePath;
      bool isDownloaded = _downloadedTracksMetadata.containsKey(track.id);
      
      if (track.source == 'local') {
        filePath = track.previewUrl;
      } else if (isDownloaded) {
        final meta = _downloadedTracksMetadata[track.id];
        filePath = meta?['filePath'] as String? ?? '';
      } else {
        throw Exception('Track is not local or downloaded.');
      }
      
      if (filePath.isEmpty) {
        throw Exception('File path is empty.');
      }
      
      final file = File(filePath);
      // Validate Existence AND Size
      bool fileExists = await file.exists();
      int fileSize = fileExists ? await file.length() : 0;
      
      if (!fileExists || fileSize < 50 * 1024) { // Check for validity (< 50KB assumed corrupt)
        if (fileExists) {
             print("MusicProvider: File exists but too small ($fileSize bytes). Deleting: $filePath");
             try { await file.delete(); } catch (_) {}
        }
        await _handleMissingOfflineFile(track.id, filePath);
        
        // Fallback to online if possible
        if (!_isOfflineMode && _networkService.isConnected) {
            if (kDebugMode) print("MusicProvider: Local file missing, falling back to online for ${track.trackName}");
            // Recursive call to playTrack will now see it as NOT downloaded (since we removed metadata)
            // and attempt online playback.
            await playTrack(track, 
                playlistTracks: setContext ? (isDownloaded ? await getDownloadedTracks() : _localTracks) : null,
                setContext: setContext,
                clearQueue: clearQueue
            );
            return;
        }
        
        throw Exception('File not found and cannot play online: $filePath');
      }
      
      _currentTrack = track;
      _paletteGenerator = null; // Reset palette immediately
      _isOfflineTrack = true;
      
      if (setContext) {
        List<Track> contextTracks;
        String contextDesc;
        if (isDownloaded) {
          contextTracks = await getDownloadedTracks();
          contextDesc = "Downloads";
        } else {
          contextTracks = _localTracks;
          contextDesc = "Local Tracks";
        }
        
        _setPlaybackContext(contextTracks, clearQueue: clearQueue);
        if (kDebugMode) {
          print("MusicProvider: Set playback context to $contextDesc");
        }
      } else {
        _updateCurrentIndex();
      }
      
      if (kDebugMode) {
        print('MusicProvider: Playing offline file: $filePath');
      }
      
      await _audioService.playLocalFile(filePath,
        title: track.trackName,
        artist: track.artistName,
        artUri: track.albumArtUrl,
        id: track.id,
        hasNext: _hasNext(),
        hasPrevious: _hasPrevious(),
      );
      
      _updateRecentlyPlayed(track);
      notifyListeners();
      _handlePlaybackOrContextChangeForPreloading();
      
    } catch (e, s) {
      if (kDebugMode) {
        print('MusicProvider: ERROR PLAYING OFFLINE TRACK');
        print('Track: ${track.trackName}');
        print('Error: $e');
        print('Stack trace: $s');
      }
      await _handlePlaybackError('Failed to play offline track: ${e.toString()}');
    }
  }
    


  // --- Player Controls ---
  Future<void> pauseTrack() async {
    if (_isCasting) {
      await _castService.pause();
      _isPlaying = false;
      notifyListeners();
      return;
    }
    await _audioService.pause();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> resumeTrack() async {
    if (_isCasting) {
      await _castService.play();
      _isPlaying = true;
      notifyListeners();
      return;
    }
    await _audioService.resume();
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> seekTo(Duration position) async {
    if (_isCasting) {
      await _castService.seek(position.inSeconds.toDouble());
      return;
    }
    if (_currentTrack == null) return; final dur = _duration; final clamped = position.isNegative ? Duration.zero : (dur > Duration.zero && position > dur ? dur : position); try { await _audioService.seekTo(clamped); _position = clamped; notifyListeners(); } catch (e) { _errorMessage = 'Error seeking.'; notifyListeners(); }
  }

  Future<void> stopTrack() async {
    if (_isStopping) return;
    _isStopping = true;
    
    if (_isCasting) {
      await _castService.stop();
      _isPlaying = false;
      _isStopping = false;
      notifyListeners();
      return;
    }
    
    try { 
      await _audioService.stop(); 
    } catch (e) { 
      print('Error stopping service: $e'); 
    } finally { 
      _isPlaying = false; 
      _currentTrack = null; 
      _isOfflineTrack = false; 
      _position = Duration.zero; 
      _duration = Duration.zero; 
      _currentIndex = -1; 
      _currentPlayingTracks = null; 
      _currentPlaylistId = null; 
      _shuffledPlaylist = []; 
      _queue.clear(); 
      
      // FIX: Ensure UI is minimized when track stops
      _isPlayerExpanded = false; 
      
      _isStopping = false;
      notifyListeners(); 
    }
  }
  
  // --- Casting Methods ---
  void startCastingDiscovery() {
    _isSearchingDevices = true;
    notifyListeners();
    _castService.startDiscovery();
    _castService.devicesStream.listen((devices) {
      _castDevices = devices;
      notifyListeners();
    });
  }

  void stopCastingDiscovery() {
    _isSearchingDevices = false;
    _castService.stopDiscovery();
    notifyListeners();
  }

  Future<void> connectToCastDevice(CastDevice device) async {
    final success = await _castService.connect(device);
    if (success) {
      _isCasting = true;
      _audioService.pause(); // Pause local playback
      
      // If we are currently playing something, transfer it
      if (_currentTrack != null) {
        // Build high quality URL
        String? streamUrl;
        if (_currentTrack!.source == 'youtube' || _currentTrack!.source == 'piped') {
           streamUrl = await _innerTubeService.getAudioStreamUrl(_currentTrack!.id);
        } else {
           // Local file casting might require a local HTTP server, omitting for simple scope
           // For now, assume remote URLs only or just remote tracks
           streamUrl = null; 
        }
        
        if (streamUrl != null) {
          await _castService.loadMedia(
            url: streamUrl,
            title: _currentTrack!.trackName,
            artist: _currentTrack!.artistName,
            imageUrl: _currentTrack!.albumArtUrl,
          );
        }
      }
    }
    notifyListeners();
  }

  Future<void> disconnectCastDevice() async {
    await _castService.disconnect();
    _isCasting = false;
    notifyListeners();
  }

  // --- Error Handling ---
  void _clearError() { if (_errorMessage != null) { _errorMessage = null; notifyListeners(); } }
  Future<void> _handlePlaybackError(String message) async { 
    print("Playback Error: $message"); 
    _errorMessage = message.length > 150 ? '${message.substring(0, 147)}...' : message; 
    
    // Automatic Failover: If it's an online track and we have a next one, try skipping
    if (!_isOfflineTrack && !_isOfflineMode && _networkService.isConnected) {
       _consecutiveErrors++;
       if (_consecutiveErrors <= 2) {
          if (kDebugMode) print("MusicProvider: Attempting auto-skip after error...");
          skipToNext();
          return;
       }
    }
    
    await stopTrack(); 
    _consecutiveErrors = 0; // Reset
  }

  // --- Queue Management ---
  void addToQueue(Track track) { _queue.add(track); print("Added to queue: ${track.trackName}. Size: ${_queue.length}"); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void addListToQueue(List<Track> tracks) { _queue.addAll(tracks); print("Added ${tracks.length} to queue. Size: ${_queue.length}"); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void playNext(Track track) { _queue.insert(0, track); print("Play next: ${track.trackName}. Size: ${_queue.length}"); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void reorderQueueItem(int oldIndex, int newIndex) { if (oldIndex < 0 || oldIndex >= _queue.length || newIndex < 0) return; final int iIdx = newIndex > oldIndex ? newIndex - 1 : newIndex; final tr = _queue.removeAt(oldIndex); _queue.insert(iIdx.clamp(0, _queue.length), tr); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }

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
      notifyListeners();
      _handlePlaybackOrContextChangeForPreloading(); // Also call after removing from queue
    }
  }

  void clearQueue() { if (_queue.isEmpty) return; _queue.clear(); print("Queue cleared."); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }


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
          if (ytEquivalent != null) {
            playableId = ytEquivalent.id;
          } else {
            if (kDebugMode) print("MusicProvider: Could not find YouTube equivalent for Spotify track ${nextTrack.trackName} for preloading.");
            return;
          }
        }
        final bitrate = await _getBitrate(); // Use current adaptive bitrate for preloading
        final url = await _innerTubeService.getAudioStreamUrl(playableId, preferredBitrate: bitrate);
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


  // --- Internal Metadata Fetchers (with Caching) ---
  final Map<String, Artist> _artistCache = {};
  final Map<String, Album> _albumCache = {};

  Future<Artist?> _fetchArtistInternal(String artistName) async {
    // 1. Check Cache
    if (_artistCache.containsKey(artistName)) {
      if (kDebugMode) print("MusicProvider: Cache hit for artist $artistName");
      return _artistCache[artistName];
    }
    
    try {
      // 2. Fetch Logic
      final searchResults = await _innerTubeService.searchArtists(artistName, limit: 1);
      if (searchResults.isEmpty) return null;
      
      final artistInfo = searchResults.first;
      final detailsMap = await _innerTubeService.getArtistDetails(artistInfo.id);
      
      // FIX: For artist search results, the artist's name is in trackName, not artistName
      final artist = Artist(
        id: artistInfo.id,
        name: artistInfo.trackName.isNotEmpty ? artistInfo.trackName : artistName,
        imageUrl: artistInfo.albumArtUrl,
        topTracks: (detailsMap['tracks'] as List?)?.cast<Track>(),
        topAlbums: (detailsMap['albums'] as List?)?.cast<Album>(),
      );

      
      // 3. Cache Result
      _artistCache[artistName] = artist;
      return artist;
    } catch (e) {
      if (kDebugMode) print("MusicProvider: Internal artist fetch error: $e");
      return null;
    }
  }

  Future<Album?> _fetchAlbumInternal(String albumName, String artistName) async {
    final key = '$albumName|$artistName';
    
    // 1. Check Cache
    if (_albumCache.containsKey(key)) {
       if (kDebugMode) print("MusicProvider: Cache hit for album $albumName");
       return _albumCache[key];
    }

    try {
      // 2. Fetch Logic (Legacy implementation for valid tracks)
      final tracks = await _innerTubeService.searchSongs('$albumName $artistName', limit: 30);
      
      if (tracks.isNotEmpty) {
         final first = tracks.first;
         final album = Album(
           id: 'album_${first.artistName}_${first.albumName}'.replaceAll(' ', '_'),
           name: first.albumName.isNotEmpty ? first.albumName : albumName,
           artistName: first.artistName.isNotEmpty ? first.artistName : artistName,
           imageUrl: first.albumArtUrl,
           tracks: tracks,
         );
         
         // 3. Cache Result
         _albumCache[key] = album;
         return album;
      }
      return null;
    } catch (e) {
      if (kDebugMode) print("MusicProvider: Internal album fetch error: $e");
      return null;
    }
  }
  
  // --- Public Prefetcher ---
  Future<void> prefetchMetadata(Track track) async {
     if (track.artistName.isEmpty) return;
     
     // Fire and forget - don't await in UI thread
     _fetchArtistInternal(track.artistName);
     
     if (track.albumName.isNotEmpty) {
       _fetchAlbumInternal(track.albumName, track.artistName);
     }
  }

  // --- Optimized Navigation Methods ---
  Future<void> navigateToArtist(String artistName) async { 
    if (kDebugMode) print("PROVIDER ACTION: Navigate to Artist: $artistName");
    _isLoadingArtist = true;
    _currentArtistDetails = null; // Clear old
    _errorMessage = null; 
    notifyListeners(); 

    try { 
      final artist = await _fetchArtistInternal(artistName);
      if (artist != null) {
        _currentArtistDetails = artist;
      } else {
        throw Exception("Artist not found");
      }
    } catch (e) { 
      _errorMessage = "Could not load artist details.";
      _currentArtistDetails = null; 
    } finally { 
      _isLoadingArtist = false; 
      notifyListeners(); 
    } 
  }

  /// Robust navigation using an existing Artist/Track object from search results
  Future<void> navigateToArtistObject(Track artistTrack) async {
    if (kDebugMode) print("PROVIDER ACTION: Navigate to Artist Object: ${artistTrack.trackName} (${artistTrack.id})");
    _isLoadingArtist = true;
    _currentArtistDetails = null;
    _errorMessage = null;
    notifyListeners();

    try {
      // Check cache first using name
      if (_artistCache.containsKey(artistTrack.trackName)) {
        _currentArtistDetails = _artistCache[artistTrack.trackName];
        if (kDebugMode) print("MusicProvider: Cache hit for artist object ${artistTrack.trackName}");
        return;
      }
      
      // 1. Use ID directly
      final browseId = artistTrack.id;
      
      // 2. Fetch full details
      final detailsMap = await _innerTubeService.getArtistDetails(browseId);
      
      // 3. Construct Artist
      _currentArtistDetails = Artist(
        id: browseId,
        name: artistTrack.trackName, 
        imageUrl: artistTrack.albumArtUrl,
        topTracks: (detailsMap['tracks'] as List?)?.cast<Track>(),
        topAlbums: (detailsMap['albums'] as List?)?.cast<Album>(),
      );
      
      // Cache it
      _artistCache[artistTrack.trackName] = _currentArtistDetails!;
      
       print("PROVIDER: Artist info loaded for ${_currentArtistDetails?.name}");
    } catch (e) {
      _errorMessage = "Could not load artist details.";
      if (kDebugMode) print("PROVIDER ERROR: $e");
      _currentArtistDetails = null;
    } finally {
      _isLoadingArtist = false;
      notifyListeners();
    }
  }

  Future<void> navigateToAlbum(String albumName, String artistName) async { 
    if (kDebugMode) print("PROVIDER ACTION: Navigate to Album: $albumName by $artistName");
    _isLoadingAlbum = true;
    _currentAlbumDetails = null;
    _errorMessage = null;
    notifyListeners();
    
    try {
      final album = await _fetchAlbumInternal(albumName, artistName);
      if (album != null) {
        _currentAlbumDetails = album;
      } else {
        throw Exception("Album not found");
      }
    } catch (e) { 
      _errorMessage = "Could not load album details."; 
      _currentAlbumDetails = null; 
    } finally { 
      _isLoadingAlbum = false; 
      notifyListeners(); 
    } 
  }

  // --- Network & Mode Management ---
  void _setupConnectivityMonitoring() { _networkQualitySubscription = _networkService.onNetworkQualityChanged.listen((q) => _handleNetworkQualityChange(q), onError: (e) => print("NetQual stream error: $e")); _connectivityStatusSubscription = _networkService.onConnectivityChanged.listen((c) => _handleConnectivityChange(c), onError: (e) => print("Connect stream error: $e")); _networkService.checkNetworkQualityNow().then((q) { _handleNetworkQualityChange(q); _handleConnectivityChange(q != NetworkQuality.offline); }); }

  void _handleNetworkQualityChange(NetworkQuality quality) {
    // Adjust bitrates based on network quality (existing logic)
    // Adjust bitrates based on network quality ONLY if Auto Mode is enabled
    if (!_isLowDataMode && _isAutoBitrate) {
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
        if (kDebugMode) print("MusicProvider: Auto-adjusted bitrate to Wifi:$_wifiBitrate, Cell:$_cellularBitrate");
      }
    }

    // The following lines related to calling _audioService.configureBufferSettings are now removed
    // as that method in AudioService is commented out.
    // // Only configure if playing online content
    // if (currentTrack != null && !_isOfflineTrack) {
    //     _audioService.configureBufferSettings(
    //         bufferDuration: const Duration(seconds: 30),
    //         minBufferDuration: const Duration(seconds: 5),
    //         maxBufferDuration: const Duration(seconds: 60)
    //     );
    // }
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
  // --- Bitrate Settings ---
  void setWifiBitrate(int bitrate) { 
    if (_wifiBitrate != bitrate || _isAutoBitrate) { 
      _wifiBitrate = bitrate; 
      _isAutoBitrate = false; // Manual override disables Auto
      _saveSettings(); 
      notifyListeners(); 
    } 
  }
  void setCellularBitrate(int bitrate) { 
    if (_cellularBitrate != bitrate || _isAutoBitrate) { 
      _cellularBitrate = bitrate; 
      _isAutoBitrate = false; // Manual override disables Auto
      _saveSettings(); 
      notifyListeners(); 
    } 
  }
  
  void setAutoBitrate(bool enable) {
    if (_isAutoBitrate != enable) {
      _isAutoBitrate = enable;
      if (enable) {
         // Trigger immediate check to apply auto settings
         _handleNetworkQualityChange(_networkService.networkQuality);
      }
      _saveSettings();
      notifyListeners();
    }
  }

  void setMusicSource(MusicSource source) {
    if (_currentMusicSource != source) {
      if (kDebugMode) {
        print('MusicProvider: Switching music source from ${_currentMusicSource.displayName} to ${source.displayName}');
      }
      _currentMusicSource = source;
      _saveSettings();
      
      // Clear caches when switching sources
      _cachedTracks.clear();
      _tracks = [];
      _trendingTracks = [];
      _fullTrendingTracks = [];
      
      notifyListeners(); // Immediate update for UI switch
      
      // OPTIMIZED RELOAD LOGIC
      if (source == MusicSource.local) {
         // Immediately load local files if empty
         if (_localTracks.isEmpty) {
           loadLocalMusicFiles();
         }
      } else if (_networkService.isConnected && !_isOfflineMode) {
        // Only fetch if online
        fetchTracks(forceRefresh: true);
        fetchTrendingTracks(forceRefresh: true);
      }
    }
  }
  
  Future<int> _getBitrate() async { if (_isOfflineMode || !_networkService.isConnected) return 0; if (_isLowDataMode) return min(_cellularBitrate, _wifiBitrate); final type = await _networkService.getConnectionType(); return (type == ConnectivityResult.wifi) ? _wifiBitrate : _cellularBitrate; }

  // --- Local Music ---
  Future<void> loadLocalMusicFiles({bool forceRescan = false}) async { if (_isLoadingLocal && !forceRescan) return; _isLoadingLocal = true; notifyListeners(); try { _localTracks = await _localMusicService.fetchLocalMusicFromMediaStore(); _localTracks = LocalMusicService.sortTracks(_localTracks, _localTracksSortCriteria); _errorMessage = null; } catch (e) { _errorMessage = 'Failed to load local files: ${e.toString()}'; _localTracks = []; } finally { _isLoadingLocal = false; notifyListeners(); } }
  void sortLocalTracks(SortCriteria criteria) { if (_localTracksSortCriteria == criteria && _localTracks.isNotEmpty) return; _localTracksSortCriteria = criteria; _localTracks = LocalMusicService.sortTracks(_localTracks, criteria); _saveSettings(); notifyListeners(); }
  Future<void> addLocalMusicFolder() async { String? iMsg="Adding folder..."; _errorMessage=iMsg; notifyListeners(); try { final String? p = await _localMusicService.pickDirectory(); if(p!=null){await loadLocalMusicFiles(forceRescan:true); if(_errorMessage==iMsg) _errorMessage="Local music refreshed.";} else if(_errorMessage==iMsg) _errorMessage=null;} catch(e) {_errorMessage='Failed to add folder: ${e.toString()}';} finally {notifyListeners();} }
  Future<void> pickAndPlayLocalFile() async { try { final t = await _localMusicService.pickMusicFile(); if (t != null) { if (!_localTracks.any((tr) => tr.id == t.id)) { _localTracks.add(t); sortLocalTracks(_localTracksSortCriteria); } await playOfflineTrack(t); } } catch (e) { _errorMessage = 'Failed to pick file: ${e.toString()}'; notifyListeners(); } }
  Future<void> playAllLocalTracks({int startIndex = 0, bool? shuffle}) async { if (_localTracks.isEmpty) { _errorMessage = 'No local music found.'; notifyListeners(); return; } try { _setPlaybackContext(_localTracks); if (shuffle != null && shuffle != _shuffleEnabled) { _shuffleEnabled = shuffle; _saveSettings(); } Track t; if (_shuffleEnabled) {
    t = _shuffledPlaylist.isNotEmpty ? _shuffledPlaylist[0] : _localTracks[0];
  } else {
    t = _localTracks[startIndex.clamp(0, _localTracks.length - 1)];
  } await playOfflineTrack(t); } catch (e) { await _handlePlaybackError('Failed to play local tracks.'); } }

  // --- Playlist Management ---
  Future<void> loadUserPlaylists() async { try { final p = await SharedPreferences.getInstance(); final s = p.getString('userPlaylists'); if (s != null) _userPlaylists = List<Map<String, dynamic>>.from(jsonDecode(s)).map((j) => Playlist.fromJson(j)).toList(); } catch (_) { _userPlaylists = []; } }
  Future<void> saveUserPlaylists() async { try { final p = await SharedPreferences.getInstance(); await p.setString('userPlaylists', jsonEncode(_userPlaylists.map((pl) => pl.toJson()).toList())); } catch (e) { _addToRetryQueue(_RetryOperation('Save playlists', saveUserPlaylists)); } }
  Future<void> createPlaylist(String name, {List<Track>? initialTracks, String? imageUrl}) async { if (name.trim().isEmpty) { _errorMessage = "Name empty."; notifyListeners(); return; } try { final pl = Playlist(id: 'pl_${DateTime.now().millisecondsSinceEpoch}', name: name.trim(), imageUrl: imageUrl ?? '', tracks: initialTracks ?? []); _userPlaylists.add(pl); await saveUserPlaylists(); _errorMessage = "Playlist created."; notifyListeners(); } catch (_) { _errorMessage = 'Failed to create.'; notifyListeners(); } }
  Future<void> deletePlaylist(String playlistId) async { final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) return; try { _userPlaylists.removeAt(i); await saveUserPlaylists(); if (_currentPlaylistId == playlistId) await stopTrack(); _errorMessage = "Playlist deleted."; notifyListeners(); } catch (_) { _errorMessage = 'Failed to delete.'; notifyListeners(); } }
  Future<void> renamePlaylist(String playlistId, String newName) async { if (newName.trim().isEmpty) { _errorMessage = "Name empty."; notifyListeners(); return; } final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) return; try { _userPlaylists[i] = _userPlaylists[i].copyWith(name: newName.trim()); await saveUserPlaylists(); _errorMessage = "Renamed."; notifyListeners(); } catch (_) { _errorMessage = "Failed to rename."; notifyListeners(); } }
  Future<void> addTrackToPlaylist(String playlistId, Track track) async { final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) return; final pl = _userPlaylists[i]; if (pl.tracks.any((t) => t.id == track.id)) { _errorMessage = "Already in playlist."; notifyListeners(); return; } try { _userPlaylists[i] = pl.copyWith(tracks: [...pl.tracks, track]); await saveUserPlaylists(); _errorMessage = "Added to ${pl.name}."; notifyListeners(); } catch (_) { _errorMessage = 'Failed to add track.'; notifyListeners(); } }
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async { final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) return; final pl = _userPlaylists[i]; final tN = pl.tracks.firstWhereOrNull((t) => t.id == trackId)?.trackName ?? '?'; try { final uT = pl.tracks.where((t) => t.id != trackId).toList(); if (uT.length < pl.tracks.length) { _userPlaylists[i] = pl.copyWith(tracks: uT); await saveUserPlaylists(); _errorMessage = "Removed '$tN'."; if (_currentPlaylistId == playlistId && _currentTrack?.id == trackId) await skipToNext(); notifyListeners(); } } catch (_) { _errorMessage = 'Failed to remove track.'; notifyListeners(); } }
  Future<void> reorderTrackInPlaylist(String playlistId, int oldIndex, int newIndex) async { final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) return; final pl = _userPlaylists[i]; if (oldIndex < 0 || oldIndex >= pl.tracks.length || newIndex < 0) return; try { final t = List<Track>.from(pl.tracks); final tr = t.removeAt(oldIndex); int iI = (newIndex > oldIndex) ? newIndex - 1 : newIndex; iI = iI.clamp(0, t.length); t.insert(iI, tr); _userPlaylists[i] = pl.copyWith(tracks: t); await saveUserPlaylists(); notifyListeners(); } catch (_) { _errorMessage = "Failed to reorder."; notifyListeners(); } }
  Future<void> playPlaylist(String playlistId, {int startIndex = 0, bool? shuffle}) async { final i = _userPlaylists.indexWhere((p) => p.id == playlistId); if (i < 0) { _errorMessage = 'Playlist not found.'; notifyListeners(); return; } final pl = _userPlaylists[i]; if (pl.tracks.isEmpty) { _errorMessage = "'${pl.name}' empty."; notifyListeners(); return; } if (shuffle != null && shuffle != _shuffleEnabled) { _shuffleEnabled = shuffle; _saveSettings(); } _setPlaybackContext(pl.tracks, playlistId: playlistId); Track t; if (_shuffleEnabled) {
    t = _shuffledPlaylist.isNotEmpty ? _shuffledPlaylist[0] : pl.tracks[0];
  } else {
    t = pl.tracks[startIndex.clamp(0, pl.tracks.length - 1)];
  } await playTrack(t, playlistId: playlistId, playlistTracks: pl.tracks); }
  Future<void> importPlaylist(Playlist playlist) async { try { final i = _userPlaylists.indexWhere((p) => p.id == playlist.id); if (i >= 0) {
    _userPlaylists[i] = playlist;
  } else {
    _userPlaylists.add(playlist);
  } await saveUserPlaylists(); _errorMessage = "Imported '${playlist.name}'."; notifyListeners(); } catch (e) { _errorMessage = 'Failed to import playlist.'; _addToRetryQueue(_RetryOperation('Import: ${playlist.name}', () => importPlaylist(playlist))); notifyListeners(); } }

  // --- Downloading ---
  Future<Directory> _getDownloadsDirectory() async { try { final d = await getApplicationSupportDirectory(); final dl = Directory('${d.path}/offline_music'); if (!await dl.exists()) await dl.create(recursive: true); return dl; } catch (e) { throw Exception("Could not access downloads directory."); } }
  Future<String> _buildDownloadFilePath(String trackId) async { final d = await _getDownloadsDirectory(); return '${d.path}/$trackId.mp3'; }
  Future<String> _buildArtDownloadPath(String trackId) async { final d = await _getDownloadsDirectory(); return '${d.path}/$trackId.jpg'; }
  Future<void> downloadTrack(Track track) async { final id = track.id; if (await isTrackDownloaded(id)) { _errorMessage = "${track.trackName} downloaded."; notifyListeners(); return; } if (_isDownloading[id] == true) { _errorMessage = "${track.trackName} downloading."; notifyListeners(); return; } if (track.source == 'local') { _errorMessage = "Cannot download local files."; notifyListeners(); return; } if (_isOfflineMode || !_networkService.isConnected) { _errorMessage = 'Offline: Cannot download.'; notifyListeners(); return; } if (_concurrentDownloads >= 6) { _addToDownloadQueue(track); return; } CancelToken cT = CancelToken(); _isDownloading[id] = true; _downloadProgress[id] = 0.0; _downloadCancelTokens[id] = cT; _concurrentDownloads++; if (!_currentlyDownloadingTracks.any((t)=> t.id == id)) _currentlyDownloadingTracks.add(track); notifyListeners(); String fP = ''; try { String sId = id; if (track.source == 'spotify') { final yt = await _spotifyService.findYouTubeTrack(track); if (yt != null) {
    sId = yt.id;
  } else {
    throw Exception("No playable version.");
  } } final sUrl = await _innerTubeService.getAudioStreamUrl(sId, preferredBitrate: 256);
      fP = await _buildDownloadFilePath(id);
      
      // Download Artwork simultaneously (if available)
      String aP = '';
      if (track.albumArtUrl.isNotEmpty) {
          aP = await _buildArtDownloadPath(id);
          try {
              await _networkService.downloadFile(track.albumArtUrl, aP);
          } catch (e) {
              if (kDebugMode) print('MusicProvider: Art download failed: $e');
              aP = ''; // Fallback to network if local art fails
          }
      }

      await _networkService.downloadFile(sUrl, fP, cancelToken: cT, onProgress: (p) {
        if (_isDownloading[id] == true) {
          _downloadProgress[id] = p;
          notifyListeners();
        }
      });
      
      if (!cT.isCancelled) {
         // Validate file size before saving metadata
         final file = File(fP);
         if (await file.exists() && await file.length() > 50 * 1024) { // 50KB min
            _downloadedTracksMetadata[id] = {
              'track': track,
              'filePath': fP,
              'artPath': aP,
              'downloadDate': DateTime.now()
            };
            await saveDownloadedTracksMetadata();
            _errorMessage = "${track.trackName} downloaded.";
         } else {
             // File too small or missing - likely an error page or empty
             if (await file.exists()) await file.delete();
             throw Exception("Download failed: File corrupt or too small.");
         }
      } else {
        _errorMessage = "${track.trackName} cancelled.";
        if (fP.isNotEmpty) {
           try { final f = File(fP); if (await f.exists()) await f.delete(); } catch (_) {}
        }
      }
  } catch (e) { if (!cT.isCancelled) { _errorMessage = 'Download failed: ${track.trackName}'; if (fP.isNotEmpty) try { final f = File(fP); if (await f.exists()) await f.delete(); } catch (_) {} bool retry = e is DioException && [DioExceptionType.connectionTimeout, DioExceptionType.sendTimeout, DioExceptionType.receiveTimeout, DioExceptionType.connectionError, DioExceptionType.unknown].contains(e.type); if (retry) _addToRetryQueue(_RetryOperation('Download: ${track.trackName}', () => downloadTrack(track))); } } finally { if (_isDownloading.containsKey(id)) { _isDownloading.remove(id); _downloadProgress.remove(id); _downloadCancelTokens.remove(id); _currentlyDownloadingTracks.removeWhere((t) => t.id == id); _concurrentDownloads = max(0, _concurrentDownloads - 1); } notifyListeners(); _processDownloadQueue(); } }
  void cancelDownload(String trackId) { _downloadQueue.removeWhere((t) => t.id == trackId); _downloadCancelTokens[trackId]?.cancel('Cancelled by user.'); }
  Future<void> deleteDownloadedTrack(String trackId) async { final meta = _downloadedTracksMetadata[trackId]; if (meta == null) { _errorMessage = "Not downloaded."; notifyListeners(); return; } final fp = meta['filePath'] as String?; final ap = meta['artPath'] as String?; final tn = (meta['track'] as Track?)?.trackName ?? '?'; try { if (_isPlaying && _isOfflineTrack && _currentTrack?.id == trackId) await stopTrack(); if (fp != null) { final f = File(fp); if (await f.exists()) await f.delete(); } if (ap != null) { final af = File(ap); if (await af.exists()) await af.delete(); } _downloadedTracksMetadata.remove(trackId); await saveDownloadedTracksMetadata(); _errorMessage = "Removed $tn."; } catch (_) { _errorMessage = 'Failed to delete $tn.'; } finally { notifyListeners(); } }
  Future<bool> isTrackDownloaded(String trackId) async { final meta = _downloadedTracksMetadata[trackId]; if (meta != null) { final p = meta['filePath'] as String?; if (p != null && p.isNotEmpty) { if (await File(p).exists()) {
    // Also check file size to ensure it's not a corrupt/empty file
    if (await File(p).length() > 50 * 1024) { // 50KB min
      return true;
    } else {
      if (kDebugMode) print("MusicProvider: Found downloaded file for $trackId but it's too small. Treating as missing.");
      await _handleMissingOfflineFile(trackId, p);
      return false;
    }
  } else { await _handleMissingOfflineFile(trackId, p); return false; } } } return false; }
  Future<String?> getDownloadedTrackPath(String trackId) async { if (await isTrackDownloaded(trackId)) return _downloadedTracksMetadata[trackId]?['filePath'] as String?; return null; }
  Future<List<Track>> getDownloadedTracks() async { List<String> r = []; for (var e in _downloadedTracksMetadata.entries) { final p = e.value['filePath'] as String?; if (p == null || !(await File(p).exists())) r.add(e.key); } if (r.isNotEmpty) { for (var id in r) {
    _downloadedTracksMetadata.remove(id);
  } await _saveDownloadedTracksMetadataInternal(); notifyListeners(); } return _downloadedTracksMetadata.values.where((m) => m['track'] is Track).map((m) => m['track'] as Track).toList(); }
  Future<void> _loadDownloadedTracksMetadata() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('downloadedTracks');
      if (s != null) {
        final l = jsonDecode(s) as List;
        final dDir = await _getDownloadsDirectory();
        
        _downloadedTracksMetadata = {};
        for (var i in l) {
          if (i['id'] != null && i['filePath'] != null && i['track'] != null) {
            String storedPath = i['filePath'];
            String id = i['id'];
            
            // FIX: Normalize path if it doesn't exist at stored location 
            // but exists in the current downloads directory.
            String finalPath = storedPath;
            if (!await File(storedPath).exists()) {
               // Try to resolve relative to current directory
               final filename = storedPath.split('/').last;
               final currentPath = '${dDir.path}/$filename';
               if (await File(currentPath).exists()) {
                  if (kDebugMode) print("MusicProvider: Corrected path for $id: $storedPath -> $currentPath");
                  finalPath = currentPath;
               }
            }
            
            _downloadedTracksMetadata[id] = {
              'track': Track.fromJson(i['track']),
              'filePath': finalPath,
              'downloadDate': i['downloadDate'] != null ? DateTime.fromMillisecondsSinceEpoch(i['downloadDate']) : null
            };
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print("MusicProvider: Error loading download metadata: $e");
      _downloadedTracksMetadata = {};
    }
  }
  Future<void> saveDownloadedTracksMetadata() async => await _saveDownloadedTracksMetadataInternal();
  Future<void> _saveDownloadedTracksMetadataInternal() async { final l = _downloadedTracksMetadata.values.map((m) => {'id': (m['track'] as Track).id, 'filePath': m['filePath'], 'downloadDate': (m['downloadDate'] as DateTime?)?.millisecondsSinceEpoch, 'track': (m['track'] as Track).toJson()}).toList(); try { final p = await SharedPreferences.getInstance(); await p.setString('downloadedTracks', jsonEncode(l)); } catch (e) { _addToRetryQueue(_RetryOperation('Save dl meta', _saveDownloadedTracksMetadataInternal)); } }
  Future<void> _handleMissingOfflineFile(String trackId, String expectedPath) async { bool mRem = _downloadedTracksMetadata.remove(trackId) != null; if (mRem) await _saveDownloadedTracksMetadataInternal(); int cB = _localTracks.length; _localTracks.removeWhere((t) => t.id == expectedPath); bool lRem = _localTracks.length < cB; if (mRem || lRem) notifyListeners(); }
  void _addToDownloadQueue(Track track) { if (_isDownloading[track.id]==true || _downloadQueue.any((t)=>t.id==track.id) || _downloadedTracksMetadata.containsKey(track.id)) return; _downloadQueue.add(track); _errorMessage = '${track.trackName} queued.'; notifyListeners(); _processDownloadQueue(); }
  Future<void> _processDownloadQueue() async { if (_downloadQueue.isEmpty || _isOfflineMode || !_networkService.isConnected || _concurrentDownloads >= 6) return; final t = _downloadQueue.removeAt(0); notifyListeners(); await downloadTrack(t); }
  void pauseAllDownloads({bool clearQueue = false}) { final ids = List<String>.from(_downloadCancelTokens.keys); int c = 0; for (final id in ids) { _downloadCancelTokens[id]?.cancel("Downloads paused"); c++; } if (c > 0) print("Paused $c downloads."); if (clearQueue && _downloadQueue.isNotEmpty) { _downloadQueue.clear(); notifyListeners(); } }
  
  /// Batch download multiple tracks - adds to queue efficiently
  Future<void> downloadTracks(List<Track> tracks, {bool skipDownloaded = true}) async {
    int added = 0;
    for (final track in tracks) {
      if (skipDownloaded && await isTrackDownloaded(track.id)) continue;
      if (_isDownloading[track.id] == true) continue;
      if (_downloadQueue.any((t) => t.id == track.id)) continue;
      if (track.source == 'local') continue;
      _downloadQueue.add(track);
      added++;
    }
    if (added > 0) {
      _errorMessage = 'Queued $added tracks for download';
      notifyListeners();
      // Start processing queue (will respect concurrent limit)
      _processDownloadQueue();
    }
  }

  // --- Spotify Integration ---
  Future<void> importSpotifyPlaylist(String spotifyPlaylistId, String playlistName, String imageUrl) async { if (_isOfflineMode) { _errorMessage = 'Cannot import offline.'; notifyListeners(); return; } _errorMessage = 'Importing Spotify playlist...'; notifyListeners(); try { final playlist = await _spotifyService.getPlaylistWithTracks(spotifyPlaylistId, playlistName, imageUrl); await importPlaylist(playlist); _errorMessage = "Imported '${playlist.name}'."; } catch (e) { _errorMessage = 'Failed to import Spotify: ${e.toString()}'; _addToRetryQueue(_RetryOperation('Import Spotify: $playlistName', () => importSpotifyPlaylist(spotifyPlaylistId, playlistName, imageUrl))); } finally { notifyListeners(); } }

  // --- Cross-Source Playback Helpers ---
  
  /// Determines if we should search for an equivalent track in the current music source
  bool _shouldSearchForEquivalent(Track track) {
    // Don't search for local tracks
    if (track.source == 'local') return false;
    
    // If current source is Local but track is from YouTube, we can't play it
    if (_currentMusicSource == MusicSource.local && track.source == 'youtube') {
      return false; // Can't search for local equivalent
    }
    
    // For YouTube source, we can play any track directly via InnerTube
    return false;
  }
  
  /// Attempts to find an equivalent track in the current music source
  Future<Track?> _findEquivalentTrack(Track originalTrack) async {
    try {
      // Build a search query from the track metadata
      final searchQuery = '${originalTrack.artistName} ${originalTrack.trackName}';
      
      if (kDebugMode) {
        print('MusicProvider: Searching for: "$searchQuery"');
      }
      
      List<Track> results = [];
      
      // Search using InnerTube service
      results = await _innerTubeService.searchSongs(searchQuery, limit: 5);
      
      if (results.isEmpty) {
        if (kDebugMode) {
          print('MusicProvider: No results found for "$searchQuery"');
        }
        return null;
      }
      
      // Try to find the best match
      // First, try exact match on track name
      Track? bestMatch = results.firstWhereOrNull((track) => 
        track.trackName.toLowerCase() == originalTrack.trackName.toLowerCase()
      );
      
      // If no exact match, try partial match
      bestMatch ??= results.firstWhereOrNull((track) => 
          track.trackName.toLowerCase().contains(originalTrack.trackName.toLowerCase()) ||
          originalTrack.trackName.toLowerCase().contains(track.trackName.toLowerCase())
        );
      
      // If still no match, just use the first result
      bestMatch ??= results.first;
      
      if (kDebugMode) {
        print('MusicProvider: Best match: ${bestMatch.trackName} by ${bestMatch.artistName}');
      }
      
      return bestMatch;
      
    } catch (e) {
      if (kDebugMode) {
        print('MusicProvider: Error finding equivalent track: $e');
      }
      return null;
    }
  }

  // --- API Content Fetching ---
  Future<List<Track>> fetchTracks({bool forceRefresh = false}) async { 
    const k = 'popular_music'; 
    final now = DateTime.now();
    
    if (!forceRefresh && _cachedTracks.containsKey(k)) {
        final cachedTime = _discoveryCacheTimes[k];
        if (cachedTime != null && now.difference(cachedTime) < _discoveryCacheTTL) {
            return _cachedTracks[k]!;
        }
    }

    if (_isOfflineMode || _currentMusicSource == MusicSource.local) { 
      _errorMessage = "Offline: No new tracks."; 
      notifyListeners(); 
      return _tracks; 
    } 
    try { 
      // Use InnerTube for home/popular tracks
      final fetched = await _innerTubeService.getHomeTracks(limit: 20);
      _tracks = fetched;
      _recommendedTracks = fetched; // Populate for you section as well 
      _cachedTracks[k] = _tracks; 
      _discoveryCacheTimes[k] = now;
      notifyListeners(); 
      return _tracks; 
    } catch (e) { 
      _errorMessage = 'Failed to load tracks.'; 
      _addToRetryQueue(_RetryOperation('Fetch tracks', () => fetchTracks(forceRefresh: true))); 
      notifyListeners(); 
      return _tracks; 
    } 
  }
  Future<List<Track>> fetchTrendingTracks({bool forceRefresh = false}) async { 
    const k = 'trending_music'; 
    final now = DateTime.now();

    if (!forceRefresh && _cachedTracks.containsKey(k)) { 
      final cachedTime = _discoveryCacheTimes[k];
      if (cachedTime != null && now.difference(cachedTime) < _discoveryCacheTTL) {
        _fullTrendingTracks = _cachedTracks[k]!; 
        _trendingTracks = _fullTrendingTracks.take(5).toList(); 
        return _fullTrendingTracks;
      }
    } 
    if (_isOfflineMode || _currentMusicSource == MusicSource.local) { 
      _errorMessage = "Offline: No trending."; 
      notifyListeners(); 
      return _fullTrendingTracks; 
    } 
    try { 
      // Use InnerTube for trending tracks
      _fullTrendingTracks = await _innerTubeService.getTrendingTracks(limit: 20); 
      _cachedTracks[k] = _fullTrendingTracks; 
      _discoveryCacheTimes[k] = now;
      _trendingTracks = _fullTrendingTracks.take(5).toList(); 
      notifyListeners(); 
      return _fullTrendingTracks; 
    } catch (e) { 
      _errorMessage = 'Failed to load trending.'; 
      _addToRetryQueue(_RetryOperation('Fetch trending', () => fetchTrendingTracks(forceRefresh: true))); 
      notifyListeners(); 
      return _fullTrendingTracks; 
    } 
  }

  // Method for generic track search, used by SearchTabContent
  Future<List<Track>> searchTracks(String query, {bool forceRefresh = false}) async {
    // Search using the appropriate service based on current music source
    if (_isOfflineMode && !_networkService.isConnected) {
      _errorMessage = "Offline: Cannot perform search.";
      notifyListeners();
      return []; // Return empty list in offline mode
    }
    
    if (query.trim().isEmpty) {
      _searchedTracks = [];
      notifyListeners();
      return [];
    }
    
    // Check Search Cache for speed
    if (!forceRefresh && _searchCache.containsKey(query)) {
       if (kDebugMode) print('MusicProvider: Search Cache HIT for "$query"');
       _searchedTracks = _searchCache[query]!;
       notifyListeners();
       return _searchedTracks;
    }
    
    try {
      _clearError(); // Clear previous errors before a new search
      
      if (kDebugMode) {
        print('MusicProvider: Searching for "$query" using ${_currentMusicSource.displayName}');
      }
      
      // Use InnerTube service for YouTube Music search or local search
      
      // Always search local tracks first
      List<Track> localResults = _localTracks.where((track) {
          final searchLower = query.toLowerCase();
          return track.trackName.toLowerCase().contains(searchLower) ||
                 track.artistName.toLowerCase().contains(searchLower) ||
                 track.albumName.toLowerCase().contains(searchLower);
        }).toList();

      List<Track> onlineResults = [];
      
      if (_currentMusicSource != MusicSource.local && !_isOfflineMode) {
        // Use InnerTube/YouTube Music API if allowed
        try {
           onlineResults = await _innerTubeService.searchSongs(query, limit: 50);
        } catch (e) {
           if (kDebugMode) print("Online search failed: $e");
        }
      }
      
      // Combine results (Local first)
      _searchedTracks = [...localResults, ...onlineResults];
      
      // Update Search Cache (limit size to 10 entries)
      if (_searchCache.length > 10) {
        _searchCache.remove(_searchCache.keys.first);
      }
      _searchCache[query] = _searchedTracks;

      if (kDebugMode) {
        print('MusicProvider: Found ${_searchedTracks.length} results (Local: ${localResults.length}, Online: ${onlineResults.length}) for "$query"');
      }
      
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

  // Helper for direct local search (used by Library screen)
  List<Track> searchLocalTracks(String query) {
    if (query.isEmpty) return _localTracks;
    final lower = query.toLowerCase();
    return _localTracks.where((t) => 
      t.trackName.toLowerCase().contains(lower) || 
      t.artistName.toLowerCase().contains(lower) || 
      t.albumName.toLowerCase().contains(lower)
    ).toList();
  }

  Future<void> searchPlaylists(String query) async {
     if (query.trim().isEmpty) {
       _playlistSearchResults = [];
       notifyListeners();
       return;
     }
     
     if (_isOfflineMode) {
        // Could search local playlists if implemented
        return;
     }

     try {
       final playlists = await _innerTubeService.searchPlaylists(query, limit: 20);
       _playlistSearchResults = playlists;
     } catch (e) {
       print("Playlist Search Error: $e");
       _playlistSearchResults = [];
     }
     notifyListeners();
  }

  Future<void> fetchArtistTracks(String artistName, {bool forceRefresh = false}) async { 
    final k = 'artist_$artistName'; 
    if (!forceRefresh && _cachedTracks.containsKey(k)) { 
      _artistTracks = _cachedTracks[k]!; 
      notifyListeners(); 
      return; 
    } 
    if (_isOfflineMode) { 
      _errorMessage = "Offline: No artist tracks."; 
      notifyListeners(); 
      return; 
    } 
    try { 
      if (kDebugMode) {
        print('MusicProvider: Fetching artist tracks for "$artistName" using ${_currentMusicSource.displayName}');
      }
      
      // Use appropriate service based on current music source
      if (_currentMusicSource == MusicSource.local) {
        // Search local tracks by artist
        _artistTracks = _localTracks.where((track) => 
          track.artistName.toLowerCase().contains(artistName.toLowerCase())
        ).toList();
      } else {
        // Use InnerTube for artist tracks (using new searchArtists method for finding the artist, 
        // but wait, fetchArtistTracks in context of SearchScreen tab 2 expects LIST OF ARTISTS?
        // OR tracks by the artist?
        // The UI in SearchScreen Tab 2 expects a list of artists (via searchArtists).
        // BUT the existing method name `fetchArtistTracks` sounds like "get tracks OF an artist".
        // Let's check usage. 
        // In SearchScreen: musicProvider.fetchArtistTracks(query); 
        // Then it uses `provider.artistTracks` and iterates unique artists.
        // So it expects a list of tracks or artists.
        // `searchArtists` returns List<Track> (where each track represents an artist hit).
        // So yes, I should use searchArtists here.
        
        _artistTracks = await _innerTubeService.searchArtists(artistName, limit: 30);
      }
      
      _cachedTracks[k] = _artistTracks; 
      notifyListeners(); 
    } catch (e) { 
      _errorMessage = 'Failed for $artistName.'; 
      _addToRetryQueue(_RetryOperation('Fetch artist: $artistName', () => fetchArtistTracks(artistName, forceRefresh: true))); 
      notifyListeners(); 
    } 
  }

  // --- Artist & Playlist Details ---
  Future<Map<String, dynamic>> fetchArtistDetails(String browseId) async {
    return _innerTubeService.getArtistDetails(browseId);
  }

  Future<List<Track>> fetchPlaylistDetails(String browseId) async {
    return _innerTubeService.getPlaylistDetails(browseId);
  }

  /// Fetch album tracks for displaying album contents
  Future<List<Track>> fetchAlbumTracks(String albumBrowseId) async {
    return _innerTubeService.getAlbumTracks(albumBrowseId);
  }

  Future<void> fetchGenreTracks(String genre, {bool forceRefresh = false}) async { 
    final k = 'genre_$genre'; 
    if (!forceRefresh && _cachedTracks.containsKey(k)) { 
      _genreTracks = _cachedTracks[k]!; 
      notifyListeners(); 
      return; 
    } 
    if (_isOfflineMode) { 
      _errorMessage = "Offline: No genre tracks."; 
      notifyListeners(); 
      return; 
    } 
    try { 
      if (kDebugMode) {
        print('MusicProvider: Fetching genre tracks for "$genre" using ${_currentMusicSource.displayName}');
      }
      
      // Use appropriate service based on current music source
      if (_currentMusicSource == MusicSource.local) {
        // For local, we don't have genre metadata, so search in album/track names
        _genreTracks = _localTracks.where((track) {
          final searchLower = genre.toLowerCase();
          return track.trackName.toLowerCase().contains(searchLower) ||
                 track.albumName.toLowerCase().contains(searchLower);
        }).toList();
      } else {
        // Use InnerTube for genre tracks
        _genreTracks = await _innerTubeService.searchSongs('$genre music', limit: 30);
      }
      
      _cachedTracks[k] = _genreTracks; 
      notifyListeners(); 
    } catch (e) { 
      _errorMessage = 'Failed for $genre.'; 
      _addToRetryQueue(_RetryOperation('Fetch genre: $genre', () => fetchGenreTracks(genre, forceRefresh: true))); 
      notifyListeners(); 
    } 
  }

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
  Future<void> clearAllCaches() async { try { _cachedTracks.clear(); _tracks = []; _trendingTracks = []; _fullTrendingTracks = []; _artistTracks = []; _genreTracks = []; _retryQueue.clear(); _lyricsService.clearCache(); _errorMessage = 'Caches cleared.'; notifyListeners(); if (_networkService.isConnected && !_isOfflineMode) { await fetchTracks(); await fetchTrendingTracks(); } } catch (_) { _errorMessage = 'Failed cache clear.'; notifyListeners(); } }

  // --- Sleep Timer ---
  Timer? _sleepTimer;
  int _sleepTimerMinutes = 0;

  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepTimerMinutes = minutes;
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        stopTrack();
        _sleepTimerMinutes = 0;
        notifyListeners();
      });
      _errorMessage = "Sleep timer set for $minutes minutes.";
    } else if (minutes == 0) {
       // Logic for "End of Track" could be handled in _onTrackComplete
       // For now, we'll just treat 0 as "cancel" if passed explicitly, or handle "End of Track" differently if needed.
       // If the UI sends 0 for "End of Track", we might need a flag.
       // Let's assume 0 means cancel for now based on typical UI, or we can add a specific flag.
       // If the UI meant "End of Track", we'd need a bool flag _stopAfterCurrentTrack.
       // Let's implement _stopAfterCurrentTrack logic.
       _stopAfterCurrentTrack = true;
       _errorMessage = "Playback will stop after this track.";
    } else {
      _errorMessage = "Sleep timer cancelled.";
    }
    notifyListeners();
  }

  bool _stopAfterCurrentTrack = false;



  // --- Palette Generation ---
  Future<void> updatePalette() async {
    final track = _currentTrack;
    if (track == null) {
      _paletteGenerator = null;
      notifyListeners();
      return;
    }
    
    // Explicit check for artwork
    if (track.albumArtUrl.isEmpty) {
       // Check if it's a local track - might need specific handling later
       // For now, reset to default dark
       _paletteGenerator = null;
       notifyListeners();
       return;
    }

    final trackId = track.id;
    
    // 1. Check Cache first for instant update
    if (_paletteCache.containsKey(trackId)) {
        if (kDebugMode) print('MusicProvider: Using cached palette for ${track.trackName}');
        _paletteGenerator = _paletteCache[trackId];
        // Note: We don't notifyListeners() here IF it's already set 
        // but since we reset it to null on track change, we should notify.
        notifyListeners();
        return;
    }
    
    try {
      if (kDebugMode) print('MusicProvider: Generating palette for ${track.trackName}...');
      
      ImageProvider? imageProvider;
      bool isLocalFile = false;
      
      // Determine ImageProvider with high priority for offline/local sources
      final offlineMeta = _downloadedTracksMetadata[trackId];
      final artPath = offlineMeta?['artPath'] as String?;

      if (artPath != null && artPath.isNotEmpty && File(artPath).existsSync()) {
          // 1. Downloaded YouTube Track Artwork
          isLocalFile = true;
          imageProvider = FileImage(File(artPath));
          if (kDebugMode) print('MusicProvider: Using offline art for ${track.trackName}');
      } else if (_downloadedTracksMetadata.containsKey(trackId)) {
          // LEGACY FALLBACK: Check if art file exists even if not in metadata
          final fallbackPath = await _buildArtDownloadPath(trackId);
          if (File(fallbackPath).existsSync()) {
             isLocalFile = true;
             imageProvider = FileImage(File(fallbackPath));
             // Update metadata for next time
             _downloadedTracksMetadata[trackId]!['artPath'] = fallbackPath;
             saveDownloadedTracksMetadata();
             if (kDebugMode) print('MusicProvider: Recovered legacy art for ${track.trackName}');
          }
      } 
      
      if (imageProvider == null && track.source == 'local') {
          // 2. Local Device Track Artwork (via MediaStore)
          final bytes = await _localMusicService.getTrackArtwork(track.id);
          if (bytes != null) {
              imageProvider = MemoryImage(bytes);
              isLocalFile = true;
          } else if (track.albumArtUrl.isNotEmpty && File(track.albumArtUrl).existsSync()) {
              imageProvider = FileImage(File(track.albumArtUrl));
              isLocalFile = true;
          }
      } 
      
      // Final fallback to Network
      imageProvider ??= NetworkImage(track.albumArtUrl);

      final gen = await PaletteGenerator.fromImageProvider(
        ResizeImage(imageProvider, width: 100, height: 100),
        maximumColorCount: 15,
      );

      // 3. Post-processing: Boost Vibrancy and Harmony
      final palette = _boostVibrancy(gen);
      
      // Strict check: Ensure we are still playing the same track to avoid race conditions
      if (_currentTrack?.id == trackId) {
        _paletteGenerator = palette;
        
        // Update cache (LRU management: remove oldest if full)
        if (_paletteCache.length > 15) {
            _paletteCache.remove(_paletteCache.keys.first);
        }
        _paletteCache[trackId] = palette;
        
        notifyListeners();
        if (kDebugMode) print('MusicProvider: Palette updated for ${track.trackName} (${isLocalFile ? "Local" : "Network"})');

        // PROACTIVE FIX: If played online but missing local art, download it now
        if (!isLocalFile && _downloadedTracksMetadata.containsKey(trackId)) {
           final aP = await _buildArtDownloadPath(trackId);
           if (track.albumArtUrl.isNotEmpty) {
             _networkService.downloadFile(track.albumArtUrl, aP).then((_) {
                _downloadedTracksMetadata[trackId]!['artPath'] = aP;
                saveDownloadedTracksMetadata();
                if (kDebugMode) print('MusicProvider: Proactively saved artwork for $trackId');
             }).catchError((_) {});
           }
        }
      }
    } catch (e) {
      if (kDebugMode) print('MusicProvider: Error generating palette for ${track.trackName}: $e');
    }
  }

  /// Post-processes a palette to ensure colors are vibrant enough for a liquid UI.
  PaletteGenerator _boostVibrancy(PaletteGenerator original) {
    // If we have a decent vibrant color, we trust it mostly.
    // Otherwise, we take the dominant/muted colors and "boost" them.
    
    // This is a simplified simulation of boosting. In a real app, you'd reconstruct 
    // the PaletteGenerator or just store the Color objects. 
    // Since PaletteGenerator is mostly immutable, we return it but we will
    // apply the "boost" logic in the UI layer (NowPlayingScreen) as well.
    // FOR NOW: We return original and ensure our UI logic handles "drab" palettes.
    return original;
  }

  // --- Dispose ---
  @override
  void dispose() {
    print('MusicProvider: Disposing...');
    
    // FIX: Cancel all audio subscriptions to prevent memory leaks
    for (final sub in _audioSubscriptions) {
      sub.cancel();
    }
    _audioSubscriptions.clear();
    _notifyDebouncer?.cancel();
    
    _audioService.dispose();
    _innerTubeService.dispose();
    _lyricsService.dispose();
    _retryTimer?.cancel();
    _networkQualitySubscription?.cancel();
    _connectivityStatusSubscription?.cancel();
    _reconnectionTimer?.cancel();
    _sleepTimer?.cancel();
    _downloadCancelTokens.forEach((_, token) { if (!token.isCancelled) token.cancel("Provider disposed"); });
    _downloadCancelTokens.clear();
    print('MusicProvider: Disposed.');
    super.dispose();
  }


  // --- Preloading Logic ---
  Future<void> _prefetchNextTrack() async {
    if (_queue.isEmpty) return;

    Track? nextTrack;

    // 1. Determine Next Track based on Shuffle/Repeat/Queue
    if (_queue.isNotEmpty) {
      nextTrack = _queue.first;
    } else {
      final list = _getActivePlaylist();
      if (list.isNotEmpty) {
        int nextIndex = _currentIndex + 1;
        if (nextIndex >= list.length) {
          nextIndex = (_repeatMode == RepeatMode.all) ? 0 : -1;
        }
        if (nextIndex >= 0 && nextIndex < list.length) {
          nextTrack = list[nextIndex];
        }
      }
    }

    if (nextTrack == null) return;
    if (nextTrack.id == _currentTrack?.id) return;

    if (kDebugMode) print('MusicProvider: Prefetching next track: ${nextTrack.trackName}');

    if (!_isOfflineMode && !_isOfflineTrack && nextTrack.source != 'spotify') {
        // Audio Prefetch through InnerTubeService (Now also resolves URL for faster start)
        _innerTubeService.getAudioStreamUrl(nextTrack.id).then((url) {
           if (kDebugMode) print('MusicProvider: Stream URL prefetched for ${nextTrack!.trackName}');
        }).catchError((e) {
           if (kDebugMode) print('MusicProvider: Stream prefetch failed: $e');
        });
        
        // Lyrics Prefetch
        _lyricsService.getParsedLyrics(
          title: nextTrack.trackName,
          artist: nextTrack.artistName,
          durationMs: nextTrack.durationMs,
          videoId: nextTrack.id
        ).then((_) {
           if (kDebugMode) print('MusicProvider: Lyrics prefetch complete for ${nextTrack!.trackName}');
        }).catchError((e) {
           if (kDebugMode) print('MusicProvider: Lyrics prefetch failed: $e');
        });
    }
  }

} // End of MusicProvider class

// Helper class for retry operations (Keep as is)
class _RetryOperation {
  final String description;
  final Future<dynamic> Function() execute;
  int attempts = 1;
  _RetryOperation(this.description, this.execute);
}