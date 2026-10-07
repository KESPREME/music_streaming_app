// lib/widgets/lyric_swept_line.dart
// One lyric line, with a progressive word/syllable wipe.
//
// THE REBUILD-SCOPE CONSTRAINT
//
// A lyrics list has hundreds of lines and a clock that ticks sixty times a
// second. Rebuilding the list on each tick is the most expensive thing this
// screen could do, and it is what it used to do - a 16ms timer calling setState
// on the screen. So the isolation here is structural, not incidental:
//
//   * A line outside its own animation window never rebuilds. The gate is
//     [LyricClock.isAnimating], checked inside the builder, so a 60Hz clock
//     costs nothing for lines that are merely on screen.
//   * A line inside its window rebuilds its own subtree and nothing above it.
//     Only the active line is ever inside its window.
//   * Each line sits in a [RepaintBoundary], so a repainting wipe cannot force
//     its neighbours to repaint.
//
// One small subtree per frame, not one list per frame.
//
// WHY NO ShaderMask AND NO Opacity
//
// Both were the reason the highlight could not simply be added. A ShaderMask
// over a line is a saveLayer per line per frame; an Opacity above it is
// another. Worse, the floating nav bar and the mini-player are backdrop
// lenses, and a translucent layer between a lens and its content isolates the
// backdrop the lens samples - the glass goes flat for the duration. This widget
// paints with a clip and a colour, never with a mask.
//
// MEASURING ONCE, NOT PER FRAME
//
// The clip width has to be "how wide are the first N characters". That is a
// text measurement, and doing it per frame at 60Hz would cost more than the
// rest of the line put together. It is also entirely static for a given text,
// style and width. So [TextPainter.getOffsetForCaret] is walked once per
// layout into a prefix-width table, and each frame is then a single array
// lookup.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/lyrics_entry.dart';
import '../services/lyrics/lyric_clock.dart';
import '../services/lyrics/lyric_growth.dart';
import '../services/lyrics/lyric_sub_line.dart' show SubLineReveal;
import '../services/lyrics/word_lift.dart';
import '../services/lyrics/lyric_sweep.dart';
import '../services/lyrics/lyric_words.dart' show LyricWord;

/// A lyric line that lights progressively as the song reaches it.
class LyricSweptLine extends StatefulWidget {
  const LyricSweptLine({
    super.key,
    required this.entry,
    required this.clock,
    required this.style,
    required this.dimColor,
    required this.isActive,
    this.onTap,
    this.rise = true,
    this.glow = true,
    this.isBrowsing = false,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.subLineProvider,
    this.subLineStyle,
    this.subLineListenable,
  });

  final LyricsEntry entry;
  final LyricClock clock;
  final TextStyle style;

  /// Colour of the part not yet sung.
  final Color dimColor;

  /// Whether this is the line currently being sung. Only the active line gets
  /// the wipe; every other line is drawn once as plain text and never listens
  /// to the clock at all.
  final bool isActive;

  final VoidCallback? onTap;

  /// Whether the sung word RISES while it is being sung.
  ///
  /// True only in the full panel. BitChord passes `rise = false` to the strip and
  /// the sub-row for the same reason (PlayerLyrics.kt:2289-2292, 2616): on a
  /// single pinned line the movement stops reading as emphasis and starts
  /// reading as the strip twitching once a second.
  final bool rise;

  /// Whether a held note swells its letters and blooms.
  ///
  /// Panel only, for the same reason as [rise].
  final bool glow;

  /// Whether the reader is dragging the list.
  ///
  /// Everything is drawn static and unblurred while this is true, so the words
  /// under a moving finger are whole rather than half-wiped.
  final bool isBrowsing;

  /// Clamps the line to this many rows. One for the seek-bar strip - a wrapped
  /// line there grows the deck, which is the one surface that must never resize
  /// itself.
  final int? maxLines;

  final TextOverflow overflow;

  /// The transformed line drawn beneath this one, or null.
  ///
  /// The transform is a SUB-LINE, never a replacement. The word timings on
  /// [entry] are spans of characters in [entry]'s own text; swapping that text
  /// would make every span index the wrong letters and the wipe would light up
  /// words that are not being sung.
  ///
  /// A CALLBACK rather than a string so it is read inside the listenable below,
  /// which rebuilds only this row's sub-line during the reveal instead of
  /// rebuilding all thirty rows of the lyric every frame.
  final String? Function()? subLineProvider;

  /// Style for the sub-line. Smaller and dimmer than [style] by default so the
  /// original stays the line being read.
  final TextStyle? subLineStyle;

  /// Drives the sub-line's reveal. Omit it and the sub-line is static.
  final Listenable? subLineListenable;

  @override
  State<LyricSweptLine> createState() => _LyricSweptLineState();
}

class _LyricSweptLineState extends State<LyricSweptLine> {
  /// Width of the first N characters, for N in 0..text.length.
  ///
  /// Rebuilt only when the text, the style or the available width changes.
  List<double> _prefixWidths = const <double>[];

  /// `(start, end)` character span of each timed word in the line text.
  List<(int, int)?> _wordSpans = const <(int, int)?>[];

  String _measuredText = '';
  TextStyle? _measuredStyle;
  double _measuredWidth = -1;

  @override
  void dispose() {
    _prefixWidths = const <double>[];
    _wordSpans = const <(int, int)?>[];
    super.dispose();
  }

  void _ensureMeasured(double availableWidth) {
    if (_measuredText == widget.entry.text &&
        _measuredStyle == widget.style &&
        _measuredWidth == availableWidth &&
        _prefixWidths.length == widget.entry.text.length + 1) {
      return;
    }

    final text = widget.entry.text;
    final widths = List<double>.filled(text.length + 1, 0);
    if (text.isEmpty || availableWidth <= 0) {
      _prefixWidths = widths;
      _measuredText = text;
      _measuredStyle = widget.style;
      _measuredWidth = availableWidth;
      return;
    }

    final painter = TextPainter(
      text: TextSpan(text: text, style: widget.style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: availableWidth);

    // Walking the caret gives the advance at every character boundary, which
    // is exactly the clip width a wipe of N characters needs.
    for (var i = 0; i < text.length; i++) {
      widths[i + 1] = painter
          .getOffsetForCaret(TextPosition(offset: i + 1), Rect.zero)
          .dx;
    }
    painter.dispose();

    _wordSpans = _locateWords(text, widget.entry.timedWords);

    _prefixWidths = widths;
    _measuredText = text;
    _measuredStyle = widget.style;
    _measuredWidth = availableWidth;
  }

  /// Where each timed word sits in [text] as a `(start, end)` span, or null
  /// where it could not be found.
  ///
  /// Located by walking the text with a search rather than by summing word
  /// lengths. The line text carries separators the words do not, and a source's
  /// word timings are not obliged to tile it exactly. A span that is merely
  /// approximate would lift the wrong substring - and that reads fine in a
  /// screenshot and wrong the moment it moves, so it is worth the search.
  static List<(int, int)?> _locateWords(String text, List<LyricWord> words) {
    final out = List<(int, int)?>.filled(words.length, null);
    var cursor = 0;
    for (var i = 0; i < words.length; i++) {
      final needle = words[i].text.trim();
      if (needle.isEmpty) continue;
      final at = text.indexOf(needle, cursor);
      if (at < 0) continue;
      out[i] = (at, at + needle.length);
      cursor = at + needle.length;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: _buildPrimary(),
          ),
          _buildSubLineSlot(),
        ],
      ),
    );
  }

  /// The transform row, listening only to itself.
  Widget _buildSubLineSlot() {
    final provider = widget.subLineProvider;
    if (provider == null) return const SizedBox.shrink();
    final listenable = widget.subLineListenable;
    if (listenable == null) {
      final text = provider();
      return text == null ? const SizedBox.shrink() : _buildSubLine(text, 1);
    }
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final text = provider();
        if (text == null || text.trim().isEmpty) return const SizedBox.shrink();
        return _buildSubLine(text, _reveal);
      },
    );
  }

  /// 0..1 for the sub-line reveal. Read off the listenable's owner.
  ///
  /// The controller is passed as a [Listenable] rather than as its concrete type
  /// so this widget does not depend on the transform service.
  double get _reveal {
    final l = widget.subLineListenable;
    if (l is SubLineReveal) return l.progress;
    return 1;
  }

  /// The line itself.
  ///
  /// Swept whenever the SOURCE carries word timings, not only while this line is
  /// the one being sung. A line that has been sung closes up as it recedes, so
  /// the panel reads as one continuous light travelling through the song; a
  /// version that snapped a receding line to fully-lit made every handover a jump.
  ///
  /// BitChord does exactly this (`PlayerLyrics.kt:2297`), with one exception:
  /// while the reader is browsing by hand every line is drawn static, so the
  /// text under a moving finger is legible instead of half-wiped.
  Widget _buildPrimary() {
    final entry = widget.entry;
    final sweepable = entry.isWordSynced && !_isBrowsing;

    if (!sweepable) {
      return Text(
        entry.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureMeasured(constraints.maxWidth);
        return AnimatedBuilder(
          animation: widget.clock,
          builder: (context, _) => _buildSwept(),
        );
      },
    );
  }

  /// True while the reader is dragging the list by hand.
  ///
  /// Fed by the panel, not discovered here: this widget has no view of the
  /// scroll. Pass false and every word-synced line sweeps.
  bool get _isBrowsing => widget.isBrowsing;

  /// The transform, revealed downward out from behind the original.
  ///
  /// Height grows from nothing while the words slide down from behind the line
  /// above and fade up. The alpha is applied to the text colour rather than with
  /// an [Opacity] widget on purpose: an Opacity here would allocate a saveLayer
  /// per lyric line - thirty of them for a full song - and this sits in a list
  /// that is already rebuilding on a clock.
  Widget _buildSubLine(String text, double reveal) {
    final base = widget.subLineStyle ??
        widget.style.copyWith(
          fontSize: (widget.style.fontSize ?? 28) * 0.72,
          fontWeight: FontWeight.w500,
          height: 1.15,
        );
    final progress = reveal.isNaN ? 0.0 : reveal.clamp(0.0, 1.0);
    // Squared, matching the reference: it stays faint for most of the travel and
    // arrives at full strength at the end rather than fading in evenly.
    final alpha = progress * progress;
    final style = base.copyWith(
      color: (base.color ?? Colors.white).withValues(alpha: alpha),
    );

    // heightFactor of 0 collapses the row entirely, so a closed sub-line costs
    // no vertical space in a list of thirty.
    return Align(
      alignment: Alignment.topLeft,
      heightFactor: progress,
      child: Transform.translate(
        offset: Offset(0, -base.fontSize! * 0.6 * (1 - progress)),
        child: Text(text, style: style, maxLines: 3),
      ),
    );
  }

  /// The words of the line that are actually lifting, drawn as their own slices.
  ///
  /// Returns null when nothing is moving, which is the case for every word
  /// outside its own rise-and-fall window - and that is nearly all of a line at
  /// any instant. The caller then falls back to the cheaper whole-line clip.
  ///
  /// Why this is a separate path from the clip rather than a replacement for it:
  /// the clip answers "how far through the line is the voice", which is a
  /// horizontal fact and is what colours the line. The lift answers "which WORD is
  /// being sung right now", which is a vertical fact and is what makes the motion
  /// legible. A highlight without the lift reads as whole lines lighting up in
  /// turn; a lift without the clip leaves nothing coloured. They are two
  /// different questions and both need answering.
  ///
  Widget _buildSwept() {
    final entry = widget.entry;
    final now = widget.clock.positionMs;

    // The gate that does the work. Outside its own window this line is drawn
    // once, plainly, and the 60Hz clock stops mattering to it.
    final animating = LyricClock.isAnimating(
      nowMs: now,
      fromMs: entry.animatesFromMs,
      untilMs: entry.animatesUntilMs,
    );
    if (!animating) {
      return Text(entry.text, style: widget.style);
    }

    final length = entry.text.length;
    if (length == 0) return const SizedBox.shrink();

    final revealed =
        revealedChars(entry, now).clamp(0.0, length.toDouble()).round();
    if (revealed <= 0) {
      return Text(entry.text, style: widget.style.copyWith(color: widget.dimColor));
    }
    if (revealed >= length) {
      return Text(entry.text, style: widget.style);
    }

    // ONE Stack for the whole line.
    //
    // The dim base, the lit-and-clipped copy, the lifted word slices and the
    // held-word swell are all overlays on the same line, so they belong in the
    // same coordinate space. Returning each as its own subtree was how the row
    // grew without bound: a Stack whose children are ALL positioned has no
    // non-positioned child to size against and falls back to `constraints.
    // biggest`, which inside a ListView row is unbounded.
    final litWidth = revealed < _prefixWidths.length
        ? _prefixWidths[revealed]
        : _prefixWidths.isNotEmpty
            ? _prefixWidths.last
            : 0.0;
    if (litWidth <= 0) {
      return Text(entry.text, style: widget.style.copyWith(color: widget.dimColor));
    }

    // NO headroom padding, deliberately.
    //
    // A lifted or swelling word is drawn at a NEGATIVE offset and paints outside
    // this row's own box. Nothing between here and the viewport clips per-row:
    // `ImageFiltered` does not clip, `Container` does not clip, and a ListView
    // clips to the viewport rather than to each child. There is also 28dp of
    // margin between lyric rows, against a worst case of 6dp of rise.
    //
    // Reserving the headroom with padding was tried first and is wrong twice
    // over: it indents every line by a constant amount, and it makes the row
    // TALLER on the frames a word is moving than on the frames it is not, so the
    // line jumps as the voice passes over it. Both are visible while scrolling.
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Text(entry.text, style: widget.style.copyWith(color: widget.dimColor)),
        ClipRect(
          clipper: _LeftWidthClipper(litWidth),
          child: Text(entry.text, style: widget.style),
        ),
        ..._liftedSlices(entry, now),
        ...(widget.glow ? _heldWordGrowth(entry, revealed, now) : const []),
      ],
    );
  }

  /// The words that are lifting right now, as positioned overlays on the line.
  ///
  /// Empty on almost every frame: a word is only off the floor between its rise
  /// and its fall, which is nearly all of a line at any instant. So this costs one
  /// comparison per word rather than a re-layout, and the rest of the line stays a
  /// single Text.
  ///
  /// Why the lift is not a replacement for the colour clip: the clip answers "how
  /// far through the line is the voice", a horizontal fact, and is what colours
  /// the line. The lift answers "which WORD is being sung right now", a vertical
  /// fact, and is what makes the motion legible. A highlight without the lift
  /// reads as whole lines lighting up in turn; a lift without the clip leaves
  /// nothing coloured. Two different questions, both need answering.
  List<Widget> _liftedSlices(LyricsEntry entry, int now) {
    final words = entry.timedWords;
    if (!widget.rise) return const [];
    if (words.isEmpty || _wordSpans.isEmpty) return const [];

    final out = <Widget>[];
    for (var i = 0; i < words.length; i++) {
      final span = _wordSpans[i];
      if (span == null) continue;
      final lift = wordLiftPx(words, i, now);
      // BitChord's own floor for "off the floor". A slice lifted by a hundredth
      // of a dp is not a movement, it is a sub-pixel re-layout of the word on
      // top of itself, and at 60Hz that reads as shimmer on a dense line.
      if (lift <= 0.01) continue;
      final width = _prefixWidths[span.$2] - _prefixWidths[span.$1];
      if (width <= 0) continue;

      out.add(
        Positioned(
          left: _prefixWidths[span.$1],
          // Measured from the row's own top, so the word rises out of the line
          // and paints into the margin above it.
          top: 0,
          child: Transform.translate(
            offset: Offset(0, -lift),
            child: SizedBox(
              width: width,
              child: Text(
                entry.text.substring(span.$1, span.$2),
                style: widget.style,
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }

  /// The letters of any held word, redrawn one at a time on top of the line.
  ///
  /// Empty on almost every frame: most lines have no word held long enough to
  /// qualify, and the whole feature is designed so that is the normal case - so
  /// this allocates nothing until it finds something to animate.
  List<Widget> _heldWordGrowth(LyricsEntry entry, int revealed, int now) {
    final words = entry.timedWords;
    if (words.isEmpty || _wordSpans.length != words.length) return const [];

    final growing = growingWordsOf(words);
    if (growing.isEmpty) return const [];

    final style = widget.style;
    final em = style.fontSize ?? lyricGrowthBaseFontSize;

    final sample = CharGrowth();
    final layers = <Widget>[];

    for (final word in growing) {
      final span = _wordSpans[word.index];
      if (span == null) continue;
      final offset = span.$1;
      // The settle this word's letters share with every other word. Read ONCE
      // per word rather than per letter, because it depends only on the word's
      // own end stamp - not on which letter is being sampled.
      final fall = wordFall(words, word.index, now);
      for (var i = 0; i < word.length; i++) {
        final charIndex = offset + i;
        if (charIndex >= _prefixWidths.length - 1) break;
        // Not yet sung, so not yet grown: the swell follows the voice.
        if (revealed < charIndex + 1) continue;

        word.sampleInto(i, now, sample);
        if (sample.scale <= 1.0 && sample.bloom <= 0.0) continue;

        final left = _prefixWidths[charIndex];
        final letter = entry.text[charIndex];
        // Anything past the letters themselves is a combining mark or a stray
        // separator; growing it on its own would detach it from its base.
        if (letter.trim().isEmpty) continue;

        layers.add(
          Positioned(
            left: left + sample.shift * em,
            top: 0,
            child: Transform.translate(
              // The swell's lift, in MULTIPLES of the ordinary sung-word rise -
              // the same 2dp the flat words use - and then multiplied by the
              // word's shared settle.
              //
              // Not a fraction of the font size. That was wrong twice over: it made
              // the same lyric lift further at a larger zoom, and it broke the
              // handover that lets a grown word be handed back to the cheap
              // whole-word slice, because a letter at rest has to come to rest at
              // exactly the lift `wordLiftPx` gives that word.
              offset: Offset(0, -sample.rise * wordRiseDp * fall),
              child: Transform.scale(
                // Painted about its own centre, which is what makes it a swell
                // rather than a slide.
                scale: sample.scale,
                child: Text(
                  letter,
                  // The bloom is an additive pass over the same glyph, so a held
                  // word reads as LIT rather than merely large. Carried on the
                  // style rather than passed to the widget, because `Text` takes
                  // a paint through its style - there is no `foreground`
                  // parameter on it.
                  style: sample.bloom > 0.01
                      ? style.copyWith(
                          foreground: Paint()
                            ..color = (style.color ?? Colors.white)
                                .withValues(alpha: sample.bloom)
                            ..blendMode = BlendMode.plus,
                        )
                      : style,
                ),
              ),
            ),
          ),
        );
      }
    }

    if (layers.isEmpty) return const [];
    return layers;
  }

@override
  void didUpdateWidget(covariant LyricSweptLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.text != widget.entry.text ||
        oldWidget.style != widget.style) {
      // Force re-measure on the next layout.
      _measuredText = '';
    }
  }
}

/// Fallback font size when a style carries none, for the em-relative lean.
const double lyricGrowthBaseFontSize = 28;

/// Clips to the first [width] logical pixels, from the leading edge.
///
/// The wipe is left-anchored, which is what makes it read as the line filling
/// from where the singing starts. [shouldReclip] is true whenever the width
/// moves, which is every frame of a wipe - and false otherwise, so a settled
/// line is not re-clipped on each clock tick.
class _LeftWidthClipper extends CustomClipper<Rect> {
  const _LeftWidthClipper(this.width);

  final double width;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, width, size.height);

  @override
  bool shouldReclip(_LeftWidthClipper oldClipper) =>
      oldClipper.width != width;
}

/// The visual falloff for lyric lines, kept beside the widget that renders it
/// so the ladder cannot drift from its consumer.
/// Builds the type for a lyric line at a given distance from the active one.
///
/// [fontBuilder] is injected rather than hard-coded so the falloff ladder can be
/// tested without resolving the Jakarta face. That face is not bundled in
/// assets - the app fetches it at runtime - so a test that touches it either
/// throws or waits on the network, which makes it untestable rather than
/// merely slow. Production callers pass nothing and get the real font.
typedef LyricFontBuilder = TextStyle Function(double fontSize, FontWeight weight);

TextStyle _defaultLyricFont(double fontSize, FontWeight weight) =>
    GoogleFonts.plusJakartaSans(fontSize: fontSize, fontWeight: weight);

class LyricLineStyle {
  const LyricLineStyle._();

  /// ONE easing and ONE duration for every lyric dimension.
  ///
  /// Blur, alpha, scale and scroll all move on the same cubic, so a handover
  /// reads as one movement rather than four things settling at slightly
  /// different rates. It is monotonic with almost no initial acceleration, which
  /// keeps a line from snapping into place and then creeping - an overshooting
  /// curve here makes the motion finish before the animation does, which reads
  /// as the page jumping early (invariant 16).
  ///
  /// BitChord's `LYRIC_EASING` / `LYRIC_SETTLE_MS`
  /// (PlayerLyrics.kt:367-368), read here rather than approximated.
  static const Curve lyricEase = Cubic(0.41, 0.0, 0.12, 0.99);
  static const Duration lyricSettle = Duration(milliseconds: 400);

  /// Scale of a line that is not the active one.
  ///
  /// Tweened on the same spec as the blur so a line recedes and returns as one
  /// movement. BitChord `INACTIVE_SCALE` (PlayerLyrics.kt:337).
  static const double inactiveScale = 0.98;

  /// Alpha by distance from the active line, symmetric in both directions.
  ///
  /// The floor of 0.46 is the important part: a line never fades to invisible,
  /// so the whole lyric stays readable without scrolling. An earlier version
  /// faded past lines toward 0.12 AND masked the top and bottom of the list
  /// with a gradient, which together made the outer lines genuinely unreadable.
  static const List<double> alphaLadder = [1.0, 0.8, 0.7, 0.58, 0.46];

  /// Blur by distance, in dp, applied only at rest.
  ///
  /// Lifted to zero while the reader is scrolling so browsing is always crisp.
  /// Capped at 2.4: the old ladder went to 5.0, which turned every line outside
  /// the centre into a smear.
  static const List<double> blurLadder = [0.0, 1.0, 1.0, 1.7, 2.4];

  /// Uniform alpha while the reader is scrolling by hand.
  ///
  /// Browsing is not a state to be dimmed through: the user is trying to read
  /// the words, so everything comes up to meet them.
  static const double browsingAlpha = 0.8;

  /// Alpha for a line whose source had no timings at all.
  static const double unsyncedAlpha = 0.95;

  static double alphaForDistance(int distance) {
    if (distance <= 0) return alphaLadder.first;
    final i = distance < alphaLadder.length ? distance : alphaLadder.length - 1;
    return alphaLadder[i];
  }

  static double blurForDistance(int distance) {
    if (distance <= 0) return blurLadder.first;
    final i = distance < blurLadder.length ? distance : blurLadder.length - 1;
    return blurLadder[i];
  }

  /// Blur is lifted to zero while browsing, so the whole lyric can be read.
  static double blurFor({
    required int distance,
    required bool isBrowsing,
  }) =>
      isBrowsing ? 0.0 : blurForDistance(distance.abs());

  /// The alpha a line [distance] from the active one sits at.
  static double alphaFor({
    required int distance,
    required bool isBrowsing,
    required bool isSynced,
  }) =>
      isBrowsing
          ? browsingAlpha
          : (isSynced ? alphaForDistance(distance) : unsyncedAlpha);

  /// The scale a line [distance] from the active one sits at.
  static double scaleFor({required int distance}) =>
      distance == 0 ? 1.0 : inactiveScale;

  /// The style for a line [distance] from the active one.
  ///
  /// ONE font size and ONE weight for every line.
  ///
  /// This used to hand the active line 28dp/w800 and every other line 26dp/w700,
  /// which looked like emphasis and cost something real: the font change
  /// invalidates the row's cached prefix-width table, so every handover
  /// re-ran a [TextPainter] layout pass over the whole line. Emphasis now comes
  /// from [scaleFor] and the alpha ladder, which are free.
  static TextStyle styleFor({
    required int distance,
    required bool isBrowsing,
    bool isSynced = true,
    double fontSize = 28,
    double height = 1.25,
    LyricFontBuilder? fontBuilder,
  }) {
    final font = fontBuilder ?? _defaultLyricFont;
    return font(fontSize, FontWeight.w700).copyWith(
      height: height,
      color: Colors.white.withValues(
        alpha: alphaFor(
          distance: distance,
          isBrowsing: isBrowsing,
          isSynced: isSynced,
        ),
      ),
    );
  }
}

/// ONE tween for every dimension of a lyric row.
  ///
  /// Blur, text alpha and scale all cross-fade together on
  /// [LyricLineStyle.lyricEase] over [LyricLineStyle.lyricSettle], so a line that
  /// recedes dims, blurs and settles as one movement. BitChord runs three
  /// separate `animateXAsState` calls with the identical spec for exactly this
  /// reason (`PlayerLyrics.kt:1849-2001`).
  ///
  /// Alpha and scale used to STEP - they were read straight off the distance
  /// index at build time, so a handover repainted every row at a new constant and
/// the list looked like it blinked between three states.
  ///
  /// The tween runs from the previously rendered value to the new one, so a
  /// handover that arrives mid-settle continues from where it was instead of
  /// snapping. One controller rather than three, because three controllers on
  /// the same row would finish at three slightly different moments.
  class AnimatedLyricRow extends StatefulWidget {
  const AnimatedLyricRow({
    super.key,
    required this.blurSigma,
    required this.alpha,
    required this.scale,
    required this.style,
    required this.child,
    this.duration = LyricLineStyle.lyricSettle,
  });

  final double blurSigma;
  final double alpha;
  final double scale;
  final TextStyle style;
  final Widget child;
  final Duration duration;

  @override
  State<AnimatedLyricRow> createState() => _AnimatedLyricRowState();
}

class _AnimatedLyricRowState extends State<AnimatedLyricRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late double _fromBlur = widget.blurSigma;
  late double _fromAlpha = widget.alpha;
  late double _fromScale = widget.scale;

  @override
  void initState() {
    super.initState();
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant AnimatedLyricRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final t = _controller.value;
    if (oldWidget.blurSigma == widget.blurSigma &&
        oldWidget.alpha == widget.alpha &&
        oldWidget.scale == widget.scale) {
      return;
    }
    // Continue from what is on screen, not from where the old target was: a
    // handover arriving 120ms into a 400ms settle must not jump.
    _fromBlur = _lerp(_fromBlur, widget.blurSigma, t);
    _fromAlpha = _lerp(_fromAlpha, widget.alpha, t);
    _fromScale = _lerp(_fromScale, widget.scale, t);
    _controller.forward(from: 0);
  }

  static double _lerp(double from, double to, double t) =>
      t >= 1.0 ? to : from + (to - from) * t;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = LyricLineStyle.lyricEase.transform(_controller.value);
        final sigma = _lerp(_fromBlur, widget.blurSigma, t);
        final alpha = _lerp(_fromAlpha, widget.alpha, t);
        final scale = _lerp(_fromScale, widget.scale, t);

        // The alpha rides the DEFAULT text style rather than an [Opacity] widget.
        //
        // An Opacity here would allocate a saveLayer per lyric row - thirty of
        // them for a full song - inside a list that is already rebuilding on a
        // clock. `Text` resolves against DefaultTextStyle, so this reaches every
        // Text in the subtree by one inherited-notify instead of thirty rebuilds
        // of our own, and the sub-row's smaller type follows it for free.
        final style = widget.style.copyWith(
          color: (widget.style.color ?? Colors.white).withValues(alpha: alpha),
        );

        Widget row = DefaultTextStyle.merge(
          style: style,
          child: Transform.scale(
            // Anchored to the row's own left edge, matching the reference's
            // `TransformOrigin(alignEnd ? 1f : 0f, 0.5f)`. Scaling about the centre
            // of a full-width row walks the words sideways as they recede, which
            // reads as the text drifting rather than settling.
            alignment: Alignment.centerLeft,
            scale: scale,
            child: child,
          ),
        );

        if (sigma <= 0.01) return row;
        return ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: row,
        );
      },
      child: widget.child,
    );
  }
}

/// The line's blur as an ANIMATED value.
///
/// BitChord tweens the blur radius over LYRIC_SETTLE_MS in the same direction the
/// line moved - a line that fades DOWN from active to passive should ALSO blur out
/// as it recedes, rather than flipping between two independent alphas. Rendering
/// the sigma instantly from distance made the recede AND the repaint of every
/// other row rebuild one after another, which is precisely what did not read as
/// the same motion.
class AnimatedBlur extends StatefulWidget {
  const AnimatedBlur({
    super.key,
    required this.sigma,
    required this.child,
    this.duration = LyricLineStyle.lyricSettle,
  });

  final double sigma;
  final Widget child;
  final Duration duration;

  @override
  State<AnimatedBlur> createState() => _AnimatedBlurState();
}

class _AnimatedBlurState extends State<AnimatedBlur>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  double _from = 0;
  double _current = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.sigma;
    _current = widget.sigma;
  }

  @override
  void didUpdateWidget(covariant AnimatedBlur oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sigma != widget.sigma) {
      _from = _current;
      _controller
        ..stop()
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = LyricLineStyle.lyricEase.transform(_controller.value);
        final v = _from + (widget.sigma - _from) * t;
        _current = v;
        if (v <= 0.01) return widget.child;
        return ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: v, sigmaY: v),
          child: widget.child,
        );
      },
    );
  }
}
