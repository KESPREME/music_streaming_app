// lib/screens/lyrics_screen.dart
// The lyric panel: a scrolling list of lines that follows the song.
//
// WHERE IT SITS
//
// Inside the player, this panel is the page ABOVE the deck - the deck (seek bar,
// transport, volume) is a sibling below it in a column, not an overlay on top.
// So the panel's area already ends where the deck begins, and it needs no
// inset: an earlier version was handed the deck's height anyway and reserved it
// a second time, which lifted the globe/translate discs a deck-height off the
// bottom and left them visible only when the deck was away.
//
// WHAT IT OWNS
//
//   * following the song: the active line, and the scroll that leads it
//   * browsing: a finger on the list stops the follow and flattens the ladders
//   * the ladders: each row's alpha / blur / scale by distance, on one spec
//   * the fan-out: rows below the line being scrolled to trail the list a beat
//     (`lyric_stagger.dart`), driven only by our own scroll
//   * the two mode discs (romanize / translate) and the sub-lines they reveal
//
// WHAT IT DOES NOT OWN
//
//   * the clock. The player owns ONE clock shared with the seek-bar strip and
//     hands it down; stand-alone (no clock given) the panel makes its own and
//     feeds it from the provider.
//   * how a line is drawn. That is `LyricLine`, one render object per line.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../theme/app_font.dart';
import '../models/lyrics_entry.dart';
import '../providers/music_provider.dart';
import '../services/lyrics/lyric_clock.dart';
import '../services/lyrics/lyric_clock_feed.dart';
import '../services/lyrics/lyric_sub_line.dart';
import '../services/lyrics/lyric_sweep.dart';
import '../services/lyrics/lyrics_translation_service.dart';
import '../utils/color_utils.dart';
import '../widgets/lyric_caption.dart';
import '../widgets/lyric_line/animated_lyric_row.dart';
import '../widgets/lyric_line/lyric_gap_dots.dart';
import '../widgets/lyric_line/lyric_line.dart';
import '../widgets/lyric_line/lyric_line_style.dart';
import '../widgets/lyric_line/lyric_stagger.dart';
import '../widgets/lyric_line/lyric_sub_line_view.dart';
import '../widgets/lyric_line/lyric_typography.dart';
import '../widgets/lyric_line/lyrics_skeleton.dart';
import '../widgets/lyrics_mode_discs.dart';
import '../widgets/lyrics_standalone_chrome.dart';

/// Real-time kinetic lyrics.
class LyricsScreen extends StatefulWidget {
  const LyricsScreen({
    super.key,
    this.onMinimize,
    this.onTabTap,
    this.onReturnToAlbum,
    this.isEmbedded = false,
    this.showHeader = true,
    this.showBottomScrubber = true,
    this.trackKey,
    this.translationLanguage,
    this.clock,
    this.discsVisible,
    this.onTransformStatusChanged,
    this.onDisplayLinesChanged,
  });

  final VoidCallback? onMinimize;
  final Function(int)? onTabTap;
  final VoidCallback? onReturnToAlbum;

  /// True inside the player, which draws its own header and deck.
  final bool isEmbedded;
  final bool showHeader;
  final bool showBottomScrubber;

  /// Ties the sub-line to a track, so a transform belonging to the previous song
  /// can never be painted under this one.
  final String? trackKey;

  /// Language the translation targets. Null follows the 	ranslation_language`n  /// setting, then the device's base language, then n.
  final String? translationLanguage;

  /// The clock to follow. The player passes the ONE it shares with the seek-bar
  /// strip; null makes the panel create and feed its own.
  final LyricClock? clock;

  /// Whether the two mode discs are on screen, decided by the caller.
  ///
  /// The discs belong to the player's controls: they arrive with the deck and
  /// leave with it, on ONE decision. A second, independent idle timer here let
  /// them disagree - exactly how they once sat on screen while the player had
  /// already gone away. Null means "no caller opinion": the panel falls back to
  /// a local idle timer, which is what the stand-alone screen uses.
  final bool? discsVisible;

  /// Told when what the panel is doing to the words changes: translating,
  /// romanizing, or showing one of them.
  ///
  /// The player's caption under the lyric says it. The panel owns the transform
  /// (it owns the reveal timers that go with it), so it PUBLISHES the little the
  /// caption needs rather than the player reaching into it. Called only when the
  /// status actually changes, never from inside a build.
  final ValueChanged<LyricTransformStatus>? onTransformStatusChanged;

  /// The text of each line as it is SHOWN (the translation or romanization when
  /// one is on, otherwise null), so the strip above the seek bar says what the
  /// panel says. Called only when the lines change, never from inside a build.
  final ValueChanged<List<String>?>? onDisplayLinesChanged;

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  // ── The clock ──────────────────────────────────────────────────────────────

  late LyricClock _clock;
  bool _ownsClock = false;
  LyricClockFeed? _feed;
  bool _listeningToClock = false;

  // ── The line being sung ────────────────────────────────────────────────────

  int _currentLineIndex = 0;

  /// The song-time range over which [_currentLineIndex] stays the answer, so the
  /// 60Hz clock tick costs two comparisons instead of a scan of the lyric.
  int _activeFromMs = 0;
  int _activeUntilMs = -1;

  List<LyricsEntry>? _lyricsRef;

  /// The list the per-line state below has been made to match.
  List<LyricsEntry>? _syncedLyrics;
  String? _currentTrackId;
  final List<GlobalKey> _itemKeys = [];

  // ── Browsing ───────────────────────────────────────────────────────────────

  /// True while the reader is dragging the lyric by hand.
  ///
  /// This is the "browsing" state: blur goes to zero and the alpha ladder
  /// flattens, so every line can be read while the finger is down.
  ///
  /// It must be a FINGER, never "the list is moving". The old trigger read
  /// `position.isScrollingNotifier`, which our own `animateScrollBy` also flips -
  /// so every line handover announced itself as a browse, cleared the blur and
  /// switched the auto-follow off for the whole resume window.
  bool _isUserScrolling = false;
  bool _autoScrollEnabled = true;
  Timer? _browseTimer;
  Duration _browseIdleMs = Duration.zero;

  // ── The fan-out ────────────────────────────────────────────────────────────

  /// Holds the rows below the line being scrolled to a beat behind the list as
  /// it moves (see `lyric_stagger.dart`). Driven only by OUR scroll - a finger
  /// never starts it, and a finger that arrives ends it.
  late final LyricStagger _stagger = LyricStagger(vsync: this);

  // ── Sub-lines ──────────────────────────────────────────────────────────────

  final SubLineController _subController = SubLineController();
  final Map<int, ({String text, LyricsEntry entry})> _subEntries = {};

  // ── Stand-alone discs ──────────────────────────────────────────────────────

  bool _discsLocallyVisible = true;
  Timer? _discIdleTimer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _ownsClock = widget.clock == null;
    _clock = widget.clock ?? LyricClock(vsync: this);
    _subController.addListener(_onSubLineChanged);
    _subController.addListener(_publishTransformStatus);
    _subController.addListener(_publishDisplayLines);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkLyrics();
    });
    if (widget.discsVisible == null) _pokeDiscs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<MusicProvider>(context, listen: false);
    final track = provider.currentTrack;

    // A stand-alone panel feeds its own clock; inside the player the player does.
    if (_ownsClock && _feed == null) {
      _feed = LyricClockFeed(clock: _clock, provider: provider)..start();
    }

    // The panel listens to the clock only while it is in a subtree whose tickers
    // are running. Kept mounted but hidden, it must not hold the frame loop up.
    _syncClockListener(TickerMode.valuesOf(context).enabled);

    if (track != null && _currentTrackId != track.id) {
      final wasNull = _currentTrackId == null;
      _currentTrackId = track.id;
      _currentLineIndex = 0;
      _activeFromMs = 0;
      _activeUntilMs = -1;
      _itemKeys.clear();
      _subEntries.clear();
      // Dropped so the next build re-adopts for this track even if it happens to
      // be handed the very same list object.
      _syncedLyrics = null;
      _placedForTrack = null;
      _stagger.cancel();
      // No fetch here: the provider fetches lyrics itself on every track change.
      // This used to force-refresh on top of that, which bypassed both caches and
      // asked every source a second time for each song.
      if (!wasNull) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(LyricsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Drop the sub-line on a track change, HERE rather than in the caller: this
    // widget owns the controller because it owns the reveal timers that go with
    // it. A transform belonging to the previous song must never be painted under
    // this one, and the mode resets with it.
    final next = widget.trackKey;
    if (next != null && next != oldWidget.trackKey) {
      _subController.onTrackChanged(next);
      _subEntries.clear();
    }
    if (oldWidget.clock != widget.clock && widget.clock != null) {
      _syncClockListener(false);
      if (_ownsClock) {
        _feed?.dispose();
        _feed = null;
        _clock.dispose();
        _ownsClock = false;
      }
      _clock = widget.clock!;
      _syncClockListener(TickerMode.valuesOf(context).enabled);
    }
  }

  @override
  void dispose() {
    _syncClockListener(false);
    _browseTimer?.cancel();
    _discIdleTimer?.cancel();
    _stagger.dispose();
    _scrollController.dispose();
    _subController
      ..removeListener(_onSubLineChanged)
      ..removeListener(_publishTransformStatus)
      ..removeListener(_publishDisplayLines)
      ..dispose();
    _feed?.dispose();
    if (_ownsClock) _clock.dispose();
    super.dispose();
  }

  void _syncClockListener(bool enabled) {
    if (enabled && !_listeningToClock) {
      _clock.addListener(_onClockTick);
      _listeningToClock = true;
      _syncActiveLine(_clock.positionMs);
      // Coming back from hidden (the panel is kept mounted so opening it costs no
      // first frame): the song has moved on while nobody was following it, and
      // scrolling there while the panel fades in would read as the list racing
      // to catch up. Place it, don't animate it.
      if (_syncedLyrics != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCurrent());
      }
    } else if (!enabled && _listeningToClock) {
      _clock.removeListener(_onClockTick);
      _listeningToClock = false;
      // Hidden: the ticker driving the fan-out is muted with the rest of the
      // panel, so a run left open would resume part-way when the panel returns.
      _stagger.cancel();
    }
  }

  void _onClockTick() => _syncActiveLine(_clock.positionMs);

  void _onSubLineChanged() {
    if (_subController.shownMode == SubLineMode.original) _subEntries.clear();
  }

  // ── What the caption says about the transform ─────────────────────────────

  LyricTransformStatus _publishedStatus = LyricTransformStatus.none;

  /// The transform state as the caption wants it: in flight first, then what the
  /// reader asked to see, in the order the caption itself reads them.
  ///
  /// "Shown" is the mode REQUESTED, not the one still folding away: the caption
  /// answers the tap at once, as the disc beside it does.
  LyricTransformStatus _transformStatus() {
    final c = _subController;
    switch (c.loadingMode) {
      case SubLineMode.translated:
        return const LyricTransformStatus(LyricTransformPhase.translating);
      case SubLineMode.romanized:
        return const LyricTransformStatus(LyricTransformPhase.romanizing);
      case SubLineMode.original:
      case null:
        break;
    }
    if (c.mode == SubLineMode.translated &&
        c.status(SubLineMode.translated) == SubLineStatus.ready) {
      return LyricTransformStatus(
        LyricTransformPhase.translated,
        language: c.targetLanguage,
      );
    }
    if (c.mode == SubLineMode.romanized &&
        c.status(SubLineMode.romanized) == SubLineStatus.ready) {
      return const LyricTransformStatus(LyricTransformPhase.romanized);
    }
    return LyricTransformStatus.none;
  }

  /// Tells the caller when the status CHANGES. The controller notifies on every
  /// frame of a 460ms reveal; the caption cares about four distinct moments.
  ///
  /// Delivered a microtask later, not now: the controller also notifies from
  /// `didUpdateWidget` (a track change resets it), which is inside a build, and a
  /// listener that rebuilds the caption from there is a setState during build.
  void _publishTransformStatus() {
    final next = _transformStatus();
    if (next == _publishedStatus) return;
    _publishedStatus = next;
    scheduleMicrotask(() {
      if (!mounted) return;
      widget.onTransformStatusChanged?.call(next);
    });
  }

  List<String>? _publishedLines;

  static bool _sameLines(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Tells the caller when the shown text CHANGES, by content: the controller
  /// notifies on every frame of the reveal, and a parent that rebuilt per frame
  /// for a string list that has not moved would be the cost of this feature.
  void _publishDisplayLines() {
    final lyrics =
        Provider.of<MusicProvider>(context, listen: false).currentLyrics;
    final next =
        lyrics == null ? null : _subController.displayedLinesFor(lyrics);
    final prev = _publishedLines;
    final same = (next == null && prev == null) ||
        (next != null && prev != null && _sameLines(next, prev));
    if (same) return;
    _publishedLines = next;
    scheduleMicrotask(() {
      if (!mounted) return;
      widget.onDisplayLinesChanged?.call(next);
    });
  }

  void _checkLyrics() {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    if (provider.currentTrack != null) {
      _currentTrackId = provider.currentTrack!.id;
      if (!provider.hasSyncedLyrics || provider.currentLyrics == null) {
        provider.fetchLyrics();
      }
    }
  }

  void _ensureKeys(int count) {
    if (_itemKeys.length != count) {
      _itemKeys
        ..clear()
        ..addAll(List.generate(count, (_) => GlobalKey()));
    }
  }

  /// Brings the per-line state into line with [lyrics] when the LIST changes.
  ///
  /// Changing provider changes the words, not the song, so `didChangeDependencies`
  /// - which resets everything only when the track id moves - never sees it. The
  /// active line is an INDEX into the list, so an index carried across from a
  /// different lyric points at a different line.
  ///
  /// Recomputed from the clock's own position rather than reset to zero, because
  /// the player has not moved: resetting would scroll the panel back to the top
  /// of the song mid-track.
  void _adoptLyrics(List<LyricsEntry>? lyrics) {
    _lyricsRef = lyrics;
    if (identical(_syncedLyrics, lyrics)) return;
    _syncedLyrics = lyrics;
    _subEntries.clear();
    // Rows are about to mean different lines (new heights, a new lead line); the
    // fan-out is indexed by row, so a run left over would shift the wrong ones.
    _stagger.cancel();
    _ensureKeys(lyrics?.length ?? 0);

    final active = lyrics == null || lyrics.isEmpty
        ? 0
        : activeLineIndex(lyrics, _clock.positionMs);
    _currentLineIndex = active < 0 ? 0 : active;
    _recomputeActiveWindow(lyrics);

    if (lyrics != null && lyrics.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_placedForTrack != _currentTrackId) {
          // First lyric for this song: put the list where the singing is. A list
          // that opens at the top and then animates to the verse reads as the
          // panel catching up.
          _placedForTrack = _currentTrackId;
          _jumpToCurrent();
        } else if (_autoScrollEnabled && !_isUserScrolling) {
          // A different source for the SAME song (a provider switch): rows have
          // new heights and the lead line has moved, so follow it - animated,
          // because the reader is looking at this list.
          _scrollToCurrentLine();
        }
      });
    }
  }

  /// The song the list was last placed for. Null means "place it next time".
  String? _placedForTrack;

  /// Puts the lead line at the top anchor with no animation, refining once the
  /// rows around it exist.
  void _jumpToCurrent({int pass = 0}) {
    if (!mounted || !_scrollController.hasClients) return;
    // A placement is not a handover: nothing is travelling, so nothing fans out.
    if (pass == 0) _stagger.cancel();
    final target = _scrollTargetIndex;
    if (target < 0 || target >= _itemKeys.length) return;
    final position = _scrollController.position;
    final offset = _targetOffsetFor(target)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _scrollController.jumpTo(offset);
    if (pass >= _maxRefinePasses) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (target >= _itemKeys.length ||
          _itemKeys[target].currentContext == null) {
        return;
      }
      if ((_targetOffsetFor(target) - _scrollController.offset).abs() > 1.0) {
        _jumpToCurrent(pass: pass + 1);
      }
    });
  }

  void _recomputeActiveWindow(List<LyricsEntry>? lyrics) {
    if (lyrics == null || lyrics.isEmpty) {
      _activeFromMs = 0;
      _activeUntilMs = -1;
      return;
    }
    final i = _currentLineIndex.clamp(0, lyrics.length - 1);
    _activeFromMs = i == 0 && lyrics[0].timeMs > 0 ? -1 : lyrics[i].timeMs;
    _activeUntilMs =
        i + 1 < lyrics.length ? lyrics[i + 1].timeMs : 1 << 30;
  }

  /// Advances the active-line index, rebuilding only when it actually moves.
  void _syncActiveLine(int positionMs) {
    final lyrics = _lyricsRef;
    if (lyrics == null || lyrics.isEmpty) return;
    // Still inside the current line's window: the common case, and the only one
    // a 60Hz tick should pay for.
    if (positionMs >= _activeFromMs && positionMs < _activeUntilMs) return;

    final raw = activeLineIndex(lyrics, positionMs);
    final active = raw < 0 ? 0 : raw;
    final changed = active != _currentLineIndex;
    _currentLineIndex = active;
    // The window moves even when the index does not (the very first call, a seek
    // within the same line), or the early return above would never be reached.
    _recomputeActiveWindow(lyrics);
    if (!changed || !mounted) return;
    _ensureKeys(lyrics.length);
    setState(() {});

    if (_autoScrollEnabled && !_isUserScrolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrentLine();
      });
    }
  }

  void _onLineTap(int index, List<LyricsEntry> lyrics) {
    if (index < 0 || index >= lyrics.length) return;
    final entry = lyrics[index];
    final provider = Provider.of<MusicProvider>(context, listen: false);

    HapticFeedback.lightImpact();
    // Announced, so the words may roll backwards to it.
    _clock.jump(entry.timeMs);
    provider.seekTo(Duration(milliseconds: entry.timeMs));

    _exitBrowse(rebuild: false);
    setState(() {
      _currentLineIndex = index;
      _autoScrollEnabled = true;
    });
    _recomputeActiveWindow(lyrics);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentLine());
  }

  // ── Browsing ───────────────────────────────────────────────────────────────

  /// How long the reader has to be still before the browse gives way.
  ///
  /// 600ms is the reference's short answer, used while the singing is still on
  /// screen. 5s is its fallback, used when the reader has parked the list
  /// somewhere the song has left - snapping back then is the wrong answer.
  static const Duration _browseResumeOnScreen = Duration(milliseconds: 600);
  static const Duration _browseResumeFallback = Duration(seconds: 5);

  /// The tick the browse's idle budget is counted on. Runs only while browsing.
  static const Duration _browsePeriod = Duration(milliseconds: 250);

  /// The resume window that applies right now.
  Duration get _browseResumeLimit =>
      _focusRowVisible() ? _browseResumeOnScreen : _browseResumeFallback;

  /// Whether the line being sung is inside the viewport right now.
  ///
  /// ONE answer for "is the singing on screen", used to choose the resume window.
  bool _focusRowVisible() {
    if (!_scrollController.hasClients) return false;
    final lyrics = _lyricsRef;
    if (lyrics == null || lyrics.isEmpty) return true;
    final index = _currentLineIndex;
    if (index < 0 || index >= _itemKeys.length) return false;
    final box = _itemKeys[index].currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final listBox = _listKey.currentContext?.findRenderObject();
    final listTop =
        listBox is RenderBox ? listBox.localToGlobal(Offset.zero).dy : 0.0;
    final dy = box.localToGlobal(Offset.zero).dy - listTop;
    final viewport = _scrollController.position.viewportDimension;
    return dy >= 0 && dy <= viewport * 0.8;
  }

  void _enterBrowse() {
    if (_isUserScrolling) return;
    // The finger owns the list now. A fan-out still running would keep pulling
    // rows around under it for a few hundred ms, so it ends here.
    _stagger.cancel();
    _browseIdleMs = Duration.zero;
    _browseTimer?.cancel();
    _browseTimer = Timer.periodic(_browsePeriod, (_) => _advanceBrowseIdle());
    setState(() {
      _isUserScrolling = true;
      _autoScrollEnabled = false;
    });
  }

  /// Leaves the browse state.
  ///
  /// Deliberately does NOT scroll. The reader moved the list on purpose and half
  /// a second of stillness is not them changing their mind; yanking them back to
  /// the singing line is what made the old resume feel like a fight. The next
  /// line change re-arms the follow.
  void _exitBrowse({bool rebuild = true}) {
    _browseTimer?.cancel();
    _browseTimer = null;
    _browseIdleMs = Duration.zero;
    if (!_isUserScrolling) return;
    _isUserScrolling = false;
    _autoScrollEnabled = true;
    if (rebuild && mounted) setState(() {});
  }

  /// Any scroll activity restarts the idle budget.
  void _noteBrowseActivity() {
    if (_isUserScrolling) _browseIdleMs = Duration.zero;
  }

  void _advanceBrowseIdle() {
    if (!mounted || !_isUserScrolling) return;
    _browseIdleMs += _browsePeriod;
    if (_browseIdleMs < _browseResumeLimit) return;
    _exitBrowse();
  }

  /// Distinguishes a finger from our own scroll animation.
  ///
  /// `dragDetails` is non-null only for a user gesture; a programmatic
  /// `animateTo` or `jumpTo` dispatches the same notification classes with none
  /// attached. That single null check is the whole difference between "the
  /// reader is looking around" and "the panel is following the song".
  ///
  /// The browse is timed from the LAST SCROLL ACTIVITY, not from one end event:
  /// keyed to `ScrollEndNotification` alone, a missed end left the panel in
  /// browsing mode for the rest of the song.
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails == null) return false;
      _enterBrowse();
      return false;
    }
    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification ||
        notification is ScrollEndNotification) {
      _noteBrowseActivity();
    }
    // Never consume: the list, and the player's own deck-collapse tracker above
    // us, still need to see every notification.
    return false;
  }

  // ── Following the song ─────────────────────────────────────────────────────

  /// The list itself, for measuring rows against it rather than against zero.
  final GlobalKey _listKey = GlobalKey(debugLabel: 'lyricList');

  /// Where the line being sung is anchored from the top of the list.
  ///
  /// BitChord anchors the lead line at `scrollOffset = 0` under 30dp of content
  /// padding, and its lyric box begins well below the header. The list here
  /// begins right under ours, so the extra clearance is in the padding: it puts
  /// the sung line where the reference puts it and leaves the line before it
  /// visible, fading under the top edge.
  static const double _listTopPadding = 96.0;

  /// Fraction of the panel's own height reserved below the last lyric line.
  /// BitChord `PlayerLyrics.kt:1796`.
  static const double _tailViewportFraction = 0.8;

  /// Vertical space between rows (half above, half below each).
  static const double _rowGap = 28.0;

  /// Row pitch used before anything has been measured.
  static const double _assumedRowPitch = 90.0;

  /// How many extra passes [_animateLineToView] may take to land exactly.
  ///
  /// A lazy list has not built the rows outside its viewport, so a jump - a
  /// seek, or anything above the first built row - has no box to measure. One
  /// estimated pass gets the list close enough that the target builds, and the
  /// next pass is exact. Two is enough; a third would be a layout loop wearing a
  /// scroll's clothes.
  static const int _maxRefinePasses = 2;

  /// The line the scroll should land on, which LEADS the singing.
  ///
  /// Brightness and motion are deliberately two different indices: the highlight
  /// must never run ahead of what is actually being sung, but the list may.
  int get _scrollTargetIndex {
    final lyrics = _lyricsRef;
    if (lyrics == null || lyrics.isEmpty) return _currentLineIndex;
    final focused = focusLineIndex(lyrics, _clock.positionMs);
    return focused >= 0 ? focused : _currentLineIndex;
  }

  /// How long the move to the lead line should take: the gap it is covering,
  /// clamped to [scrollLeadMs]'s bounds.
  ///
  /// Never zero. It used to be zero when `_activeLineNeedsScroll` said the lead
  /// line was already on screen, and a zero duration meant `jumpTo` - so at every
  /// line change, where the lead line IS the line just entered and is always on
  /// screen, the list hard-cut one line instead of gliding. "Already in place" is
  /// a question about the OFFSET (see [_animateLineToView]), not about whether the
  /// row is visible: a row one line below the anchor is visible and still has a
  /// line to travel.
  Duration get _scrollRunUp {
    final lyrics = _lyricsRef;
    if (lyrics == null || lyrics.isEmpty) return LyricLineStyle.lyricSettle;
    return Duration(milliseconds: scrollLeadMs(lyrics, _clock.positionMs));
  }

  /// Moves the list so the line the reader is about to need sits where the eye
  /// already is: lead line, duration taken from the gap the move covers,
  /// top-anchored.
  void _scrollToCurrentLine() {
    if (!_scrollController.hasClients) return;
    final target = _scrollTargetIndex;
    if (target < 0 || target >= _itemKeys.length) return;
    _animateLineToView(target, 0);
  }

  /// Scrolls so [target] lands at the top of the list's content box.
  ///
  /// Self-correcting, because "land at the top" is only measurable once the row
  /// exists. Silently doing nothing when it did not - which is what a plain
  /// `ensureVisible` on an unbuilt key does - is how a backward seek used to
  /// leave the list stranded on the wrong verse.
  void _animateLineToView(int target, int pass) {
    if (!mounted || !_scrollController.hasClients) return;

    // A new handover supersedes the last one's fan-out, and does so BEFORE
    // anything is measured: `_targetOffsetFor` reads row positions through
    // `localToGlobal`, which includes the paint shift, so a row still held back
    // by the previous run would be measured where it is drawn rather than where
    // it is laid out and the new target would be off by the shift. The cost is a
    // snap of whatever the last run had left, which is at most a few px unless
    // two lines arrive inside one handover.
    //
    // Passes 1 and 2 are the correction after a run, not a handover: they leave
    // the tail of it alone.
    if (pass == 0) _stagger.cancel();

    final offset = _targetOffsetFor(target);
    // Already there: nothing to animate. Judged by the offset the list would
    // travel to, within a pixel - the only honest "nothing to do".
    if ((offset - _scrollController.offset).abs() < 1.0) return;
    final duration = pass == 0 ? _scrollRunUp : LyricLineStyle.lyricSettle;

    // `animateTo` on the offset rather than `ensureVisible` on the context: one
    // offset, one curve, one duration, so a handover reads as a single movement
    // instead of composing with whatever animation was already in flight.
    final fanOut = pass == 0 ? _fanOutFor(target, offset, duration) : null;
    final scroll = _scrollController.animateTo(
      offset,
      duration: duration,
      curve: LyricLineStyle.lyricEase,
    );
    // On the same frame as the scroll, so both tickers share a time base and the
    // rows are on the list's own curve.
    if (fanOut != null) _stagger.start(fanOut);

    scroll.whenComplete(() {
      if (!mounted) return;
      if (fanOut != null) _endFanOutIfCutShort(fanOut);
      if (pass >= _maxRefinePasses) return;
      // One frame later: the row only gets laid out - and only gets a context -
      // on the next frame's layout pass.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || pass >= _maxRefinePasses) return;
        // The reader took the list in the meantime. Correcting now would
        // `animateTo` out from under their finger and hand them back to the song.
        if (_isUserScrolling) return;
        if (target >= _itemKeys.length ||
            _itemKeys[target].currentContext == null) {
          return;
        }
        final exact = _targetOffsetFor(target);
        if ((exact - _scrollController.offset).abs() > 1.0) {
          _animateLineToView(target, pass + 1);
        }
      });
    });
  }

  /// The slack between a scroll ending and the fan-out clock reading its
  /// duration, in ms. A frame and a half: both are the same ticker time, this is
  /// only rounding.
  static const double _fanOutSlackMs = 24.0;

  /// The fan-out that goes with a move to [target], or null when there should be
  /// none.
  ///
  /// None when motion is reduced; when the target row has not been built (the
  /// distance is a guess, and a run sized on a guess is a run that over- or
  /// under-shoots); and when the move is a seek across the song rather than a
  /// handover to the next line - a stretch of more than a viewport would hold
  /// rows hundreds of px behind a list that is already gone.
  LyricScrollRun? _fanOutFor(int target, double offset, Duration duration) {
    if (MediaQuery.disableAnimationsOf(context)) return null;
    if (target >= _itemKeys.length ||
        _itemKeys[target].currentContext == null) {
      return null;
    }
    final position = _scrollController.position;
    // The distance the list will actually travel: `animateTo` is aimed at
    // `offset`, but the extents bound where it can arrive.
    final destination = offset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    final delta = destination - position.pixels;
    if (delta.abs() < 1.0 || delta.abs() > position.viewportDimension) {
      return null;
    }
    return LyricScrollRun(
      focusIndex: target,
      delta: delta,
      durationMs: duration.inMilliseconds,
    );
  }

  /// Ends [run] if the scroll it describes stopped before it should have.
  ///
  /// The scroll's future completes when its activity ends, whatever ended it. A
  /// normal end is at or after the run's duration; an earlier one means
  /// something took the list - a touch that stopped it dead, a jump, a newer
  /// move. With the list frozen mid-way the rows would otherwise finish a fan-out
  /// the list never made. A newer run is none of this one's business.
  void _endFanOutIfCutShort(LyricScrollRun run) {
    if (!identical(_stagger.run, run)) return;
    if (_stagger.elapsedMs < run.durationMs - _fanOutSlackMs) _stagger.cancel();
  }

  /// A best guess for where [target] sits, for a row the list has not built: the
  /// mean pitch of the rows that are laid out, times the index.
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

  double _targetOffsetFor(int target) {
    final contextOfItem = _itemKeys[target].currentContext;
    if (contextOfItem == null) return _estimatedOffsetFor(target);
    return _topAnchorOffsetFor(contextOfItem);
  }

  /// Measures [contextOfItem] against the LIST, not against the screen: a row's
  /// y is measured from the screen but `pixels` from the start of the content,
  /// and mixing the two bakes the panel's own top offset into every handover.
  /// The arithmetic itself is [topAnchorOffset].
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

  // ── Stand-alone discs ──────────────────────────────────────────────────────

  void _pokeDiscs() {
    if (!_discsLocallyVisible && mounted) {
      setState(() => _discsLocallyVisible = true);
    }
    _discIdleTimer?.cancel();
    _discIdleTimer = Timer(lyricsDiscIdleTimeout, () {
      if (!mounted) return;
      setState(() => _discsLocallyVisible = false);
    });
  }

  bool get _discsShown => widget.discsVisible ?? _discsLocallyVisible;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final track = musicProvider.currentTrack;
    final accentColor = ColorUtils.getVibrantAccent(
      musicProvider.paletteGenerator,
      const Color(0xFFE89838),
    );

    final Widget mainContent = Column(
      children: [
        if (track != null && widget.showHeader)
          LyricsMiniHeader(
            track: track,
            provider: musicProvider,
            accentColor: accentColor,
            isEmbedded: widget.isEmbedded,
            onReturnToAlbum: widget.onReturnToAlbum,
            onTabTap: widget.onTabTap,
          )
        else if (widget.isEmbedded)
          SizedBox(height: MediaQuery.of(context).padding.top + 90.0),
        Expanded(child: _buildLyricsBody(context, musicProvider)),
        if (widget.showBottomScrubber) LyricsMiniScrubber(provider: musicProvider),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: widget.isEmbedded
          ? mainContent
          : Stack(
              children: [
                Positioned.fill(child: LyricsStandaloneBackground(track: track)),
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      LyricsPullHandle(onMinimize: widget.onMinimize),
                      Expanded(child: mainContent),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLyricsBody(BuildContext context, MusicProvider musicProvider) {
    final lyrics = musicProvider.currentLyrics;
    _adoptLyrics(lyrics);

    if (lyrics == null || lyrics.isEmpty) {
      // A lookup in flight with nothing yet to show gets the skeleton; one that
      // came back empty says so. With lyrics already on screen (a provider
      // switch) neither applies: the list stays put until the new one lands.
      if (musicProvider.isLoadingLyrics) {
        return const Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: _listTopPadding),
            child: LyricsSkeleton(),
          ),
        );
      }
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
              'No lyrics for this track',
              style: AppFont.style(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final isSynced = lyrics.any((e) => e.timeMs > 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;

        final list = NotificationListener<ScrollNotification>(
          // Scope is the inner list only, so the surrounding page's scrolls
          // cannot open the browse state on this panel.
          onNotification: _handleScrollNotification,
          child: ListView.builder(
            key: _listKey,
            controller: _scrollController,
            // Room below the last line so a reader who has scrolled to the end
            // can read it, rather than half of it (`PlayerLyrics.kt:1796`).
            // That is the ONLY bottom clearance: this panel already ends where
            // the deck begins.
            padding: EdgeInsets.fromLTRB(
              18,
              _listTopPadding,
              18,
              viewportHeight * _tailViewportFraction,
            ),
            physics: const BouncingScrollPhysics(),
            itemCount: lyrics.length,
            itemBuilder: (context, index) =>
                _buildRow(context, index, lyrics, isSynced),
          ),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                // A tap in the LOWER HALF brings the stand-alone discs back when
                // they are away. A Listener, so it never competes with the list's
                // own drag. Inside the player the caller owns the discs.
                onPointerDown: widget.discsVisible == null
                    ? (event) {
                        final box = context.findRenderObject() as RenderBox?;
                        if (box == null || !box.hasSize) return;
                        if (box.globalToLocal(event.position).dy <
                            box.size.height / 2) {
                          return;
                        }
                        if (!_discsLocallyVisible) _pokeDiscs();
                      }
                    : null,
                child: _FadingEdges(height: viewportHeight, child: list),
              ),
            ),
            // Floated over the foot of the panel: they cost the lyric no height.
            // They sit at the panel's own bottom because the panel already ends
            // at the deck - no inset.
            Positioned(
              left: 24,
              bottom: 12,
              child: LyricsDiscReveal(
                visible: _discsShown,
                child: _buildDisc(
                  icon: Icons.language_rounded,
                  semanticLabel: 'Show romanized lyrics',
                  activeSemanticLabel: 'Show original script',
                  mode: SubLineMode.romanized,
                ),
              ),
            ),
            Positioned(
              right: 24,
              bottom: 12,
              child: LyricsDiscReveal(
                visible: _discsShown,
                child: _buildDisc(
                  icon: Icons.translate_rounded,
                  semanticLabel: 'Show translated lyrics',
                  activeSemanticLabel: 'Show original lyrics',
                  mode: SubLineMode.translated,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Rows ───────────────────────────────────────────────────────────────────

  /// The transformed entry for lyric [index], or null when none is showing.
  ///
  /// Null for the wrong track and for a length mismatch rather than guessing: a
  /// sub-line under the wrong lyric is worse than no sub-line. Cached by index so
  /// the line's render object keeps ONE entry (and its geometry) through the
  /// 460ms reveal instead of being handed a new one every frame.
  LyricsEntry? _subEntryAt(int index) {
    if (_subController.shownMode == SubLineMode.original) return null;
    if (_subController.progress <= 0) return null;
    final current = _lyricsRef;
    if (current == null) return null;
    // Null unless the transform on hand was made for THIS lyric - by content, not
    // by length: two providers' versions of a song often have the same number of
    // lines, and a sub-line under the wrong words is a lie with a UI attached.
    final lines = _subController.linesFor(current);
    if (lines == null) return null;
    if (index < 0 || index >= lines.length) return null;
    final text = lines[index];
    if (text.trim().isEmpty) return null;
    // Identical to the original: nothing to add, and drawing it would look like
    // a duplicate.
    if (text.trim().toLowerCase() == current[index].text.trim().toLowerCase()) {
      return null;
    }
    final cached = _subEntries[index];
    if (cached != null && cached.text == text) return cached.entry;
    final entry = LyricsEntry(timeMs: current[index].timeMs, text: text);
    _subEntries[index] = (text: text, entry: entry);
    return entry;
  }

  Widget _buildRow(
    BuildContext context,
    int index,
    List<LyricsEntry> lyrics,
    bool isSynced,
  ) {
    final entry = lyrics[index];
    final key = index < _itemKeys.length ? _itemKeys[index] : null;
    final delta = index - _currentLineIndex;
    final distance = delta.abs();

    if (entry.text.trim().isEmpty) return SizedBox(key: key, height: _rowGap);

    final browsing = _isUserScrolling;
    final alpha = LyricLineStyle.alphaFor(
      distance: distance,
      isBrowsing: browsing,
      isSynced: isSynced,
    );

    if (entry.isMusicalBreak) {
      final next = index + 1 < lyrics.length ? lyrics[index + 1].timeMs : null;
      return LyricStaggerShift(
        stagger: _stagger,
        index: index,
        child: KeyedSubtree(
          key: key,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LyricGapDots(
              clock: _clock,
              startMs: entry.timeMs,
              endMs: next ?? entry.timeMs + 4000,
              active: delta == 0,
              alpha: alpha,
            ),
          ),
        ),
      );
    }

    final style = isSynced
        ? LyricTypography.synced()
        : LyricTypography.unsynced();
    final isActive = isSynced && delta == 0;

    // Every row that draws anything is held in a LyricStaggerShift (below): the
    // fan-out is by index, so a gap row that sat still between two rows that
    // moved would be run over by the one above it.
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isSynced ? () => _onLineTap(index, lyrics) : null,
      child: Padding(
        // 6 here + 8 inside the row = the 14dp each side the rows always had. The
        // 8 inside is paint headroom: a lifted word, a swelling letter and a blur
        // all draw outside the line's own box, and this is the room they draw in.
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: AnimatedLyricRow(
          alpha: alpha,
          blurDp: isSynced
              ? LyricLineStyle.blurFor(distance: distance, isBrowsing: browsing)
              : 0.0,
          scale: isSynced ? LyricLineStyle.scaleFor(distance: distance) : 1.0,
          // A line-synced line is lit once it is being sung or has been sung.
          lit: (!isSynced || delta <= 0) ? 1.0 : 0.0,
          builder: (context, v) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              key: key,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LyricLine(
                  entry: entry,
                  clock: _clock,
                  style: style,
                  alpha: v.alpha,
                  lit: v.lit,
                  blurSigma: v.blurSigma,
                  feather: isActive,
                  // The sweep keeps running while browsing; the swell does not.
                  glow: isActive && !browsing,
                ),
                LyricSubLineView(
                  controller: _subController,
                  clock: _clock,
                  style: LyricTypography.subLine(),
                  original: entry,
                  entryProvider: () => _subEntryAt(index),
                  alpha: v.alpha,
                  lit: v.lit,
                  blurSigma: v.blurSigma,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return LyricStaggerShift(stagger: _stagger, index: index, child: row);
  }

  // ── The two mode discs ─────────────────────────────────────────────────────

  Widget _buildDisc({
    required IconData icon,
    required String semanticLabel,
    required String activeSemanticLabel,
    required SubLineMode mode,
  }) {
    return ListenableBuilder(
      listenable: _subController,
      builder: (context, _) {
        _reconcileSubLine();

        final status = _subController.status(mode);
        // The globe is pointless on a lyric that is already Latin, and saying so
        // is better than a disc that spins, returns the identical text and renders
        // a sub-line indistinguishable from the original above it. Decided from
        // the LYRIC rather than from the last tap, so the disc is right the moment
        // it appears; the controller applies the same rule on the tap.
        final alreadyLatin = mode == SubLineMode.romanized && _lyricIsLatinScript;
        final nothingToDo = alreadyLatin || status == SubLineStatus.sameLanguage;
        // Lit by the transform REQUESTED, not the one still folding away: the disc
        // answers the tap at once.
        final showing = _subController.mode == mode;

        return TransformDisc(
          icon: icon,
          semanticLabel: alreadyLatin
              ? 'These lyrics already use Latin characters'
              : status == SubLineStatus.sameLanguage
                  ? 'Already in ${LyricsTranslationService.languageName(_subController.targetLanguage)}'
                  : showing
                      ? activeSemanticLabel
                      : semanticLabel,
          // Per disc: only the transform in flight spins. One flag for both made
          // the OTHER disc spin too, and invited a tap on it that raced the first.
          state: status == SubLineStatus.loading
              ? TransformButtonState.loading
              : nothingToDo
                  ? TransformButtonState.sameLanguage
                  : showing
                      ? TransformButtonState.ready
                      : TransformButtonState.idle,
          active: showing,
          onTap: () => _onDiscTap(mode),
        );
      },
    );
  }

  /// Drops the transform if the lyric it was made for has been replaced.
  ///
  /// A provider switch changes the words under the same track, so the track key
  /// never notices; and a sub-line made for the old words, painted under the new
  /// ones, is a translation of a different lyric. Compared by content, so a
  /// refetch that returns the same words keeps what the reader asked for.
  ///
  /// Deferred to after the frame: this is called while the discs build, and the
  /// controller notifies.
  void _reconcileSubLine() {
    final entries = _lyricsRef;
    if (entries == null || _subController.matchesLyrics(entries)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Asked again: a tap in the meantime may already have adopted the new
      // lyric, and resetting THEN would cancel the request it just started.
      final latest = _lyricsRef;
      if (latest != null && !_subController.matchesLyrics(latest)) {
        _subController.onSourceChanged();
      }
    });
  }

  /// Whether every lyric line is already in Latin script.
  bool get _lyricIsLatinScript {
    final entries = _lyricsRef;
    if (entries == null || entries.isEmpty) return false;
    return LyricsTranslationService.entriesAreLatin(entries);
  }

  Future<void> _onDiscTap(SubLineMode mode) async {
    if (_lyricsRef == null) return;
    final track = widget.trackKey;
    if (track == null || track.isEmpty) return;

    // Read on every tap, so a change in Settings takes effect without a restart;
    // the caller's explicit language wins. The device fallback is a BASE language
    // (`en`), not `Platform.localeName` (`en_US`), which was sent as `tl=en_US`.
    final language = widget.translationLanguage ??
        await LyricsTranslationService.instance.targetLanguage();
    if (!mounted) return;
    // Re-read: the lyric may have been replaced while the setting was read.
    final entries = _lyricsRef;
    if (entries == null) return;

    final outcome = await _subController.toggle(
      mode,
      trackKey: track,
      sourceLines: [for (final entry in entries) entry.text],
      targetLanguage: language,
    );
    if (!mounted) return;

    // TELL the reader rather than doing nothing. A disc that silently refuses a
    // tap is indistinguishable from a broken one.
    switch (outcome) {
      case SubLineTap.sameLanguage:
        _showTransformMessage(
          mode == SubLineMode.romanized
              ? 'These lyrics already use Latin characters'
              : 'Already in ${LyricsTranslationService.languageName(language)}',
        );
      case SubLineTap.unavailable:
        _showTransformMessage(
          mode == SubLineMode.romanized
              ? 'Romanization is unavailable for these lyrics'
              : 'Translation is unavailable right now',
        );
      case SubLineTap.shown ||
            SubLineTap.hidden ||
            SubLineTap.ignored ||
            SubLineTap.superseded ||
            SubLineTap.empty:
        break;
    }
  }
  /// A snackbar rather than a new panel: this is a confirmation about a tap the
  /// reader just made, and the reference treats it as a transient message too
  /// (`PlayerLyrics.kt:2791-2794`).
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
}

/// Fades the top and bottom 28dp of the list to nothing.
///
/// BitChord `fadingEdges()` (`PlayerQueue.kt:125-146`): an offscreen layer with
/// a vertical gradient, so a line scrolling off dissolves instead of being cut by
/// a hard edge - which is what the "Lyrics by X" row used to slice through.
///
/// NOTHING GLASS may sit inside this: it is a translucent layer, and a backdrop
/// lens under one goes flat. The discs are outside it for that reason.
class _FadingEdges extends StatelessWidget {
  const _FadingEdges({required this.height, required this.child});

  final double height;
  final Widget child;

  static const double _edge = 28.0;

  @override
  Widget build(BuildContext context) {
    if (height <= _edge * 2) return child;
    final fraction = _edge / height;
    // Built once per height, not once per repaint of the mask.
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Color(0x00000000),
        Color(0xFF000000),
        Color(0xFF000000),
        Color(0x00000000),
      ],
      stops: [0.0, fraction, 1.0 - fraction, 1.0],
    );
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => shader.createShader(rect),
      child: child,
    );
  }
}
