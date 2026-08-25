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
import 'package:palette_generator/palette_generator.dart';
// import 'package:device_info_plus/device_info_plus.dart'; // Commented out: Unused
import 'package:dio/dio.dart'; // Used by NetworkService for downloads
import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart'; // Commented out: Unused
import 'package:shared_preferences/shared_preferences.dart';
// For network diagnostics
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
import '../services/stream_resolution_service.dart';
import 'accent_controller.dart';
import '../services/cast_service.dart'; // Cast Service
import 'package:cast/cast.dart'; // Cast Models
import '../services/lyrics/lyrics_service.dart'; // Multi-provider lyrics service
import '../services/recommendation_service.dart'; // AI recommendation engine
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

/// Top-level so it can run in an isolate via [compute]; keeps large JSON
/// encodes off the UI thread.
String _jsonEncode(Object data) => jsonEncode(data);

List<dynamic> _jsonDecode(String s) => jsonDecode(s) as List<dynamic>;

class MusicProvider with ChangeNotifier, WidgetsBindingObserver {
  /// Album-art accent feed (null when not injected).
  final AccentController? _accentController;


  final GlobalKey<NavigatorState> playerNavigatorKey = GlobalKey<NavigatorState>();
  
  // BATTERY FIX: App lifecycle management
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool get isInBackground => _appLifecycleState == AppLifecycleState.paused || 
                              _appLifecycleState == AppLifecycleState.inactive;
  
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
  final bool _isMiniPlayerVisible = true; // Control mini player visibility (e.g. hide when bottom sheet is open)
  
  bool get isMiniPlayerVisible => _isMiniPlayerVisible;

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

  /// Infinite autoplay: when a context ends, keep playing related tracks.
  bool _isAutoQueueEnabled = true;
  bool get isAutoQueueEnabled => _isAutoQueueEnabled;
  Future<void> setAutoQueueEnabled(bool enabled) async {
    if (_isAutoQueueEnabled == enabled) return;
    _isAutoQueueEnabled = enabled;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('autoQueueEnabled', enabled);
  }
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
  String? _errorMessage;
  bool _isLoadingLocal = false;
  Artist? _currentArtistDetails; // Added state for artist screen
  Album? _currentAlbumDetails; // Added state for album screen
  bool _isLoadingArtist = false; // Loading state for artist screen
  bool _isLoadingAlbum = false; // Loading state for album screen
  final Map<String, double> _downloadProgress = {};
  final Map<String, DateTime> _lastProgressNotify = {};
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
  final List<String> _failedTrackIds = [];
  
  // Discovery Caching (TTL based)
  final Map<String, DateTime> _discoveryCacheTimes = {};
  static const Duration _discoveryCacheTTL = Duration(minutes: 30);
  
  // Search Caching (Speed up back/forth)
  final Map<String, List<Track>> _searchCache = {};

  // Services
  final AudioService _audioService = AudioService();
  final SpotifyService _spotifyService = SpotifyService();
  final LocalMusicService _localMusicService = LocalMusicService();
  final NetworkService _networkService = NetworkService();
  final InnerTubeService _innerTubeService = InnerTubeService.instance;
  final StreamResolutionService _streamResolution = StreamResolutionService.instance;
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
  final RecommendationService _recommendationService = RecommendationService(); // AI recommendations
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
      if (kDebugMode) debugPrint("MusicProvider: Using cached lyrics for ${_currentTrack!.trackName}");
      return; 
    }
    
    _isLoadingLyrics = true;
    _lyricsError = null;
    _currentLyrics = null;
    _lyricsTrackId = _currentTrack!.id;
    notifyListeners();
    
    try {
      if (kDebugMode) debugPrint("MusicProvider: Fetching lyrics for ${_currentTrack!.trackName} (Force: $forceRefresh)");
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
        debugPrint("Lyrics Fetch Error: $e");
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
  

  
  // --- Initialization & Setup ---
  DateTime? _lastPositionNotify;
  MusicProvider({AccentController? accentController})
      : _accentController = accentController {
    _initialize();
  }
  
  Future<void> _initialize() async {
    if (kDebugMode) debugPrint('MusicProvider: Initializing...');
    
    await _loadSettings();
    await _loadLikedSongs();
    await _loadRecentlyPlayed();
    await loadUserPlaylists();
    await _loadDownloadedTracksMetadata();
    await _loadRecentlyShownIds(); // For You diversity persistence
    
    // Initialize lyrics service (disk cache)
    await _lyricsService.initialize();
    
    // Initialize recommendation engine
    await _recommendationService.initialize();
    
    _setupAudioListeners();
    _startRetryTimer();
    _setupConnectivityMonitoring();
    
    // BATTERY FIX: Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    final isConnected = _networkService.isConnected;
    if (isConnected && !_isOfflineMode) {
      try {
        await Future.wait([
          fetchTracks(),
          fetchTrendingTracks()
        ]);
      } catch (e) {
        _errorMessage = 'Could not load initial content.';
        if (kDebugMode) debugPrint('MusicProvider: Error loading initial content: $e');
      }
    } else {
      _errorMessage = _isOfflineMode
          ? (_userManuallySetOffline ? 'Currently in offline mode.' : 'No internet connection.')
          : 'No internet connection.';
    }
    
    unawaited(loadLocalMusicFiles());
    if (kDebugMode) debugPrint('MusicProvider: Initialization complete.');
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
  
  // BATTERY FIX: Handle app lifecycle to pause background work
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    
    if (kDebugMode) debugPrint('MusicProvider: App lifecycle changed to $state');
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App going to background - reduce work
        // Audio continues via foreground service (just_audio_background)
        // Note: Palette generation is now skipped in updatePalette() via isInBackground check
        break;
      case AppLifecycleState.resumed:
        // App returning to foreground - resume normal operation
        // Force refresh palette if track changed while in background
        if (_currentTrack != null && _paletteGenerator == null) {
          updatePalette();
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }
  
  void _setupAudioListeners() {
    if (kDebugMode) debugPrint('MusicProvider: Setting up audio listeners...');
    
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
      if (kDebugMode) debugPrint("MusicProvider: Position stream error: $e");
    }));
    
    // Duration stream
    _audioSubscriptions.add(_audioService.onDurationChanged.listen((dur) {
      if ((_duration - dur).abs() > const Duration(milliseconds: 500) && dur > Duration.zero) {
        if (kDebugMode) debugPrint('MusicProvider: Duration updated: $dur');
        _duration = dur;
        _debouncedNotify();
      }
    }, onError: (e) {
      if (kDebugMode) debugPrint("MusicProvider: Duration stream error: $e");
    }));
    
    // Playback state stream - THIS IS CRITICAL
    _audioSubscriptions.add(_audioService.onPlaybackStateChanged.listen((playing) {
      if (kDebugMode) {
        debugPrint('MusicProvider: Playback state changed: $playing (was: $_isPlaying)');
        if (_currentTrack != null) {
          debugPrint('MusicProvider: Current track: ${_currentTrack!.trackName}');
        }
      }
      
      if (_isPlaying != playing) {
        _isPlaying = playing;
        
        if (!playing && _currentTrack != null) {
          if (kDebugMode) debugPrint('MusicProvider: ⚠️ Playback stopped unexpectedly!');
        }
        
        notifyListeners(); // Immediate notify for play/pause
      }
    }, onError: (e) {
      if (kDebugMode) debugPrint("MusicProvider: Playback state stream error: $e");
    }));
    
    // FIX: Restore track completion handling via playerStateStream
    // This listener handles both debugging AND track completion detection
    _audioSubscriptions.add(_audioService.playerStateStream.listen((state) {
      if (kDebugMode) {
        debugPrint('MusicProvider: Player state: ${state.playing ? "PLAYING" : "PAUSED"}, '
              'Processing: ${state.processingState}');
      }
      
      // FIX: Detect track completion and advance to next track
      // ProcessingState.completed means the current track finished playing
      if (state.processingState == ProcessingState.completed && 
          _currentTrack != null && 
          !_isStopping) {
        if (kDebugMode) debugPrint('MusicProvider: Track completed naturally, calling _onTrackComplete');
        _onTrackComplete();
      }
    }, onError: (e) {
      if (kDebugMode) debugPrint("MusicProvider: Player state stream error: $e");
    }));
    
    if (kDebugMode) debugPrint('MusicProvider: Audio listeners set up complete');
    
    // --- Navigation Listeners ---
    _audioSubscriptions.add(_audioService.onSkipToNext.listen((_) {
      if (kDebugMode) debugPrint("MusicProvider: External SkipNext triggered (Notification/LockScreen)");
      _handleAutoSkipToNext();
    }));
    
    _audioSubscriptions.add(_audioService.onSkipToPrevious.listen((_) {
      if (kDebugMode) debugPrint("MusicProvider: External SkipPrevious triggered (Notification/LockScreen)");
      skipToPrevious();
    }));
    
    // Listen for Critical Playback Errors (Corrupt Files)
    _audioSubscriptions.add(_audioService.onPlaybackError.listen((error) async {
       if (error == "Source error" && _currentTrack != null) {
           if (kDebugMode) debugPrint("MusicProvider: Source error detected for ${_currentTrack!.trackName}");
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
      _isAutoQueueEnabled = p.getBool('autoQueueEnabled') ?? true;
      
      final sourceValue = p.getString('musicSource') ?? 'youtube'; 
      _currentMusicSource = MusicSource.fromString(sourceValue); 
      
      if (kDebugMode) {
        debugPrint('Settings: Loaded music source = "$sourceValue" → ${_currentMusicSource.displayName}');
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
        debugPrint('Settings loaded successfully.');
      }
    } catch (e) { 
      if (kDebugMode) {
        debugPrint("Error loading settings: $e"); 
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
        debugPrint('Settings: Saved music source = "${_currentMusicSource.value}" (${_currentMusicSource.displayName})');
        debugPrint('Settings saved successfully.');
      }
    } catch (e) { 
      _errorMessage = "Failed to save settings."; 
      if (kDebugMode) {
        debugPrint('Settings: Error saving - $e');
      }
      notifyListeners(); 
    } 
  }

  // --- Playback Control & Context ---
  void toggleShuffle() { _shuffleEnabled = !_shuffleEnabled; if (_shuffleEnabled && _currentPlayingTracks != null) { _shufflePlaylist(); } else { _updateCurrentIndex(); } _saveSettings(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  
  /// Shuffle and play a list of tracks immediately
  Future<void> shuffleAndPlay(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    
    // Enable shuffle if not already enabled
    if (!_shuffleEnabled) {
      _shuffleEnabled = true;
      _saveSettings();
    }
    
    // Set context and shuffle
    _setPlaybackContext(tracks);
    
    // Play first track from shuffled list
    if (_shuffledPlaylist.isNotEmpty) {
      await playTrack(_shuffledPlaylist[0], playlistTracks: tracks);
    }
  }
  
  void cycleRepeatMode() { _repeatMode = RepeatMode.values[(_repeatMode.index + 1) % RepeatMode.values.length]; _saveSettings(); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void _shufflePlaylist() { if (_currentPlayingTracks == null || _currentPlayingTracks!.isEmpty) { _shuffledPlaylist = []; _currentIndex = -1; return; } _shuffledPlaylist = List.from(_currentPlayingTracks!)..shuffle(Random()); _updateCurrentIndex(); /* Preload handled by toggleShuffle or setPlaybackContext */ }
  List<Track> _getActivePlaylist() => _shuffleEnabled ? _shuffledPlaylist : (_currentPlayingTracks ?? []);
  void _updateCurrentIndex() { final list = _getActivePlaylist(); _currentIndex = (_currentTrack != null && list.isNotEmpty) ? list.indexWhere((t) => t.id == _currentTrack!.id) : -1; }

  // --- Advance-race protection ---
  // Natural end-of-track triggers BOTH the nav-monitor (dummy item) and the
  // completed handler. This guard suppresses the second advance for the same
  // track within a short window.
  DateTime? _lastAutoAdvanceAt;
  String? _lastAutoAdvanceTrackId;
  bool _consumeDuplicateAutoAdvance(String? trackId) {
    final now = DateTime.now();
    final isDup = _lastAutoAdvanceAt != null &&
        _lastAutoAdvanceTrackId == trackId &&
        now.difference(_lastAutoAdvanceAt!).inMilliseconds < 2000;
    if (!isDup) {
      _lastAutoAdvanceAt = now;
      _lastAutoAdvanceTrackId = trackId;
    }
    return isDup;
  }

  // Bumped whenever user intent starts/retargets playback; stale async
  // continuations (e.g. autoplay fetches) compare and abort.
  int _playbackGeneration = 0;

  /// Force-reloads the current track, bypassing play/pause toggle logic.
  /// Needed because after auto-advance the player sits on a silent dummy item,
  /// so seek(Duration.zero)/resume would target the wrong source.
  Future<void> _replayCurrentTrack() async {
    final t = _currentTrack;
    if (t == null) return;
    _currentTrack = null; // force playTrack full path
    await playTrack(t, playlistTracks: _currentPlayingTracks, playlistId: _currentPlaylistId);
  }


  void _setPlaybackContext(List<Track>? tracks, {String? playlistId, bool clearQueue = true}) { if (!listEquals(_currentPlayingTracks, tracks) || _currentPlaylistId != playlistId) { debugPrint("Setting playback context. ID: $playlistId, Tracks: ${tracks?.length ?? 0}, ClearQueue: $clearQueue"); _currentPlayingTracks = tracks != null ? List.from(tracks) : null; _currentPlaylistId = playlistId; if (clearQueue && _queue.isNotEmpty) { _queue.clear(); debugPrint("Playback context changed, queue cleared."); } if (_shuffleEnabled && _currentPlayingTracks != null) {
    _shufflePlaylist();
  } else {
    _updateCurrentIndex();
  } _handlePlaybackOrContextChangeForPreloading();} else { _updateCurrentIndex(); }  }
  /// Handles skip events arriving via the audio-service stream (dummy-item
  /// auto-advance and media-session skips). Guards the double-advance race
  /// with the completed handler and honors repeat-one.
  Future<void> _handleAutoSkipToNext() async {
    if (_consumeDuplicateAutoAdvance(_currentTrack?.id)) return;

    if (_repeatMode == RepeatMode.one && _currentTrack != null) {
      // Replay the actual track: after auto-advance the player is parked on
      // the next dummy item, so seeking/resuming there would play silence.
      await _replayCurrentTrack();
      _handlePlaybackOrContextChangeForPreloading();
      return;
    }
    await skipToNext();
  }

  Future<void> _onTrackComplete() async {
    if (kDebugMode) debugPrint('MusicProvider: _onTrackComplete event for ${_currentTrack?.trackName}');
    
    // Record enhanced play signal for recommendation agent
    if (_currentTrack != null) {
      final listenTimeMs = _position.inMilliseconds;
      final durationMs = _duration.inMilliseconds;
      
      // Calculate completion rate (0-1)
      final completionRate = durationMs > 0 
          ? (listenTimeMs / durationMs).clamp(0.0, 1.0) 
          : 1.0;
      
      // Skip timing if skipped early
      final skipTimingMs = completionRate < 0.5 ? listenTimeMs : null;
      
      _recommendationService.recordPlay(
        _currentTrack!,
        completionRate: completionRate,
        listenTimeMs: listenTimeMs,
        skipTimingMs: skipTimingMs,
      );
    }
    
    if (_stopAfterCurrentTrack) {
      _stopAfterCurrentTrack = false;
      stopTrack();
      return;
    }

    if (_repeatMode == RepeatMode.one) {
       await _replayCurrentTrack();
       _handlePlaybackOrContextChangeForPreloading();
       return;
    }

    // The nav-monitor usually advances first (dummy item); if it already did,
    // this completed event must not advance a second time.
    // ponytail: recommendation stats below may be approximate under the race —
    // acceptable signal noise; revisit only if recommendations degrade.
    if (_consumeDuplicateAutoAdvance(_currentTrack?.id)) return;

    _updateCurrentIndex();
    
    // 1. Check Queue
    if (_queue.isNotEmpty) {
       final next = _queue.removeAt(0);
       if (kDebugMode) debugPrint("MusicProvider: Playing next from queue: ${next.trackName}");
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
       if (kDebugMode) debugPrint('MusicProvider: Advancing to index $nextIdx');
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
       if (kDebugMode) debugPrint('MusicProvider: Looping context to start.');
       _playTrackInternal(list[0], setContext: false, clearQueue: false);
    } else {
       // Check playback context type
       bool isListNotEmpty = list.isNotEmpty;
       bool isFirstLocal = isListNotEmpty && list.first.source == 'local';
       bool isFirstDownloaded = isListNotEmpty && _downloadedTracksMetadata.containsKey(list.first.id);
       bool isOfflineContext = isListNotEmpty && (isFirstLocal || isFirstDownloaded || _isOfflineTrack || _isOfflineContext);
       
       if (isOfflineContext) {
           // Local/downloaded playlists loop
           if (kDebugMode) debugPrint('MusicProvider: End of Downloaded List -> Looping to start');
           _playOfflineTrackInternal(list[0], setContext: false, clearQueue: false);
       } else if (isListNotEmpty && _currentPlayingTracks != null && _currentPlayingTracks!.length > 1) {
           // Multi-track playlists loop
           if (kDebugMode) debugPrint('MusicProvider: End of Online Playlist -> Looping to start');
           _playTrackInternal(list[0], setContext: false, clearQueue: false);
        } else {
            // ENHANCED: Single track or For You context -> Smart Autoplay
            if (!_isAutoQueueEnabled) {
              if (kDebugMode) debugPrint('MusicProvider: Auto Queue disabled, stopping.');
              stopTrack();
              return;
            }
            _startAutoplayFromRecommendations();
        }
    }
  }
  
  /// Start autoplay with AI-recommended tracks based on current track
  Future<void> _startAutoplayFromRecommendations() async {
    if (_currentTrack == null) {
      stopTrack();
      return;
    }

    // Own this playback attempt; any user interaction bumps the generation
    // and aborts this continuation before it can hijack playback.
    final gen = ++_playbackGeneration;

    if (kDebugMode) debugPrint('MusicProvider: Starting autoplay recommendations for ${_currentTrack!.trackName}');

    try {
      // Get recommendations based on current track
      final List<Track> recommendations;

      if (_currentTrack!.source == 'youtube' && _currentTrack!.id.length == 11) {
        // Use current track as seed for related content
        recommendations = await _innerTubeService.getSuggestions(_currentTrack!.id, limit: 20);
      } else {
        // Fallback: use recently played seeds
        recommendations = await _fetchPersonalizedForYou();
      }

      if (gen != _playbackGeneration) {
        if (kDebugMode) debugPrint('MusicProvider: Autoplay aborted (user took over).');
        return;
      }
      
      if (recommendations.isEmpty) {
        if (kDebugMode) debugPrint('MusicProvider: No recommendations found, stopping.');
        stopTrack();
        return;
      }
      
      // Filter and rank recommendations
      final filtered = recommendations.where((t) {
        final id = t.id;
        if (id.length != 11) return false;
        if (id.startsWith('PL') || id.startsWith('VL') || id.startsWith('UC')) return false;
        if (t.id == _currentTrack!.id) return false; // Exclude current
        return true;
      }).toList();
      
      if (filtered.isEmpty) {
        if (kDebugMode) debugPrint('MusicProvider: No valid recommendations after filtering.');
        stopTrack();
        return;
      }
      
      // Use recommendation agent for sequence-planned autoplay
      final ranked = _recommendationService.getAutoplayRecommendations(
        _currentTrack!,
        filtered,
        limit: 15,
      );
      
      if (ranked.isEmpty) {
        stopTrack();
        return;
      }
      
      // Set new context and play first recommendation
      if (gen != _playbackGeneration) {
        if (kDebugMode) debugPrint('MusicProvider: Autoplay aborted before start (user took over).');
        return;
      }
      final nextTrack = ranked.first;
      if (kDebugMode) debugPrint('MusicProvider: Autoplay -> ${nextTrack.trackName}');
      
      // Set remaining as new playlist context
      _setPlaybackContext(ranked, clearQueue: false);
      await _playTrackInternal(nextTrack, setContext: false, clearQueue: false);
      
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: Autoplay error: $e');
      stopTrack();
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
      debugPrint("Error in _playTrackInternal: $e"); 
    } 
  }
  Future<bool> _shouldPlayOffline(Track track) async => track.source == 'local' || await isTrackDownloaded(track.id);
  Future<void> skipToNext() async {
    debugPrint('MusicProvider: SkipNext requested.');
    _playbackGeneration++; // invalidate stale async continuations
    if (_currentTrack == null) return;
    if (_queue.isNotEmpty) { 
      final next = _queue.removeAt(0); 
      debugPrint("MusicProvider: Skipping to next from queue: ${next.trackName}"); 
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
  Future<void> skipToPrevious() async { debugPrint('SkipPrevious requested.'); _playbackGeneration++; if (_currentTrack == null) return; if (_position > const Duration(seconds: 3)) { await seekTo(Duration.zero); if (!_isPlaying) await resumeTrack(); _handlePlaybackOrContextChangeForPreloading(); return; } final list = _getActivePlaylist(); if (list.isEmpty) return; _updateCurrentIndex(); if (_currentIndex == -1 && list.isNotEmpty) { await _playTrackInternal(list.last); return; } int prev = _currentIndex - 1; if (prev >= 0) { await _playTrackInternal(list[prev]); } else { if (_repeatMode != RepeatMode.off) {
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
      debugPrint('MusicProvider: Request playTrack: ${track.trackName} (ID: ${track.id})');
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

    _playbackGeneration++; // invalidate stale async continuations
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
      if (kDebugMode) debugPrint('MusicProvider: Skipping non-playable track: ${track.trackName} (ID: $trackId)');
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
          debugPrint('MusicProvider: Converting Spotify track to YouTube: ${track.trackName}');
        }
        final yt = await _spotifyService.findYouTubeTrack(track);
        if (yt != null) {
          playableId = yt.id;
          // Keep _currentTrack as the ORIGINAL track so playlist index
          // lookups (which match by original id) stay valid.
          effectiveTrack = track.copyWith(
            id: playableId,
            source: 'youtube',
            previewUrl: yt.previewUrl,
          );
        } else {
          throw Exception("Could not find playable version of '${track.trackName}'.");
        }
      }

      // Await the bitrate that was started earlier
      final bitrate = await bitrateFuture;
      if (bitrate == 0) {
        throw Exception('Cannot determine bitrate - check network connection.');
      }

      if (kDebugMode) {
        debugPrint('MusicProvider: Fetching stream URL for ${effectiveTrack.trackName} (bitrate: $bitrate kbps)');
      }


      // Resolve stream URL via the racing resolution service
      // (InnerTube ANDROID_VR vs Saavn 320kbps, first validated wins).
      final resolved = await _streamResolution.resolve(ResolveRequest(
        videoId: playableId,
        title: effectiveTrack.trackName,
        artist: effectiveTrack.artistName,
        durationMs: effectiveTrack.durationMs,
      ));

      if (resolved == null || resolved.url.isEmpty) {
        throw Exception('Failed to get stream: all sources exhausted');
      }
      if (kDebugMode) {
        debugPrint('MusicProvider: Stream resolved via ${resolved.source}');
      }

      final playHeaders = <String, String>{
        if (resolved.userAgent != null) 'User-Agent': resolved.userAgent!,
      };

      // Play the resolved URL. YouTube bot-gates URLs per-request (rotation),
      // so a rejected URL often just needs a fresh resolution — retry up to
      // 3 times, invalidating the cache each round.
      ResolvedStream current = resolved;
      for (var attempt = 1; attempt <= 3; attempt++) {
        final headers = <String, String>{
          if (current.userAgent != null) 'User-Agent': current.userAgent!,
        };
        try {
          await _audioService.play(current.url,
            headers: headers.isNotEmpty ? headers : null,
            title: effectiveTrack.trackName,
            artist: effectiveTrack.artistName,
            artUri: effectiveTrack.albumArtUrl,
            id: effectiveTrack.id,
            hasNext: _hasNext(),
            hasPrevious: _hasPrevious(),
          );
          break;
        } catch (e) {
          if (attempt == 3) rethrow;
          if (kDebugMode) {
            debugPrint('MusicProvider: Playback failed ($e). Re-resolving (attempt ${attempt + 1}/3)...');
          }
          _streamResolution.invalidate(playableId);
          final retry = await _streamResolution.resolve(ResolveRequest(
            videoId: playableId,
            title: effectiveTrack.trackName,
            artist: effectiveTrack.artistName,
            durationMs: effectiveTrack.durationMs,
          ));
          if (retry == null || retry.url.isEmpty) rethrow;
          current = retry;
        }
      }

      // Update state - Note: _isPlaying will be updated by the stream listener
      // Don't set _isPlaying = true here to avoid race condition
      // Keep the ORIGINAL track so playlist index lookups (by original id),
      // same-tap toggles and download keys stay valid even after Spotify→YT
      // conversion. The playable YT variant only lives in the audio source.
      _currentTrack = track;
      _updateRecentlyPlayed(track);
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
        debugPrint('MusicProvider: Successfully started playback of ${effectiveTrack.trackName}');
      }
      _consecutiveErrors = 0; // Reset error count on success
      _failedTrackIds.remove(effectiveTrack.id);
      
    } catch (e, s) {
      if (kDebugMode) {
        debugPrint('MusicProvider: ERROR PLAYING TRACK');
        debugPrint('Track: ${track.trackName}');
        debugPrint('Error: $e');
        debugPrint('Stack trace: $s');
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
    await _playOfflineTrackInternal(track, setContext: setContext, clearQueue: clearQueue, contextList: contextList);
    
    if (setContext && contextList != null) {
       _setPlaybackContext(contextList, clearQueue: clearQueue);
    }
  }

  Future<void> _playOfflineTrackInternal(Track track, {bool setContext = true, bool clearQueue = true, List<Track>? contextList}) async {
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
             debugPrint("MusicProvider: File exists but too small ($fileSize bytes). Deleting: $filePath");
             try { await file.delete(); } catch (_) {}
        }
        await _handleMissingOfflineFile(track.id, filePath);
        
        // Fallback to online if possible
        if (!_isOfflineMode && _networkService.isConnected) {
            if (kDebugMode) debugPrint("MusicProvider: Local file missing, falling back to online for ${track.trackName}");
            // Recursive call to playTrack will now see it as NOT downloaded (since we removed metadata)
            // and attempt online playback. Preserve the caller's original context list
            // so skips stay inside what the user tapped from.
            await playTrack(track,
                playlistTracks: setContext ? (contextList ?? _currentPlayingTracks ?? (isDownloaded ? await getDownloadedTracks() : _localTracks)) : null,
                playlistId: _currentPlaylistId,
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
          debugPrint("MusicProvider: Set playback context to $contextDesc");
        }
      } else {
        _updateCurrentIndex();
      }
      
      if (kDebugMode) {
        debugPrint('MusicProvider: Playing offline file: $filePath');
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
        debugPrint('MusicProvider: ERROR PLAYING OFFLINE TRACK');
        debugPrint('Track: ${track.trackName}');
        debugPrint('Error: $e');
        debugPrint('Stack trace: $s');
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
      debugPrint('Error stopping service: $e'); 
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
  StreamSubscription? _castDevicesSub;

  void startCastingDiscovery() {
    _isSearchingDevices = true;
    notifyListeners();
    _castService.startDiscovery();
    // Keep exactly ONE devices subscription; re-invocations must not stack
    // duplicate listeners on the broadcast stream.
    _castDevicesSub ??= _castService.devicesStream.listen((devices) {
      _castDevices = devices;
      notifyListeners();
    });
  }

  void stopCastingDiscovery() {
    _isSearchingDevices = false;
    _castDevicesSub?.cancel();
    _castDevicesSub = null;
    _castService.stopDiscovery();
    notifyListeners();
  }

  Future<void> connectToCastDevice(CastDevice device) async {
    final success = await _castService.connect(device);
    if (success) {
      // If we are currently playing something, transfer it
      if (_currentTrack != null) {
        // Build high quality URL
        String? streamUrl;
        if (_currentTrack!.source == 'youtube' || _currentTrack!.source == 'piped') {
           final castResolved = await _streamResolution.resolve(ResolveRequest(
             videoId: _currentTrack!.id,
             title: _currentTrack!.trackName,
             artist: _currentTrack!.artistName,
             durationMs: _currentTrack!.durationMs,
           ));
           streamUrl = castResolved?.url;
        } else {
           // Local file casting might require a local HTTP server, omitting for simple scope
           // For now, assume remote URLs only or just remote tracks
           streamUrl = null;
        }

        if (streamUrl != null) {
          _isCasting = true;
          unawaited(_audioService.pause()); // Pause local playback
          await _castService.loadMedia(
            url: streamUrl,
            title: _currentTrack!.trackName,
            artist: _currentTrack!.artistName,
            imageUrl: _currentTrack!.albumArtUrl,
          );
        } else {
          _errorMessage = 'Casting unavailable for this track.';
        }
      } else {
        _isCasting = true;
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
    debugPrint("Playback Error: $message");

    // Dummy padding sources (silent WAV) must never count as track failures —
    // they exist only so notification buttons stay clickable.
    final id = _currentTrack?.id ?? '';
    if (id == 'prev_dummy' || id == 'next_dummy') {
      if (kDebugMode) debugPrint('MusicProvider: Ignoring dummy source error.');
      return;
    }

    // Same track already failed recently: do not loop on it.
    if (_failedTrackIds.contains(id)) {
      await stopTrack();
      return;
    }
    _failedTrackIds.add(id);
    if (_failedTrackIds.length > 20) _failedTrackIds.remove(_failedTrackIds.first);

    _errorMessage = message.length > 150 ? '${message.substring(0, 147)}...' : message;

    // Automatic Failover: If it's an online track and we have a next one, try skipping
    if (!_isOfflineTrack && !_isOfflineMode && _networkService.isConnected) {
       _consecutiveErrors++;
       if (_consecutiveErrors <= 1) {
          if (kDebugMode) debugPrint("MusicProvider: Attempting auto-skip after error...");
          skipToNext();
          return;
       }
    }

    await stopTrack();
    _consecutiveErrors = 0; // Reset
  }

  // --- Queue Management ---
  void addToQueue(Track track) { _queue.add(track); debugPrint("Added to queue: ${track.trackName}. Size: ${_queue.length}"); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void addListToQueue(List<Track> tracks) { _queue.addAll(tracks); debugPrint("Added ${tracks.length} to queue. Size: ${_queue.length}"); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void playNext(Track track) { _queue.insert(0, track); debugPrint("Play next: ${track.trackName}. Size: ${_queue.length}"); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }
  void reorderQueueItem(int oldIndex, int newIndex) { if (oldIndex < 0 || oldIndex >= _queue.length || newIndex < 0) return; final int iIdx = newIndex > oldIndex ? newIndex - 1 : newIndex; final tr = _queue.removeAt(oldIndex); _queue.insert(iIdx.clamp(0, _queue.length), tr); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }

  // Updated to accept Track object or index
  void removeFromQueue(dynamic item) {
    bool removed = false;
    if (item is int && item >= 0 && item < _queue.length) {
      final rTr = _queue.removeAt(item);
      debugPrint("Removed from queue by index: ${rTr.trackName}. Size: ${_queue.length}");
      removed = true;
    } else if (item is Track) {
      final initialLength = _queue.length;
      _queue.removeWhere((t) => t.id == item.id);
      if (_queue.length < initialLength) {
        debugPrint("Removed from queue by track: ${item.trackName}. Size: ${_queue.length}");
        removed = true;
      }
    } else if (item is String) { // Remove by track ID
       final initialLength = _queue.length;
      _queue.removeWhere((t) => t.id == item);
      if (_queue.length < initialLength) {
        debugPrint("Removed from queue by track ID: $item. Size: ${_queue.length}");
        removed = true;
      }
    }


    if (removed) {
      notifyListeners();
      _handlePlaybackOrContextChangeForPreloading(); // Also call after removing from queue
    }
  }

  void clearQueue() { if (_queue.isEmpty) return; _queue.clear(); debugPrint("Queue cleared."); notifyListeners(); _handlePlaybackOrContextChangeForPreloading(); }


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
        if (kDebugMode) debugPrint("MusicProvider: Attempting to preload ${nextTrack.trackName}");
        String playableId = nextTrack.id;
        if (nextTrack.source == 'spotify') {
          final ytEquivalent = await _spotifyService.findYouTubeTrack(nextTrack);
          if (ytEquivalent != null) {
            playableId = ytEquivalent.id;
          } else {
            if (kDebugMode) debugPrint("MusicProvider: Could not find YouTube equivalent for Spotify track ${nextTrack.trackName} for preloading.");
            return;
          }
        }
        final preloadResolved = await _streamResolution.resolve(ResolveRequest(
          videoId: playableId,
          title: nextTrack.trackName,
          artist: nextTrack.artistName,
          durationMs: nextTrack.durationMs,
        ));
        if (preloadResolved == null) return;
        await _audioService.preloadTrack(preloadResolved.url, userAgent: preloadResolved.userAgent);
      } catch (e) {
        if (kDebugMode) debugPrint("MusicProvider: Error preloading next track ${nextTrack.trackName}: $e");
      }
    } else {
      if (kDebugMode) debugPrint("MusicProvider: No suitable next track to preload or next is same as current/local/downloaded.");
    }
  }

  // Call _preloadNextTrack after a track starts playing or context changes
  void _handlePlaybackOrContextChangeForPreloading() {
    // Clear any existing preloaded track if context changes significantly
    // This is implicitly handled by AudioService if a different track is played.
    // Explicitly: _audioService.cancelPreload(); (if such method existed)

    // Then try to preload the new next track
    _preloadNextTrack();
    
    // Also prefetch lyrics for upcoming tracks
    _prefetchUpcomingLyrics();
  }
  
  /// Prefetch lyrics for the next 3 tracks in the playlist/queue
  void _prefetchUpcomingLyrics() {
    if (_currentIndex < 0) return;
    
    final playlist = _getActivePlaylist();
    if (playlist.isEmpty) return;
    
    final upcoming = <Map<String, String>>[];
    
    // Add next 3 tracks from playlist
    for (int i = 1; i <= 3; i++) {
      final nextIndex = _currentIndex + i;
      if (nextIndex < playlist.length) {
        final track = playlist[nextIndex];
        upcoming.add({
          'title': track.trackName,
          'artist': track.artistName,
          'videoId': track.source == 'youtube' ? track.id : null,
        }.map((key, value) => MapEntry(key, value ?? '')));
      }
    }
    
    // Also add queue items
    for (int i = 0; i < 3 && i < _queue.length; i++) {
      final track = _queue[i];
      upcoming.add({
        'title': track.trackName,
        'artist': track.artistName,
        'videoId': track.source == 'youtube' ? track.id : null,
      }.map((key, value) => MapEntry(key, value ?? '')));
    }
    
    if (upcoming.isNotEmpty) {
      _lyricsService.prefetchLyrics(upcoming);
    }
  }


  // --- Internal Metadata Fetchers (with Caching) ---
  final Map<String, Artist> _artistCache = {};
  final Map<String, Album> _albumCache = {};

  /// Keeps insertion-ordered caches bounded (FIFO eviction).
  static void _capCache<K, V>(Map<K, V> cache, int max) {
    while (cache.length > max) {
      cache.remove(cache.keys.first);
    }
  }

  Future<Artist?> _fetchArtistInternal(String artistName) async {
    // 1. Check Cache
    if (_artistCache.containsKey(artistName)) {
      if (kDebugMode) debugPrint("MusicProvider: Cache hit for artist $artistName");
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
      _capCache(_artistCache, 100);
      return artist;
    } catch (e) {
      if (kDebugMode) debugPrint("MusicProvider: Internal artist fetch error: $e");
      return null;
    }
  }

  Future<Album?> _fetchAlbumInternal(String albumName, String artistName) async {
    final key = '$albumName|$artistName';
    
    // 1. Check Cache
    if (_albumCache.containsKey(key)) {
       if (kDebugMode) debugPrint("MusicProvider: Cache hit for album $albumName");
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
         _capCache(_albumCache, 100);
         return album;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint("MusicProvider: Internal album fetch error: $e");
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
    if (kDebugMode) debugPrint("PROVIDER ACTION: Navigate to Artist: $artistName");
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
    if (kDebugMode) debugPrint("PROVIDER ACTION: Navigate to Artist Object: ${artistTrack.trackName} (${artistTrack.id})");
    _isLoadingArtist = true;
    _currentArtistDetails = null;
    _errorMessage = null;
    notifyListeners();

    try {
      // Check cache first using name
      if (_artistCache.containsKey(artistTrack.trackName)) {
        _currentArtistDetails = _artistCache[artistTrack.trackName];
        if (kDebugMode) debugPrint("MusicProvider: Cache hit for artist object ${artistTrack.trackName}");
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
      _capCache(_artistCache, 100);
      
       debugPrint("PROVIDER: Artist info loaded for ${_currentArtistDetails?.name}");
    } catch (e) {
      _errorMessage = "Could not load artist details.";
      if (kDebugMode) debugPrint("PROVIDER ERROR: $e");
      _currentArtistDetails = null;
    } finally {
      _isLoadingArtist = false;
      notifyListeners();
    }
  }

  Future<void> navigateToAlbum(String albumName, String artistName) async { 
    if (kDebugMode) debugPrint("PROVIDER ACTION: Navigate to Album: $albumName by $artistName");
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
  void _setupConnectivityMonitoring() { _networkQualitySubscription = _networkService.onNetworkQualityChanged.listen((q) => _handleNetworkQualityChange(q), onError: (e) => debugPrint("NetQual stream error: $e")); _connectivityStatusSubscription = _networkService.onConnectivityChanged.listen((c) => _handleConnectivityChange(c), onError: (e) => debugPrint("Connect stream error: $e")); _networkService.checkNetworkQualityNow().then((q) { _handleNetworkQualityChange(q); _handleConnectivityChange(q != NetworkQuality.offline); }); }

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
        if (kDebugMode) debugPrint("MusicProvider: Auto-adjusted bitrate to Wifi:$_wifiBitrate, Cell:$_cellularBitrate");
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

  void _handleConnectivityChange(bool isConnected) { if (!isConnected && !_isOfflineMode) { _isOfflineMode = true; _userManuallySetOffline = false; _saveSettings(); _showOfflineModeNotification('Connection lost.'); _switchToOfflineVersionIfAvailable(); pauseAllDownloads(); notifyListeners(); } else if (isConnected && _isOfflineMode && !_userManuallySetOffline) { goOnline(); } else if (isConnected && _isOfflineMode && _userManuallySetOffline) { if (!_isReconnecting) _showReconnectionPrompt(); _processRetryQueue(); _processDownloadQueue(); } else if (isConnected && !_isOfflineMode) { if (_isReconnecting) { _isReconnecting = false; _errorMessage = null; notifyListeners(); } _processRetryQueue(); _processDownloadQueue(); } }
  void goOnline() { if (_isOfflineMode) { bool wasOffline = _isOfflineMode; _isOfflineMode = false; _userManuallySetOffline = false; _isReconnecting = false; _saveSettings(); _errorMessage = 'You are now online.'; notifyListeners(); if (wasOffline) _refreshDataOnReconnect(); _processRetryQueue(); _processDownloadQueue(); } }
  void goOffline() { if (!_isOfflineMode) { _isOfflineMode = true; _userManuallySetOffline = true; _isReconnecting = false; _saveSettings(); _showOfflineModeNotification('Offline mode enabled.'); _switchToOfflineVersionIfAvailable(); pauseAllDownloads(); notifyListeners(); } }
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
  Future<void> _loadLikedSongs() async { try { final p = await SharedPreferences.getInstance(); final s = p.getString('likedSongs'); if (s != null) _likedSongs = (await compute(_jsonDecode, s)).map((j) => Track.fromJson(Map<String, dynamic>.from(j as Map))).toList(); } catch (_) { _likedSongs = []; } }
  Future<void> _saveLikedSongs() async { try { final p = await SharedPreferences.getInstance(); await p.setString('likedSongs', await compute(_jsonEncode, _likedSongs.map((t) => t.toJson()).toList())); } catch (e) { _addToRetryQueue(_RetryOperation('Save liked', _saveLikedSongs)); } }

  // --- Recently Played ---
  Future<void> _updateRecentlyPlayed(Track track) async { _recentlyPlayed.removeWhere((t) => t.id == track.id); _recentlyPlayed.insert(0, track); if (_recentlyPlayed.length > 20) _recentlyPlayed = _recentlyPlayed.take(20).toList(); await _saveRecentlyPlayed(); }
  void removeFromRecentlyPlayed(String trackId) { int count = _recentlyPlayed.length; _recentlyPlayed.removeWhere((t) => t.id == trackId); if (_recentlyPlayed.length < count) { _saveRecentlyPlayed(); notifyListeners(); } }
  Future<void> _loadRecentlyPlayed() async { try { final p = await SharedPreferences.getInstance(); final s = p.getString('recentlyPlayed'); if (s != null) _recentlyPlayed = (await compute(_jsonDecode, s)).map((j) => Track.fromJson(Map<String, dynamic>.from(j as Map))).toList(); } catch (_) { _recentlyPlayed = []; } }
  Future<void> _saveRecentlyPlayed() async { try { final p = await SharedPreferences.getInstance(); await p.setString('recentlyPlayed', await compute(_jsonEncode, _recentlyPlayed.map((t) => t.toJson()).toList())); } catch (e) { _addToRetryQueue(_RetryOperation('Save recent', _saveRecentlyPlayed)); } }

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
        debugPrint('MusicProvider: Switching music source from ${_currentMusicSource.displayName} to ${source.displayName}');
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

  // --- Playlist Management ---
  Future<void> loadUserPlaylists() async { try { final p = await SharedPreferences.getInstance(); final s = p.getString('userPlaylists'); if (s != null) _userPlaylists = (await compute(_jsonDecode, s)).map((j) => Playlist.fromJson(Map<String, dynamic>.from(j as Map))).toList(); } catch (_) { _userPlaylists = []; } }
  Future<void> saveUserPlaylists() async { try { final p = await SharedPreferences.getInstance(); await p.setString('userPlaylists', await compute(_jsonEncode, _userPlaylists.map((pl) => pl.toJson()).toList())); } catch (e) { _addToRetryQueue(_RetryOperation('Save playlists', saveUserPlaylists)); } }
  Future<void> createPlaylist(String name, {List<Track>? initialTracks, String? imageUrl}) async { 
    if (name.trim().isEmpty) { 
      _errorMessage = "Name empty."; 
      notifyListeners(); 
      return; 
    } 
    try { 
      final pl = Playlist(
        id: 'pl_${DateTime.now().millisecondsSinceEpoch}', 
        name: name.trim(), 
        imageUrl: imageUrl ?? '', 
        tracks: initialTracks ?? []
      ); 
      _userPlaylists.add(pl); 
      await saveUserPlaylists(); 
      _errorMessage = "Playlist created."; 
      notifyListeners(); 
    } catch (e, stack) { 
      debugPrint("Error creating playlist: $e\n$stack");
      // PROACTIVE FIX: Showing runtimeType to identify "Instance of" errors
      _errorMessage = 'Failed to create (${e.runtimeType}): $e'; 
      notifyListeners(); 
    } 
  }

  Future<void> deletePlaylist(String playlistId) async { 
    final i = _userPlaylists.indexWhere((p) => p.id == playlistId); 
    if (i < 0) return; 
    try { 
      _userPlaylists.removeAt(i); 
      await saveUserPlaylists(); 
      if (_currentPlaylistId == playlistId) await stopTrack(); 
      _errorMessage = "Playlist deleted."; 
      notifyListeners(); 
    } catch (e) { 
      _errorMessage = 'Failed to delete (${e.runtimeType}): $e'; 
      notifyListeners(); 
    } 
  }

  Future<void> renamePlaylist(String playlistId, String newName) async { 
    if (newName.trim().isEmpty) { 
      _errorMessage = "Name empty."; 
      notifyListeners(); 
      return; 
    } 
    final i = _userPlaylists.indexWhere((p) => p.id == playlistId); 
    if (i < 0) return; 
    try { 
      _userPlaylists[i] = _userPlaylists[i].copyWith(name: newName.trim()); 
      await saveUserPlaylists(); 
      _errorMessage = "Renamed."; 
      notifyListeners(); 
    } catch (e) { 
      _errorMessage = "Failed to rename (${e.runtimeType}): $e"; 
      notifyListeners(); 
    } 
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async { 
    final i = _userPlaylists.indexWhere((p) => p.id == playlistId); 
    if (i < 0) {
      _errorMessage = "Playlist not found.";
      notifyListeners();
      return;
    }
    final pl = _userPlaylists[i]; 
    if (pl.tracks.any((t) => t.id == track.id)) { 
      _errorMessage = "Already in playlist."; 
      notifyListeners(); 
      return; 
    } 
    try { 
      // Create a clean copy of the track to ensure no transient fields cause issues
      final cleanTrack = track.copyWith(); 
      _userPlaylists[i] = pl.copyWith(tracks: [...pl.tracks, cleanTrack]); 
      await saveUserPlaylists(); 
      _errorMessage = "Added to ${pl.name}."; 
      notifyListeners(); 
    } catch (e, stack) { 
      debugPrint("Error adding to playlist: $e\n$stack");
      _errorMessage = 'Failed to add track (${e.runtimeType}): $e'; 
      notifyListeners(); 
    } 
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async { 
    final i = _userPlaylists.indexWhere((p) => p.id == playlistId); 
    if (i < 0) return; 
    final pl = _userPlaylists[i]; 
    final tN = pl.tracks.firstWhereOrNull((t) => t.id == trackId)?.trackName ?? '?'; 
    try { 
      final uT = pl.tracks.where((t) => t.id != trackId).toList(); 
      if (uT.length < pl.tracks.length) { 
        _userPlaylists[i] = pl.copyWith(tracks: uT); 
        await saveUserPlaylists(); 
        _errorMessage = "Removed '$tN'."; 
        if (_currentPlaylistId == playlistId && _currentTrack?.id == trackId) await skipToNext(); 
        notifyListeners(); 
      } 
    } catch (e) { 
      _errorMessage = 'Failed to remove track: $e'; 
      notifyListeners(); 
    } 
  }

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
  } } final dlResolved = await _streamResolution.resolve(ResolveRequest(
        videoId: sId,
        title: track.trackName,
        artist: track.artistName,
        durationMs: track.durationMs,
      ));
      final sUrl = dlResolved?.url;
      if (sUrl == null) throw Exception('No downloadable stream found.');
      fP = await _buildDownloadFilePath(id);
      
      // Download Artwork simultaneously (if available)
      String aP = '';
      if (track.albumArtUrl.isNotEmpty) {
          aP = await _buildArtDownloadPath(id);
          try {
              await _networkService.downloadFile(track.albumArtUrl, aP);
          } catch (e) {
              if (kDebugMode) debugPrint('MusicProvider: Art download failed: $e');
              aP = ''; // Fallback to network if local art fails
          }
      }

      await _networkService.downloadFile(sUrl, fP, cancelToken: cT, onProgress: (p) {
        if (_isDownloading[id] == true) {
          _downloadProgress[id] = p;
          // Throttle global notifications: Dio fires per-chunk (10-50x/sec per
          // file, xN concurrent). Mirrors the position-tick throttle below.
          final now = DateTime.now();
          if (!_lastProgressNotify.containsKey(id) ||
              now.difference(_lastProgressNotify[id]!) >= const Duration(milliseconds: 250)) {
            _lastProgressNotify[id] = now;
            notifyListeners();
          }
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
            _invalidateDownloadedTracksCache();
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
  Future<void> deleteDownloadedTrack(String trackId) async { final meta = _downloadedTracksMetadata[trackId]; if (meta == null) { _errorMessage = "Not downloaded."; notifyListeners(); return; } final fp = meta['filePath'] as String?; final ap = meta['artPath'] as String?; final tn = (meta['track'] as Track?)?.trackName ?? '?'; try { if (_isPlaying && _isOfflineTrack && _currentTrack?.id == trackId) await stopTrack(); if (fp != null) { final f = File(fp); if (await f.exists()) await f.delete(); } if (ap != null) { final af = File(ap); if (await af.exists()) await af.delete(); } _downloadedTracksMetadata.remove(trackId); await saveDownloadedTracksMetadata(); _invalidateDownloadedTracksCache(); _errorMessage = "Removed $tn."; } catch (_) { _errorMessage = 'Failed to delete $tn.'; } finally { notifyListeners(); } }
  Future<bool> isTrackDownloaded(String trackId) async { final meta = _downloadedTracksMetadata[trackId]; if (meta != null) { final p = meta['filePath'] as String?; if (p != null && p.isNotEmpty) { if (await File(p).exists()) {
    // Also check file size to ensure it's not a corrupt/empty file
    if (await File(p).length() > 50 * 1024) { // 50KB min
      return true;
    } else {
      if (kDebugMode) debugPrint("MusicProvider: Found downloaded file for $trackId but it's too small. Treating as missing.");
      await _handleMissingOfflineFile(trackId, p);
      return false;
    }
  } else { await _handleMissingOfflineFile(trackId, p); return false; } } } return false; }
  Future<String?> getDownloadedTrackPath(String trackId) async { if (await isTrackDownloaded(trackId)) return _downloadedTracksMetadata[trackId]?['filePath'] as String?; return null; }
  Future<List<Track>> getDownloadedTracks() async {
    // Cached: FutureBuilders call this on every tab re-entry; each uncached
    // call costs one disk stat per downloaded track.
    final cached = _downloadedTracksCache;
    if (cached != null) return cached;
    List<String> r = []; for (var e in _downloadedTracksMetadata.entries) { final p = e.value['filePath'] as String?; if (p == null || !(await File(p).exists())) r.add(e.key); } if (r.isNotEmpty) { for (var id in r) {
    _downloadedTracksMetadata.remove(id);
  } await _saveDownloadedTracksMetadataInternal(); _invalidateDownloadedTracksCache(); notifyListeners(); }
    final result = _downloadedTracksMetadata.values.where((m) => m['track'] is Track).map((m) => m['track'] as Track).toList();
    _downloadedTracksCache = result;
    return result; }
  List<Track>? _downloadedTracksCache;
  void _invalidateDownloadedTracksCache() => _downloadedTracksCache = null;
  Future<void> _loadDownloadedTracksMetadata() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('downloadedTracks');
      if (s != null) {
        final l = await compute(_jsonDecode, s);
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
                  if (kDebugMode) debugPrint("MusicProvider: Corrected path for $id: $storedPath -> $currentPath");
                  finalPath = currentPath;
               }
            }
            
            _downloadedTracksMetadata[id] = {
              'track': Track.fromJson(i['track']),
              'filePath': finalPath,
              'artPath': i['artPath'] as String?,
              'downloadDate': i['downloadDate'] != null ? DateTime.fromMillisecondsSinceEpoch(i['downloadDate']) : null
            };
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("MusicProvider: Error loading download metadata: $e");
      _downloadedTracksMetadata = {};
    }
  }
  Future<void> saveDownloadedTracksMetadata() async => await _saveDownloadedTracksMetadataInternal();
  Future<void> _saveDownloadedTracksMetadataInternal() async { final l = _downloadedTracksMetadata.values.map((m) => {'id': (m['track'] as Track).id, 'filePath': m['filePath'], 'artPath': m['artPath'], 'downloadDate': (m['downloadDate'] as DateTime?)?.millisecondsSinceEpoch, 'track': (m['track'] as Track).toJson()}).toList(); try { final p = await SharedPreferences.getInstance(); await p.setString('downloadedTracks', await compute(_jsonEncode, l)); } catch (e) { _addToRetryQueue(_RetryOperation('Save dl meta', _saveDownloadedTracksMetadataInternal)); } }
  Future<void> _handleMissingOfflineFile(String trackId, String expectedPath) async { bool mRem = _downloadedTracksMetadata.remove(trackId) != null; if (mRem) await _saveDownloadedTracksMetadataInternal(); _invalidateDownloadedTracksCache(); int cB = _localTracks.length; _localTracks.removeWhere((t) => t.previewUrl == expectedPath); bool lRem = _localTracks.length < cB; if (mRem || lRem) notifyListeners(); }
  void _addToDownloadQueue(Track track) { if (_isDownloading[track.id]==true || _downloadQueue.any((t)=>t.id==track.id) || _downloadedTracksMetadata.containsKey(track.id)) return; _downloadQueue.add(track); _errorMessage = '${track.trackName} queued.'; notifyListeners(); _processDownloadQueue(); }
  Future<void> _processDownloadQueue() async { if (_downloadQueue.isEmpty || _isOfflineMode || !_networkService.isConnected || _concurrentDownloads >= 6) return; final t = _downloadQueue.removeAt(0); notifyListeners(); await downloadTrack(t); }
  void pauseAllDownloads({bool clearQueue = false}) { final ids = List<String>.from(_downloadCancelTokens.keys); int c = 0; for (final id in ids) { _downloadCancelTokens[id]?.cancel("Downloads paused"); c++; } if (c > 0) debugPrint("Paused $c downloads."); if (clearQueue && _downloadQueue.isNotEmpty) { _downloadQueue.clear(); notifyListeners(); } }
  
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

  // --- API Content Fetching ---
  
  // Recently shown track IDs for diversity (persisted)
  final List<String> _recentlyShownTrackIds = [];
  static const int _maxRecentlyShown = 200;
  
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
      // ENHANCED: Fetch personalized content based on recently played seeds
      final personalized = await _fetchPersonalizedForYou();
      
      // PHASE 2 FIX: Filter and apply diversity + AI ranking
      final processed = _processForYouTracks(personalized, 20);
      
      _tracks = processed;
      _recommendedTracks = processed; 
      _cachedTracks[k] = _tracks; _capCache(_cachedTracks, 60); 
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
  
  /// Fetch personalized For You content using recently played as seeds
  Future<List<Track>> _fetchPersonalizedForYou() async {
    final allTracks = <Track>[];
    final seenIds = <String>{};
    
    // Get recently played tracks as seeds (up to 5)
    final seeds = _recentlyPlayed.take(5).where((t) => 
      t.source == 'youtube' && t.id.length == 11
    ).toList();
    
    if (seeds.isNotEmpty) {
      // Fetch related tracks from multiple seeds for variety
      for (final seed in seeds.take(3)) {
        try {
          final related = await _innerTubeService.getSuggestions(seed.id, limit: 15);
          for (final track in related) {
            if (!seenIds.contains(track.id)) {
              seenIds.add(track.id);
              allTracks.add(track);
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('MusicProvider: Error fetching related for ${seed.trackName}: $e');
        }
      }
      
      // Also fetch from liked songs if available
      final likedSeeds = _likedSongs.take(2).where((t) => 
        t.source == 'youtube' && t.id.length == 11 && !seenIds.contains(t.id)
      );
      
      for (final seed in likedSeeds) {
        try {
          final related = await _innerTubeService.getSuggestions(seed.id, limit: 10);
          for (final track in related) {
            if (!seenIds.contains(track.id)) {
              seenIds.add(track.id);
              allTracks.add(track);
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('MusicProvider: Error fetching related for liked ${seed.trackName}: $e');
        }
      }
    }
    
    // Always include some home tracks for discovery of new artists
    try {
      final homeTracks = await _innerTubeService.getHomeTracks(limit: 20);
      for (final track in homeTracks) {
        if (!seenIds.contains(track.id)) {
          seenIds.add(track.id);
          allTracks.add(track);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: Error fetching home tracks: $e');
    }
    
    // If no seeds available, just use home tracks
    if (allTracks.isEmpty) {
      return await _innerTubeService.getHomeTracks(limit: 50);
    }
    
    return allTracks;
  }
  
  /// Process For You tracks: filter, diversify, and rank with AI
  List<Track> _processForYouTracks(List<Track> raw, int limit) {
    // 0. DEDUPLICATE: Remove duplicate track IDs (keep first occurrence)
    final seenIds = <String>{};
    final deduped = <Track>[];
    for (final track in raw) {
      if (!seenIds.contains(track.id)) {
        seenIds.add(track.id);
        deduped.add(track);
      }
    }
    
    // 1. FILTER: Only tracks (not albums/playlists)
    // Valid YouTube video IDs are 11 characters and don't start with PL/VL/UC
    final tracks = deduped.where((t) {
      final id = t.id;
      if (id.length != 11) return false;
      if (id.startsWith('PL') || id.startsWith('VL') || id.startsWith('UC')) return false;
      if (t.trackName.isEmpty || t.artistName.isEmpty) return false;
      return true;
    }).toList();
    
    if (tracks.isEmpty) return raw.take(limit).toList();
    
    // 2. DIVERSITY: Filter out recently shown tracks first
    final recentSet = _recentlyShownTrackIds.toSet();
    final notRecentlyShown = tracks.where((t) => !recentSet.contains(t.id)).toList();
    final recentlyShown = tracks.where((t) => recentSet.contains(t.id)).toList();
    
    // 3. AI RANKING: Apply hybrid recommendation scoring
    final rankedFresh = _recommendationService.rankTracks(notRecentlyShown, limit: limit);
    
    // 4. If we don't have enough fresh tracks, add from recently shown
    List<Track> result;
    if (rankedFresh.length >= limit) {
      result = rankedFresh.take(limit).toList();
    } else {
      final remaining = limit - rankedFresh.length;
      final rankedRecent = _recommendationService.rankTracks(recentlyShown, limit: remaining);
      result = [...rankedFresh, ...rankedRecent];
    }
    
    // 5. Record shown and ensure absolute uniqueness
    final finalResult = <Track>[];
    final finalSeen = <String>{};
    
    for (final track in result) {
      if (!finalSeen.contains(track.id)) {
        finalSeen.add(track.id);
        finalResult.add(track);
      }
    }
    
    _recordShownTracks(finalResult);
    
    return finalResult;
  }
  
  /// Record shown tracks for diversity penalty
  void _recordShownTracks(List<Track> tracks) {
    for (final track in tracks) {
      if (!_recentlyShownTrackIds.contains(track.id)) {
        _recentlyShownTrackIds.add(track.id);
      }
    }
    
    // Trim to max size (LRU-style)
    while (_recentlyShownTrackIds.length > _maxRecentlyShown) {
      _recentlyShownTrackIds.removeAt(0);
    }
    
    // Persist asynchronously
    _saveRecentlyShownIds();
  }
  
  /// Load recently shown IDs from SharedPreferences
  Future<void> _loadRecentlyShownIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList('recently_shown_track_ids') ?? [];
      _recentlyShownTrackIds.clear();
      _recentlyShownTrackIds.addAll(ids);
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: Error loading recently shown IDs: $e');
    }
  }
  
  /// Save recently shown IDs to SharedPreferences
  Future<void> _saveRecentlyShownIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('recently_shown_track_ids', _recentlyShownTrackIds);
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: Error saving recently shown IDs: $e');
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
      _cachedTracks[k] = _fullTrendingTracks; _capCache(_cachedTracks, 60); 
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
       if (kDebugMode) debugPrint('MusicProvider: Search Cache HIT for "$query"');
       _searchedTracks = _searchCache[query]!;
       notifyListeners();
       return _searchedTracks;
    }
    
    try {
      _clearError(); // Clear previous errors before a new search
      
      if (kDebugMode) {
        debugPrint('MusicProvider: Searching for "$query" using ${_currentMusicSource.displayName}');
      }
      
      // Use InnerTube service for YouTube Music search or local search
      
      // Always search local tracks first
      final searchLower = query.toLowerCase();
      List<Track> localResults = _localTracks.where((track) {
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
           if (kDebugMode) debugPrint("Online search failed: $e");
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
        debugPrint('MusicProvider: Found ${_searchedTracks.length} results (Local: ${localResults.length}, Online: ${onlineResults.length}) for "$query"');
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
       debugPrint("Playlist Search Error: $e");
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
        debugPrint('MusicProvider: Fetching artist tracks for "$artistName" using ${_currentMusicSource.displayName}');
      }
      
      // Use appropriate service based on current music source
      if (_currentMusicSource == MusicSource.local) {
        // Search local tracks by artist
        _artistTracks = _localTracks.where((track) => 
          track.artistName.toLowerCase().contains(artistName.toLowerCase())
        ).toList();
      } else {
        // SearchScreen tab 2 iterates unique artists over these hits,
        // so searchArtists (artist results as Track objects) is correct here.
        _artistTracks = await _innerTubeService.searchArtists(artistName, limit: 30);
      }
      
      _cachedTracks[k] = _artistTracks; _capCache(_cachedTracks, 60); 
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
        debugPrint('MusicProvider: Fetching genre tracks for "$genre" using ${_currentMusicSource.displayName}');
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
      
      _cachedTracks[k] = _genreTracks; _capCache(_cachedTracks, 60); 
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
  Future<void> clearAllCaches() async { try { _cachedTracks.clear(); _tracks = []; _trendingTracks = []; _fullTrendingTracks = []; _artistTracks = []; _genreTracks = []; _retryQueue.clear(); _lyricsService.clearCache(); _errorMessage = 'Caches cleared.'; notifyListeners(); if (_networkService.isConnected && !_isOfflineMode) { await fetchTracks(); await fetchTrendingTracks(); } } catch (_) { _errorMessage = 'Failed cache clear.'; notifyListeners(); } }

  // --- Sleep Timer ---
  Timer? _sleepTimer;

  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        stopTrack();
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
  /// Feed the dominant palette color to the app accent when album-adaptive
  /// mode is on. No-op otherwise (zero cost when the feature is off).
  void _feedAlbumAccent(PaletteGenerator palette) {
    final controller = _accentController;
    if (controller == null || !controller.isAlbumAdaptive) return;
    Color? color = palette.dominantColor?.color;
    color ??= palette.vibrantColor?.color;
    if (color == null && palette.colors.isNotEmpty) {
      color = palette.colors.first;
    }
    controller.setAlbumAccent(color);
  }

  Future<void> updatePalette() async {
    final track = _currentTrack;
    if (track == null) {
      _paletteGenerator = null;
      notifyListeners();
      return;
    }
    
    // Explicit check for artwork
    if (track.albumArtUrl.isEmpty) {
       _paletteGenerator = null;
       _accentController?.setAlbumAccent(null);
       notifyListeners();
       return;
    }

    // BATTERY FIX: Skip expensive palette generation if app is in background
    if (isInBackground) {
      if (kDebugMode) debugPrint('MusicProvider: Skipping palette generation (background)');
      return; 
    }

    final trackId = track.id;
    
    // 1. Check Cache first for instant update
    if (_paletteCache.containsKey(trackId)) {
        if (kDebugMode) debugPrint('MusicProvider: Using cached palette for ${track.trackName}');
        _paletteGenerator = _paletteCache[trackId];
        _feedAlbumAccent(_paletteCache[trackId]!);
        // Note: We don't notifyListeners() here IF it's already set
        // but since we reset it to null on track change, we should notify.
        notifyListeners();
        return;
    }
    
    try {
      if (kDebugMode) debugPrint('MusicProvider: Generating palette for ${track.trackName}...');
      
      ImageProvider? imageProvider;
      bool isLocalFile = false;
      
      // Determine ImageProvider with high priority for offline/local sources
      final offlineMeta = _downloadedTracksMetadata[trackId];
      final artPath = offlineMeta?['artPath'] as String?;

      if (artPath != null && artPath.isNotEmpty && File(artPath).existsSync()) {
          // 1. Downloaded YouTube Track Artwork
          isLocalFile = true;
          imageProvider = FileImage(File(artPath));
          if (kDebugMode) debugPrint('MusicProvider: Using offline art for ${track.trackName}');
      } else if (_downloadedTracksMetadata.containsKey(trackId)) {
          // LEGACY FALLBACK: Check if art file exists even if not in metadata
          final fallbackPath = await _buildArtDownloadPath(trackId);
          if (File(fallbackPath).existsSync()) {
             isLocalFile = true;
             imageProvider = FileImage(File(fallbackPath));
             // Update metadata for next time (entry may have been removed
             // mid-flight — never force-unwrap)
             _downloadedTracksMetadata[trackId]?['artPath'] = fallbackPath;
             saveDownloadedTracksMetadata();
             if (kDebugMode) debugPrint('MusicProvider: Recovered legacy art for ${track.trackName}');
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
      final palette = gen;
      
      // Strict check: Ensure we are still playing the same track to avoid race conditions
      if (_currentTrack?.id == trackId) {
        _paletteGenerator = palette;
        _feedAlbumAccent(palette);
        
        // Update cache (LRU management: remove oldest if full)
        if (_paletteCache.length > 15) {
            _paletteCache.remove(_paletteCache.keys.first);
        }
        _paletteCache[trackId] = palette;
        
        notifyListeners();
        if (kDebugMode) debugPrint('MusicProvider: Palette updated for ${track.trackName} (${isLocalFile ? "Local" : "Network"})');

        // PROACTIVE FIX: If played online but missing local art, download it now
        if (!isLocalFile && _downloadedTracksMetadata.containsKey(trackId)) {
           final aP = await _buildArtDownloadPath(trackId);
           if (track.albumArtUrl.isNotEmpty) {
             _networkService.downloadFile(track.albumArtUrl, aP).then((_) {
                final meta = _downloadedTracksMetadata[trackId];
                if (meta == null) return; // entry removed while downloading
                meta['artPath'] = aP;
                saveDownloadedTracksMetadata();
                if (kDebugMode) debugPrint('MusicProvider: Proactively saved artwork for $trackId');
             }).catchError((_) {});
           }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('MusicProvider: Error generating palette for ${track.trackName}: $e');
    }
  }

  // --- Dispose ---
  @override
  void dispose() {
    debugPrint('MusicProvider: Disposing...');
    WidgetsBinding.instance.removeObserver(this); // Stop lifecycle updates
    
    // FIX: Cancel all audio subscriptions to prevent memory leaks
    for (final sub in _audioSubscriptions) {
      sub.cancel();
    }
    _audioSubscriptions.clear();
    _notifyDebouncer?.cancel();
    
    _audioService.dispose();
    _innerTubeService.dispose();
    _lyricsService.dispose();
    unawaited(_recommendationService.close());
    stopCastingDiscovery();
    _retryTimer?.cancel();
    _networkQualitySubscription?.cancel();
    _connectivityStatusSubscription?.cancel();
    _sleepTimer?.cancel();
    _downloadCancelTokens.forEach((_, token) { if (!token.isCancelled) token.cancel("Provider disposed"); });
    _downloadCancelTokens.clear();
    debugPrint('MusicProvider: Disposed.');
    super.dispose();
  }


  // --- Preloading Logic ---
  Future<void> _prefetchNextTrack() async {
    Track? nextTrack;

    // Determine Next Track based on Shuffle/Repeat/Queue
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

    if (kDebugMode) debugPrint('MusicProvider: Prefetching next track: ${nextTrack.trackName}');

    if (!_isOfflineMode && !_isOfflineTrack && nextTrack.source != 'spotify') {
        // Audio prefetch — warms the StreamResolutionService cache so the
        // next track starts without a network round-trip.
        _streamResolution.resolve(ResolveRequest(
          videoId: nextTrack.id,
          title: nextTrack.trackName,
          artist: nextTrack.artistName,
          durationMs: nextTrack.durationMs,
        )        ).then((resolved) {
           if (kDebugMode && resolved != null) {
             debugPrint('MusicProvider: Stream URL prefetched for ${nextTrack!.trackName}');
           }
        }).catchError((e) {
           if (kDebugMode) debugPrint('MusicProvider: Stream prefetch failed: $e');
        });
        
        // Lyrics Prefetch
        _lyricsService.getParsedLyrics(
          title: nextTrack.trackName,
          artist: nextTrack.artistName,
          durationMs: nextTrack.durationMs,
          videoId: nextTrack.id
        ).then((_) {
           if (kDebugMode) debugPrint('MusicProvider: Lyrics prefetch complete for ${nextTrack!.trackName}');
        }).catchError((e) {
           if (kDebugMode) debugPrint('MusicProvider: Lyrics prefetch failed: $e');
        });
    }
  }


  // --- Smart Artist Recommendations ---
  Future<List<dynamic>> getSmartLibraryArtists() async {
    final Set<String> uniqueArtistNames = {};
    final List<dynamic> smartArtists = [];

    // 1. Get AI Recommended Artists
    // Find metadata for these names from recent history/cache if possible
    
    // 2. Get Artists from Liked Songs (High priority)
    for (final track in _likedSongs) {
      if (!uniqueArtistNames.contains(track.artistName)) {
        uniqueArtistNames.add(track.artistName);
        smartArtists.add(track); // Using Track as artist placeholder
      }
    }

    // 3. Get Artists from Recently Played
    for (final track in _recentlyPlayed) {
      if (!uniqueArtistNames.contains(track.artistName)) {
        uniqueArtistNames.add(track.artistName);
        smartArtists.add(track);
      }
    }

    // Sort by name or relevance? For now, leave mixed (Recommendation priority order)
    return smartArtists;
  }
} // End of MusicProvider class

// Helper class for retry operations (Keep as is)
class _RetryOperation {
  final String description;
  final Future<dynamic> Function() execute;
  int attempts = 1;
  _RetryOperation(this.description, this.execute);
}

