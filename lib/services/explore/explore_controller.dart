import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/explore/explore_engine.dart';
import 'package:music_streaming_app/services/explore/explore_policy.dart';
import 'package:music_streaming_app/services/explore/explore_session.dart';
import 'package:music_streaming_app/services/recommendation/taste_profile.dart';

/// Fetches one batch of candidate sources. [anchor] is the track the user
/// is currently on (seed chain); null on cold start.
typedef ExploreSourceFetcher = Future<ExploreSources> Function(Track? anchor);

/// Starts playback for [track] with [upcoming] as queue context.
typedef ExplorePlayer = Future<void> Function(
    Track track, List<Track> upcoming);

/// Artist-level implicit feedback sink (existing RecommendationService).
typedef ExploreSwipeFeedback = void Function(String artistName,
    {required bool wasAccepted});

/// Orchestrates the Explore stream: session state, autoplay-on-settle,
/// generation-race protection, refill and implicit feedback.
///
/// Playback itself is NOT owned here — [ExplorePlayer] routes into the
/// proven MusicProvider pipeline (spec: no second playback system).
class ExploreController extends ChangeNotifier {
  ExploreController({
    required ExploreEngine engine,
    required ExploreSourceFetcher fetchSources,
    required ExplorePlayer play,
    required TasteProfile Function() profileProvider,
    required ExploreSwipeFeedback recordSwipeOutcome,
    required bool Function(String trackId) isCurrentTrack,
    bool Function(String trackId)? isPlayingTrack,
    required void Function(bool enabled) onAutoplayChanged,
    this.autoplayEnabled = true,
    ExploreSession? existingSession,
  })  : _engine = engine,
        _fetchSources = fetchSources,
        _play = play,
        _profileProvider = profileProvider,
        _recordSwipeOutcome = recordSwipeOutcome,
        _isCurrentTrack = isCurrentTrack,
        _isPlayingTrack = isPlayingTrack,
        _onAutoplayChanged = onAutoplayChanged,
        _session = existingSession {
    _settledAt = _session?.active == null ? null : DateTime.now();
  }

  final ExploreEngine _engine;
  final ExploreSourceFetcher _fetchSources;
  final ExplorePlayer _play;
  final TasteProfile Function() _profileProvider;
  final ExploreSwipeFeedback _recordSwipeOutcome;
  final bool Function(String trackId) _isCurrentTrack;
  final bool Function(String trackId)? _isPlayingTrack;
  final void Function(bool enabled) _onAutoplayChanged;

  ExploreSession? _session;
  bool autoplayEnabled = true;
  bool _isLoading = false;
  bool _isRefilling = false;
  bool _exhausted = false;
  int _emptyStreak = 0;
  String? _error;
  int _playbackGeneration = 0;
  DateTime? _settledAt;
  DateTime? _lastSettledAt;

  ExploreSession? get session => _session;
  bool get isLoading => _isLoading;
  bool get isRefilling => _isRefilling;
  bool get exhausted => _exhausted;
  String? get error => _error;
  int get playbackGeneration => _playbackGeneration;
  Track? get activeTrack => _session?.active?.track;

  Future<void> start({Track? seed, bool forceNew = false}) async {
    // Restore (spec #122): an existing, non-exhausted session returns
    // as-is; an explicit new session request rebuilds (spec #68).
    if (_session != null && _session!.items.isNotEmpty && !_exhausted &&
        !forceNew) {
      return;
    }
    if (forceNew) {
      _session = null;
      _exhausted = false;
      _emptyStreak = 0;
    }
    final gen = ++_playbackGeneration;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final sources = await _fetchSources(seed);
      _session ??= ExploreSession(
        sessionId: DateTime.now().millisecondsSinceEpoch,
        startedAt: DateTime.now(),
        seed: seed,
      );
      final items = await _engine.generate(
        profile: _profileProvider(),
        sources: sources,
        seed: seed,
        exclude: _session!.shownItemIds,
        limit: ExplorePolicy.initialBatch,
        generation: _session!.generation,
      );
      _session!.appendBatch(items);
      if (_session!.items.isEmpty) {
        _exhausted = true;
        _error = 'Nothing new right now';
      }
      _isLoading = false;
      notifyListeners();
      // Autoplay page 0 for a fresh session (page-settle semantics).
      if (_session!.items.isNotEmpty && _session!.currentIndex < 0) {
        await settle(0);
      }
      debugPrint('EXPLORE_SESSION session=${_session!.sessionId} '
          'seed=${seed?.trackName ?? 'none'} candidates=${items.length} '
          'current=${_session!.currentIndex} '
          'remaining=${_session!.remaining.length} '
          'gen=$gen exhausted=$_exhausted');
    } catch (e) {
      _isLoading = false;
      _error = 'Could not load Explore';
      debugPrint('EXPLORE_SESSION start failed: $e');
      notifyListeners();
    }
  }

  /// THE hot path. Called when a page settles (never mid-drag).
  Future<void> settle(int index) async {
    final s = _session;
    if (s == null || s.items.isEmpty) return;
    if (index == s.currentIndex) return; // rebuild — no restart (spec #5)
    if (index < 0 || index >= s.items.length) return;

    // Implicit swipe feedback for the page just left (spec #52 — gentle).
    final prev = s.active;
    if (prev != null && _lastSettledAt != null) {
      final dwell = DateTime.now().difference(_lastSettledAt!);
      _recordSwipeOutcome(
        prev.track.artistName.split(',').first.trim(),
        wasAccepted:
            dwell.inSeconds >= ExplorePolicy.skipDwellSeconds,
      );
    }

    s.advanceTo(index);
    _settledAt = DateTime.now();
    _lastSettledAt = _settledAt;
    notifyListeners();

    final item = s.active!;
    final gen = ++_playbackGeneration;

    if (!autoplayEnabled) {
      debugPrint('EXPLORE_ITEM rank=$index title=${item.track.trackName} '
          'reason=${item.reason} score=${item.score.toStringAsFixed(2)} '
          'autoplay=off');
      return;
    }

    final isAlreadyPlaying = _isCurrentTrack(item.track.id) &&
        (_isPlayingTrack?.call(item.track.id) ?? true);
    if (isAlreadyPlaying) {
      // Same track already actively playing — never restart mid-stride.
      debugPrint('EXPLORE_PREFETCH prepared=[$index] mediaResolved=skip '
          'already-playing');
      return;
    }

    final upcoming =
        s.upcoming(count: 4).map((i) => i.track).toList();
    try {
      debugPrint('EXPLORE_PLAY title=${item.track.trackName} gen=$gen');
      await _play(item.track, upcoming);
      if (gen != _playbackGeneration) return;
      debugPrint('EXPLORE_ITEM rank=$index title=${item.track.trackName} '
          'artist=${item.track.artistName} reason=${item.reason.name} '
          'score=${item.score.toStringAsFixed(2)} '
          'confidence=${item.confidence.toStringAsFixed(2)}');
    } catch (e) {
      if (gen == _playbackGeneration) {
        _error = 'Playback failed — swipe to continue';
        debugPrint('EXPLORE_ITEM play failed: $e');
      }
    }
    if (gen != _playbackGeneration) return;
    notifyListeners();
    await _maybeRefill();
  }

  Future<void> _maybeRefill() async {
    final s = _session;
    if (s == null || _isRefilling || _exhausted || !s.needsRefill) return;
    _isRefilling = true;
    notifyListeners();
    try {
      // 1. Pick a seed track from recent unexhausted items to avoid hammering an anchor with no related songs
      Track? anchor = s.active?.track;
      if (anchor == null || _emptyStreak > 0) {
        final candidates = s.items.reversed.take(6).map((i) => i.track).toList();
        if (candidates.isNotEmpty) {
          anchor = candidates[_emptyStreak % candidates.length];
        }
      }
      anchor ??= s.seed;

      var sources = await _fetchSources(anchor);
      // Sliding exclusion window: keep recent 60 items so very long sessions (e.g. 50+ songs)
      // do not permanently starve due to candidate pool exhaustion.
      final excludeSet = s.shownItemIds.length > 60
          ? s.shownItemIds.skip(s.shownItemIds.length - 60).toSet()
          : s.shownItemIds;

      var items = await _engine.generate(
        profile: _profileProvider(),
        sources: sources,
        seed: null,
        exclude: excludeSet,
        limit: ExplorePolicy.refillBatch,
        generation: s.generation,
      );

      if (items.isEmpty) {
        _emptyStreak++;
        if (_emptyStreak >= 2) {
          _exhausted = true;
          debugPrint('EXPLORE_SESSION sources exhausted '
              'shown=${s.shownItemIds.length}');
        }
      } else {
        _emptyStreak = 0;
        _exhausted = false;
        s.appendBatch(items);
      }
      debugPrint('EXPLORE_PREFETCH prepared=[${s.remaining.length} ahead] '
          'refill=${items.length} remaining=${s.remaining.length} '
          'exhausted=$_exhausted');
    } catch (e) {
      // Network hiccup: keep the session alive; refill retries next settle.
      debugPrint('EXPLORE_PREFETCH refill failed: $e');
    } finally {
      _isRefilling = false;
    }
    notifyListeners();
  }

  /// Start a meaningfully new session (spec #68) — anchored on the
  /// current active track when present.
  Future<void> refresh() async {
    final seed = activeTrack ?? _session?.seed;
    await start(seed: seed, forceNew: true);
  }

  void toggleAutoplay() {
    autoplayEnabled = !autoplayEnabled;
    _onAutoplayChanged(autoplayEnabled);
    notifyListeners();
  }

  /// Explicit negative feedback (spec #46): record + move on. The item
  /// cannot reappear this session (shown-set) either way.
  Future<void> dislikeCurrent() async {
    final item = _session?.active;
    if (item == null) return;
    _recordSwipeOutcome(
        item.track.artistName.split(',').first.trim(),
        wasAccepted: false);
    debugPrint('EXPLORE_SKIP title=${item.track.trackName} '
        'artist=${item.track.artistName.split(',').first.trim()}');
    final next = (_session!.currentIndex + 1);
    if (next < _session!.items.length) {
      await settle(next);
    }
  }

  /// Surface for tests/diagnostics.
  Set<String> get shownItemIds => _session?.shownItemIds ?? const {};
  List<Track> upcomingTracks({int count = ExplorePolicy.prefetchAhead}) =>
      _session?.upcoming(count: count).map((i) => i.track).toList() ??
      const [];

  /// Triggers background refill of the candidate stream when near end of loaded items.
  Future<void> maybeRefill() => _maybeRefill();

  @visibleForTesting
  Future<void> maybeRefillForTest() => _maybeRefill();

  @visibleForTesting
  void debugForceDwell(Duration dwell) =>
      _lastSettledAt = DateTime.now().subtract(dwell);
}
