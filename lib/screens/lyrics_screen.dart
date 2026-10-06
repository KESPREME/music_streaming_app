// lib/screens/lyrics_screen.dart
import 'dart:async';
import 'dart:io';
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
  bool _isUserScrolling = false;
  bool _autoScrollEnabled = true;
  Timer? _scrollResumeTimer;
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

    _scrollController.addListener(_onScroll);
  }

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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollResumeTimer?.cancel();
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

  void _onScroll() {
    if (!_isUserScrolling &&
        _scrollController.position.isScrollingNotifier.value) {
      if (mounted) {
        setState(() {
          _isUserScrolling = true;
          _autoScrollEnabled = false;
        });
      }
    }

    if (_isUserScrolling) {
      _scrollResumeTimer?.cancel();
      _scrollResumeTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) {
          setState(() {
            _isUserScrolling = false;
            _autoScrollEnabled = true;
            if (_autoScrollEnabled) _scrollToCurrentLine();
          });
        }
      });
    }
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
    _correctTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
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

void _scrollToCurrentLine() {
    if (_currentLineIndex >= 0 && _currentLineIndex < _itemKeys.length) {
      final key = _itemKeys[_currentLineIndex];
      final keyContext = key.currentContext;

      // Leading the singing by a beat rather than following it.
      //
      // Scrolling to the line being sung puts it under the singer's mouth and
      // leaves the reader looking at what just passed. Aiming at the line the
      // clock is about to reach puts the words being sung where the eye already
      // is. The lead is bounded by the gap to the next line - see
      // scrollLeadMs - so a fast passage does not run the verse off the top.
      final target = _scrollTargetIndex;

      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.32,
          duration: _lyricScrollDuration,
          curve: _lyricScrollCurve,
        );
        return;
      }

      final screenHeight = MediaQuery.of(context).size.height;
      final paddingTop = screenHeight * 0.22;
      const double estimatedItemHeight = 70.0;
      final itemTop = paddingTop + (target * estimatedItemHeight);
      final targetOffset =
          itemTop - (screenHeight * 0.32) + (estimatedItemHeight / 2);

      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: _lyricScrollDuration,
        curve: _lyricScrollCurve,
      );
    }
  }

  /// The line the scroll should centre on, which leads the singing.
  int get _scrollTargetIndex {
    final lyrics = _lyricsRef;
    if (lyrics == null || lyrics.isEmpty) return _currentLineIndex;
    final focused = focusLineIndex(lyrics, _clock.positionMs);
    return focused >= 0 ? focused : _currentLineIndex;
  }

  List<LyricsEntry>? _lyricsRef;

  /// Reference easing for lyric motion: a long settle with almost no initial
  /// acceleration, which keeps a line from snapping into place and then
  /// creeping. Monotonic - an overshooting curve here makes the scroll finish
  /// before the animation does, which reads as the page jumping early.
  static const Curve _lyricScrollCurve = Cubic(0.41, 0.0, 0.12, 0.99);
  static const Duration _lyricScrollDuration = Duration(milliseconds: 400);

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
    return FadeTransition(
      opacity: _fadeController,
      child: Stack(
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
            child: ListView.builder(
            controller: _scrollController,
            // The top inset clears the header's glass discs; the bottom one is
            // the measured player deck, which is an overlay above this screen
            // and would otherwise swallow the last lines of the lyric.
            padding: EdgeInsets.fromLTRB(24, 56, 24, 8 + widget.bottomInset),
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
    return TransformDisc(
      icon: icon,
      semanticLabel: semanticLabel,
      state: _subController.isBusy
          ? TransformButtonState.loading
          : _subController.shownMode == mode
              ? TransformButtonState.ready
              : TransformButtonState.idle,
      active: _subController.shownMode == mode,
      onTap: () => _onDiscTap(mode),
    );
  }

  Future<void> _onDiscTap(SubLineMode mode) async {
    final entries = _lyricsRef;
    final track = widget.trackKey;
    if (entries == null || track == null || track.isEmpty) return;

    await _subController.toggle(
      mode,
      trackKey: track,
      sourceLines: entries.map((e) => e.text).toList(),
      targetLanguage: widget.translationLanguage ?? Platform.localeName,
    );
    if (mounted) setState(() {});
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

    // Always animated, even through 0: an animated 0.0 keeps the exact same
    // child and only the sigma tween moves, so a line that crosses its window
    // comes in at the same blur it leaves with rather than blinking it on the
    // slice boundary. BitChord tweens the radius over LYRIC_SETTLE_MS.
    line = AnimatedBlur(
      sigma: blur,
      duration: const Duration(milliseconds: 340),
      child: line,
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 14.0),
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
