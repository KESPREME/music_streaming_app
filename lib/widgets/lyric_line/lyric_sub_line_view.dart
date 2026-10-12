// lib/widgets/lyric_line/lyric_sub_line_view.dart
// A translation or romanization, revealed under its original.
//
// BitChord `revealBelow` (`PlayerLyrics.kt`): the sub-line's height opens with
// the reveal, it slides down 60% of its own height out from behind the line
// above, and its alpha is the reveal SQUARED - faint for most of the travel,
// full strength on arrival rather than fading in evenly.
//
// THE CLIP IS THE POINT. The old version let the sliding text paint over the
// original line while it travelled (an `Align(heightFactor)` does not clip), so
// turning a translation on briefly drew two lines of text on top of each other:
// the "dupes" reported on a translate toggle.
//
// It is drawn by [LyricLine] too, with the ORIGINAL as its timing source, so a
// translation sweeps in step with the words it translates instead of sitting
// there fully lit.

import 'package:flutter/widgets.dart';

import '../../models/lyrics_entry.dart';
import '../../services/lyrics/lyric_clock.dart';
import '../../services/lyrics/lyric_sub_line.dart';
import 'lyric_line.dart';

/// Alpha of a sub-line at full reveal. BitChord `SUB_LYRIC_ALPHA`.
const double lyricSubLineAlpha = 0.85;

class LyricSubLineView extends StatelessWidget {
  const LyricSubLineView({
    super.key,
    required this.controller,
    required this.clock,
    required this.style,
    required this.original,
    required this.entryProvider,
    required this.alpha,
    required this.lit,
    required this.blurSigma,
  });

  final SubLineReveal controller;
  final LyricClock clock;
  final TextStyle style;

  /// The line this sits under; drives the sweep when it is word-synced.
  final LyricsEntry original;

  /// The transformed line, or null when none is showing. A callback so it is
  /// read inside the listenable below: only this sub-line rebuilds during the
  /// reveal, not all thirty rows of the lyric.
  final LyricsEntry? Function() entryProvider;

  final double alpha;
  final double lit;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final entry = entryProvider();
        if (entry == null || entry.text.trim().isEmpty) {
          return const SizedBox.shrink();
        }
        final reveal = controller.progress.isNaN
            ? 0.0
            : controller.progress.clamp(0.0, 1.0).toDouble();
        if (reveal <= 0) return const SizedBox.shrink();

        final fontSize = style.fontSize ?? 19;
        return ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            // Collapses to nothing when closed, so a hidden sub-line reserves no
            // height in a list of thirty rows.
            heightFactor: reveal,
            child: Transform.translate(
              offset: Offset(0, -fontSize * 1.3 * 0.6 * (1 - reveal)),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: LyricLine(
                  entry: entry,
                  timingSource: original.isWordSynced ? original : null,
                  clock: clock,
                  style: style,
                  alpha: alpha * lyricSubLineAlpha * reveal * reveal,
                  lit: lit,
                  blurSigma: blurSigma,
                  // A translation has no words of its own to lift or swell.
                  rise: false,
                  glow: false,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
