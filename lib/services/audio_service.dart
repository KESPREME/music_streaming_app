// lib/services/audio_service.dart
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
         minBufferDuration: Duration(milliseconds: 2000), // 2s (was 15s)
         maxBufferDuration: Duration(milliseconds: 15000), // 15s (was 60s)
         bufferForPlaybackDuration: Duration(milliseconds: 500), // 0.5s (was 2.5s)
         bufferForPlaybackAfterRebufferDuration: Duration(milliseconds: 1000),
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

  // Streams
  Stream<Duration> get onPositionChanged => _audioPlayer.positionStream.map((position) => position); // removed null check as it's non-nullable usually or handled
  Stream<Duration> get onDurationChanged => _audioPlayer.durationStream.map((duration) => duration ?? Duration.zero);
  Stream<bool> get onPlaybackStateChanged => _audioPlayer.playingStream;
  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream; 
  Stream<bool> get onPlaybackComplete => _audioPlayer.processingStateStream
      .map((state) => state == ProcessingState.completed);

  AudioService() {
    _initAudioSession();
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
        androidWillPauseWhenDucked: true,
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
  }) async {
    try {
      if (kDebugMode) {
        print('AudioService: play() called with URL: $url, customSource: ${customSource != null}');
      }
      
      // Validate inputs
      if (url == null && customSource == null) {
        throw Exception('Cannot play: Both URL and source are null');
      }
      
      await _initAudioSession();
      
      // Stop current playback
      if (_audioPlayer.playing) {
        if (kDebugMode) print('AudioService: Stopping current playback');
        await _audioPlayer.stop();
      }

      _currentUrl = url;
      _isLocalFile = false;

      // Initialize AudioSource
      AudioSource audioSource; // Fix: Declare variable here
      
      if (customSource != null) {
         if (kDebugMode) print('AudioService: Using custom AudioSource (Stream Proxy)');
         audioSource = customSource;
      } else {
        // ... (Source from URL logic) ...
        // Only run this if we rely on the URL
        
        // Check preloaded source
        if (url == _preloadedUrl && _preloadedSource != null) {
            audioSource = _preloadedSource!;
            _preloadedSource = null;
            _preloadedUrl = null;
        } else {
            // New URL based source
             _preloadedSource = null;
             _preloadedUrl = null;
             
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
            
            final headers = <String, String>{
              'Accept-Encoding': 'gzip',
            };
            
            if (url.contains('c=ANDROID')) {
               headers['User-Agent'] = 'com.google.android.youtube/17.31.35 (Linux; U; Android 11) gzip';
            } else if (url.contains('c=IOS')) {
               headers['User-Agent'] = 'com.google.ios.youtube/19.29.1 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X)';
            }
            
            
            // Create MediaItem tag for Lock Screen / Notification
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
               audioSource = AudioSource.uri(uri, tag: tag);
            } else {
               audioSource = AudioSource.uri(uri, headers: headers.isNotEmpty ? headers : null, tag: tag);
            }
        }
      }

      if (kDebugMode) print('AudioService: Setting audio source...');
      
      // Set the audio source
      await _audioPlayer.setAudioSource(audioSource);
      
      if (kDebugMode) print('AudioService: Starting playback...');
      
      // Start playback
      await _audioPlayer.play();
      
      if (kDebugMode) print('AudioService: Playback started successfully');
      
    } on PlayerException catch (e) {
      if (kDebugMode) {
        print('AudioService: PlayerException during play');
        print('Error code: ${e.code}');
        print('Error message: ${e.message}');
      }
      throw Exception('Audio player error: ${e.message}');
    } catch (e, s) {
      if (kDebugMode) {
        print('AudioService: Error playing audio');
        print('Error: $e');
        print('Stack: $s');
      }
      throw Exception('Failed to play audio: $e');
    }
  }

  Future<void> playLocalFile(String filePath, {
    String? title,
    String? artist,
    String? artUri,
    String? id,
  }) async {
    try {
      await _initAudioSession();
      await _audioPlayer.stop();

      // Check if file exists
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      _currentFilePath = filePath;
      _isLocalFile = true;

      // Create metadata tag
      MediaItem? tag;
      if (title != null) {
        tag = MediaItem(
          id: id ?? filePath,
          title: title,
          artist: artist,
          artUri: artUri != null ? Uri.parse(artUri) : null, 
        );
      }

      // Create audio source from local file with tag
      final audioSource = AudioSource.uri(Uri.file(filePath), tag: tag);

      // Set the audio source and play
      await _audioPlayer.setAudioSource(audioSource); // Removed initialConfiguration
      await _audioPlayer.play();
    } on PlayerException catch (e) {
      print('just_audio PlayerException during playLocalFile: ${e.message}');
      throw Exception('Failed to play local file: ${e.message}');
    } catch (e) {
      print('Error playing local file: $e');
      throw Exception('Failed to play local file: $e');
    }
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
    try {
      // If the player has completed, it means the stream was likely closed.
      // Re-seeking to the current position can often re-establish the connection for network streams.
      if (_audioPlayer.processingState == ProcessingState.completed) {
        if (kDebugMode) print("AudioService: Stream completed, seeking to current position to resume.");
        await _audioPlayer.seek(_audioPlayer.position);
      }
      await _audioPlayer.play();
    } on PlayerException catch (e) {
      print('just_audio PlayerException during resume: ${e.message}');
      throw Exception('Failed to resume audio: ${e.message}');
    } catch (e) {
      print('Error resuming audio: $e');
      throw Exception('Failed to resume audio: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      _currentUrl = null;
      _currentFilePath = null;
      _isLocalFile = false;
      _preloadedUrl = null; // Clear preloaded info on stop
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
    try {
      await _audioPlayer.setVolume(volume);
    } catch (e) {
      print('Error setting volume: $e');
      throw Exception('Failed to set volume: $e');
    }
  }

  Future<void> setSpeed(double speed) async {
    try {
      await _audioPlayer.setSpeed(speed);
    } catch (e) {
      print('Error setting speed: $e');
      throw Exception('Failed to set speed: $e');
    }
  }

  // Handle network quality changes
  // void _handleNetworkQualityChange(NetworkQuality quality) { // Commented out method
  //   // If we're playing a remote file and network quality drops
  //   if (_isPlaying && !_isLocalFile && _currentUrl != null) {
  //     if (quality == NetworkQuality.poor) {
  //       // Reduce buffer size for poor networks to prevent long buffering
  //       _audioPlayer.setAndroidAudioAttributes(
  //         const AndroidAudioAttributes(
  //           contentType: AndroidAudioContentType.music,
  //           usage: AndroidAudioUsage.media,
  //           flags: AndroidAudioFlags.audibilityEnforced,
  //           // Use low latency mode for poor networks
  //         ),
  //       );
  //     }
  //   }
  // }

  // Handle playback errors
  void _handlePlaybackError(dynamic error) {
    // If it's a network error and we have a URL, we might want to retry
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
        // Wait with exponential backoff
        final backoffSeconds = pow(2, attempt) + (Random().nextInt(1000) / 1000.0);
        await Future.delayed(Duration(milliseconds: (backoffSeconds * 1000).round()));

        // Check if we're still connected
        if (!_networkService.isConnected) continue;

        // Get current position
        final position = _audioPlayer.position;

        // Try to play again with proper headers
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
        
        final audioSource = AudioSource.uri(Uri.parse(_currentUrl!), headers: headers);
        await _audioPlayer.setAudioSource(audioSource);

        // Seek to previous position if needed
        if (position > Duration.zero) {
          await _audioPlayer.seek(position);
        }

        await _audioPlayer.play();
        return; // Success
      } catch (e) {
        print('Retry attempt $attempt failed: $e');
        // Continue to next attempt
      }
    }

    print('All retry attempts failed');
  }

  bool get _isPlaying => _audioPlayer.playing;

  // --- Preloading ---
  LockCachingAudioSource? _preloadedSource;
  String? _preloadedUrl;

  Future<void> preloadTrack(String url) async {
    if (url == _preloadedUrl && _preloadedSource != null) {
      if (kDebugMode) print("AudioService: Track $url already preloaded or being preloaded.");
      return;
    }
    if (kDebugMode) print("AudioService: Preloading track $url");
    _preloadedUrl = url;
    try {
      // Dispose previous preloaded source if any
      // await _preloadedSource?.dispose(); // LockCachingAudioSource doesn't have dispose directly, it's managed by player

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
      // Pre-buffering happens implicitly when the source is set or by calling load.
      // We don't want to play it, just have it ready.
      // `just_audio` often starts buffering when setAudioSource is called.
      // To ensure it buffers a decent amount, we can "prepare" it without playing.
      // This is a bit of a conceptual step as just_audio handles much of this.
      // We could potentially use a separate player instance for preloading if more control is needed.
      // For now, just creating LockCachingAudioSource is the main step.
      // If more aggressive pre-buffering is needed, one might call:
      // await _audioPlayer.setAudioSource(_preloadedSource!);
      // await _audioPlayer.load(); // This would start loading it into the main player
      // await _audioPlayer.stop(); // And then stop it.
      // This is complex if current track is playing.
      // A simpler approach is to let LockCachingAudioSource handle its caching.
      // The main benefit comes when this _preloadedSource is used in play() later.
      if (kDebugMode) print("AudioService: Set up LockCachingAudioSource for $url");

    } catch (e) {
      if (kDebugMode) print("AudioService: Error preloading track $url: $e");
      _preloadedUrl = null;
      _preloadedSource = null;
    }
  }



  void dispose() {
    _audioPlayer.dispose();
  }
}
