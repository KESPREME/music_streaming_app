// lib/services/audio_service.dart
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
// import 'package:path_provider/path_provider.dart'; // Unused import
import 'package:flutter/foundation.dart';
import '../services/network_service.dart';
import '../utils/network_config.dart';
import 'dart:math';


class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final NetworkService _networkService = NetworkService();
  bool _isInitialized = false;
  String? _currentUrl;
  String? _currentFilePath; // Reinstated: Used in playLocalFile
  bool _isLocalFile = false;
  // AudioLoadConfiguration? _currentLoadConfiguration; // Store current load config - REMOVED

  // Streams
  Stream<Duration> get onPositionChanged => _audioPlayer.positionStream.map((position) => position ?? Duration.zero);
  Stream<Duration> get onDurationChanged => _audioPlayer.durationStream.map((duration) => duration ?? Duration.zero);
  Stream<bool> get onPlaybackStateChanged => _audioPlayer.playingStream;
  Stream<PlayerState> get playerStateStream => _audioPlayer.playerStateStream; // Expose the full player state
  Stream<bool> get onPlaybackComplete => _audioPlayer.processingStateStream
      .map((state) => state == ProcessingState.completed);

  AudioService() {
    // Apply a default load configuration when service is initialized
    // configureBufferSettings( // Commented out call
    //   bufferDuration: const Duration(seconds: 30), // Default overall buffer hint
    //   minBufferDuration: const Duration(milliseconds: 15000), // Android specific
    //   maxBufferDuration: const Duration(milliseconds: 60000), // Android specific
    // );

    _initAudioSession();

    // Listen for network quality changes
    // _networkService.onNetworkQualityChanged.listen((quality) { // Commented out listener
    //   _handleNetworkQualityChange(quality);
    // });
  }

  Future<void> _initAudioSession() async {
    if (_isInitialized) return;

    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: const AndroidAudioAttributes(
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

  Future<void> play(String url) async {
    try {
      await _initAudioSession();
      await _audioPlayer.stop();

      _currentUrl = url;
      _isLocalFile = false;

      // Create audio source from URL
      AudioSource audioSource;
      if (url == _preloadedUrl && _preloadedSource != null) {
        if (kDebugMode) print("AudioService: Using preloaded source for $url");
        audioSource = _preloadedSource!;
        _preloadedSource = null; // Consume the preloaded source
        _preloadedUrl = null;
      } else {
        if (kDebugMode) print("AudioService: Creating new AudioSource.uri for $url. Preloaded URL was $_preloadedUrl");
        // If a different track is played than preloaded, clear preloaded info
        _preloadedSource = null;
        _preloadedUrl = null;
        audioSource = AudioSource.uri(Uri.parse(url));
      }

      // Set the audio source and play
      await _audioPlayer.setAudioSource(audioSource); // Removed initialConfiguration
      await _audioPlayer.play();
    } on PlayerException catch (e) {
      print('just_audio PlayerException during play: ${e.message}');
      throw Exception('Failed to play audio: ${e.message}');
    } catch (e) {
      print('Error playing audio: $e');
      throw Exception('Failed to play audio: $e');
    }
  }

  Future<void> playLocalFile(String filePath) async {
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

      // Create audio source from local file
      final audioSource = AudioSource.uri(Uri.file(filePath));

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

        // Try to play again
        final audioSource = AudioSource.uri(Uri.parse(_currentUrl!));
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

      _preloadedSource = LockCachingAudioSource(Uri.parse(url));
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

  // Future<void> configureBufferSettings({ // Commented out entire method
  //   Duration? bufferDuration,
  //   Duration? minBufferDuration,
  //   Duration? maxBufferDuration,
  // }) async {
  //   try {
  //     // Define effective durations, falling back to sensible defaults if null
  //     // These names match the parameters of AndroidLoadControl and DarwinLoadControl
  //     final Duration androidMinBufferDur = minBufferDuration ?? const Duration(milliseconds: 15000);
  //     final Duration androidMaxBufferDur = maxBufferDuration ?? const Duration(milliseconds: 60000);
  //     final Duration androidBufferForPlaybackDur = bufferDuration ?? const Duration(milliseconds: 2500);

  //     final Duration darwinPreferredForwardBufferDur = bufferDuration ?? const Duration(seconds: 30);

  //     final audioLoadConfiguration = AudioLoadConfiguration(
  //       androidLoadControl: AndroidLoadControl(
  //         minBufferDur: androidMinBufferDur,
  //         maxBufferDur: androidMaxBufferDur,
  //         bufferForPlaybackDur: androidBufferForPlaybackDur,
  //         prioritizeTimeOverSizeThresholds: true,
  //       ),
  //       darwinLoadControl: DarwinLoadControl(
  //         preferredForwardBufferDuration: darwinPreferredForwardBufferDur,
  //       ),
  //     );

  //     await _audioPlayer.setAudioLoadConfiguration(audioLoadConfiguration);

  //     if (kDebugMode) {
  //       print("AudioService: Buffer settings configured - Android(min:$androidMinBufferDur, max:$androidMaxBufferDur, playback:$androidBufferForPlaybackDur), Darwin(forward:$darwinPreferredForwardBufferDur)");
  //     }
  //   } catch (e) {
  //     if (kDebugMode) {
  //       print("AudioService: Error configuring buffer settings: $e");
  //     }
  //   }
  // }

  void dispose() {
    _audioPlayer.dispose();
  }
}
