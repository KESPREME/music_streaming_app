// lib/services/audio_service.dart
import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
// import 'package:path_provider/path_provider.dart'; // Unused import
import 'package:flutter/foundation.dart';
import '../services/network_service.dart';
import '../utils/network_config.dart';
import 'dart:math';


class AudioService {
  // Initialize player with aggressive buffer settings directly
  final AudioPlayer _audioPlayer = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
       androidLoadControl: AndroidLoadControl(
         minBufferDuration: Duration(milliseconds: 1000), // 1s (was 2s)
         maxBufferDuration: Duration(milliseconds: 15000), // 15s
         bufferForPlaybackDuration: Duration(milliseconds: 200), // 0.2s (was 0.5s)
         bufferForPlaybackAfterRebufferDuration: Duration(milliseconds: 800),
         prioritizeTimeOverSizeThresholds: true,
         backBufferDuration: Duration(seconds: 30),
       ),
       darwinLoadControl: DarwinLoadControl(
         preferredForwardBufferDuration: Duration(seconds: 15),
         automaticallyWaitsToMinimizeStalling: false,
       ),
    ),
  );
  
  final NetworkService _networkService = NetworkService();
  bool _isInitialized = false;
  String? _currentUrl;
  String? _currentFilePath;
  bool _isLocalFile = false;
  bool _hasPrevious = false; // State to persist window
  bool _hasNext = false;     // State to persist window
  
  // Subscription management for proper cleanup
  final List<StreamSubscription> _subscriptions = [];

  // Streams
  Stream<Duration> get onPositionChanged => _audioPlayer.positionStream.map((position) => position);
  Stream<Duration> get onDurationChanged => _audioPlayer.durationStream.map((duration) => duration ?? Duration.zero);
  Stream<bool> get onPlaybackStateChanged => _audioPlayer.playingStream;
  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream; 
  Stream<bool> get onPlaybackComplete => _audioPlayer.processingStateStream
      .map((state) => state == ProcessingState.completed);

  // Navigation Streams
  final _onSkipToNextController = StreamController<void>.broadcast();
  Stream<void> get onSkipToNext => _onSkipToNextController.stream;

  final _onSkipToPreviousController = StreamController<void>.broadcast();
  Stream<void> get onSkipToPrevious => _onSkipToPreviousController.stream;

  // Error Stream
  final _onPlaybackErrorController = StreamController<String>.broadcast();
  Stream<String> get onPlaybackError => _onPlaybackErrorController.stream;

  AudioService() {
    _initAudioSession();
    _monitorIndexChanges();
  }

  // Monitor index changes to trigger external navigation
  void _monitorIndexChanges() {
    _startNavigationMonitor();
  }

  Future<void> _initAudioSession() async {
    if (_isInitialized) return;

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
          flags: AndroidAudioFlags.none,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false, // Fix: Don't stop music on notifications
      ));

      // Set up error handling
      _audioPlayer.playbackEventStream.listen(
            (event) {},
        onError: (Object e, StackTrace st) {
          print('Audio player error: $e');
          _handlePlaybackError(e);
        },
      );

      _isInitialized = true;
    } catch (e) {
      print('Error initializing audio session: $e');
    }
  }

  Future<void> play(String? url, {
    bool isLocal = false, 
    AudioSource? customSource,
    String? title,
    String? artist,
    String? artUri,
    String? id,
    bool hasPrevious = false,
    bool hasNext = false,
  }) async {
    try {
      if (kDebugMode) {
        print('AudioService: play() called. Prev: $hasPrevious, Next: $hasNext');
      }
      
      // Validate inputs
      if (url == null && customSource == null) {
        throw Exception('Cannot play: Both URL and source are null');
      }
      
      await _initAudioSession();
      
      // Stop current playback
      if (_audioPlayer.playing) {
        await _audioPlayer.stop();
      }

      _currentUrl = url;
      _isLocalFile = isLocal; // FIX: Correctly track if current playback is local
      _hasPrevious = hasPrevious;
      _hasNext = hasNext;

      // Initialize Main AudioSource
      AudioSource mainSource;
      
      if (customSource != null) {
         mainSource = customSource;
      } else {
         // ... (Logic to create mainSource from URL)
         // Check preloaded source
        if (url == _preloadedUrl && _preloadedSource != null) {
            mainSource = _preloadedSource!;
            _preloadedSource = null;
            _preloadedUrl = null;
        } else {
             // Standard URL source creation
             Uri uri;
            try {
              if (isLocal && url != null) {
                 uri = Uri.file(url);
              } else if (url != null) {
                 uri = Uri.parse(url);
              } else {
                 throw Exception('URL required if customSource is null');
              }
            } catch (e) {
               throw Exception('Invalid URL: $e');
            }
            
            final headers = <String, String>{ 'Accept-Encoding': 'gzip' };
            if (url!.contains('c=ANDROID')) {
               headers['User-Agent'] = 'com.google.android.youtube/17.31.35 (Linux; U; Android 11) gzip';
            } else if (url.contains('c=IOS')) {
               headers['User-Agent'] = 'com.google.ios.youtube/19.29.1 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X)';
            }
            
            MediaItem? tag;
            if (title != null) {
              tag = MediaItem(
                id: id ?? url ?? 'unknown',
                title: title ?? 'Unknown Track',
                artist: artist ?? 'Unknown Artist',
                artUri: artUri != null ? Uri.parse(artUri) : null,
              );
            }

            if (isLocal) {
               // FIX: Use AudioSource.file for local files as recommended by just_audio
               mainSource = AudioSource.file(url!, tag: tag);
            } else {
               mainSource = AudioSource.uri(uri, headers: headers.isNotEmpty ? headers : null, tag: tag);
            }
        }
      }

      // Construct Windowed Playlist
      final List<AudioSource> playlistChildren = [];
      
      // ALWAYS add Previous Dummy (Button always visible)
      playlistChildren.add(_createDummySource(id: "prev_dummy", title: "Previous Track"));
      
      // Current
      playlistChildren.add(mainSource);
      
      // ALWAYS add Next Dummy (Button always visible)
      playlistChildren.add(_createDummySource(id: "next_dummy", title: "Next Track"));

      // Note: We used to conditionally add these based on hasPrevious/hasNext,
      // but user requested they always be present (and potentially disabled or just no-op).
      // just_audio_background doesn't support "disabled" state easily without custom actions,
      // so we let them be clickable and handle the event to do nothing or stop if invalid.

      AudioSource finalSource = ConcatenatingAudioSource(children: playlistChildren);
      int initialIndex = 1; // Current track is always at index 1 now

      if (kDebugMode) print('AudioService: Setting source with window size ${playlistChildren.length}, index $initialIndex');
      
      // FIX: Prevent navigation monitor from triggering during setup
      _isConfiguring = true;
      try {
        await _audioPlayer.setAudioSource(finalSource, initialIndex: initialIndex);
        await _audioPlayer.play();
      } finally {
        // Ensure flag is reset even if play fails
        Future.delayed(const Duration(milliseconds: 500), () {
           _isConfiguring = false;
        });
      }
      
      // Listen for index changes SPECIFIC to this playback session logic
      // We don't want old listeners interfering, but _monitorIndexChanges is global.
      // Ideally, the global listener handles any "current" playing sequence.
      
    } on PlayerException catch (e) {
      if (kDebugMode) print('AudioService: PlayerException: ${e.message}');
      throw Exception('Audio player error: ${e.message}');
    } catch (e) {
      if (kDebugMode) print('AudioService: Error playing: $e');
      throw Exception('Failed to play audio: $e');
    }
  }

  AudioSource _createDummySource({required String id, required String title}) {
    // We use a silent audio source or just a placeholder. 
    // Ideally, a small silent file. Since we don't have one handy safely, 
    // we use a failing URI but with a tag? No, that causes error.
    // We can use the SAME URI as the current track (if URL available) or a known dummy.
    // Better: Use a silent DurationSource if just_audio supported it, but it doesn't support streams in bg easily.
    // Best Trick: Use the current URL/Source but with a "SKIP" tag.
    // When the player tries to load it, we catch it? 
    // Actually, just_audio allows AudioSource.uri(Uri.parse("asset:///...")) etc.
    // If we use a non-playable URI, the player stops with error.
    // But we want to CATCH the transition before it errors or while it tries to load.
    
    // Using a valid but empty MP3 data URI is safe for "Silence" and won't crash.
    // Tiny silent MP3 data URI
    final silentUri = Uri.parse("data:audio/mp3;base64,SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU4LjI5LjEwMAAAAAAAAAAAAAAA//OEAAAAAAAAAAAAAAAAAAAAAAAASW5mbwAAAA8AAAAEAAABIADAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMD//////////////////////////////////////////////////////////////////wAAABFMYXZjNTguNTQuMTAwAAAAAAAAAAAA//OEAAAAAAAAAAAAAAAAAAAAAAA=");
    
    return AudioSource.uri(
      silentUri,
      tag: MediaItem(
        id: id,
        title: title, 
        artist: "",
        artUri: null, // No art
      ),
    );
  }

  Future<void> playLocalFile(String filePath, {
    String? title,
    String? artist,
    String? artUri,
    String? id,
    bool hasPrevious = false,
    bool hasNext = false,
  }) async {
    await play(filePath, isLocal: true, title: title, artist: artist, artUri: artUri, id: id, hasPrevious: hasPrevious, hasNext: hasNext);
  }

  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
    } catch (e) {
      print('Error pausing audio: $e');
      throw Exception('Failed to pause audio: $e');
    }
  }

  Future<void> resume() async {
      // If the player has completed, it means the stream was likely closed.
      if (_audioPlayer.processingState == ProcessingState.completed) {
         // If we are resumed from "Completed" state, we might need to check if we are on a Dummy.
         // But play() normally handles new tracks.
         // If we just resume same track:
        if (kDebugMode) print("AudioService: Stream completed, seeking to current position to resume.");
        await _audioPlayer.seek(_audioPlayer.position);
      }
      await _audioPlayer.play();
  }

  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _currentUrl = null;
      _currentFilePath = null;
      _isLocalFile = false;
      _preloadedUrl = null;
      _preloadedSource = null;
    } catch (e) {
      print('Error stopping audio: $e');
      throw Exception('Failed to stop audio: $e');
    }
  }

  Future<void> seekTo(Duration position) async {
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      print('Error seeking audio: $e');
      throw Exception('Failed to seek audio: $e');
    }
  }

  Future<void> setVolume(double volume) async {
    await _audioPlayer.setVolume(volume);
  }

  Future<void> setSpeed(double speed) async {
    await _audioPlayer.setSpeed(speed);
  }

  // Handle playback errors
  void _handlePlaybackError(dynamic error) {
    if (!_isLocalFile && _currentUrl != null &&
        (error.toString().contains('network') ||
            error.toString().contains('connection') ||
            error.toString().contains('socket'))) {
      _retryPlayback();
    }
  }

  // Retry playback with exponential backoff
  Future<void> _retryPlayback() async {
    if (_currentUrl == null || _isLocalFile) return;

    for (int attempt = 0; attempt < NetworkConfig.maxRetries; attempt++) {
      try {
        final backoffSeconds = pow(2, attempt) + (Random().nextInt(1000) / 1000.0);
        await Future.delayed(Duration(milliseconds: (backoffSeconds * 1000).round()));

        if (!_networkService.isConnected) continue;

        final position = _audioPlayer.position;

        final headers = <String, String>{
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          'Accept-Encoding': 'gzip, deflate',
          'Connection': 'keep-alive',
          'DNT': '1',
        };
        
        if (_currentUrl!.contains('googlevideo.com') || _currentUrl!.contains('youtube.com')) {
          headers['Referer'] = 'https://www.youtube.com/';
          headers['Origin'] = 'https://www.youtube.com';
        }
        
        // Note: Retrying simple single source for now to keep it robust
        // But we should try to restore the window if possible
        AudioSource mainSource = AudioSource.uri(Uri.parse(_currentUrl!), headers: headers);
        
        // Reconstruct Windowed Playlist logic - Restore ALWAYS structure
        final List<AudioSource> playlistChildren = [];
        playlistChildren.add(_createDummySource(id: "prev_dummy", title: "Previous Track"));
        playlistChildren.add(mainSource);
        playlistChildren.add(_createDummySource(id: "next_dummy", title: "Next Track"));
        
        AudioSource finalSource = ConcatenatingAudioSource(children: playlistChildren);
        int initialIndex = 1;

        // FIX: Prevent navigation monitor from triggering during setup
        _isConfiguring = true;
        try {
          await _audioPlayer.setAudioSource(finalSource, initialIndex: initialIndex);

          if (position > Duration.zero) {
            await _audioPlayer.seek(position);
          }

          await _audioPlayer.play();
          return; 
        } finally {
           Future.delayed(const Duration(milliseconds: 500), () {
             _isConfiguring = false;
           });
        } 
      } catch (e) {
        print('Retry attempt $attempt failed: $e');
      }
    }

    print('All retry attempts failed');
  }

  bool get _isPlaying => _audioPlayer.playing;

  // --- Preloading ---
  LockCachingAudioSource? _preloadedSource;
  String? _preloadedUrl;

  Future<void> preloadTrack(String url) async {
    if (url == _preloadedUrl && _preloadedSource != null) return;
    if (kDebugMode) print("AudioService: Preloading track $url");
    _preloadedUrl = url;
    try {
      final headers = <String, String>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
        'DNT': '1',
      };
      
      if (url.contains('googlevideo.com') || url.contains('youtube.com')) {
        headers['Referer'] = 'https://www.youtube.com/';
        headers['Origin'] = 'https://www.youtube.com';
      }
      _preloadedSource = LockCachingAudioSource(Uri.parse(url), headers: headers);
      if (kDebugMode) print("AudioService: Set up LockCachingAudioSource for $url");

    } catch (e) {
      if (kDebugMode) print("AudioService: Error preloading track $url: $e");
      _preloadedUrl = null;
      _preloadedSource = null;
    }
  }
  
  // Internal monitor for navigation
  DateTime _lastNavigationEvent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isConfiguring = false; // Flag to prevent self-triggering during setup

  void _startNavigationMonitor() {
      // FIX: Store subscription for proper cleanup
      _subscriptions.add(_audioPlayer.currentIndexStream.listen((index) {
          if (index == null || _isConfiguring) return; // Ignore during configuration
          
          // DO NOT trigger navigation if player is in a transition/error state
          final pState = _audioPlayer.playerState.processingState;
          if (pState == ProcessingState.idle || pState == ProcessingState.loading) return;
          
          final source = _audioPlayer.audioSource as ConcatenatingAudioSource;
          // Strategy: identify if we are on a "dummy"
          if (index >= 0 && index < source.children.length) {
             final child = source.children[index];
             if (child is UriAudioSource) {
                // Rate limit navigation events (debounce 500ms)
                if (DateTime.now().difference(_lastNavigationEvent).inMilliseconds < 500) {
                   return;
                }
                
                final sequence = _audioPlayer.sequence;
                if (sequence != null && index < sequence.length) {
                   final tag = sequence[index].tag;
                   if (tag is MediaItem) {
                      if (tag.id == "prev_dummy") {
                          _lastNavigationEvent = DateTime.now();
                          _onSkipToPreviousController.add(null);
                      } else if (tag.id == "next_dummy") {
                          _lastNavigationEvent = DateTime.now();
                          _onSkipToNextController.add(null);
                      }
                   }
                }
             }
          }
      }));
    
    // --- Error Handling Monitor ---
    // FIX: Store subscriptions for proper cleanup
    _subscriptions.add(_audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.idle) {
             // Idle usually happens after stop or reset, but check for error
        }
    }));
    
    // Listen for Player Exceptions explicitly
    _subscriptions.add(_audioPlayer.playbackEventStream.listen((event) {}, 
        onError: (Object e, StackTrace stackTrace) {
            print('AudioService: Playback Event Exception: $e');
            // Check for specific error substrings if possible
            if (e.toString().contains("Source error") || e.toString().contains("UnrecognizedInputFormatException")) {
                 print("AudioService: CRITICAL - Corrupt Source Detected.");
                 _onPlaybackErrorController.add("Source error");
            }
    }));
  }

  void dispose() {
    // FIX: Cancel all subscriptions before disposing
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    
    _audioPlayer.dispose();
    _onSkipToNextController.close();
    _onSkipToPreviousController.close();
    _onPlaybackErrorController.close();
  }
}
