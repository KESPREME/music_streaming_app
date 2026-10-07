import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/lyrics_entry.dart';
import '../services/lyrics/lyric_clock.dart';
import '../services/lyrics/lyric_sweep.dart';
import 'lyric_swept_line.dart';

/// What the strip above the seek bar is currently saying.
///
/// The reference has five branches and they are genuinely different facts, not
/// flavours of one state (PlayerLyrics.kt:2492-2681). Ours used to collapse all
/// five into "an intro phrase", which meant a song with no lyrics anywhere
/// cheerfully displayed *Let it breathe* for the whole track while the row
/// underneath said **Lyrics unavailable**. Two truths, one line.
enum LyricStripState {
  /// A lookup is in flight. Static and dim.
  loading,

  /// The song is playing but nothing has been sung yet.
  intro,

  /// The lookup finished with nothing. Held, then fades out entirely.
  unavailable,

  /// Lyrics exist but carry no timings, so there is nothing to sweep and nothing
  /// to follow. Offers the way in instead of pretending.
  unsynced,

  /// A plain line-synced line, drawn as text.
  plain,

  /// A word-synced line, drawn as the sweep.
  swept,
}

/// The one-line lyric that sits above the seek bar.
///
/// BitChord's `CurrentLyricStrip` (PlayerLyrics.kt:509). Three decisions in here
/// that are load-bearing, and all three were wrong before:
///
/// * **One clock.** The index came off `positionStream` (≈200ms cadence) while the
///   wipe came off `LyricClock`. Two clocks means the line that switches and the
///   line that sweeps can disagree for up to a stream period. Here both read
///   [clock], and the widget only rebuilds when the INDEX moves.
/// * **No lift, no bloom.** The reference passes `rise = false` and
///   `glowAlpha = 0` for exactly this widget (`:2616`, `:2334`): on a single
///   pinned line a word rising once a second reads as the strip twitching.
/// * **One line.** Clamped to one row with an ellipsis. This sits in the deck,
///   which must never resize itself under a layout that is supposed to be fixed.
class LyricStrip extends StatefulWidget {
  const LyricStrip({
    super.key,
    required this.lyrics,
    required this.clock,
    required this.introPhrase,
    required this.onTap,
    this.isLoading = false,
    this.hasLyrics = false,
    this.positionOverrideMs,
  });

  /// The lyric for the current track, or null while it is being fetched.
  final List<LyricsEntry>? lyrics;

  /// The panel's clock. The single source of truth for both the line and the wipe.
  final LyricClock clock;

  /// Shown before the first vocal line.
  final String introPhrase;

  final bool isLoading;

  /// Whether the lookup produced anything at all.
  final bool hasLyrics;

  /// Set while the reader is dragging the scrubber, so the strip shows the line
  /// they are scrubbing TO rather than the one playing.
  final int? positionOverrideMs;

  final VoidCallback onTap;

  @override
  State<LyricStrip> createState() => _LyricStripState();
}

class _LyricStripState extends State<LyricStrip> {
  int _index = -1;
  bool _isAnimated = false;

  /// True once the lookup has come back empty, so the strip can hold and fade.
  bool _showUnavailable = false;
  Timer? _unavailableTimer;

  /// How long "no lyrics" is held before it fades.
  static const Duration _unavailableHold = Duration(seconds: 5);

  /// How long the fade itself takes.
  static const Duration _unavailableFade = Duration(milliseconds: 900);

  double _unavailableOpacity = 0.55;

  /// The unresolved-to-dismissed timer for the unavailable state.
  Timer? _unavailableFadeTimer;

  @override
  void initState() {
    super.initState();
    widget.clock.addListener(_onClock);
    _resolveIndex();
  }

  @override
  void didUpdateWidget(covariant LyricStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock != widget.clock) {
      oldWidget.clock.removeListener(_onClock);
      widget.clock.addListener(_onClock);
      _resolveIndex(force: true);
      return;
    }
    _reconcileAvailability();
  }

  @override
  void dispose() {
    widget.clock.removeListener(_onClock);
    _unavailableTimer?.cancel();
    _unavailableFadeTimer?.cancel();
    super.dispose();
  }

  /// The clock ticks about sixty times a second. Rebuilding the strip on every
  /// tick would rebuild a Row that is almost always showing the same words; the
  /// index is the only thing worth rebuilding for.
  void _onClock() {
    _resolveIndex();
  }

  void _resolveIndex({bool force = false}) {
    final lyrics = widget.lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      if (force || _index != -1) setState(() => _index = -1);
      _reconcileAvailability();
      return;
    }
    final override = widget.positionOverrideMs;
    final positionMs =
        override ?? widget.clock.positionMs;
    final next = activeLineIndex(lyrics, positionMs);
    if (next == _index && !force) return;
    if (mounted) setState(() => _index = next);
  }

  /// Drives the hold-then-fade of "no lyrics".
  ///
  /// A strip that empties the instant the answer arrives looks like a glitch; the
  /// reference holds it for five seconds so a slow lookup is not reported as a
  /// miss (PlayerLyrics.kt:2641-2668).
  void _reconcileAvailability() {
    final unavailable = !widget.isLoading && !widget.hasLyrics;
    if (unavailable == _showUnavailable) return;

    _unavailableTimer?.cancel();
    _unavailableFadeTimer?.cancel();

    if (unavailable) {
      _showUnavailable = true;
      _unavailableOpacity = 0.55;
      if (!mounted) return;
      setState(() {});
      _unavailableTimer = Timer(_unavailableHold, () {
        if (!mounted) return;
        _unavailableFadeTimer = Timer.periodic(
          const Duration(milliseconds: 16),
          (timer) {
            if (!mounted) {
              timer.cancel();
              return;
            }
            setState(() {
              _unavailableOpacity -= 16 / _unavailableFade.inMilliseconds;
            });
            if (_unavailableOpacity <= 0) {
              timer.cancel();
              _showUnavailable = false;
            }
          },
        );
      });
    } else {
      _showUnavailable = false;
      if (mounted) setState(() {});
    }
  }

  /// Everything the current position resolves to, in one place.
  ({LyricStripState state, LyricsEntry? entry, String text}) _resolve() {
    if (widget.isLoading) {
      return (state: LyricStripState.loading, entry: null, text: '');
    }
    if (_showUnavailable) {
      return (state: LyricStripState.unavailable, entry: null, text: '');
    }

    final lyrics = widget.lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return (state: LyricStripState.loading, entry: null, text: '');
    }

    final index = _index;
    if (index < 0 || index >= lyrics.length) {
      return (
        state: LyricStripState.intro,
        entry: null,
        text: widget.introPhrase,
      );
    }

    final line = lyrics[index];
    final text = line.text.trim();
    final firstVocal = lyrics.indexWhere(
      (e) => e.text.trim().isNotEmpty && !e.isMusicalBreak,
    );
    final positionMs = widget.positionOverrideMs ?? widget.clock.positionMs;
    final beforeFirstVocal = firstVocal >= 0 &&
        (index < firstVocal || positionMs < lyrics[firstVocal].timeMs);

    if (text.isEmpty || line.isMusicalBreak || beforeFirstVocal) {
      return (
        state: LyricStripState.intro,
        entry: null,
        text: widget.introPhrase,
      );
    }

    if (!widget.hasSyncedLyricsAnywhere) {
      return (state: LyricStripState.unsynced, entry: null, text: '');
    }
    if (line.isWordSynced) {
      return (state: LyricStripState.swept, entry: line, text: text);
    }
    return (state: LyricStripState.plain, entry: line, text: text);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve();
    _isAnimated = resolved.state == LyricStripState.swept;

    return Semantics(
      label: switch (resolved.state) {
        LyricStripState.swept ||
        LyricStripState.plain =>
          'Current lyric: ${resolved.text}. Tap to open full lyrics.',
        LyricStripState.unsynced => 'Lyrics are not timed for this song. '
            'Tap to open full lyrics.',
        LyricStripState.unavailable => 'No lyrics found for this song.',
        LyricStripState.loading => 'Looking for lyrics.',
        LyricStripState.intro =>
          'No words yet. Tap to open full lyrics.',
      },
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: _isAnimated
              ? AnimatedBuilder(
                  // Only the WIPE animates here, and it animates on the clock -
                  // not on a switcher, because the line does not change when the
                  // words inside it do.
                  animation: widget.clock,
                  builder: (context, _) => _body(resolved),
                )
              : _body(resolved),
        ),
      ),
    );
  }

  Widget _body(({LyricStripState state, LyricsEntry? entry, String text}) resolved) {
    switch (resolved.state) {
      case LyricStripState.loading:
        return _plain(
          key: const ValueKey('lyric-strip-loading'),
          text: widget.introPhrase,
          alpha: 0.55,
          weight: FontWeight.w500,
          glyph: Icons.music_note_rounded,
        );

      case LyricStripState.unavailable:
        return Opacity(
          key: const ValueKey('lyric-strip-unavailable'),
          opacity: _unavailableOpacity.clamp(0.0, 1.0),
          child: _plain(
            text: 'No lyrics found',
            alpha: 0.55,
            weight: FontWeight.w500,
          ),
        );

      case LyricStripState.unsynced:
        // No timings, so there is nothing to sweep and nothing to follow. Say so
        // and offer the way in, rather than showing words that will never light.
        return Row(
          key: const ValueKey('lyric-strip-unsynced'),
          children: [
            const Icon(
              Icons.music_note_rounded,
              size: 16,
              color: Colors.white54,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Open lyrics',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.15,
                ),
              ),
            ),
          ],
        );

      case LyricStripState.intro:
        return _plain(
          key: ValueKey<String>('lyric-strip-intro:${resolved.text}'),
          text: resolved.text,
          alpha: 0.60,
          weight: FontWeight.w500,
          glyph: Icons.music_note_rounded,
        );

      case LyricStripState.plain:
        return _animatedLine(
          key: ValueKey<String>('lyric-strip-plain:${resolved.entry!.timeMs}'),
          child: Text(
            resolved.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _style(alpha: 0.95, weight: FontWeight.w600),
          ),
        );

      case LyricStripState.swept:
        return _animatedLine(
          key: ValueKey<String>('lyric-strip-swept:${resolved.entry!.timeMs}'),
          child: LyricSweptLine(
            entry: resolved.entry!,
            clock: widget.clock,
            style: _style(alpha: 0.95, weight: FontWeight.w600),
            dimColor: Colors.white.withValues(alpha: stripUnsungAlpha),
            // The strip is ONE pinned line, so the panel's motion is off here on
            // purpose: a word rising on a fixed row once a second reads as the
            // strip twitching, not as emphasis. Same call as the reference
            // (PlayerLyrics.kt:2616, rise = false).
            rise: false,
            glow: false,
            // Clamped: a wrapped lyric line here would grow the deck, and the
            // deck is the one surface that must never resize itself.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            isActive: true,
            onTap: widget.onTap,
          ),
        );
    }
  }

  /// The line-to-line handover.
  ///
  /// 340ms both ways, sliding 35% of the strip's own height in AND out, with the
  /// outgoing line travelling downward (PlayerLyrics.kt:2584-2627). Ours slid in
  /// 28% and did not slide out at all, so a handover read as the new line fading
  /// up through a stationary old one.
  Widget _animatedLine({required Key key, required Widget child}) =>
      AnimatedSwitcher(
        duration: stripHandoverDuration,
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, stripSlideFraction),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[...previous, if (current != null) current],
        ),
        child: child,
      );

  Widget _plain({
    required String text,
    required double alpha,
    required FontWeight weight,
    Key? key,
    IconData? glyph,
  }) =>
      Row(
        key: key,
        children: [
          if (glyph != null) ...[
            Icon(glyph, size: 16, color: Colors.white.withValues(alpha: alpha)),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _style(alpha: alpha, weight: weight),
            ),
          ),
        ],
      );

  TextStyle _style({required double alpha, required FontWeight weight}) =>
      GoogleFonts.plusJakartaSans(
        color: Colors.white.withValues(alpha: alpha),
        fontSize: 14.5,
        fontWeight: weight,
        letterSpacing: -0.15,
      );
}

/// Alpha of the part of the strip that has not been sung yet.
///
/// `UNSUNG_ALPHA_STRIP` (PlayerLyrics.kt:153). Distinct from the panel's 0.45: a
/// single pinned line has nothing behind it for the eye to compare against, so it
/// needs more of its own colour to stay readable.
const double stripUnsungAlpha = 0.55;

/// How long one line takes to hand over to the next.
const Duration stripHandoverDuration = Duration(milliseconds: 340);

/// How far of the strip's own height the handover slides.
///
/// `it * 0.35f` on both sides of the reference's `AnimatedContent`.
const double stripSlideFraction = 0.35;

extension _HasSyncedLyrics on LyricStrip {
  /// Whether ANY line in the lyric carries timings.
  ///
  /// Decides between "unsynced" and "swept": a line with no timings anywhere on
  /// the song will never light up, and offering a static line that pretends to be
  /// following along is worse than saying it is not timed.
  bool get hasSyncedLyricsAnywhere {
    final lyrics = this.lyrics;
    if (lyrics == null) return false;
    return lyrics.any((e) => e.isWordSynced);
  }
}