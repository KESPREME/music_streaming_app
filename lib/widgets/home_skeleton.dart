import 'package:flutter/material.dart';

import '../presentation/home/home_tokens.dart' as t;
import 'home_sections.dart';
import 'search_skeleton.dart';

/// Loading placeholder for Home.
///
/// ## Why a skeleton rather than a spinner
///
/// A spinner says "wait". A skeleton says "this is what is coming, and it is
/// this shape" - and because the placeholders are laid out to the same metrics
/// as the sections that replace them, the arrival of real content does not move
/// anything. The eye is already tracking the rows that land where the grey
/// blocks were, so nothing jumps at the moment it would be most noticeable.
///
/// That is the whole design constraint. Every dimension below is read from
/// [HomeTokens] or from a helper the real widget also uses, never re-typed. A
/// skeleton built from its own numbers is worse than no skeleton at all,
/// because it promises a layout the screen then refuses to keep.
///
/// ## Composition
///
/// Shaped like the real screen: one hero, then compact square rails, with a
/// circle rail last. The rail count is deliberately small - four placeholder
/// sections is enough to establish the rhythm, and a long list of grey blocks
/// overstates how much content is coming.
///
/// ## Not this
///
/// This never replaces content that exists. A refresh over a cached feed keeps
/// showing the feed; only a genuine cold start with nothing cached gets this.
/// See `MusicProvider.isHomeLoading`.
class HomeSkeleton extends StatefulWidget {
  /// Clearance below the last placeholder, matching the real screen's tail.
  final double bottomInset;

  /// Whether to include a hero-sized placeholder at the top.
  final bool withHero;

  const HomeSkeleton({
    super.key,
    this.bottomInset = 0,
    this.withHero = true,
  });

  @override
  State<HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<HomeSkeleton>
    with SingleTickerProviderStateMixin {
  // One controller for the whole screen. A controller per block would mean one
  // ticker per block; the painter reads this through `repaint`, so a tick costs
  // one repaint and no layout or build.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: kShimmerPeriod,
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour the OS "remove animations" setting: a perpetual travelling
    // highlight is exactly the unrequested motion that setting exists to stop.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final sweep = reduceMotion ? null : _sweep;

    return IgnorePointer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(bottom: 100 + widget.bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.withHero)
                _HeroSkeleton(sweep: sweep, bottomInset: 12)
              else
                const SizedBox(height: 12),
              _RailSkeleton(sweep: sweep, index: 0, bottomInset: 0),
              _RailSkeleton(sweep: sweep, index: 1, bottomInset: 0),
              _ArtistSkeleton(sweep: sweep, index: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hero-sized placeholder, matched to the real carousel's height formula.
class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton({required this.sweep, required this.bottomInset});

  final Animation<double>? sweep;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final contentW =
        t.HomeTokens.contentWidth(MediaQuery.sizeOf(context).width);
    // The same expression home_screen uses, not a copy of its number.
    final heroH = (contentW * t.HomeTokens.heroCardFraction * (5 / 4))
        .clamp(280.0, 380.0);
    // Hero cards are portrait, so the width follows from the height.
    final heroW = (heroH * (4 / 5)).clamp(0.0, contentW);

    return Padding(
      padding: EdgeInsets.fromLTRB(t.HomeTokens.contentPadding, 0,
          t.HomeTokens.contentPadding, bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleLine(sweep: sweep, index: 0),
          ShimmerBlock(
            sweep: sweep,
            rowWidth: contentW,
            rowOffset: 0,
            width: heroW,
            height: heroH,
            radius: t.HomeTokens.heroRadius,
            bandFraction: kHomeShimmerBandFraction,
          ),
        ],
      ),
    );
  }
}

/// A compact square rail: a title, then square tiles.
class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton({
    required this.sweep,
    required this.index,
    required this.bottomInset,
  });

  final Animation<double>? sweep;
  final int index;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final contentW =
        t.HomeTokens.contentWidth(MediaQuery.sizeOf(context).width);
    final cardW = contentW * t.HomeTokens.squareCardFraction;
    // Two and a bit cards, so the rail reads as scrollable rather than as a
    // fixed pair - which is what a real rail of this width looks like.
    final visible = (contentW / (cardW + _railGap)).ceil() + 1;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleLine(sweep: sweep, index: index),
          SizedBox(
            // Exactly what _SquareRailSection reserves: card + text block + the
            // same 12dp it leaves. Reserving anything less overflows the tile,
            // anything more and the placeholder is taller than the content it
            // stands in for, which is the shift this whole file exists to
            // avoid.
            height: cardW + homeRailTextBlockHeight(context) + _railSlack,
            child: Row(
              children: [
                for (var i = 0; i < visible; i++) ...[
                  if (i > 0) const SizedBox(width: _railGap),
                  _TileSkeleton(
                    sweep: sweep,
                    size: cardW,
                    variant: index + i,
                    contentWidth: contentW,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Spacing between rail cards, matching the real rail's right padding.
  static const double _railGap = 14.0;

  /// The slack the real rail reserves below its text block.
  static const double _railSlack = 12.0;
}

/// A circle rail, for artists.
class _ArtistSkeleton extends StatelessWidget {
  const _ArtistSkeleton({required this.sweep, required this.index});

  final Animation<double>? sweep;
  final int index;

  @override
  Widget build(BuildContext context) {
    final contentW =
        t.HomeTokens.contentWidth(MediaQuery.sizeOf(context).width);
    final portraitH = homeArtistPortraitHeight(context);
    const portraitW = 88.0;
    // Matches _ArtistShelf's own 28dp right padding, and sizes the run to the
    // width so the placeholder is as scrollable as the real rail.
    const gap = 28.0;
    final visible = (contentW / (portraitW + gap)).ceil() + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleLine(sweep: sweep, index: index),
        SizedBox(
          height: portraitH,
          child: Row(
            children: [
              for (var i = 0; i < visible; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                _TileSkeleton(
                  sweep: sweep,
                  size: 72,
                  variant: index + i,
                  contentWidth: contentW,
                  circle: true,
                  width: portraitW,
                  singleCaption: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One tile: square artwork plus its caption.
///
/// The art width can differ from the art height - a portrait is a circle over a
/// wider column - so both are separate.
///
/// [singleCaption] exists because the two real tiles do not match: a square card
/// carries a title and a subtitle, while an artist portrait carries only a name.
/// Giving the portrait two lines made it 18px taller than the box reserved for
/// it.
class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton({
    required this.sweep,
    required this.size,
    required this.variant,
    required this.contentWidth,
    this.circle = false,
    this.width,
    this.singleCaption = false,
  });

  final Animation<double>? sweep;
  final double size;
  final int variant;
  final double contentWidth;
  final bool circle;
  final double? width;
  final bool singleCaption;

  static const List<double> _titleFractions = [0.68, 0.46, 0.58, 0.74, 0.52];
  static const List<double> _subtitleFractions = [0.34, 0.44, 0.27, 0.38, 0.31];

  // From HomeTokens' card typography.
  static const double _titleH = 20.0;
  static const double _subtitleH = 20.0;
  static const double _textGap = 2.0;

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    return SizedBox(
      width: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ShimmerBlock(
            sweep: sweep,
            rowWidth: contentWidth,
            rowOffset: 0,
            width: size,
            height: size,
            radius: t.HomeTokens.cardRadius,
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            bandFraction: kHomeShimmerBandFraction,
          ),
          const SizedBox(height: 8),
          ShimmerBlock(
            sweep: sweep,
            rowWidth: contentWidth,
            rowOffset: 0,
            width: w,
            fraction: _titleFractions[variant % _titleFractions.length],
            height: _titleH,
            radius: 4,
            bandFraction: kHomeShimmerBandFraction,
          ),
          const SizedBox(height: _textGap),
          if (!singleCaption)
            ShimmerBlock(
              sweep: sweep,
              rowWidth: contentWidth,
              rowOffset: 0,
              width: w,
              fraction: _subtitleFractions[variant % _subtitleFractions.length],
              height: _subtitleH,
              radius: 4,
              bandFraction: kHomeShimmerBandFraction,
            ),
        ],
      ),
    );
  }
}

/// A section title placeholder.
///
/// Title line only, no subtitle: most Home shelves arrive without one, and a
/// guessed second line shifts everything under it when the guess is wrong.
class _TitleLine extends StatelessWidget {
  const _TitleLine({required this.sweep, required this.index});

  final Animation<double>? sweep;
  final int index;

  static const double _height = 24.0;
  static const double _gutter = t.HomeTokens.contentPadding;

  @override
  Widget build(BuildContext context) {
    final contentW =
        t.HomeTokens.contentWidth(MediaQuery.sizeOf(context).width);
    // Ragged widths, cycled, so a run of placeholders reads as headings rather
    // than as a row of identical bars.
    const fractions = [0.34, 0.27, 0.41, 0.22, 0.31];
    final fraction = fractions[index % fractions.length];

    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 0),
      child: ShimmerBlock(
        sweep: sweep,
        rowWidth: contentW,
        rowOffset: 0,
        width: contentW,
        fraction: fraction,
        height: _height,
        radius: 6,
        bandFraction: kHomeShimmerBandFraction,
      ),
    );
  }
}

/// Home uses a wider band than Search.
///
/// Half the travel distance rather than 0.42. On a screen-sized sweep a narrow
/// band reads as a hard line scanning past, where on a 64dp search row the same
/// width reads as a soft light. Same gesture, different apparent speed, because
/// the distance is so much longer.
const double kHomeShimmerBandFraction = 0.5;
