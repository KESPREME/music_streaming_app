// lib/screens/lyrics_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/app_image_cache.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/music_provider.dart';
import '../models/track.dart';
import '../models/lyrics_entry.dart';
import '../services/lyrics/lyric_sub_line.dart';
import '../services/lyrics/lyrics_translation_service.dart';
import '../services/lyrics/lyric_clock.dart';
import '../services/lyrics/lyric_sweep.dart';
import '../widgets/lyric_swept_line.dart';
import '../utils/color_utils.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/lyrics_mode_discs.dart';
import '../widgets/audio_quality_language_sheet.dart';
import '../widgets/thin_slider.dart';
import '../utils/image_quality_utils.dart';

/// Real-time Animated Kinetic Lyrics Screen matching Image 2 with Apple Music liquid glass design.
class LyricsScreen extends StatefulWidget {
  final VoidCallback? onMinimize;
  final Function(int)? onTabTap;
  final VoidCallback? onReturnToAlbum;
  final bool isEmbedded;
  final bool showHeader;
  final bool showBottomScrubber;

  /// Controls for the footer row. All optional: when they are all null the row
  /// is not rendered at all, which is what the standalone variant wants.
  ///
  /// Track actions are deliberately NOT here. The star and the options menu
  /// belong to the track rather than to the lyric, and they live in the player
  /// header so they stay reachable from the artwork page. The list is padded
  /// clear of them instead, which is a smaller change than relocating a control
  /// that has to work in two places.
  final VoidCallback? onFavorite;
  final bool isFavorite;
  final VoidCallback? onOptions;

  /// Whether a translation target has been chosen.
  final bool canTranslate;

  /// Logical pixels of space to keep clear at the foot of the list.
  ///
  /// The player deck is drawn ABOVE this screen as a separate overlay, because
  /// that overlay is what the artwork-to-lyrics flight depends on. The list has
  /// no way to know it is there, so without this it scrolls its last lines
  /// underneath the scrubber - the one thing a lyric view must never do.
  ///
  /// Passed as a plain number rather than a listenable so the caller decides when
  /// to rebuild; the measurement already de-jitters, so there is nothing to
  /// resolve per frame.
  final double bottomInset;

  /// Ties the sub-line to a track, so a transform belonging to the previous song
  /// can never be painted under this one.
  final String? trackKey;

  /// Language the translation targets. Null falls back to the platform locale.
  final String? translationLanguage;

  /// Lets the caller own the discs' visibility from outside.
  ///
  /// BitChord parks the two mode discs WITH the player chrome: they open when the
  /// scrubber is up and close as soon as the chrome fades for stillness, with the
  /// SAME timer, from the SAME tap. Standing up a second, independent idle timer
  /// here let them disagree - exactly how they once sat on the screen while the
  /// player had already gone away.
  ///
  /// Null means "no caller opinion": the panel falls back to its local one-shot
  /// timer (`_discsVisible`), which is what the stand-alone previews and tests use.
  final bool? chromeHidden;

  const LyricsScreen({
    super.key,
    this.onMinimize,
    this.onTabTap,
    this.onReturnToAlbum,
    this.isEmbedded = false,
    this.showHeader = true,
    this.showBottomScrubber = true,
    this.onFavorite,
    this.isFavorite = false,
    this.onOptions,
    this.canTranslate = false,
    this.bottomInset = 0,
    this.trackKey,
    this.translationLanguage,
    this.chromeHidden,
  });

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

int _currentLineIndex = 0;

  /// True while the reader is dragging the lyric by hand.
  ///
  /// This is the "browsing" state: blur goes to zero and the alpha ladder
  /// flattens, so every line of the song can be read while the finger is down.
  ///
  /// It must be a FINGER, never "the list is moving". The old trigger read
  /// `position.isScrollingNotifier`, which our own `animateScrollBy` also flips -
  /// so every line handover announced itself as a browse, cleared the blur and
  /// switched the auto-follow off for the whole resume window. The panel was
  /// disabling itself once per line. See [_handleScrollNotification].
  bool _isUserScrolling = false;
  bool _autoScrollEnabled = true;
  Timer? _correctTimer;
  StreamSubscription<Duration>? _positionSub;
  late LyricClock _clock;

  /// Holds the translated / romanized sub-line and its reveal.
  ///
  /// Owned by the screen rather than by the caller so the reveal has a home for
  /// its timers. The CALLER owns the fetch decision - the discs are outside this
  /// widget - which is why it is handed in rather than created here.
  final SubLineController _subController = SubLineController();
  SubLineController get subController => _subController;

  /// Whether the mode discs are on screen.
  ///
  /// They start visible and leave after [lyricsDiscIdleTimeout] of no touching.
  /// The alternative - pinning them permanently - is a control sitting on the
  /// words for a reader who never asked for it.
  bool _discsVisible = true;
  Timer? _discIdleTimer;

  /// Restarts the discs' idle countdown.
  void _pokeDiscs() {
    if (!_discsVisible && mounted) setState(() => _discsVisible = true);
    _discIdleTimer?.cancel();
    _discIdleTimer = Timer(lyricsDiscIdleTimeout, () {
      if (!mounted) return;
      setState(() => _discsVisible = false);
    });
  }

  /// Brings the discs back after a tap in the lower half of the panel.
  ///
  /// Only while they are away. With them on screen this is not registered at all,
  /// so the list scrolls off its own slop as usual and a tap on a line keeps
  /// meaning "seek to this line".
  void _revealDiscsOnTap() {
    if (_discsVisible) return;
    _pokeDiscs();
  }

  /// The transform line for lyric [index], or null when none is showing.
  ///
  /// Returns null for the wrong track and for a length mismatch rather than
  /// guessing: a sub-line under the wrong lyric is worse than no sub-line, and
  /// nothing about that is recoverable by looking at it.
  String? _subLineAt(int index) {
    if (_subController.shownMode == SubLineMode.original) return null;
    if (_subController.progress <= 0) return null;
    final lines = _subController.lines;
    final current = _lyricsRef;
    if (lines == null || current == null) return null;
    if (lines.length != current.length) return null;
    if (index < 0 || index >= lines.length) return null;
    return lines[index];
  }
  /// The list the per-line state below has been made to match.
  List<LyricsEntry>? _syncedLyrics;

  int _lastReportedMs = -1;
  int _stalledTicks = 0;
  String? _currentTrackId;

  late AnimationController _fadeController;
  final List<GlobalKey> _itemKeys = [];

@override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // The clock is created here, not in a post-frame callback. The first build
    // already renders every visible lyric line, and each of them reads the
    // clock - deferring creation to after the first frame left that build
    // reading an uninitialised late field.
    _clock = LyricClock(vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLyrics();
      _fadeController.forward();
    });

    }

  /// No offset listener on purpose.
  ///
  /// An earlier version watched `position.isScrollingNotifier` and treated any
  /// movement as a browse. That is what made the panel's own follow turn the
  /// browse on once per line. The state is now driven entirely by
  /// [_handleScrollNotification], which can tell a finger from an animation.
  @override
void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<MusicProvider>(context, listen: false);
    final track = provider.currentTrack;

    // The clock exists from initState; the stream subscription needs a
    // resolved provider, so it is wired the first time dependencies are
    // available. Guarded because didChangeDependencies runs more than once.
    _startPositionUpdates();

    if (track != null && _currentTrackId != track.id) {
      final wasNull = _currentTrackId == null;
      _currentTrackId = track.id;
      _currentLineIndex = 0;
      _itemKeys.clear();
      // Dropped so the next build re-adopts for this track even if it happens to
      // be handed the very same list object.
      _syncedLyrics = null;
      _clock.resync(0);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          provider.fetchLyrics(forceRefresh: !wasNull);
        }
      });
    }
  }

  @override
  void didUpdateWidget(LyricsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Drop the sub-line on a track change, HERE rather than in the caller: this
    // widget owns the controller because it owns the reveal timers that go with
    // it. A transform belonging to the previous song must never be painted under
    // this one, and the mode resets with it - leaving it on "translated" would
    // label the originals as a translation.
    final next = widget.trackKey;
    if (next != null && next != oldWidget.trackKey) {
      _subController.onTrackChanged(next);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _discIdleTimer?.cancel();
    _positionSub?.cancel();
    _correctTimer?.cancel();
    _clock.dispose();
    _subController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _checkLyrics() {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    if (provider.currentTrack != null) {
      _currentTrackId = provider.currentTrack!.id;
      if (!provider.hasSyncedLyrics || provider.currentLyrics == null) {
        provider.fetchLyrics();
      }
      // No else branch. The list is adopted by identity in the build that renders
      // it, which is the only place that knows whether it is a new list or the
      // same one - re-syncing keys here would fire on every unrelated rebuild.
    }
  }

  void _ensureKeys(int count) {
    if (_itemKeys.length != count) {
      _itemKeys.clear();
      for (var i = 0; i < count; i++) {
        _itemKeys.add(GlobalKey());
      }
    }
  }

  /// Runs the clock when there is something to animate and stops it when there is
  /// not. Idempotent, and deliberately callable from the loading branch too.
  void _reconcileClock(MusicProvider provider) {
    final lyrics = provider.currentLyrics;
    if (lyrics != null && lyrics.isNotEmpty) {
      if (!_clock.isRunning) _clock.start();
    } else if (_clock.isRunning) {
      _clock.stop();
    }
  }

  /// Brings the per-line state into line with [lyrics] when the LIST changes.
  ///
  /// Changing provider changes the words, not the song, so `didChangeDependencies`
  /// - which resets everything only when the track id moves - never sees it. The
  /// active line is an INDEX into the list, so an index carried across from a
  /// different lyric points at a different line, and `_syncActiveLine` cannot
  /// repair it: it returns early precisely when the new active line happens to
  /// equal the stale one. So it is repaired here instead.
  ///
  /// Recomputed from the clock's own position rather than reset to zero, because
  /// the player has not moved. Resetting to zero would scroll the panel back to
  /// the top of the song mid-track.
  void _adoptLyrics(List<LyricsEntry>? lyrics) {
    // Kept so the auto-scroll can aim at the line the clock is about to reach
    // rather than only the one being sung.
    _lyricsRef = lyrics;

    if (identical(_syncedLyrics, lyrics)) return;
    _syncedLyrics = lyrics;

    // Keys are per line, so a list of any different length invalidates them all.
    _ensureKeys(lyrics?.length ?? 0);

    final positionMs = _clock.positionMs;
    final active = lyrics == null || lyrics.isEmpty
        ? 0
        : activeLineIndex(lyrics, positionMs);
    _currentLineIndex = active < 0 ? 0 : active;
  }

/// How long the reader has to be still before the browse gives way.
  ///
  /// 600ms is the reference's short answer, used while the singing is still on
  /// screen. 5s is its fallback, used when the reader has parked the list
  /// somewhere the song has left - snapping back then is the wrong answer.
  static const Duration _browseResumeOnScreen = Duration(milliseconds: 600);
  static const Duration _browseResumeFallback = Duration(seconds: 5);

  /// How often the panel re-reads the player, which is also the tick the browse's
  /// idle budget is counted on.
  static const Duration _correctionPeriod = Duration(milliseconds: 250);

  /// How long the reader has been still, counted on [_correctionPeriod].
  Duration _browseIdleMs = Duration.zero;

  /// The resume window that applies right now.
  Duration get _browseResumeLimitForCurrentPosition {
    final lyrics = _lyricsRef;
    if (lyrics == null || lyrics.isEmpty) return _browseResumeOnScreen;
    final index = _currentLineIndex;
    if (index < 0 || index >= _itemKeys.length) return _browseResumeFallback;
    final box = _itemKeys[index].currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return _browseResumeFallback;
    final position = box.localToGlobal(Offset.zero);
    final viewport = _scrollController.hasClients
        ? _scrollController.position
        : null;
    if (viewport == null) return _browseResumeFallback;
    final onScreen = position.dy >= 0 &&
        position.dy <= viewport.viewportDimension * 0.8;
    return onScreen ? _browseResumeOnScreen : _browseResumeFallback;
  }

  /// Enters the browse state.
  ///
  /// Separate from [_handleScrollNotification] so the tick that ends the browse
  /// and the notification that starts it cannot be confused for one another.
  void _enterBrowse() {
    if (_isUserScrolling) return;
    setState(() {
      _isUserScrolling = true;
      _autoScrollEnabled = false;
    });
  }

  /// Leaves the browse state.
  ///
  /// Deliberately does NOT scroll. The reader moved the list on purpose and half a
  /// second of stillness is not them changing their mind; yanking them back to the
  /// singing line is what made the old resume feel like a fight. The next line
  /// change re-arms the follow.
  void _exitBrowse() {
    if (!_isUserScrolling) return;
    setState(() {
      _isUserScrolling = false;
      _autoScrollEnabled = true;
      _browseIdleMs = Duration.zero;
    });
  }

  /// Ends the browse once the finger has been off the glass long enough.
  /// Arms the end of a browse.
  ///
  /// No `isPlaying` guard, and deliberately so. The reference suppresses its own
  /// resume while paused because a paused panel there still tracks the clock; ours
  /// cannot - [LyricClock] stops when the song stops moving, so a paused panel has
  /// nothing to follow and there is nothing to yank the reader back to. The guard
  /// only ever made the resume refuse to arm.
  ///
  /// The idle time is counted on [_correctTimer] rather than in a [Timer] of its
  /// own. A timer armed from inside a scroll-notification dispatch is scheduled
  /// outside the binding's fake-async zone, so it does not fire under
  /// `flutter test` at all - and a resume that cannot be observed is a resume that
  /// cannot be trusted. One clock, one place, no second timer to leak.
  void _noteBrowseActivity() {
    if (!_isUserScrolling) return;
    _browseIdleMs = Duration.zero;
  }

  /// Ticks the browse's idle budget down. Called from [_correctTimer].
  void _advanceBrowseIdle() {
    if (!_isUserScrolling) {
      _browseIdleMs = Duration.zero;
      return;
    }
    _browseIdleMs += _correctionPeriod;
    if (_browseIdleMs < _browseResumeLimitForCurrentPosition) return;
    _exitBrowse();
  }

  /// Distinguishes a finger from our own scroll animation.
  ///
  /// `dragDetails` is non-null only for a user gesture; a programmatic
  /// `animateTo` or `jumpTo` dispatches the same notification classes with no
  /// drag attached. That single null check is the whole difference between "the
  /// reader is looking around" and "the panel is following the song".
  ///
  /// It is declared per concrete class rather than against [ScrollNotification]
  /// because the field lives on each subclass, not on the base.
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails == null) return false;
      _enterBrowse();
      return false;
    }

    // The browse is timed from the LAST SCROLL ACTIVITY, not from one end event.
    //
    // Keying it to `ScrollEndNotification` alone meant the whole resume hinged
    // on a single class arriving: miss it - a physics simulation that ends
    // quietly, a nested scroll, a gesture the list never won - and the panel
    // stayed in browsing mode for the rest of the song with every line
    // unblurred. Re-arming on anything that moves is both simpler and what a
    // reader expects: stop touching it, and it comes back.
    if (_isScrollActivity(notification)) _noteBrowseActivity();
    // Never consume: the list still needs to see every notification of its own.
    return false;
  }

  /// Whether [notification] says the finger is still moving the list.
  static bool _isScrollActivity(ScrollNotification notification) =>
      notification is ScrollUpdateNotification ||
      notification is OverscrollNotification ||
      notification is ScrollEndNotification;

  /// Whether the line being sung is inside the viewport right now.
  ///
  /// Decides which resume window applies: the short one is only honest when the
  /// reader has not parked the list somewhere the singing has left.
  bool _activeLineVisible() {
    if (!_scrollController.hasClients) return false;
    final lyrics = _lyricsRef;
    if (lyrics == null || lyrics.isEmpty) return true;
    final index = _currentLineIndex;
    if (index < 0 || index >= _itemKeys.length) return true;
    final box = _itemKeys[index].currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return true;
    final position = box.localToGlobal(Offset.zero);
    final viewport = _scrollController.position;
    return position.dy >= viewport.viewportDimension * 0.02 &&
        position.dy <= viewport.viewportDimension * 0.72;
  }

void _startPositionUpdates() {
    if (_positionSub != null) return;
    final provider = Provider.of<MusicProvider>(context, listen: false);
    // The clock subscribes to the player's position stream and interpolates
    // between readings on the display's own tick.
    //
    // This replaces a 16ms Timer.periodic that called setState on the screen,
    // which rebuilt every visible line sixty times a second for the whole song.
    // positionStream itself is far too coarse to drive a wipe (it emits every
    // ~200ms and unevenly), so it feeds the clock rather than replacing it.
    _positionSub = provider.positionStream.listen((pos) {
      if (!mounted) return;
      _clock.report(pos.inMilliseconds, rate: provider.playbackSpeed);
      _syncActiveLine(_clock.positionMs);
    });

    // A coarse correction, not a driver. The clock's own ticker provides the
    // smoothness; this only keeps the anchor honest when the stream is silent -
    // while paused, or between readings - and it is the thing that lets a seek
    // land even if no position event accompanies it.
    //
    // It is also what decides whether the clock is allowed to run at all. A
    // ticker that fires while the song is standing still schedules a frame
    // every 16ms for nothing, so the screen never goes idle. Two consecutive
    // corrections with no movement means the song is not advancing, and the
    // clock stops rather than animating a highlight that cannot move.
    _correctTimer = Timer.periodic(_correctionPeriod, (_) {
      if (!mounted) return;

      // The browse's idle budget rides this tick rather than a timer of its own.
      _advanceBrowseIdle();

      final reported = provider.position.inMilliseconds;

      if (reported == _lastReportedMs) {
        _stalledTicks++;
        if (_stalledTicks >= 2 && _clock.isRunning) {
          _clock.stop();
          return;
        }
      } else {
        _stalledTicks = 0;
        _lastReportedMs = reported;
        if (!_clock.isRunning && _lyricsRef != null && _lyricsRef!.isNotEmpty) {
          _clock.start();
        }
      }

      _clock.report(reported, rate: provider.playbackSpeed);
      _syncActiveLine(_clock.positionMs);
    });
  }

  /// Advances the active-line index, rebuilding only when it actually moves.
  void _syncActiveLine(int positionMs) {
    final lyrics = Provider.of<MusicProvider>(context, listen: false).currentLyrics;
    if (lyrics == null || lyrics.isEmpty) return;

    final active = activeLineIndex(lyrics, positionMs);
    if (active == _currentLineIndex) {
      // No rebuild. This is the whole reason position ticks are cheap: the list
      // is only rebuilt when the active line actually changes, roughly once per
      // line rather than sixty times a second.
      return;
    }

    _ensureKeys(lyrics.length);
    setState(() {
      _currentLineIndex = active;
    });

    if (_autoScrollEnabled && !_isUserScrolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrentLine();
      });
    }
  }

  void _onLineTap(int index, List<LyricsEntry> lyrics) {
    if (index < 0 || index >= lyrics.length) return;

    final entry = lyrics[index];
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    HapticFeedback.lightImpact();
    musicProvider.seekTo(Duration(milliseconds: entry.timeMs));

    setState(() {
      _currentLineIndex = index;
      _autoScrollEnabled = true;
      _isUserScrolling = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentLine());
  }

/// Moves the list so the line the reader is about to need sits where the eye
  /// already is.
  ///
  /// Two things were wrong here. It scrolled to [_currentLineIndex] - the line
  /// ALREADY being sung - and computed the lead index into a local that only a
  /// dead fallback branch read, so the lead never happened. And the duration was
  /// a fixed 400ms, so the list finished its move at a different moment from the
  /// silence it was supposed to fill.
  ///
  /// Now: target the lead line, take the duration from the gap the move is
  /// covering, and land the target at the top of the viewport. BitChord anchors
  /// at `scrollOffset = 0` for the same reason - the line under the singer's
  /// mouth is the one that has just gone, and the eye wants the one arriving.
  void _scrollToCurrentLine() {
    if (!_scrollController.hasClients) return;
    final target = _scrollTargetIndex;
    if (target < 0 || target >= _itemKeys.length) return;
    _animateLineToView(target, 0);
  }

  /// How many extra passes [_animateLineToView] may take to land exactly.
  ///
  /// A lazy list has not built the rows outside its viewport, so a jump - a
  /// seek, or anything above the first built row - has no box to measure. One
  /// estimated pass gets the list close enough that the target builds, and the
  /// next pass is exact. Two is enough; a third would be a layout loop wearing a
  /// scroll's clothes.
  static const int _maxRefinePasses = 2;

  /// Scrolls so [target] lands at the top of the list's content box.
  ///
  /// Self-correcting, because "land at the top" is only measurable once the
  /// row exists. Silently doing nothing when it did not - which is what a plain
  /// `ensureVisible` on an unbuilt key does - is how a backward seek used to
  /// leave the list stranded on the wrong verse with nothing to show for it.
  void _animateLineToView(int target, int pass) {
    if (!mounted || !_scrollController.hasClients) return;

    final offset = _targetOffsetFor(target);
    final duration = pass == 0 ? _scrollRunUp : _lyricSettle;
    if (duration == Duration.zero) {
      _scrollController.jumpTo(offset);
      return;
    }

    // `animateTo` on the offset rather than `ensureVisible` on the context.
    //
    // `ensureVisible` composes with whatever animation is already in flight and
    // resolves the target from the widget's own box, so a handover that arrived
    // mid-move inherited the previous move's geometry. One offset, one curve,
    // one duration: the handover reads as a single movement.
    _scrollController
        .animateTo(offset, duration: duration, curve: _lyricEase)
        .whenComplete(() {
      if (!mounted || pass >= _maxRefinePasses) return;
      // One frame later, not now: the row only gets laid out - and only gets a
      // BuildContext - on the next frame's layout pass. Refining in this frame
      // would measure a row that does not exist yet and give up.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || pass >= _maxRefinePasses) return;
        if (_itemKeys[target].currentContext == null) return;
        final exact = _targetOffsetFor(target);
        if ((exact - _scrollController.offset).abs() > 1.0) {
          _animateLineToView(target, pass + 1);
        }
      });
    });
  }

  /// A best guess for where [target] sits, for a row the list has not built.
  ///
  /// The mean PITCH - row height plus the gap - of the rows that are laid out,
  /// times the index. Lyric rows run from one line to three, so this is wrong by
  /// a row or two, which is exactly why [_animateLineToView] re-measures and
  /// corrects rather than trusting it.
  double _estimatedOffsetFor(int target) {
    final position = _scrollController.position;
    var pitchTotal = 0.0;
    var counted = 0;
    for (final key in _itemKeys) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      pitchTotal += box.size.height + _rowGap;
      counted++;
    }
    final pitch = counted == 0 ? _assumedRowPitch : pitchTotal / counted;
    return (target * pitch).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  /// Row pitch used before anything has been measured.
  ///
  /// One line of 28dp type at 1.25 line height, plus the row gap.
  static const double _assumedRowPitch = 63.0;

  /// Offset that puts [target] at the top of the list's own content box.
  ///
  /// `ensureVisible`'s `alignment` is a fraction of the VIEWPORT, which is why
  /// 0.32 looked reasonable and was not: it parked the sung line a third of the
  /// way down and pushed everything the reader had not reached yet toward the
  /// bottom edge.
  /// Offset that puts [target] at the top of the list's own content box.
  ///
  /// Falls back to [_estimatedOffsetFor] when the row is not built. Both callers
  /// are guarded on `mounted`, which is also why this takes an INDEX rather than
  /// a [BuildContext]: a context cannot cross the animation's async gap.
  double _targetOffsetFor(int target) {
    final contextOfItem = _itemKeys[target].currentContext;
    if (contextOfItem == null) return _estimatedOffsetFor(target);
    return _topAnchorOffsetFor(contextOfItem);
  }

  /// Measures [target] against the LIST, not against the screen.
  ///
  /// A row's y is measured from the screen, but `pixels` is measured from the
  /// start of the scrollable's content. Mixing the two leaves the screen's own
  /// offset - the status bar, and whatever the panel reserves above the list -
  /// baked into the answer, so every handover landed tens of pixels high and a
  /// jump landed hundreds. The arithmetic itself is [topAnchorOffset].
  double _topAnchorOffsetFor(BuildContext contextOfItem) {
    final box = contextOfItem.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return _scrollController.offset;
    final row = box.localToGlobal(Offset.zero);
    final listBox = _listKey.currentContext?.findRenderObject();
    final listTop =
        listBox is RenderBox ? listBox.localToGlobal(Offset.zero).dy : 0.0;
    final viewport = _scrollController.position;
    return topAnchorOffset(
      currentPixels: viewport.pixels,
      rowTopInViewport: row.dy - listTop,
      topInset: _listTopPadding,
      minScrollExtent: viewport.minScrollExtent,
      maxScrollExtent: viewport.maxScrollExtent,
    );
  }

  /// The list itself, for measuring rows against it rather than against zero.
  final GlobalKey _listKey = GlobalKey(debugLabel: 'lyricList');

  /// The top inset the list lays its first row out under.
  ///
  /// Kept as a constant beside the padding it describes rather than derived, so
  /// the anchor and the padding cannot drift apart.
  static const double _listTopPadding = 56.0;

  /// Fraction of the panel's own height reserved below the last lyric line.
  ///
  /// BitChord `PlayerLyrics.kt:1796`.
  static const double _tailViewportFraction = 0.8;

  /// Vertical margin around every lyric row.
  ///
  /// Named here because the offset estimate adds it per row: forgetting it makes
  /// the estimate short by a row every line, which is most of a screen by the
  /// bottom of a verse.
  static const double _rowGap = 28.0;

  /// How long the move to the lead line should take.
  ///
  /// The gap it is covering, clamped to [scrollLeadMs]'s bounds. The silence
  /// between two lines is a held breath in one song and half a verse in another,
  /// so a fixed duration either rushes the catch-up or drags behind the vocal.
  /// Zero when the target is already in place, so no animation is started that
  /// has nothing to do.
  Duration get _scrollRunUp {
    if (!_activeLineNeedsScroll) return Duration.zero;
    final lyrics = _lyricsRef;
    if (lyrics == null || lyrics.isEmpty) return _lyricSettle;
    final lead = scrollLeadMs(lyrics, _clock.positionMs);
    return Duration(milliseconds: lead);
  }

  /// Whether the lead line is far enough off to be worth animating to.
  ///
  /// Within a line's own height the list is already showing it; moving would
  /// read as a twitch on every single word.
  bool get _activeLineNeedsScroll {
    final target = _scrollTargetIndex;
    if (target < 0 || target >= _itemKeys.length) return false;
    if (target == _currentLineIndex) {
      // Same line as last time: only move if it has drifted off screen.
      return !_activeLineVisible();
    }
    return true;
  }

  /// The line the scroll should land on, which LEADS the singing.
  ///
  /// Brightness and motion are deliberately two different indices: the highlight
  /// must never run ahead of what is actually being sung, but the list may.
  /// [focusLineIndex] computes the lead with [scrollLeadMs].
  int get _scrollTargetIndex {
    final lyrics = _lyricsRef;
    if (lyrics == null || lyrics.isEmpty) return _currentLineIndex;
    final focused = focusLineIndex(lyrics, _clock.positionMs);
    return focused >= 0 ? focused : _currentLineIndex;
  }

  List<LyricsEntry>? _lyricsRef;

  /// ONE easing for every lyric motion: blur, alpha, scale, scroll.
  ///
  /// BitChord uses the same cubic for all four so a handover reads as one
  /// movement rather than four things settling at slightly different rates
  /// (PlayerLyrics.kt:365-368). Monotonic, no overshoot - invariant 16.
  static const Curve _lyricEase = Cubic(0.41, 0.0, 0.12, 0.99);

  /// How long a lyric dimension takes to settle.
  ///
  /// Blur, alpha and scale all move together on this.
  static const Duration _lyricSettle = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final track = musicProvider.currentTrack;
    final palette = musicProvider.paletteGenerator;
    final accentColor = ColorUtils.getVibrantAccent(
      palette,
      const Color(0xFFE89838),
    );

    final Widget mainContent = Column(
      children: [
        if (track != null && widget.showHeader)
          _buildTopMiniTrackHeader(
            context,
            track,
            musicProvider,
            accentColor,
          )
        else if (widget.isEmbedded)
          SizedBox(height: MediaQuery.of(context).padding.top + 90.0),
        Expanded(
          child: _buildLyricsBody(context, musicProvider, accentColor),
        ),
        if (widget.showBottomScrubber)
          _buildBottomMiniPlayerScrubber(
            context,
            musicProvider,
            accentColor,
          ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: widget.isEmbedded
          ? mainContent
          : Stack(
              children: [
                // 1. Blurred album art background (only when standalone)
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFF08080A)),
                ),
                if (track != null && track.albumArtUrl.isNotEmpty)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: ClipRect(
                        child: Transform.scale(
                          scale: 1.25,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: 65,
                              sigmaY: 65,
                            ),
                            child: SizedBox.expand(
                              child: _buildAlbumArtImage(track),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.black.withValues(alpha: 0.65),
                          Colors.black.withValues(alpha: 0.85),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildPullHandle(context),
                      Expanded(child: mainContent),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPullHandle(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        HapticFeedback.lightImpact();
        if (widget.onMinimize != null) {
          widget.onMinimize!();
        } else if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: Center(
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 6),
          width: 38,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }

  Widget _buildTopMiniTrackHeader(
    BuildContext context,
    Track track,
    MusicProvider provider,
    Color accentColor,
  ) {
    final isLiked = provider.isSongLiked(track.id);
    final topPadding = widget.isEmbedded
        ? (MediaQuery.of(context).padding.top + 32.0)
        : 6.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, 8),
      child: Row(
        children: [
          // Album art thumbnail (tapping returns to normal album view)
          GestureDetector(
            key: const ValueKey('now_playing_album_art'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              if (widget.onReturnToAlbum != null) {
                widget.onReturnToAlbum!();
              } else if (widget.onTabTap != null) {
                widget.onTabTap!(0);
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 46,
                height: 46,
                child: _buildAlbumArtImage(track),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Title & Artist (tapping returns to normal album view)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                if (widget.onReturnToAlbum != null) {
                  widget.onReturnToAlbum!();
                } else if (widget.onTabTap != null) {
                  widget.onTabTap!(0);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.trackName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artistName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // Star button (Favorite)
          _buildCircleButton(
            icon: isLiked ? Icons.star_rounded : Icons.star_outline_rounded,
            iconColor: isLiked ? accentColor : Colors.white,
            semanticLabel: 'Favorite',
            onTap: () {
              HapticFeedback.lightImpact();
              provider.toggleLike(track);
            },
          ),

          const SizedBox(width: 8),

          // Translation / Audio Quality button ("aあ")
          _buildCircleButtonWidget(
            semanticLabel: 'Pronunciation',
            child: Text(
              'aあ',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              AudioQualityLanguageSheet.show(context);
            },
          ),

          const SizedBox(width: 8),

          // Options button (vertical 3 dots matching Image 2)
          _buildCircleButton(
            icon: Icons.more_vert_rounded,
            iconColor: Colors.white,
            semanticLabel: 'Options',
            onTap: () {
              HapticFeedback.lightImpact();
              GlassOptionsSheet.show(context, track: track);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsBody(
    BuildContext context,
    MusicProvider musicProvider,
    Color accentColor,
  ) {
    if (musicProvider.isLoadingLyrics) {
      // The clock's lifecycle is reconciled in BOTH branches, not just the one
      // below. Returning the spinner early used to skip it entirely, so a
      // provider switch - which flips isLoadingLyrics on and off - could leave
      // the clock stopped by the stall detector with nothing left to restart it.
      // That reads as "the lyrics stopped" and nothing else in the build would
      // ever bring them back.
      _reconcileClock(musicProvider);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              'Loading lyrics...',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white60,
                fontSize: 15,
              ),
            ),
          ],
        ),
      );
    }

final lyrics = musicProvider.currentLyrics;
    _adoptLyrics(lyrics);

    // The clock's ticker only runs while there is something for it to animate.
    //
    // Left running unconditionally it schedules a frame every 16ms for as long
    // as the screen is up, so the lyrics view would repaint forever with an
    // empty lyric and the page would never go idle - which shows up as
    // pumpAndSettle hanging, and on a device as a screen that never sleeps.
    // Starting it here, where the lyric list is known, ties it to the content.
    _reconcileClock(musicProvider);

    if (lyrics == null || lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 56,
              color: Colors.white.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              'Lyrics not available',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    _ensureKeys(lyrics.length);

// No ShaderMask here, and that is the point.
    //
    // The list used to be masked by a vertical gradient that drove the top and
    // bottom 5% fully transparent. Combined with the old alpha floor of 0.12,
    // the lines that ended up in those bands were genuinely unreadable, and the
    // masked bands were exactly where the header buttons float - so the top of
    // the lyric was doubly hidden. A mask over a scrolling list is also a
    // saveLayer for every frame.
    //
    // Readability now comes from the alpha ladder in LyricLineStyle, which has
    // a floor of 0.46, so every line in the song can be read without scrolling
    // and the whole lyric is legible while the user scrolls.
    //
    // Revealed by SLIDE and SCALE, never by an alpha layer.
    //
    // This panel contains the two glass mode discs. A translucent layer between a
    // backdrop-filter lens and its content isolates the backdrop the lens
    // samples, so the discs went flat grey for the whole 300ms of the fade - the
    // one thing on screen the reader is reaching for. Motion reads the arrival
    // just as well without breaking the material (invariant 17; the same reason
    // the reference's panel transition is scale-only).
    return AnimatedBuilder(
      animation: _fadeController,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_fadeController.value);
        return Transform.translate(
          offset: Offset(0, 24.0 * (1.0 - t)),
          child: Transform.scale(
            scale: 0.98 + 0.02 * t,
            child: child,
          ),
        );
      },
      child: LayoutBuilder(
        // The tail of a long lyric was running off the bottom of the screen:
        // the list reserved only the deck's own height, so the last line could
        // never be scrolled fully into view. BitChord reserves 80% of its own
        // viewport underneath the content for the same reason
        // (PlayerLyrics.kt:1796) - a reader who has scrolled to the end of a
        // song should be able to read the last line, not half of it.
        builder: (context, constraints) => Stack(
        children: [
          Listener(
            // A tap in the LOWER HALF brings the discs back when they are away.
            //
            // Listener rather than GestureDetector so it never competes with the
            // list's own drag: it observes the pointer down without claiming it,
            // so a scroll still scrolls and a tap on a line still seeks. Guarded
            // so it does nothing at all while the discs are up - otherwise every
            // tap on a lyric line would also poke the idle timer, and the discs
            // would never leave.
            onPointerDown: (event) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null || !box.hasSize) return;
              final local = box.globalToLocal(event.position);
              if (local.dy < box.size.height / 2) return;
              _revealDiscsOnTap();
            },
            child: NotificationListener<ScrollNotification>(
              // Scope is the inner list only, so the surrounding page's scrolls
              // cannot open the browse state on this panel.
              onNotification: _handleScrollNotification,
              child: ListView.builder(
              key: _listKey,
              controller: _scrollController,
              // The tail of a long lyric was running off the bottom edge: the
              // list reserved only the deck's own height, so the last line could
              // never be scrolled fully into view. BitChord reserves 80% of its
              // viewport underneath the content (PlayerLyrics.kt:1796).
              //
              // It can be taken straight there because ITS deck is a sibling below
              // the panel in a Column. Ours is an OVERLAY above it, so the two
              // clearances have to be combined - and combined as a MAXIMUM, not a
              // clamp: clamping the deck's height to 80% of the panel silently
              // dropped the seek bar back over the lyric on a short panel, which
              // is the exact bug the deck inset was added to fix.
              padding: EdgeInsets.fromLTRB(
                24,
                _listTopPadding,
                24,
                math.max(
                  widget.bottomInset + 8,
                  constraints.maxHeight * _tailViewportFraction,
                ),
              ),
              physics: const BouncingScrollPhysics(),
              itemCount: lyrics.length,
              itemBuilder: (context, index) {
                return _buildKineticLyricLine(
                  index,
                  lyrics,
                  accentColor,
                  musicProvider,
                );
              },
              ),
            ),
          ),
          // Floated over the foot of the panel rather than placed in a row below
          // it: a row took its 34dp off the panel above and cost the lyric a
          // line. These cost it nothing, which is why they float - and why they
          // fade out when the reader stops touching anything, so they are never
          // parked over the words on their own.
          Positioned(
            left: 24,
            bottom: widget.bottomInset + 8,
            child: _buildDisc(
              icon: Icons.language_rounded,
              semanticLabel: _subController.shownMode == SubLineMode.romanized
                  ? 'Show original script'
                  : 'Show romanized lyrics',
              mode: SubLineMode.romanized,
            ),
          ),
          Positioned(
            right: 24,
            bottom: widget.bottomInset + 8,
            child: _buildDisc(
              icon: Icons.translate_rounded,
              semanticLabel: _subController.shownMode == SubLineMode.translated
                  ? 'Show original lyrics'
                  : 'Show translated lyrics',
              mode: SubLineMode.translated,
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// One mode disc, present only while the reader is engaged.
  Widget _buildDisc({
    required IconData icon,
    required String semanticLabel,
    required SubLineMode mode,
  }) {
    // A caller that says WHEN the player is up wins outright: the discs ride
    // the same shown/hidden decision as the scrubber, not their own timer.
    if (widget.chromeHidden != null) {
      if (widget.chromeHidden!) return const SizedBox.shrink();
    } else if (!_discsVisible) {
      return const SizedBox.shrink();
    }

    // The globe is pointless on a lyric that is already Latin, and saying so is
    // better than a disc that spins, returns the identical text and renders a
    // sub-line indistinguishable from the original above it.
    //
    // Decided from the LYRIC rather than from the last tap, so the disc is right
    // the moment it appears rather than after a round trip. The check and the
    // controller use the same function, so the two cannot disagree.
    final alreadyLatin = mode == SubLineMode.romanized && _lyricIsLatinScript;

    return TransformDisc(
      icon: icon,
      semanticLabel: alreadyLatin
          ? 'These lyrics already use Latin characters'
          : semanticLabel,
      state: _subController.isBusy
          ? TransformButtonState.loading
          : alreadyLatin
              ? TransformButtonState.sameLanguage
              : _subController.shownMode == mode
                  ? TransformButtonState.ready
                  : TransformButtonState.idle,
      active: _subController.shownMode == mode,
      onTap: () => _onDiscTap(mode),
    );
  }

  /// Whether every lyric line is already in Latin script.
  ///
  /// Read from the same source the controller reads, so a track change and a
  /// provider switch both update it without a second cache to keep in step.
  bool get _lyricIsLatinScript {
    final entries = _lyricsRef;
    if (entries == null || entries.isEmpty) return false;
    return LyricsTranslationService.isAlreadyRomanizable(
      entries.map((e) => e.text).toList(),
    );
  }

  Future<void> _onDiscTap(SubLineMode mode) async {
    final entries = _lyricsRef;
    final track = widget.trackKey;
    if (entries == null || track == null || track.isEmpty) return;

    if (mode == SubLineMode.romanized && _lyricIsLatinScript) {
      // TELL the reader rather than doing nothing. A disc that silently refuses a
      // tap is indistinguishable from a broken one, and this is a fact about
      // their song that they can act on.
      HapticFeedback.selectionClick();
      _showTransformMessage('These lyrics already use Latin characters');
      return;
    }

    await _subController.toggle(
      mode,
      trackKey: track,
      sourceLines: entries.map((e) => e.text).toList(),
      targetLanguage: widget.translationLanguage ?? Platform.localeName,
    );
    if (!mounted) return;

    if (_subController.alreadyInLanguage) {
      _showTransformMessage('These lyrics already use Latin characters');
    }
    setState(() {});
  }

  /// Says one thing about the transform, once.
  ///
  /// A snackbar rather than a new panel: this is a confirmation about a tap the
  /// reader just made, and the reference treats it as a transient message too
  /// (`PlayerLyrics.kt:2791-2794`) - it takes over the status line rather than
  /// becoming a state the panel has to hold.
  void _showTransformMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _buildCountdownDots(int remainingMs, Color accentColor) {
    // 3-dot vocal countdown indicator matching 00:03 in reference video
    final int activeDot = remainingMs <= 1100 ? 2 : (remainingMs <= 2200 ? 1 : 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final isLit = i <= activeDot;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: isLit ? 10 : 8,
            height: isLit ? 10 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLit ? Colors.white : Colors.white.withValues(alpha: 0.28),
              boxShadow: isLit
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.35),
                        blurRadius: 6,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }

Widget _buildKineticLyricLine(
    int index,
    List<LyricsEntry> lyrics,
    Color accentColor,
    MusicProvider musicProvider,
  ) {
    final entry = lyrics[index];
    if (entry.text.trim().isEmpty) return const SizedBox(height: 28);

    final int delta = index - _currentLineIndex;
    final bool isCurrentLine = delta == 0;

    Key? key;
    if (index < _itemKeys.length) {
      key = _itemKeys[index];
    }

    // ── Flat typography, no 3D barrel ──
    //
    // The old version applied a perspective rotateX of up to 0.32 rad to every
    // line either side of the active one. On a phone that is a warp, not a
    // depth cue: the outer lines are unreadable at a glance and text baselines
    // no longer line up with their neighbours. Flat type with an alpha ladder
    // gives the same sense of focus and none of the distortion.
    final baseStyle = LyricLineStyle.styleFor(
      distance: delta,
      isBrowsing: _isUserScrolling,
      isSynced: entry.isWordSynced,
    );

    final int currentPosMs = _clock.positionMs;

    final int firstVocalIdx =
        lyrics.indexWhere((e) => e.text.trim().isNotEmpty && !e.isMusicalBreak);
    final bool isFirstSungLine = index == firstVocalIdx;
    final bool showCountdown = isFirstSungLine &&
        currentPosMs < entry.timeMs &&
        (entry.timeMs - currentPosMs) <= 4500 &&
        (entry.timeMs - currentPosMs) >= 200;

    // Blur is applied per line and lifted to zero while browsing. Capped at
    // 2.4dp - the previous ladder reached 5.0, which smeared every line outside
    // the centre into illegibility even when the user had stopped moving.
    final double blur = LyricLineStyle.blurFor(
      distance: delta,
      isBrowsing: _isUserScrolling,
    );

    final swept = LyricSweptLine(
      key: key,
      entry: entry,
      clock: _clock,
      style: baseStyle,
      dimColor: isCurrentLine
          ? Colors.white.withValues(alpha: 0.45)
          : Colors.white.withValues(alpha: 0.3),
      isActive: isCurrentLine,
      // The browse state comes from here, not from inside the line: this widget
      // owns the scroll, and a line cannot tell a finger from an animation.
      isBrowsing: _isUserScrolling,
      onTap: () => _onLineTap(index, lyrics),
      // The transform rides UNDER the original. Swapping the entry's text instead
      // would make every word timing index the wrong characters, because those
      // timings are spans of the original string.
      subLineProvider: () => _subLineAt(index),
      subLineListenable: _subController,
    );

    Widget line = showCountdown
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCountdownDots(entry.timeMs - currentPosMs, accentColor),
              swept,
            ],
          )
        : swept;

    // Blur, alpha and scale are all ANIMATED, on one spec, by one controller.
    //
    // They used to be read straight off the distance index at build time, so a
    // handover repainted every row at a new constant: the list blinked between
    // three states instead of settling into the fourth.
    line = AnimatedLyricRow(
      blurSigma: blur,
      alpha: LyricLineStyle.alphaFor(
        distance: delta,
        isBrowsing: _isUserScrolling,
        isSynced: entry.isWordSynced,
      ),
      scale: LyricLineStyle.scaleFor(distance: delta),
      style: baseStyle,
      child: line,
    );

return GestureDetector(
        behavior: HitTestBehavior.translucent,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: _rowGap / 2),
          child: line,
        ),
      );
    }

  Widget _buildBottomMiniPlayerScrubber(
    BuildContext context,
    MusicProvider provider,
    Color accentColor,
  ) {
    final isPlaying = provider.isPlaying;

    return StreamBuilder<Duration>(
      stream: provider.positionStream,
      initialData: provider.position,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? provider.position;
        final dur = provider.duration;
        final double maxSec =
            dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
        final double fraction =
            (pos.inMilliseconds.toDouble() / maxSec).clamp(0.0, 1.0);
        final remaining = dur > pos ? dur - pos : Duration.zero;

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Scrubber Row: Play Button + Elapsed + ThinSlider + Remaining
              Row(
                children: [
                  // Play / Pause compact white circle button (Image 2)
                  Semantics(
                    label: isPlaying ? 'Pause' : 'Play',
                    button: true,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (isPlaying) {
                          provider.pauseTrack();
                        } else {
                          provider.resumeTrack();
                        }
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Elapsed time (Image 2: "0:22")
                  Text(
                    _formatTime(pos),
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // iPhone / BitChord style ThinSlider scrubber
                  Expanded(
                    child: ThinSlider(
                      value: fraction,
                      idleHeight: 7.0,
                      activeHeight: 12.0,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withValues(alpha: 0.24),
                      onValueChange: (val) {
                        provider.seekTo(Duration(milliseconds: (val * maxSec).toInt()));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Remaining time (Image 2: "-2:37")
                  Text(
                    '-${_formatTime(remaining)}',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

          // 2. Volume Slider Row (iPhone style ThinSlider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              children: [
                Icon(
                  Icons.volume_down_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.50),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ThinSlider(
                    value: provider.volume.clamp(0.0, 1.0),
                    idleHeight: 6.0,
                    activeHeight: 10.0,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white.withValues(alpha: 0.24),
                    onValueChange: (val) {
                      provider.setVolume(val);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.volume_up_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.50),
                ),
              ],
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color iconColor,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }

  Widget _buildCircleButtonWidget({
    required Widget child,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildAlbumArtImage(Track track) {
    final rawArt = track.albumArtUrl;
    if (rawArt.isEmpty) return _buildArtPlaceholder();
    final art = ImageQualityUtils.getHighResArtwork(rawArt);
    if (!art.contains('://')) {
      final f = File(art);
      if (f.existsSync()) return Image.file(f, fit: BoxFit.cover);
    }
      return CachedNetworkImage(
        imageUrl: art,
        fit: BoxFit.cover,
        memCacheWidth: AppImageCache.cardMemCache,
        memCacheHeight: AppImageCache.cardMemCache,
        errorWidget: (_, __, ___) => _buildArtPlaceholder(),
      );
  }

  Widget _buildArtPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Icon(Icons.music_note, color: Colors.white30, size: 24),
      ),
    );
  }

  String _formatTime(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
