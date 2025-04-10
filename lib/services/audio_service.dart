// lib/services/audio_service.dart
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../services/network_service.dart';
import '../utils/network_config.dart';
import 'dart:math';


class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final NetworkService _networkService = NetworkService();
  bool _isInitialized = false;
  String? _currentUrl;
  String? _currentFilePath;
  bool _isLocalFile = false;

  // Streams
  Stream<Duration> get onPositionChanged => _audioPlayer.positionStream.map((position) => position ?? Duration.zero);
  Stream<Duration> get onDurationChanged => _audioPlayer.durationStream.map((duration) => duration ?? Duration.zero);
  Stream<bool> get onPlaybackStateChanged => _audioPlayer.playingStream;
  Stream<bool> get onPlaybackComplete => _audioPlayer.processingStateStream
      .map((state) => state == ProcessingState.completed);

  AudioService() {
    _initAudioSession();

    // Listen for network quality changes
    _networkService.onNetworkQualityChanged.listen((quality) {
      _handleNetworkQualityChange(quality);
    });
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
      final audioSource = AudioSource.uri(Uri.parse(url));

      // Set the audio source and play
      await _audioPlayer.setAudioSource(audioSource);
      await _audioPlayer.play();
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
      await _audioPlayer.setAudioSource(audioSource);
      await _audioPlayer.play();
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
      await _audioPlayer.play();
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
  void _handleNetworkQualityChange(NetworkQuality quality) {
    // If we're playing a remote file and network quality drops
    if (_isPlaying && !_isLocalFile && _currentUrl != null) {
      if (quality == NetworkQuality.poor) {
        // Reduce buffer size for poor networks to prevent long buffering
        _audioPlayer.setAndroidAudioAttributes(
          const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
            flags: AndroidAudioFlags.audibilityEnforced,
            // Use low latency mode for poor networks
          ),
        );
      }
    }
  }

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

  void dispose() {
    _audioPlayer.dispose();
  }
}
