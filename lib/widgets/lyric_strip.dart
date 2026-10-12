// lib/widgets/lyric_strip.dart
// The one-line lyric above the seek bar.
//
// BitChord `CurrentLyricStrip` (`PlayerLyrics.kt:509`).

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/lyrics_entry.dart';
import '../services/lyrics/lyric_clock.dart';
import '../services/lyrics/lyric_sweep.dart';
import 'lyric_line/lyric_line.dart';
import 'lyric_line/lyric_typography.dart';

/// What the strip above the seek bar is currently saying.
///
/// The reference has five branches and they are genuinely different facts, not
/// flavours of one state (`PlayerLyrics.kt:2492-2681`). Ours used to collapse
/// all five into "an intro phrase", which meant a song with no lyrics anywhere
/// cheerfully displayed *Let it breathe* for the whole track while the row
/// underneath said **Lyrics unavailable**. Two truths, one line.
enum LyricStripState {
  /// A lookup is in flight. Static and dim.
  loading,

  /// The song is playing but nothing has been sung yet.
  intro,

  /// The lookup finished with nothing. Held, then fades out entirely.
  unavailable,

  /// Lyrics exist but NO line carries a timestamp, so there is nothing to follow.
  /// Offers the way in instead of pretending.
  unsynced,

  /// A line-synced line: the whole line, in one colour.
  plain,

  /// A word-synced line, drawn as the sweep.
  swept,
}

/// The one-line lyric that sits above the seek bar.
///
/// Load-bearing decisions, each of which was wrong before:
///
/// * **One clock.** Both the line that switches and the wipe inside it read
///   [clock], and this widget rebuilds only when the INDEX moves. The sweep
///   itself is a render object that listens to the clock on its own, so a
///   60Hz tick never rebuilds anything here.
/// * **No lift, no bloom, no soft edge.** The reference passes `rise = false`
///   and no glow for exactly this widget: on a single pinned line a word
///   rising once a second reads as the strip twitching.
/// * **One line.** Clamped to one row with an ellipsis. This sits in the deck,
///   which must never resize itself.
/// * **"Unsynced" means NO TIMESTAMPS, not "no word timings".** It used to mean
///   the latter, so every ordinary line-synced (LRC) song showed "Open lyrics"
///   instead of its current line.
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
    this.displayLines,
  });

  /// The lyric for the current track, or null while it is being fetched.
  final List<LyricsEntry>? lyrics;

  /// The text to show INSTEAD of each line of [lyrics], when a translation or
  /// romanization is the active mode; null to show the originals.
  ///
  /// BitChord's strip reads `displayedLyrics`, so turning a translation on
  /// changes the strip over the seek bar as well as the panel. Parallel to
  /// [lyrics]; ignored unless the lengths match, because text from another lyric
  /// under this one's timing is worse than the original. The wipe still follows
  /// the ORIGINAL line's timing (a translation has none of its own).
  ///
  /// Take it from `SubLineController.displayedLinesFor(lyrics)`, which also
  /// refuses lines that were made for a different lyric.
  final List<String>? displayLines;

  /// The player's clock: the single source of truth for both line and wipe.
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
  bool _listening = false;

  /// True once the lookup has come back empty, so the strip can hold and fade.
  bool _showUnavailable = false;
  double _unavailableOpacity = 0.55;
  Timer? _unavailableTimer;

  /// How long "no lyrics" is held before it fades.
  static const Duration _unavailableHold = Duration(seconds: 5);

  /// How long the fade itself takes.
  static const Duration _unavailableFade = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    _resolveIndex(notify: false);
    _reconcileAvailability(notify: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listens to the clock only while its subtree is live; a strip in a route
    // that is not current must not hold the frame loop up.
    _syncListener(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(covariant LyricStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock != widget.clock && _listening) {
      oldWidget.clock.removeListener(_onClock);
      widget.clock.addListener(_onClock);
    }
    _resolveIndex(notify: false);
    _reconcileAvailability(notify: false);
  }

  @override
  void dispose() {
    _syncListener(false);
    _unavailableTimer?.cancel();
    super.dispose();
  }

  void _syncListener(bool enabled) {
    if (enabled && !_listening) {
      widget.clock.addListener(_onClock);
      _listening = true;
      _resolveIndex();
    } else if (!enabled && _listening) {
      widget.clock.removeListener(_onClock);
      _listening = false;
    }
  }

  void _onClock() => _resolveIndex();

  /// The clock ticks about sixty times a second; the index moves about once every
  /// few seconds. Only the index is worth rebuilding for.
  void _resolveIndex({bool notify = true}) {
    final lyrics = widget.lyrics;
    var next = -1;
    if (lyrics != null && lyrics.isNotEmpty) {
      final position = widget.positionOverrideMs ?? widget.clock.positionMs;
      next = activeLineIndex(lyrics, position);
    }
    if (next == _index) return;
    _index = next;
    if (notify && mounted) setState(() {});
  }

  /// Drives the hold-then-fade of "no lyrics".
  ///
  /// A strip that empties the instant the answer arrives looks like a glitch; the
  /// reference holds it for five seconds so a slow lookup is not reported as a
  /// miss (`PlayerLyrics.kt:2641-2668`). The fade is an implicit animation: one
  /// timer for the hold, none for the fade.
  void _reconcileAvailability({bool notify = true}) {
    final unavailable = !widget.isLoading && !widget.hasLyrics;
    if (unavailable == _showUnavailable) return;

    _unavailableTimer?.cancel();
    _showUnavailable = unavailable;
    _unavailableOpacity = 0.55;
    if (notify && mounted) setState(() {});
    if (!unavailable) return;
    _unavailableTimer = Timer(_unavailableHold, () {
      if (!mounted) return;
      setState(() => _unavailableOpacity = 0.0);
    });
  }

  /// Everything the current position resolves to, in one place.
  ///
  /// [timing] is the ORIGINAL line when [entry] is a translation of it: the wipe
  /// follows the original's words, because the translation has none.
  ({LyricStripState state, LyricsEntry? entry, String text, LyricsEntry? timing})
      _resolve() {
    if (widget.isLoading) {
      return (state: LyricStripState.loading, entry: null, text: '', timing: null);
    }
    if (_showUnavailable) {
      return (
        state: LyricStripState.unavailable,
        entry: null,
        text: '',
        timing: null,
      );
    }

    final lyrics = widget.lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return (state: LyricStripState.loading, entry: null, text: '', timing: null);
    }
    // Timed means a line has a stamp OR words with their own. (A lyric whose first
    // line sits at 0ms is still timed if anything after it is.)
    if (!lyrics.any((e) => e.timeMs > 0 || e.isWordSynced)) {
      return (
        state: LyricStripState.unsynced,
        entry: null,
        text: '',
        timing: null,
      );
    }

    final index = _index;
    if (index < 0 || index >= lyrics.length) {
      return (
        state: LyricStripState.intro,
        entry: null,
        text: widget.introPhrase,
        timing: null,
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
        timing: null,
      );
    }

    // The active mode's text, when there is one for THIS line. The state is the
    // original's: a word-synced original still sweeps, in step, under a
    // translation.
    final display = widget.displayLines;
    final shown = display != null &&
            display.length == lyrics.length &&
            display[index].trim().isNotEmpty
        ? display[index].trim()
        : null;
    final state =
        line.isWordSynced ? LyricStripState.swept : LyricStripState.plain;
    if (shown != null && shown != text) {
      return (
        state: state,
        entry: LyricsEntry(timeMs: line.timeMs, endMs: line.endMs, text: shown),
        text: shown,
        timing: line.isWordSynced ? line : null,
      );
    }
    return (state: state, entry: line, text: text, timing: null);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve();

    return Semantics(
      label: switch (resolved.state) {
        LyricStripState.swept ||
        LyricStripState.plain =>
          'Current lyric: ${resolved.text}. Tap to open full lyrics.',
        LyricStripState.unsynced => 'Lyrics are not timed for this song. '
            'Tap to open full lyrics.',
        LyricStripState.unavailable => 'No lyrics found for this song.',
        LyricStripState.loading => 'Looking for lyrics.',
        LyricStripState.intro => 'No words yet. Tap to open full lyrics.',
      },
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: _body(resolved),
        ),
      ),
    );
  }

  Widget _body(
    ({
      LyricStripState state,
      LyricsEntry? entry,
      String text,
      LyricsEntry? timing,
    }) resolved,
  ) {
    switch (resolved.state) {
      case LyricStripState.loading:
        return _status(
          key: const ValueKey('lyric-strip-loading'),
          text: widget.introPhrase,
          alpha: 0.55,
          glyph: Icons.music_note_rounded,
        );

      case LyricStripState.unavailable:
        return AnimatedOpacity(
          key: const ValueKey('lyric-strip-unavailable'),
          opacity: _unavailableOpacity,
          duration: _unavailableFade,
          curve: Curves.easeOut,
          child: _status(text: 'No lyrics found', alpha: 1.0),
        );

      case LyricStripState.unsynced:
        // No timestamps anywhere, so there is nothing to follow. Say so and offer
        // the way in, rather than showing words that will never move.
        return _status(
          key: const ValueKey('lyric-strip-unsynced'),
          text: 'Open lyrics',
          alpha: 0.55,
          glyph: Icons.music_note_rounded,
          chevron: true,
        );

      case LyricStripState.intro:
        return _status(
          key: ValueKey<String>('lyric-strip-intro:${resolved.text}'),
          text: resolved.text,
          alpha: 0.60,
          glyph: Icons.music_note_rounded,
        );

      case LyricStripState.plain:
      case LyricStripState.swept:
        final entry = resolved.entry!;
        return _animatedLine(
          // Keyed on WHAT the line is, not when it starts: a provider switch that
          // hands over the same words at a slightly different stamp must not
          // slide the line out and the same line back in.
          key: ValueKey<String>('lyric-strip:$_index|${entry.text}'),
          child: LyricLine(
            entry: entry,
            timingSource: resolved.timing,
            clock: widget.clock,
            style: LyricTypography.strip(),
            // A single pinned line has nothing behind it for the eye to compare
            // against, so its unsung part keeps more of its own colour.
            tailAlpha: stripUnsungAlpha,
            // Off on purpose; see the class doc.
            rise: false,
            glow: false,
            feather: false,
            // Clamped: a wrapped lyric line here would grow the deck.
            maxLines: 1,
            ellipsis: true,
          ),
        );
    }
  }

  /// The line-to-line handover.
  ///
  /// 340ms both ways, sliding 35% of the strip's own height in AND out, with the
  /// outgoing line travelling the other way (`PlayerLyrics.kt:2584-2627`). The
  /// clip is what keeps a travelling line from painting outside its row.
  Widget _animatedLine({required Key key, required Widget child}) => ClipRect(
        child: AnimatedSwitcher(
          duration: stripHandoverDuration,
          switchInCurve: Curves.fastOutSlowIn,
          switchOutCurve: Curves.fastOutSlowIn,
          transitionBuilder: (child, animation) {
            // One builder serves both roles, and an AnimatedSwitcher reports the
            // same animation status for both, so the role cannot be read from the
            // animation (invariant 3). It is carried on the child instead: the
            // line that IS the current key enters from below; any other is on its
            // way out and leaves upward. (The builder is a fresh closure every
            // build, which is what makes the switcher re-run it for the outgoing
            // child with the up-to-date key.)
            final incoming = child.key == key;
            final begin = incoming
                ? const Offset(0.0, stripSlideFraction)
                : const Offset(0.0, -stripSlideFraction);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(begin: begin, end: Offset.zero)
                    .animate(animation),
                child: child,
              ),
            );
          },
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[...previous, if (current != null) current],
          ),
          child: KeyedSubtree(key: key, child: child),
        ),
      );

  /// A status line: an optional note, text, an optional chevron.
  Widget _status({
    required String text,
    required double alpha,
    Key? key,
    IconData? glyph,
    bool chevron = false,
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
              style: LyricTypography.strip().copyWith(
                color: Colors.white.withValues(alpha: alpha),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (chevron)
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.5),
            ),
        ],
      );
}

/// Alpha of the part of the strip that has not been sung yet.
///
/// `UNSUNG_ALPHA_STRIP` (`PlayerLyrics.kt:153`). Distinct from the panel's 0.45: a
/// single pinned line has nothing behind it for the eye to compare against, so it
/// needs more of its own colour to stay readable.
const double stripUnsungAlpha = 0.55;

/// How long one line takes to hand over to the next.
const Duration stripHandoverDuration = Duration(milliseconds: 340);

/// How far of the strip's own height the handover slides.
///
/// `it * 0.35f` on both sides of the reference's `AnimatedContent`.
const double stripSlideFraction = 0.35;
