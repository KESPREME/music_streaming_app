// lib/services/lyrics/lyric_clock_feed.dart
// Wires a [LyricClock] to the player.
//
// One place, so the two owners of a clock - the now-playing screen (the normal
// case: ONE clock shared by the lyric panel and the seek-bar strip) and a
// stand-alone lyrics screen - feed it identically. They used to each carry a
// copy of this plumbing, and the copies disagreed: one had a stall detector
// that stopped the clock on a guess, the other did not.
//
// WHAT FEEDS WHAT
//
//   position stream  -> clock.report   readings, dated on arrival
//   isPlaying        -> clock.setPlaying
//   seek events      -> clock.jump     an ANNOUNCED jump: the only thing allowed
//                                      to move the words backwards
//   track change     -> clock.reset
//   playback speed   -> clock.setSpeed
//
// There is deliberately NO stall detector. The old one stopped the clock after
// two 250ms polls with no movement, which fired on a buffering song or a slow
// stream and then relied on something else to restart a ticker that could not
// be restarted. Whether the song is moving is the player's to say (`isPlaying`);
// when it is playing but the readings stop advancing, the clock's steering
// absorbs it.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../providers/music_provider.dart';
import 'lyric_clock.dart';

class LyricClockFeed with WidgetsBindingObserver {
  LyricClockFeed({required this.clock, required this.provider});

  final LyricClock clock;
  final MusicProvider provider;

  StreamSubscription<Duration>? _positions;
  StreamSubscription<Duration>? _seeks;
  String? _trackId;
  bool _started = false;

  /// False while the app is not on screen (paused or hidden).
  ///
  /// The vsync ticker is muted by the scheduler then, but the clock's coarse
  /// timer is a plain `Timer.periodic` and is NOT: it kept waking the CPU ten
  /// times a second for as long as the song played with the screen off. So a
  /// backgrounded app is, to the clock, a paused song. The audio is untouched;
  /// the words simply stop being computed for nobody.
  ///
  /// `inactive` is not background: the app is still drawn (notification shade,
  /// split screen), and the words should keep moving there.
  bool _foreground = true;
  bool _observing = false;

  bool get _clockShouldRun => provider.isPlaying && _foreground;

  /// Begins feeding. Idempotent.
  void start() {
    if (_started) return;
    _started = true;

    _trackId = provider.currentTrack?.id;
    clock.reset(provider.position.inMilliseconds);
    clock.setSpeed(provider.playbackSpeed);
    clock.setPlaying(_clockShouldRun);
    clock.report(provider.position.inMilliseconds);

    _observe();

    _positions = provider.positionStream.listen(
      (position) {
        // Nothing is drawn in the background, and a reading to a paused clock
        // is published to its listeners. Resuming re-reads the player.
        if (_foreground) clock.report(position.inMilliseconds);
      },
      onError: (Object e) {
        if (kDebugMode) debugPrint('LyricClockFeed: position error: $e');
      },
    );
    _seeks = provider.seekEvents.listen((position) {
      clock.jump(position.inMilliseconds);
    });
    provider.addListener(_onProvider);
  }

  void _onProvider() {
    final id = provider.currentTrack?.id;
    if (id != _trackId) {
      // A new song: nothing about the old one's position means anything.
      _trackId = id;
      clock.reset(provider.position.inMilliseconds);
    }
    clock.setSpeed(provider.playbackSpeed);
    clock.setPlaying(_clockShouldRun);
  }

  void _observe() {
    if (_observing) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {
      // No binding (a plain unit test): there is no lifecycle to follow.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
    if (foreground == _foreground || !_started) return;
    _foreground = foreground;
    if (foreground) {
      // The player kept playing while nothing was drawn. Land on where it is
      // BEFORE the clock runs again, so the first frame back shows the right
      // line instead of the one the listener left.
      clock.jump(provider.position.inMilliseconds);
    }
    clock.setPlaying(_clockShouldRun);
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    provider.removeListener(_onProvider);
    _positions?.cancel();
    _seeks?.cancel();
    _positions = null;
    _seeks = null;
  }
}
