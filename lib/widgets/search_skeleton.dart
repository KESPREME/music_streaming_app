import 'package:flutter/material.dart';

/// Where the highlight band's left edge sits, in block-local coordinates.
///
/// Exposed rather than buried in the painter because it is the whole trick, and
/// therefore the thing worth testing: the band is positioned against the
/// **row**, then shifted back into block-local space by [rowOffset]. Two blocks
/// at different offsets in the same row therefore agree on where the band is in
/// row space, which is what makes the highlight cross the row as one gesture
/// instead of each block flashing on its own schedule.
double shimmerBandStart({
  required double t,
  required double rowWidth,
  required double rowOffset,
  double bandFraction = 0.42,
}) {
  final travel = rowWidth > 0 ? rowWidth : rowOffset;
  final band = travel * bandFraction;
  final rowStart = -band + t * (travel + band * 2);
  return rowStart - rowOffset;
}

/// Default sweep period.
///
/// One controller per screen drives every block, so this is the cost of the
/// whole placeholder rather than of one row.
const Duration kShimmerPeriod = Duration(milliseconds: 1500);

/// Default band width as a fraction of the sweep's travel distance.
const double kShimmerBandFraction = 0.42;

/// Skeleton placeholders for the search screen.
///
/// A skeleton is only worth having if the placeholder is laid out to the same
/// metrics as the content that replaces it - otherwise the list jumps at the
/// exact moment the eye is tracking the new rows, which reads as a glitch
/// rather than as arrival. So every number here is derived from the real row
/// ([SearchResultRow]): 64dp artwork at radius 12, a 14dp gap, and text blocks
/// sized to the row's own font metrics (16.5 * 1.25 and 14 * 1.3).
///
/// ## One sweep, in row space
///
/// The highlight travels across the *row*, not across each block independently.
/// That distinction is the whole difference between a sweep that reads as one
/// light moving over a row and one that reads as a dozen unrelated rectangles
/// flashing out of step - and it is the mistake the obvious implementation
/// makes: computing the band from each block's own width. A 64dp artwork and a
/// 0.68-of-the-column title bar have different widths, so the same progress
/// value lands the band at a different x in each, and the row visibly comes
/// apart as the animation runs.
///
/// So each block is told where it sits in the row and how wide the row is, the
/// band is positioned in row coordinates, and the block's own left offset is
/// subtracted. Every block in a row therefore shows the same band at the same
/// instant, and the highlight crosses the row as one gesture.
///
/// ## Cost
///
/// One controller for the whole list, read inside the painter via `repaint`. A
/// controller per block would mean N tickers; rebuilding on the animation value
/// would mean a screenful of layout every frame. This way a tick is one repaint
/// of a few dozen gradient rects and no build or layout at all.
class SearchSkeletonList extends StatefulWidget {
  /// How many placeholder rows to draw.
  final int count;

  /// Matches the artists tab, where artwork is a circle.
  final bool circular;

  /// Matches the videos tab, whose artwork is a 16:9 tile.
  final bool isVideo;

  /// Bottom clearance, so the placeholder list scrolls to the same extent the
  /// real one does.
  final double bottomInset;

  const SearchSkeletonList({
    super.key,
    this.count = 8,
    this.circular = false,
    this.isVideo = false,
    this.bottomInset = 0,
  });

  @override
  State<SearchSkeletonList> createState() => _SearchSkeletonListState();
}

class _SearchSkeletonListState extends State<SearchSkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour the OS "remove animations" setting: a perpetual sweep is exactly
    // the kind of unrequested motion that setting exists to stop.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return IgnorePointer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(0, 8, 0, 100 + widget.bottomInset),
        itemCount: widget.count,
        itemBuilder: (context, index) => SearchRowSkeleton(
          index: index,
          circular: widget.circular,
          isVideo: widget.isVideo,
          sweep: reduceMotion ? null : _sweep,
        ),
      ),
    );
  }
}

/// One placeholder row, metric-matched to `SearchResultRow`.
class SearchRowSkeleton extends StatelessWidget {
  final int index;
  final bool circular;
  final bool isVideo;
  final Animation<double>? sweep;

  const SearchRowSkeleton({
    super.key,
    this.index = 0,
    this.circular = false,
    this.isVideo = false,
    this.sweep,
  });

  // From SearchResultRow._Artwork.
  static const double _artTrack = 64;
  static const double _artVideoW = 104;
  static const double _artVideoH = 58;
  static const double _artRadius = 12;
  static const double _videoRadius = 10;

  // From SearchResultRow's padding and SizedBox(width: 14).
  static const double _gutter = 16;
  static const double _rowPadV = 8;
  static const double _gap = 14;

  // From the row's own text styles: 16.5 * 1.25 and 14 * 1.3.
  static const double _titleH = 20.5;
  static const double _subtitleH = 18.2;
  static const double _textGap = 4;

  // Ragged widths, cycled by row index, so a run of placeholders reads as text
  // rather than as a barcode. Equal widths make a loading list look like a
  // rendering bug.
  static const List<double> _titleWidths = [0.68, 0.46, 0.58, 0.74, 0.52];
  static const List<double> _subtitleWidths = [0.34, 0.44, 0.27, 0.38, 0.31];

  @override
  Widget build(BuildContext context) {
    final artW = isVideo ? _artVideoW : _artTrack;
    final artH = isVideo ? _artVideoH : _artTrack;
    final radius = isVideo ? _videoRadius : _artRadius;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: _gutter, vertical: _rowPadV),
      child: LayoutBuilder(
        builder: (context, row) {
          // Where the text column starts inside the row. The bands are placed
          // against the full row width so every block lines up.
          final textLeft = artW + _gap;

          return Row(
            children: [
              ShimmerBlock(
                sweep: sweep,
                rowWidth: row.maxWidth,
                rowOffset: 0,
                width: artW,
                height: artH,
                shape: circular ? BoxShape.circle : BoxShape.rectangle,
                radius: radius,
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShimmerBlock(
                      sweep: sweep,
                      rowWidth: row.maxWidth,
                      rowOffset: textLeft,
                      fraction: _titleWidths[index % _titleWidths.length],
                      height: _titleH,
                      radius: 5,
                    ),
                    const SizedBox(height: _textGap),
                    ShimmerBlock(
                      sweep: sweep,
                      rowWidth: row.maxWidth,
                      rowOffset: textLeft,
                      fraction: _subtitleWidths[index % _subtitleWidths.length],
                      height: _subtitleH,
                      radius: 5,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One shimmering block.
///
/// Takes either a fixed [width]/[height] or a [fraction] of its parent, so text
/// lines and artwork share one implementation. [rowWidth] and [rowOffset] place
/// it within the row so the sweep is shared rather than per-block.
class ShimmerBlock extends StatelessWidget {
  final Animation<double>? sweep;
  final double rowWidth;
  final double rowOffset;
  final double? width;
  final double? fraction;
  final double height;
  final double radius;
  final BoxShape shape;

  /// Width of the travelling highlight, as a fraction of the sweep travel.
  /// Wider reads as a slower, softer light; narrower as a scanning line.
  final double bandFraction;

  const ShimmerBlock({
    super.key,
    this.sweep,
    required this.rowWidth,
    required this.rowOffset,
    this.width,
    this.fraction,
    required this.height,
    this.radius = 6,
    this.shape = BoxShape.rectangle,
    this.bandFraction = kShimmerBandFraction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Quieter than a typical skeleton on purpose. The blocks sit on a near-black
    // glass surface, where a bright placeholder competes with the content it is
    // standing in for - the arrival of real artwork then reads as a flash rather
    // than as the screen filling in. Low base, low highlight: legible as
    // structure, never as glare.
    final base = scheme.surfaceContainerHighest.withValues(alpha: 0.30);
    final highlight = scheme.onSurface.withValues(alpha: 0.055);

    Widget box = SizedBox(
      width: width,
      height: height,
      child: fraction != null
          ? FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: CustomPaint(
                painter: ShimmerPainter(
                  base: base,
                  highlight: highlight,
                  sweep: sweep,
                  rowWidth: rowWidth,
                  rowOffset: rowOffset,
                  bandFraction: bandFraction,
                ),
              ),
            )
          : CustomPaint(
              painter: ShimmerPainter(
                base: base,
                highlight: highlight,
                sweep: sweep,
                rowWidth: rowWidth,
                rowOffset: rowOffset,
                bandFraction: bandFraction,
              ),
            ),
    );

    if (shape == BoxShape.circle) {
      box = ClipOval(child: box);
    } else {
      box = ClipRRect(borderRadius: BorderRadius.circular(radius), child: box);
    }
    return box;
  }
}

/// Paints the travelling highlight.
///
/// The band is sized and positioned against the whole row, then shifted by this
/// block's own offset, so every block in the row shows the same band at the same
/// time. It runs from fully off one edge of the row to fully off the other,
/// which leaves a beat of flat base between passes instead of parking the
/// highlight permanently somewhere on the block.
///
/// Read from the animation inside [paint] rather than rebuilt: `repaint` keeps
/// this on the paint path, so a screenful of blocks costs one repaint per frame
/// and no layout or build at all.
class ShimmerPainter extends CustomPainter {
  final Color base;
  final Color highlight;
  final Animation<double>? sweep;
  final double rowWidth;
  final double rowOffset;

  /// Width of the travelling highlight as a fraction of the sweep travel.
  final double bandFraction;

  ShimmerPainter({
    required this.base,
    required this.highlight,
    required this.sweep,
    required this.rowWidth,
    required this.rowOffset,
    this.bandFraction = kShimmerBandFraction,
  }) : super(repaint: sweep);

  @override
  void paint(Canvas canvas, Size size) {
    final t = sweep?.value ?? 0.0;
    final localStart = shimmerBandStart(
      t: t,
      rowWidth: rowWidth,
      rowOffset: rowOffset,
      bandFraction: bandFraction,
    );
    final band = (rowWidth > 0 ? rowWidth : size.width) * bandFraction;

    final paint = Paint()
      ..shader = LinearGradient(
        colors: [base, highlight, base],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(localStart, 0, band, size.height));

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(ShimmerPainter old) =>
      old.base != base ||
      old.highlight != highlight ||
      old.sweep != sweep ||
      old.rowWidth != rowWidth ||
      old.rowOffset != rowOffset ||
      old.bandFraction != bandFraction;
}
