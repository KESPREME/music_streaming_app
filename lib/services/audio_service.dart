// lib/services/audio_service.dart
import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'playback/decks.dart';
import 'playback/mine_audio_handler.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../services/network_service.dart';
import '../utils/network_config.dart';
import '../core/constants/user_agents.dart';
import 'innertube/innertube_service.dart';
import 'dart:math';


class AudioService {
  // FIX: Create equalizer first, then pass to audio pipeline
  late final AndroidEqualizer _equalizer;
  /// The pair of decks. [_audioPlayer] is whichever one is the session deck
  /// right now; every call below that said "the player" still means that one.
  late final DeckPair _decks;
  AudioPlayer get _audioPlayer => _decks.active;
  late final bool _enableEqualizer;
  
  final NetworkService _networkService = NetworkService();
  bool _isInitialized = false;

  /// The in-flight session configuration, shared so it only ever runs once.
  Future<void>? _sessionInitFuture;
  String? _currentUrl;
  String? _currentFilePath;
  bool _isLocalFile = false;
  bool _hasPrevious = false; // State to persist window
  bool _hasNext = false;     // State to persist window
  
  // Public getters for EQ access
  AndroidEqualizer get equalizer => _equalizer;
  
  // Subscription management for proper cleanup
  final List<StreamSubscription> _subscriptions = [];

  Directory? _audioCacheDir;
  Future<Directory> _getAudioCacheDir() async {
    if (_audioCacheDir != null) return _audioCacheDir!;
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/audio_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _audioCacheDir = dir;
    return dir;
  }

  DateTime? _lastAudioPrune;
  Future<void> _pruneAudioCacheIfNeeded() async {
    final now = DateTime.now();
    if (_lastAudioPrune != null &&
        now.difference(_lastAudioPrune!) < const Duration(minutes: 5)) {
      return;
    }
    _lastAudioPrune = now;
    try {
      final dir = await _getAudioCacheDir();
      if (!await dir.exists()) return;
      final entities = await dir.list().toList();
      final files = entities.whereType<File>().toList();
      int totalBytes = 0;
      final fileStats = <File, DateTime>{};
      for (final f in files) {
        try {
          final stat = await f.stat();
          totalBytes += stat.size;
          fileStats[f] = stat.modified;
        } catch (_) {}
      }
      // 350 MB budget for cached audio streams
      const maxBudget = 350 * 1024 * 1024;
      if (totalBytes > maxBudget) {
        files.sort((a, b) =>
            (fileStats[a] ?? DateTime(2000)).compareTo(fileStats[b] ?? DateTime(2000)));
        for (final f in files) {
          if (totalBytes <= 250 * 1024 * 1024) break;
          try {
            final len = await f.length();
            await f.delete();
            totalBytes -= len;
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // Streams
  //
  // These are cached rather than computed in the getter. A `.map(...)` call
  // produces a NEW Stream instance every time, and `StreamBuilder` compares
  // the incoming stream by identity — so an uncached getter makes every
  // position/duration StreamBuilder in the app (now playing x2, lyrics,
  // mini player, progress bar) cancel and re-subscribe on *every* rebuild.
  //
  // They are relays (see decks.dart): stable streams that follow whichever deck
  // is the session deck, so a crossfade handoff is invisible to every listener.
  // Cached as fields for the reason above - a getter that built a new stream
  // each call would resubscribe every StreamBuilder on every rebuild.
  final DeckRelay<Duration> _positionRelay = DeckRelay<Duration>();
  final DeckRelay<Duration?> _durationRelay = DeckRelay<Duration?>(replay: true);
  final DeckRelay<bool> _playingRelay = DeckRelay<bool>(replay: true);
  final DeckRelay<PlayerState> _stateRelay = DeckRelay<PlayerState>(replay: true);
  final DeckRelay<ProcessingState> _processingRelay =
      DeckRelay<ProcessingState>(replay: true);
  final DeckRelay<double> _volumeRelay = DeckRelay<double>(replay: true);
  final DeckRelay<int?> _indexRelay = DeckRelay<int?>(replay: true);
  final DeckRelay<PlaybackEvent> _eventRelay = DeckRelay<PlaybackEvent>();

  /// Points every relay at [p]. Called once at start and again at each handoff.
  void _attachFeeds(AudioPlayer p) {
    _positionRelay.follow(p.positionStream);
    _durationRelay.follow(p.durationStream);
    _playingRelay.follow(p.playingStream);
    _stateRelay.follow(p.playerStateStream);
    _processingRelay.follow(p.processingStateStream);
    _volumeRelay.follow(p.volumeStream);
    _indexRelay.follow(p.currentIndexStream);
    _eventRelay.follow(p.playbackEventStream);
  }

  Stream<Duration> get onPositionChanged => _positionRelay.stream;
  late final Stream<Duration> onDurationChanged =
      _durationRelay.stream.map((duration) => duration ?? Duration.zero);
  late final Stream<bool> onPlaybackStateChanged = _playingRelay.stream;
  late final Stream<PlayerState> playerStateStream = _stateRelay.stream;
  late final Stream<bool> onPlaybackComplete = _processingRelay.stream
      .map((state) => state == ProcessingState.completed);
  late final Stream<double> onVolumeChanged = _volumeRelay.stream;

  /// What the listener set. The decks' own volumes are this times a fade gain.
  double _userVolume = 1.0;
  double get volume => _userVolume;

  // --- A2.0 measurement baseline ---
  //
  // Time from asking for a track to the first non-zero position. This is the
  // only number that settles whether any of the window work actually helped,
  // so it is measured rather than inferred.
  int? _playRequestedAtMs;
  int? _startLatencyMs;

  void _markPlayRequested() {
    _playRequestedAtMs = DateTime.now().millisecondsSinceEpoch;
    _startLatencyMs = null;
  }

  /// How long the most recent track took to produce its first audio sample.
  int? get lastStartLatencyMs => _startLatencyMs;

  /// Buffer health of the current track, for the same reason.
  Duration get bufferedPosition => _audioPlayer.bufferedPosition;

  /// Identifiers of the tracks in the player window, index-aligned.
  ///
  /// Kept in step with [playSources]/[appendWindow]. The player's own
  /// `sequence` is authoritative; this is the mirror the provider reconciles
  /// against so it never has to guess what is loaded.
  List<String?> _windowTracks = [];

  /// Head metadata of the current window, kept so a retry can rebuild a tagged
  /// source for the same track.
  String? _lastTitle;
  String? _lastArtist;
  String? _lastArtUri;
  String? _lastId;

  /// True when a source is loaded in the player (not idle). Used by the
  /// provider to distinguish paused-with-source from stopped.
  bool get hasLoadedSource => _audioPlayer.processingState != ProcessingState.idle;

  /// True when parked on a silent padding item (prev/next dummy) rather than
  /// real content. With the always-windowed playlist, ProcessingState.
  /// completed fires only when a dummy finishes — i.e. it is always a
  /// trailing echo of the real track's end, never a fresh completion.
  bool get isOnPaddingItem {
    final index = _audioPlayer.currentIndex;
    if (index == null) return false;
    final sequence = _audioPlayer.sequence;
    if (sequence == null || index < 0 || index >= sequence.length) return false;
    final tag = sequence[index].tag;
    return tag is MediaItem &&
        (tag.id == 'prev_dummy' || tag.id == 'next_dummy');
  }

  // Navigation Streams
  final _onSkipToNextController = StreamController<void>.broadcast();
  Stream<void> get onSkipToNext => _onSkipToNextController.stream;

  final _onSkipToPreviousController = StreamController<void>.broadcast();
  Stream<void> get onSkipToPrevious => _onSkipToPreviousController.stream;

  // Error Stream
  final _onPlaybackErrorController = StreamController<String>.broadcast();
  Stream<String> get onPlaybackError => _onPlaybackErrorController.stream;

  /// Builds the audio effects pipeline for a device.
///
/// The Equalizer is **opt-in** and off by default, because on a device that
/// reports no equalizer capability it takes playback down with it.
///
/// `AudioEffect._activate` runs every time audio becomes active and the Android
/// equalizer's implementation reads its band count from the platform at that
/// moment. Where the platform could not create the effect - the effect object is
/// null, which several OEM builds report as
/// `AudioEffect ... id: -1 status 0 enabled 0` - that read throws and the
/// exception surfaces as a PlatformException out of `play()` and out of
/// `pause()`. Nothing on the Dart side can guard it: `_activate` is
/// library-private, so it cannot be overridden from another package.
///
/// The effect is also not reachable: the settings tile says "coming soon", and
/// `eq_enabled` defaults to false. So the pipeline was carrying an effect that
/// nothing asked for, that nothing could turn off, and that made every track
/// unplayable on affected hardware.
///
/// Pass `enableEqualizer: true` once there is a working surface for it AND the
/// device has been found to support it.
List<AndroidAudioEffect> _buildAndroidAudioEffects({
  required bool enableEqualizer,
}) {
  final effects = <AndroidAudioEffect>[];
  if (enableEqualizer) effects.add(AndroidEqualizer());
  // No loudness enhancer. One used to ride in this pipeline, but it was a
  // fresh instance nothing held a reference to, so nothing could ever enable
  // it: it only cost a native effect attached to the audio session for the life
  // of the player. An attached effect is also exactly what stops Android from
  // offloading decode to the low-power DSP, which this player asks for below.
  return effects;
}

  AudioService({bool enableEqualizer = false}) {
    // Initialize audio effects
    _equalizer = AndroidEqualizer();
    _enableEqualizer = enableEqualizer;
    _decks = DeckPair(_newPlayer);
    _attachFeeds(_decks.active);

    _initAudioSession();
    _monitorIndexChanges();
    _measureStartLatency();
    _emitWindowIndex();
    _bindSession();
  }

  /// One deck, configured the way the single player always was.
  AudioPlayer _newPlayer() => AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects:
              _buildAndroidAudioEffects(enableEqualizer: _enableEqualizer),
        ),
        // Hand sequencing to the player: it skips forward past a windowed track
        // that fails to load instead of wedging playback. Two attempts is enough
        // to ride out one flaky URL without silently skipping a whole queue.
        maxSkipsOnError: 2,
        // Offload decode to the low-power audio DSP. This is the single largest
        // battery win available on Android, and the guards keep it from fighting
        // the rest of the pipeline: gapless must still be possible (a device
        // that cannot do gapless under offload will not engage it), and a speed
        // or pitch change forces it back to the full decoder.
        androidAudioOffloadPreferences: AndroidAudioOffloadPreferences(
          audioOffloadMode: AndroidAudioOffloadMode.enabled,
          isGaplessSupportRequired: true,
          isSpeedChangeSupportRequired: false,
        ),
        // Prepare each windowed item just in time before it is reached. This is
        // what makes the window seam-free; setting it false defeats the point.
        useLazyPreparation: true,
        audioLoadConfiguration: const AudioLoadConfiguration(
          androidLoadControl: AndroidLoadControl(
            minBufferDuration: Duration(milliseconds: 1000),
            // Far beyond any single track. Latency comes from bytes being on
            // disk before the track is reached, not from a smaller threshold,
            // so the thresholds below stay aggressive. Duration is set past any
            // song so the byte ceiling is the only binding constraint.
            maxBufferDuration: Duration(minutes: 15),
            bufferForPlaybackDuration: Duration(milliseconds: 200),
            bufferForPlaybackAfterRebufferDuration: Duration(milliseconds: 800),
            prioritizeTimeOverSizeThresholds: true,
            // History only as far as the seek people actually make: nudging
            // back a few seconds for a lyric. Wider than this and the back
            // buffer competes with read-ahead for the same byte ceiling.
            backBufferDuration: Duration(seconds: 30),
          ),
          darwinLoadControl: DarwinLoadControl(
            preferredForwardBufferDuration: Duration(seconds: 15),
            automaticallyWaitsToMinimizeStalling: false,
          ),
        ),
      );

  /// The MediaItem id of whichever window entry the player is on, or null.
  ///
  /// This is the signal that the track changed. The player advances within its
  /// window by itself, so this — not a synthesised skip event — is what tells
  /// the rest of the app a new song started.
  final _windowIndexController = StreamController<String?>.broadcast();
  Stream<String?> get windowIndexStream => _windowIndexController.stream;

  void _emitWindowIndex() {
    _subscriptions.add(_indexRelay.stream.listen((index) {
      final seq = _audioPlayer.sequence;
      if (index == null || index < 0 || index >= seq.length) {
        _windowIndexController.add(null);
        return;
      }
      final tag = seq[index].tag;
      _windowIndexController.add(tag is MediaItem ? tag.id : null);
    }));
  }

  /// Records how long the current track took to produce its first sample.
  ///
  /// Stops measuring once a non-zero position is seen for the current request,
  /// so a long track does not keep re-reporting the first second.
  void _measureStartLatency() {
    _subscriptions.add(_positionRelay.stream.listen((pos) {
      final requestedAt = _playRequestedAtMs;
      if (requestedAt == null || _startLatencyMs != null) return;
      if (pos <= Duration.zero) return;
      final ms = DateTime.now().millisecondsSinceEpoch - requestedAt;
      _startLatencyMs = ms;
      if (kDebugMode) {
        debugPrint('AUDIO_LATENCY start=${ms}ms buffered='
            '${_audioPlayer.bufferedPosition.inMilliseconds}ms '
            'window=${_windowTracks.length}');
      }
    }));
  }

  // Monitor index changes to trigger external navigation
  void _monitorIndexChanges() {
    _startNavigationMonitor();
  }

  Future<void> _initAudioSession() {
    if (_isInitialized) return Future<void>.value();
    // Single-flight, not just a flag.
    //
    // Construction calls this unawaited and playback awaits it. With only the
    // `_isInitialized` guard both ran, because neither had set it yet: the
    // session was configured twice, the interruption/becoming-noisy listeners
    // were registered twice, and the second `configure` renegotiated audio focus
    // underneath a player that had already started - so the first tap after a
    // cold start went silent and only the second press worked. Sharing one
    // Future means the configuration happens once and every caller waits for
    // that same attempt.
    return _sessionInitFuture ??= _configureAudioSession().whenComplete(() {
      _sessionInitFuture = null;
    });
  }

  Future<void> _configureAudioSession() async {
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
        androidWillPauseWhenDucked: false, // Don't stop music on notifications
      ));

      // BATTERY FIX: Handle audio interruptions (calls, other apps, etc.)
      bool _wasPlayingBeforeInterruption = false;
      _subscriptions.add(
        session.interruptionEventStream.listen((event) {
          if (event.begin) {
            // Interruption started
            switch (event.type) {
              case AudioInterruptionType.duck:
                // Lower volume temporarily (handled by system)
                break;
              case AudioInterruptionType.pause:
              case AudioInterruptionType.unknown:
                // Pause playback; remember whether WE were playing so we only
                // resume what was actually playing before the interruption.
                _wasPlayingBeforeInterruption = _audioPlayer.playing;
                _pauseAllDecks();
                break;
            }
          } else {
            // Interruption ended - resume ONLY if it was playing before
            if (_wasPlayingBeforeInterruption &&
                _audioPlayer.processingState != ProcessingState.idle) {
              _audioPlayer.play();
            }
            _wasPlayingBeforeInterruption = false;
          }
        }),
      );

      // BATTERY FIX: Handle becoming noisy (headphones unplugged)
      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) {
          // Pause when headphones unplugged (standard behavior)
          _pauseAllDecks();
        }),
      );

      // Set up error handling
      _subscriptions.add(
        _eventRelay.stream.listen(
          (event) {},
          onError: (Object e, StackTrace st) {
            debugPrint('Audio player error: $e');
            _handlePlaybackError(e);
          },
        ),
      );

      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing audio session: $e');
      // A failed configure must not latch: the next attempt gets to try again
      // rather than the session being permanently "initialised" but dead.
      _isInitialized = false;
    }
  }

  Future<void> play(String? url, {
    bool isLocal = false,
    AudioSource? customSource,
    Map<String, String>? headers,
    String? title,
    String? artist,
    String? artUri,
    String? id,
    bool hasPrevious = false,
    bool hasNext = false,
  }) async {
    try {
      if (url == null && customSource == null) {
        throw Exception('Cannot play: Both URL and source are null');
      }

      await _initAudioSession();

      _sourceEpoch++;
      cancelPendingRetry();
      _currentUrl = url;
      _isLocalFile = isLocal;
      _hasPrevious = hasPrevious;
      _hasNext = hasNext;

      final source = customSource ??
          await buildSource(
            url: url,
            isLocal: isLocal,
            headers: headers,
            title: title,
            artist: artist,
            artUri: artUri,
            id: id,
          );
      if (source == null) {
        throw Exception('Cannot play: no playable source for $id');
      }

      await playSources([source], title: title, artist: artist, artUri: artUri, id: id);
    } on PlayerException catch (e) {
      // Rethrow as-is. Wrapping it in a bare Exception erased the type, so
      // [_looksLikeNetworkError] and any caller inspecting `code` (ExoPlayer
      // 2001/2002 = recoverable IO) could no longer classify the failure.
      if (kDebugMode) debugPrint('AudioService: PlayerException: ${e.message}');
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('AudioService: Error playing: $e');
      throw Exception('Failed to play audio: $e');
    }
  }

  /// Builds a tagged, cache-backed [AudioSource] for one resolved track.
  ///
  /// Every source produced here MUST carry a [MediaItem] tag. The background
  /// media session does an unchecked `source.tag as MediaItem` over the whole
  /// sequence (`just_audio_background`, `queue.add(sequence.map(...))`), so a
  /// single untagged entry throws and takes the notification down with it.
  /// Returns null rather than an untagged source when there is nothing to play.
  Future<IndexedAudioSource?> buildSource({
    String? url,
    bool isLocal = false,
    Map<String, String>? headers,
    String? title,
    String? artist,
    String? artUri,
    String? id,
    bool cacheWrites = true,
  }) async {
    if (url == null || url.isEmpty) return null;

    // A warmed connection for this exact URL wins, and is consumed once.
    // (Not for a transition's incoming deck: that source must never write the
    // cache file another deck may be filling for the same song.)
    final preloaded = cacheWrites ? takePreloaded(url) : null;
    if (preloaded != null) {
      return _retag(preloaded,
          id: id, url: url, title: title, artist: artist, artUri: artUri);
    }

    final Uri uri;
    try {
      uri = isLocal ? Uri.file(url) : Uri.parse(url);
    } catch (e) {
      throw Exception('Invalid URL: $e');
    }

    // Explicit headers (e.g. the ANDROID_VR UA that StreamResolutionService
    // derives) take precedence; otherwise sniff legacy client params from the
    // URL. googlevideo rejects playback when the UA does not match the client
    // that signed the URL.
    final resolvedHeaders = <String, String>{
      'Accept-Encoding': 'gzip',
      if (headers != null) ...headers,
    };
    if (!resolvedHeaders.containsKey('User-Agent')) {
      if (url.contains('c=ANDROID')) {
        resolvedHeaders['User-Agent'] =
            'com.google.android.youtube/17.31.35 (Linux; U; Android 11) gzip';
      } else if (url.contains('c=IOS')) {
        resolvedHeaders['User-Agent'] =
            'com.google.ios.youtube/19.29.1 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X)';
      }
    }

    // Never null: the cast above is unchecked, so a missing title would
    // produce a null tag and break the media session.
    final tag = MediaItem(
      id: (id != null && id.isNotEmpty) ? id : url,
      title: title ?? 'Unknown Track',
      artist: artist ?? 'Unknown Artist',
      artUri: (artUri != null && artUri.isNotEmpty) ? Uri.parse(artUri) : null,
    );

    if (isLocal) {
      return AudioSource.file(url, tag: tag);
    }

    if (id != null && id.isNotEmpty) {
      try {
        final dir = await _getAudioCacheDir();
        final sanitizedId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
        final cacheFile = File('${dir.path}/audio_$sanitizedId.m4a');
        if (await cacheFile.exists() && (await cacheFile.length()) > 100000) {
          return AudioSource.file(cacheFile.path, tag: tag);
        }
        // The incoming deck of a transition plays straight from the network when
        // the song is not fully cached: a second LockCachingAudioSource on the
        // same cache file, in a second player, would have two writers.
        if (!cacheWrites) {
          return AudioSource.uri(
            uri,
            headers: resolvedHeaders.isNotEmpty ? resolvedHeaders : null,
            tag: tag,
          );
        }
        unawaited(_pruneAudioCacheIfNeeded());
        return LockCachingAudioSource(
          uri,
          cacheFile: cacheFile,
          headers: resolvedHeaders.isNotEmpty ? resolvedHeaders : null,
          tag: tag,
        );
      } catch (_) {
        // Fall through to a plain URI source; still tagged.
      }
    }

    return AudioSource.uri(
      uri,
      headers: resolvedHeaders.isNotEmpty ? resolvedHeaders : null,
      tag: tag,
    );
  }

  /// Rebuilds [source] carrying [tag], so a preloaded source (created before
  /// the track's metadata was known) still satisfies the media session's
  /// unchecked `tag as MediaItem` cast.
  Future<IndexedAudioSource> _retag(
    AudioSource source, {
    required String? id,
    required String url,
    String? title,
    String? artist,
    String? artUri,
  }) async {
    final tag = MediaItem(
      id: (id != null && id.isNotEmpty) ? id : url,
      title: title ?? 'Unknown Track',
      artist: artist ?? 'Unknown Artist',
      artUri: (artUri != null && artUri.isNotEmpty) ? Uri.parse(artUri) : null,
    );
    if (source is LockCachingAudioSource) {
      // cacheFile is a Future<File> on the getter but the constructor takes a
      // File, so the original cannot be reused as-is; resolve the path and
      // reopen the same file, which keeps the warmed bytes.
      final file = await source.cacheFile;
      return LockCachingAudioSource(
        source.uri,
        cacheFile: file,
        headers: source.headers,
        tag: tag,
      );
    }
    if (source is UriAudioSource) {
      return AudioSource.uri(source.uri, headers: source.headers, tag: tag);
    }
    return source as IndexedAudioSource;
  }

  /// Installs [sources] as the player's queue and starts playback.
  ///
  /// This is the single place the player queue is set. A window of real,
  /// already-resolved tracks means ExoPlayer transitions between them
  /// seamlessly, so the player — not the caller — performs the advance.
  /// Callers use [seekToNext] when the next track is already in the window,
  /// and come back here only when it is not.
  Future<void> playSources(
    List<AudioSource> sources, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    String? title,
    String? artist,
    String? artUri,
    String? id,
  }) async {
    if (sources.isEmpty) {
      throw Exception('playSources: empty window');
    }
    await _initAudioSession();

    // A new window ends any transition in flight: both decks, gains restored.
    beforeTransport?.call();
    if (_audioPlayer.playing) {
      await _audioPlayer.stop();
    }
    await _decks.standbyIfAny?.stop();
    _activeGain = 1.0;
    _standbyGain = 0.0;
    await _audioPlayer.setVolume(_userVolume);

    // Remembered so a network-failure retry can rebuild a correctly tagged
    // source: the media session casts every sequence tag to MediaItem without
    // a check, so a retry that came back untagged would take it down.
    _lastTitle = title;
    _lastArtist = artist;
    _lastArtUri = artUri;
    _lastId = id;

    _windowTracks = List<String?>.filled(sources.length, null, growable: true);
    _markPlayRequested();

    if (kDebugMode) {
      debugPrint('AudioService: playSources window=${sources.length} '
          'index=$initialIndex pos=$initialPosition');
    }

    await _audioPlayer.setAudioSources(
      sources,
      initialIndex: initialIndex.clamp(0, sources.length - 1),
      initialPosition: initialPosition,
    );
    if (kDebugMode) debugPrint('AudioService: setAudioSources done');
    // Speed/pitch survive a source swap only if reapplied; ExoPlayer resets
    // them on setAudioSources.
    if (_speed != 1.0) await _audioPlayer.setSpeed(_speed);
    if (_pitch != 1.0) await setPitch(_pitch);
    _publishQueue();
    // `play()` must not be awaited bare. Its future resolves when the player
    // reports playing, and that report can already have happened - or arrive
    // via a path the request is not listening on - while audio is genuinely
    // playing. Awaiting it then wedges the whole playback pipeline: the track
    // is audible but nothing after this line ever runs (no window fill, no
    // station, no state update), and every later tap piles another stuck call
    // on top. Real failures still surface through the playback error listener,
    // and a play that silently fails to activate the session is retried
    // inside [_requestPlay].
    unawaited(_requestPlay().then((_) {
      if (kDebugMode) debugPrint('AudioService: play() returned');
    }));
  }

  /// Extends the live window without interrupting playback.
  Future<void> appendWindow(List<AudioSource> sources) async {
    if (sources.isEmpty) return;
    _windowTracks.addAll(List<String?>.filled(sources.length, null, growable: true));
    await _audioPlayer.addAudioSources(sources);
    _publishQueue();
    engineEvent?.call();
  }

  /// Inserts [source] at [index] in the live window without interrupting
  /// playback, used to put a preceding track in front of the head.
  ///
  /// The player's current item stays current — only its index moves — so this
  /// is safe to call mid-track. If the player rejects it the tracking list is
  /// rolled back, because a placeholder with no matching source would make
  /// [windowTrackIds] report a track that is not loaded.
  Future<void> insertWindowAt(int index, AudioSource source) async {
    final at = index.clamp(0, _windowTracks.length);
    _windowTracks.insert(at, null);
    try {
      await _audioPlayer.insertAudioSource(at, source);
      _publishQueue();
    } catch (e) {
      _windowTracks.removeAt(at);
      rethrow;
    }
  }

  /// Identifiers of the tracks currently in the player window, index-aligned.
  ///
  /// Read from the player's own sequence so it can never drift from what is
  /// actually loaded. Used to decide whether a seek stays inside the window
  /// or needs a rebuild.
  List<String?> get windowTrackIds =>
      _audioPlayer.sequence.map((s) => s.tag is MediaItem ? (s.tag! as MediaItem).id : null).toList();

  /// The windowed track after the current one, or null if the window ends here.
  String? get nextWindowTrackId {
    final seq = _audioPlayer.sequence;
    final i = _audioPlayer.currentIndex;
    if (i == null || i + 1 >= seq.length) return null;
    final tag = seq[i + 1].tag;
    return tag is MediaItem ? tag.id : null;
  }

  bool get hasNextInWindow => _audioPlayer.hasNext;
  bool get hasPreviousInWindow => _audioPlayer.hasPrevious;

  /// Where the player is in its window, or -1 when nothing is loaded.
  ///
  /// Read to tell "the sequence ended" from "ExoPlayer is halfway through
  /// stepping to the next item", which look identical from the outside.
  int get windowIndex => _audioPlayer.currentIndex ?? -1;

  Future<void> seekToNextInWindow() {
    beforeTransport?.call();
    return _audioPlayer.seekToNext();
  }

  Future<void> seekToPreviousInWindow() {
    beforeTransport?.call();
    return _audioPlayer.seekToPrevious();
  }

  /// Applies the app's repeat mode to the player.
  ///
  /// Repeat-one is delegated so it becomes a gapless native loop rather than
  /// the full re-resolve it used to be. Repeat-all is deliberately NOT
  /// delegated: the window is a bounded few tracks, so `LoopMode.all` there
  /// would loop the window rather than the playlist, and the provider drives
  /// repeat-all explicitly.
  Future<void> applyRepeatMode({required bool repeatOne}) async {
    await _audioPlayer.setLoopMode(repeatOne ? LoopMode.one : LoopMode.off);
  }

  Future<void> setShuffleOn(bool enabled) async {
    if (enabled) {
      if (!_audioPlayer.shuffleModeEnabled) await _audioPlayer.setShuffleModeEnabled(true);
    } else if (_audioPlayer.shuffleModeEnabled) {
      await _audioPlayer.setShuffleModeEnabled(false);
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    beforeTransport?.call();
    try {
      await _audioPlayer.seek(position);
    } catch (e) {
      debugPrint('Error seeking audio: $e');
      throw Exception('Failed to seek audio: $e');
    }
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
    // Retires any in-flight [_requestPlay] retry loop before pausing.
    //
    // That loop's only cancellation is [_playRequestSeq], and until now only a
    // newer *play* request bumped it - so a pause did not stop it. The loop
    // wakes up after the pause, checks `playing`, finds false (which the pause
    // is exactly why it finds), and re-issues play. The song pauses for about a
    // second and then carries on, and only the press that happens to land after
    // the loop exhausts its attempts sticks - which is why it took two or three
    // taps to pause.
    _playRequestSeq++;
    try {
      await _audioPlayer.pause();
      final standby = _decks.standbyIfAny;
      if (standby != null && standby.playing) await standby.pause();
    } catch (e) {
      debugPrint('Error pausing audio: $e');
      throw Exception('Failed to pause audio: $e');
    }
  }

  /// Asks the player to start, and insists that it actually did.
  ///
  /// `just_audio`'s [AudioPlayer.play] broadcasts `playing: true`
  /// optimistically and then *reverts* to false when
  /// `audioSession.setActive(true)` fails (just_audio.dart L1117-1120). It does
  /// not retry and it does not raise: there is no error for a listener to see.
  /// The session is routinely not ready yet immediately after a cold start or
  /// a resume, so the optimistic play evaporated and the app sat there paused
  /// with nothing wrong on screen - the only cure being a tap on play.
  ///
  /// So: issue the play, then check whether it took, and re-issue while it did
  /// not. [_playRequestSeq] makes a newer request invalidate an older retry loop
  /// so a fast tap-through cannot leave two loops fighting.
  Future<void> _requestPlay({int attempts = 3}) async {
    final seq = ++_playRequestSeq;
    for (var attempt = 0; attempt < attempts; attempt++) {
      // Checked *before* issuing play, not only after. The post-play check alone
      // still lets one spurious play() through: a pause landing during the
      // backoff delay bumps the sequence, but the loop had already decided to
      // play before it woke up, so it would resume a track the user had just
      // paused and only notice afterwards.
      if (seq != _playRequestSeq) return;
      if (_audioPlayer.playing) return;
      try {
        // play() completes on the platform play request, which can hang if the
        // session never activates. The timeout keeps the caller moving.
        await _audioPlayer.play().timeout(const Duration(seconds: 4));
      } catch (_) {
        // Fall through to the retry below.
      }
      if (seq != _playRequestSeq) return;
      if (_audioPlayer.playing) return;
      if (attempt == attempts - 1) break;
      if (kDebugMode) {
        debugPrint('AudioService: play() did not take '
            '(attempt ${attempt + 1}/$attempts) - session not active, retrying');
      }
      await Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));
    }
    if (kDebugMode && !_audioPlayer.playing) {
      debugPrint('AudioService: gave up asking the player to start');
    }
  }

  int _playRequestSeq = 0;

  /// Steps the cursor onto the entry after a dry-window repair.
  ///
  /// Deliberately not "call play() and hope the finished sequence continues":
  /// a completed player will not continue by itself, and resuming a completed
  /// item restarts *that item* from zero - the "the song played twice" report.
  /// Moving the cursor is the only unambiguous way to mean "carry on".
  Future<bool> advanceIntoWindow() async {
    if (!_audioPlayer.hasNext) return false;
    await _audioPlayer.seekToNext();
    await _requestPlay();
    return true;
  }

  Future<void> resume() async {
    // If the player has completed, the stream was likely closed. There is
    // nothing to resume *into* unless the window still holds a successor.
    if (_audioPlayer.processingState == ProcessingState.completed) {
      if (await advanceIntoWindow()) return;
      // Genuinely the end of everything: the only thing left to do is replay
      // the current item from the top, which is what a play press means here.
      await _audioPlayer.seek(Duration.zero);
    }
    await _requestPlay();
  }

  Future<void> stop() async {
    // Same hole as pause(), one layer out: a retry loop that wakes after a stop
    // would restart playback into a source that is being torn down.
    _playRequestSeq++;
    try {
      _sourceEpoch++;
      cancelPendingRetry();
      beforeTransport?.call();
      await _audioPlayer.stop();
      await _decks.standbyIfAny?.stop();
      _activeGain = 1.0;
      _standbyGain = 0.0;
      _currentUrl = null;
      _currentFilePath = null;
      _isLocalFile = false;
      _preloadedUrl = null;
      _preloadedSource = null;
    } catch (e) {
      debugPrint('Error stopping audio: $e');
      throw Exception('Failed to stop audio: $e');
    }
  }

  bool _skipSilence = false;

  /// Skips silent passages inside a song, on every deck.
  Future<void> setSkipSilence(bool enabled) async {
    _skipSilence = enabled;
    try {
      await _audioPlayer.setSkipSilenceEnabled(enabled);
      final standby = _decks.standbyIfAny;
      if (standby != null) await standby.setSkipSilenceEnabled(enabled);
    } catch (e) {
      if (kDebugMode) debugPrint('AudioService: skip silence unavailable: $e');
    }
  }

  Future<void> setVolume(double volume) async {
    _userVolume = volume.clamp(0.0, 1.0);
    await _applyGains();
  }

  double _activeGain = 1.0;
  double _standbyGain = 0.0;

  /// The deck volumes: what the listener set, times each deck's fade gain.
  /// The only writer of deck volume, so a fade and the volume control can
  /// never fight over it.
  Future<void> _applyGains() async {
    await _audioPlayer.setVolume(_userVolume * _activeGain);
    final standby = _decks.standbyIfAny;
    if (standby != null) await standby.setVolume(_userVolume * _standbyGain);
  }

  void _pauseAllDecks() {
    _audioPlayer.pause();
    _decks.standbyIfAny?.pause();
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _audioPlayer.setSpeed(speed);
  }

  double _speed = 1.0;
  double get speed => _speed;

  Future<void> setPitch(double pitch) async {
    _pitch = pitch;
    try {
      await _audioPlayer.setPitch(pitch);
    } catch (e) {
      // setPitch unsupported off Android (just_audio logs internally).
      debugPrint('AudioService: setPitch unavailable: $e');
    }
  }

  double _pitch = 1.0;
  double get pitch => _pitch;

  // Handle playback errors
  void _handlePlaybackError(dynamic error) {
    if (_retryInFlight) return;
    if (!_isLocalFile && _currentUrl != null && _looksLikeNetworkError(error)) {
      _retryPlayback();
      return;
    }
    // Not a network error, so retrying the same URL cannot heal it (bad codec,
    // deleted file, unplayable stream). If the player holds something after the
    // current item, step past the dead one instead of stalling on it. The
    // provider's index listener applies the state change like any other
    // advance, so cover, lyrics and queue all follow.
    if (_audioPlayer.hasNext) {
      if (kDebugMode) {
        debugPrint('AudioService: current item unplayable ($error) '
            '- skipping past it');
      }
      unawaited(_audioPlayer.seekToNext());
    }
  }

  bool _looksLikeNetworkError(dynamic error) {
    if (error is PlayerException) {
      // ExoPlayer codes: 2001/2002 = source IO/network errors. Codec/format
      // errors will not heal by waiting, so don't retry them.
      return const <int>{2001, 2002}.contains(error.code);
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('socket') ||
        msg.contains('timeout');
  }

  // Retry playback with exponential backoff
  //
  // Cancelled by [cancelPendingRetry] whenever a new track is installed, and
  // abandoned early if [_sourceEpoch] moves on (a fresh play() or another
  // retry). Without this, a skip during the backoff window let the loop wake
  // up and call setAudioSource on whatever track was playing NOW, clobbering it.
  Future<void> _retryPlayback() async {
    if (_currentUrl == null || _isLocalFile) return;

    final epoch = _sourceEpoch;
    final targetUrl = _currentUrl;
    _retryInFlight = true;

    try {
      for (int attempt = 0; attempt < NetworkConfig.maxRetries; attempt++) {
      try {
        final backoffSeconds = pow(2, attempt) + (Random().nextInt(1000) / 1000.0);
        await Future.delayed(Duration(milliseconds: (backoffSeconds * 1000).round()));

        // Bail out if the user moved on, or another retry superseded us.
        if (_sourceEpoch != epoch) {
          if (kDebugMode) debugPrint('AudioService: retry abandoned (source changed)');
          return;
        }
        if (_currentUrl != targetUrl) return;

        if (!_networkService.isConnected) continue;

        final position = _audioPlayer.position;

        // CRITICAL: UA must match the client that signed the URL or
        // googlevideo returns 403. Re-derive from the URL itself, falling
        // back to the WEB_REMIX UA — never a plain Chrome UA (which is what
        // caused 403s here before).
        final headers = <String, String>{
          'User-Agent': InnerTubeService.userAgentForStreamUrl(targetUrl!) ?? kWebRemixUserAgent,
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          'Accept-Encoding': 'gzip',
          'Connection': 'keep-alive',
        };

        if (targetUrl.contains('googlevideo.com') || targetUrl.contains('youtube.com')) {
          headers['Referer'] = 'https://www.youtube.com/';
          headers['Origin'] = 'https://www.youtube.com';
        }

        // Re-check after the awaits above: they touch the disk and the network.
        if (_sourceEpoch != epoch) {
          if (kDebugMode) debugPrint('AudioService: retry abandoned before install');
          return;
        }

        // A retry replaces the window with the single track it is recovering.
        // The provider rebuilds the window on its next decision, and until then
        // a one-entry window is the honest state: the rest of the queue is not
        // known-good enough to promise to the player.
        final source = await buildSource(
          url: targetUrl,
          headers: headers,
          title: _lastTitle,
          artist: _lastArtist,
          artUri: _lastArtUri,
          id: _lastId,
        );
        if (source == null) continue;

        if (_sourceEpoch != epoch) return;

        _markPlayRequested();
        await _audioPlayer.setAudioSources([source]);
        if (position > Duration.zero) {
          await _audioPlayer.seek(position);
        }
        if (_speed != 1.0) {
          await _audioPlayer.setSpeed(_speed);
        }
        await _audioPlayer.play();
        return;
      } catch (e) {
        debugPrint('Retry attempt $attempt failed: $e');
      }
      }
    } finally {
      _retryInFlight = false;
    }

    debugPrint('All retry attempts failed');
  }

  bool get _isPlaying => _audioPlayer.playing;

  // --- Preloading ---
  LockCachingAudioSource? _preloadedSource;
  String? _preloadedUrl;

  Future<void> preloadTrack(String url, {String? userAgent}) async {
    if (url == _preloadedUrl && _preloadedSource != null) return;
    if (kDebugMode) debugPrint("AudioService: Preloading track $url");
    _preloadedUrl = url;
    try {
      // Same UA discipline as buildSource(): if the caller doesn't specify one,
      // derive it from the URL — never default to a generic Chrome UA.
      final headers = <String, String>{
        'User-Agent': userAgent ?? InnerTubeService.userAgentForStreamUrl(url) ?? kWebRemixUserAgent,
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip',
        'Connection': 'keep-alive',
      };

      if (url.contains('googlevideo.com') || url.contains('youtube.com')) {
        headers['Referer'] = 'https://www.youtube.com/';
        headers['Origin'] = 'https://www.youtube.com';
      }
      _preloadedSource = LockCachingAudioSource(Uri.parse(url), headers: headers);
      if (kDebugMode) debugPrint("AudioService: Set up LockCachingAudioSource for $url");

    } catch (e) {
      if (kDebugMode) debugPrint("AudioService: Error preloading track $url: $e");
      _preloadedUrl = null;
      _preloadedSource = null;
    }
  }

  /// The preloaded source for [url], consumed once, or null.
  ///
  /// Kept so the existing prefetch path still short-circuits the first track
  /// of a window onto a connection that was already warmed.
  AudioSource? takePreloaded(String? url) {
    if (url == null || url != _preloadedUrl || _preloadedSource == null) {
      return null;
    }
    final s = _preloadedSource;
    _preloadedSource = null;
    _preloadedUrl = null;
    return s;
  }
  
  // Internal monitor for navigation
  //
  // RETIRED. The player now sequences real tracks itself, so there is no dummy
  // item left whose index change could be mistaken for "the user hit next".
  // The setup guard that used to live here existed only to hide those
  // self-inflicted index events; with the machine gone it has nothing to hide.

  /// Bumped every time a new source is installed (or playback is stopped).
  ///
  /// Long-running async work captures it and compares on resume; if it moved,
  /// the work belonged to a track the user has since left and must not touch
  /// player state. See [_retryPlayback].
  int _sourceEpoch = 0;

  /// Guards against a second retry loop stacking on top of the first when
  /// several network errors land close together.
  bool _retryInFlight = false;

  /// Abandons any in-progress retry backoff. Called when a new track starts.
  void cancelPendingRetry() {
    if (_retryInFlight) {
      if (kDebugMode) debugPrint('AudioService: cancelling pending retry');
    }
    _retryInFlight = false;
  }

  void _startNavigationMonitor() {
      // The index watcher that used to live here is gone: it existed only to
      // spot the silent dummy items and translate them into skip events. The
      // player now holds real tracks and advances on its own, so its index
      // changes are ordinary playback, not navigation intents.

      // --- Error Handling Monitor ---
      _subscriptions.add(_stateRelay.stream.listen((state) {
        if (state.processingState == ProcessingState.idle) {
          // Idle usually happens after stop or reset, but check for error
        }
      }));
    
    // Listen for Player Exceptions explicitly
    _subscriptions.add(_eventRelay.stream.listen((event) {}, 
        onError: (Object e, StackTrace stackTrace) {
            debugPrint('AudioService: Playback Event Exception: $e');
            // Check for specific error substrings if possible
            if (e.toString().contains("Source error") || e.toString().contains("UnrecognizedInputFormatException")) {
                 debugPrint("AudioService: CRITICAL - Corrupt Source Detected.");
                 _onPlaybackErrorController.add("Source error");
            }
    }));
  }

  // ── Session: what the lock screen, notification and headset see ───────────
  //
  // just_audio_background used to mirror the (single) player into the media
  // session. With two decks that cannot work - it supports one player - so the
  // mirror is ours, and it follows whichever deck is the session deck.

  void _bindSession() {
    void ignore(Object _) {}
    _subscriptions.add(
        _eventRelay.stream.listen((_) => _publishSession(), onError: ignore));
    _subscriptions.add(
        _stateRelay.stream.listen((_) => _publishSession(), onError: ignore));
    _subscriptions.add(_indexRelay.stream.listen((_) {
      _publishMedia();
      _publishSession();
      engineEvent?.call();
    }, onError: ignore));
    _subscriptions.add(
        _playingRelay.stream.listen((_) => engineEvent?.call(), onError: ignore));
    _subscriptions.add(
        _durationRelay.stream.listen((_) => _publishMedia(), onError: ignore));
  }

  void _publishSession() {
    final handler = MineAudioHandler.shared;
    if (handler == null) return;
    final p = _audioPlayer;
    handler.publish(
      playing: p.playing,
      processing: p.processingState,
      position: p.position,
      buffered: p.bufferedPosition,
      speed: p.speed,
      queueIndex: p.currentIndex,
    );
  }

  void _publishMedia() {
    final handler = MineAudioHandler.shared;
    if (handler == null) return;
    final p = _audioPlayer;
    final i = p.currentIndex;
    final seq = p.sequence;
    if (i == null || i < 0 || i >= seq.length) {
      handler.publishMedia(null);
      return;
    }
    final tag = seq[i].tag;
    handler.publishMedia(tag is MediaItem ? tag.copyWith(duration: p.duration) : null);
  }

  void _publishQueue() {
    final handler = MineAudioHandler.shared;
    if (handler == null) return;
    handler.publishQueue([
      for (final s in _audioPlayer.sequence)
        if (s.tag is MediaItem) s.tag as MediaItem,
    ]);
  }

  // ── Decks: the surface the TransitionEngine drives ────────────────────────
  //
  // Everything a crossfade needs and nothing else. The standby deck carries the
  // INCOMING track only (see decks.dart); the engine decides when and how.

  /// Called BEFORE anything the listener does to what is playing (a seek, a
  /// skip, a new window, a stop), so a transition in flight is abandoned with a
  /// short ramp rather than finished against nothing.
  VoidCallback? beforeTransport;

  /// Something the engine plans around changed: play/pause, the track, the
  /// window. The engine sleeps between songs and wakes on this.
  VoidCallback? engineEvent;

  Duration? get activeDuration => _audioPlayer.duration;
  Duration get activePosition => _audioPlayer.position;
  bool get activePlaying => _audioPlayer.playing;

  /// The tag id of the session deck's current item, or null.
  String? get currentWindowId {
    final i = _audioPlayer.currentIndex;
    final seq = _audioPlayer.sequence;
    if (i == null || i < 0 || i >= seq.length) return null;
    final tag = seq[i].tag;
    return tag is MediaItem ? tag.id : null;
  }

  Duration get standbyPosition => _decks.standbyIfAny?.position ?? Duration.zero;
  bool get standbyPlaying => _decks.standbyIfAny?.playing ?? false;
  ProcessingState get standbyProcessing =>
      _decks.standbyIfAny?.processingState ?? ProcessingState.idle;

  /// Loads [source] on the standby deck, silent and paused, cued at [cue].
  ///
  /// [rate] is a tempo stretch for beat matching, applied on top of the
  /// listener's own speed. The cue is reached by STARTING there rather than by
  /// seeking, so there is no discontinuity to hide.
  Future<void> prepareStandby(
    IndexedAudioSource source, {
    Duration cue = Duration.zero,
    double rate = 1.0,
  }) async {
    await _initAudioSession();
    final deck = _decks.standby;
    try {
      await deck.stop();
    } catch (_) {}
    _standbyGain = 0.0;
    await deck.setVolume(0.0);
    await deck.setAudioSources([source], initialIndex: 0, initialPosition: cue);
    final speed = _speed * rate;
    if ((deck.speed - speed).abs() > 1e-4) await deck.setSpeed(speed);
    if (_pitch != 1.0) {
      try {
        await deck.setPitch(_pitch);
      } catch (_) {}
    }
    if (_skipSilence) {
      try {
        await deck.setSkipSilenceEnabled(true);
      } catch (_) {}
    }
    // Same sequencing mode as the session deck, so the one-item window the
    // handoff leaves behind extends the way the old one did.
    final loop = _audioPlayer.loopMode;
    if (deck.loopMode != loop) await deck.setLoopMode(loop);
  }

  /// Starts the (already prepared, silent) standby deck.
  void playStandby() {
    _decks.standbyIfAny?.play().catchError((Object _) {});
  }

  /// Sets the two fade gains. 1.0 / 0.0 is "not mixing".
  void setDeckGains({required double active, required double standby}) {
    _activeGain = active.clamp(0.0, 1.0);
    _standbyGain = standby.clamp(0.0, 1.0);
    _applyGains().catchError((Object _) {});
  }

  /// Keeps the standby deck agreeing with the session deck about playing vs
  /// paused during a mix, so a pause (focus loss, the sleep timer, the button)
  /// takes both with it. The session deck is the one the listener controls:
  /// before the handoff it is the outgoing song, after it the incoming one, and
  /// the OTHER deck follows it either way.
  void mirrorDecks() {
    final standby = _decks.standbyIfAny;
    if (standby == null) return;
    final active = _audioPlayer;
    if (active.playing != standby.playing) {
      (active.playing ? standby.play() : standby.pause())
          .catchError((Object _) {});
    }
  }

  /// Makes the standby deck the session deck.
  ///
  /// A role swap, not a seek: nothing is re-buffered and no audio is rendered
  /// twice. The relays move to the new deck, so the rest of the app sees one
  /// continuous player whose item has changed - which is exactly what an
  /// ordinary gapless advance looks like to it.
  Future<void> swapDecks() async {
    final incoming = _decks.standbyIfAny;
    if (incoming == null) return;
    final head = incoming.sequence.isEmpty ? null : incoming.sequence.first;

    // The old head's retry loop must not wake up and reload the track that just
    // ended.
    _sourceEpoch++;
    cancelPendingRetry();

    _decks.swap();
    final g = _activeGain;
    _activeGain = _standbyGain;
    _standbyGain = g;

    _windowTracks = <String?>[null];
    _adoptHead(head);
    // Sequencing modes follow the listener, not the deck.
    final old = _decks.standbyIfAny;
    if (old != null && _audioPlayer.shuffleModeEnabled != old.shuffleModeEnabled) {
      await _audioPlayer.setShuffleModeEnabled(old.shuffleModeEnabled);
    }
    _attachFeeds(_decks.active);
    _publishMedia();
    _publishQueue();
    _publishSession();
  }

  /// Bookkeeping that tracks "the head": what a network retry would reload.
  void _adoptHead(IndexedAudioSource? head) {
    final tag = head?.tag;
    Uri? uri;
    if (head is UriAudioSource) {
      uri = head.uri;
    // ignore: experimental_member_use
    } else if (head is LockCachingAudioSource) {
      uri = head.uri;
    }
    _currentUrl = uri == null ? null : (uri.scheme == 'file' ? uri.toFilePath() : uri.toString());
    _isLocalFile = uri != null && uri.scheme == 'file';
    if (tag is MediaItem) {
      _lastTitle = tag.title;
      _lastArtist = tag.artist;
      _lastArtUri = tag.artUri?.toString();
      _lastId = tag.id;
    }
  }

  /// Ends the standby deck's part: silence it, release its decoder, and give
  /// the next transition a clean deck.
  Future<void> retireStandby() async {
    final deck = _decks.standbyIfAny;
    if (deck == null) return;
    _standbyGain = 0.0;
    try {
      await deck.setVolume(0.0);
      await deck.stop();
    } catch (_) {}
    await _applyGains();
  }

  /// Puts the session deck back to plain playback after a mix: full gain, and
  /// the listener's own speed (a beat-matched stretch is walked back).
  Future<void> settleActive() async {
    _activeGain = 1.0;
    await _applyGains();
    if ((_audioPlayer.speed - _speed).abs() > 1e-4) {
      await _audioPlayer.setSpeed(_speed);
    }
  }

  /// Sets the session deck's speed relative to the listener's own (1.0 = theirs).
  Future<void> setActiveRate(double rate) async {
    final target = _speed * rate;
    if ((_audioPlayer.speed - target).abs() > 1e-4) {
      await _audioPlayer.setSpeed(target);
    }
  }

  void dispose() {
    // FIX: Cancel all subscriptions before disposing
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    
    _decks.dispose();
    for (final relay in <DeckRelay<dynamic>>[
      _positionRelay,
      _durationRelay,
      _playingRelay,
      _stateRelay,
      _processingRelay,
      _volumeRelay,
      _indexRelay,
      _eventRelay,
    ]) {
      relay.dispose();
    }
    _onSkipToNextController.close();
    _onSkipToPreviousController.close();
    _onPlaybackErrorController.close();
  }
}


