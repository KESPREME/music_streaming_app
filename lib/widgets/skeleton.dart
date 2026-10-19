// lib/widgets/skeleton.dart
//
// Skeleton placeholders laid out to the metrics of the content they stand in
// for, so nothing jumps when the real rows arrive. Built on the search
// screen's ShimmerBlock / ShimmerPainter (one sweep per scope, paint-only:
// a tick is a repaint of a few gradient rects, never a build or a layout).
//
//   * [SkeletonScope] owns the one sweep controller for everything under it,
//     and stops it under reduce motion (a static placeholder still reads as
//     structure).
//   * [SkeletonBox] is one block.
//   * [SliverSkeletonCardGrid] / [SliverSkeletonRows] are the shapes the
//     Library grids and the list screens use.
//
// Arrival: replace the skeleton with the content inside a `FadeInSliver` or an
// AnimatedSwitcher; the placeholder never animates itself out.

import 'package:flutter/material.dart';

import 'search_skeleton.dart' show ShimmerBlock, kShimmerPeriod;

class SkeletonScope extends StatefulWidget {
  const SkeletonScope({super.key, required this.child});

  final Widget child;

  /// The sweep shared by every block under the nearest scope, or null (no
  /// scope, or reduce motion): the blocks then draw flat.
  static Animation<double>? sweepOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonSweep>()?.sweep;

  @override
  State<SkeletonScope> createState() => _SkeletonScopeState();
}

class _SkeletonScopeState extends State<SkeletonScope> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: kShimmerPeriod);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return _SkeletonSweep(sweep: still ? null : _sweep, child: widget.child);
  }
}

class _SkeletonSweep extends InheritedWidget {
  const _SkeletonSweep({required this.sweep, required super.child});

  final Animation<double>? sweep;

  @override
  bool updateShouldNotify(_SkeletonSweep old) => old.sweep != sweep;
}

/// One placeholder block: a fixed size, a [fraction] of the parent's width, or
/// a circle.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.fraction,
    this.radius = 6,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double? fraction;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final sweep = SkeletonScope.sweepOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = width ?? (c.hasBoundedWidth ? c.maxWidth : 100);
        return ShimmerBlock(
          sweep: sweep,
          rowWidth: w,
          rowOffset: 0,
          width: width ?? (fraction == null ? w : null),
          fraction: fraction,
          height: height,
          radius: radius,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
        );
      },
    );
  }
}

/// The Library's two-column card grids while they load: artist cards (a
/// circle and a name) or album cards (artwork and two lines), at the same
/// padding, aspect ratio and spacing as the real grid.
class SliverSkeletonCardGrid extends StatelessWidget {
  const SliverSkeletonCardGrid({
    super.key,
    required this.circle,
    this.count = 6,
    this.aspectRatio = 0.85,
  });

  final bool circle;
  final int count;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final card = BoxDecoration(
      color: const Color(0xFF0C0D11),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.6),
    );
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: aspectRatio,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => IgnorePointer(
            child: Semantics(
              excludeSemantics: true,
              child: Container(
                decoration: card,
                clipBehavior: Clip.antiAlias,
                child: circle
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SkeletonBox(width: 84, height: 84, circle: true),
                          const SizedBox(height: 14),
                          SkeletonBox(width: i.isEven ? 86 : 64, height: 13),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(child: SkeletonBox(height: double.infinity, radius: 0)),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox(fraction: i.isEven ? 0.78 : 0.6, height: 13),
                                const SizedBox(height: 7),
                                SkeletonBox(fraction: i.isEven ? 0.5 : 0.42, height: 11),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          childCount: count,
        ),
      ),
    );
  }
}

/// List rows while they load: artwork (square or round) and two lines.
class SliverSkeletonRows extends StatelessWidget {
  const SliverSkeletonRows({
    super.key,
    this.count = 8,
    this.art = 56,
    this.circle = false,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 100),
    this.gap = 8,
  });

  final int count;
  final double art;
  final bool circle;
  final EdgeInsets padding;
  final double gap;

  static const _titles = [0.62, 0.48, 0.7, 0.55, 0.66, 0.44];
  static const _subs = [0.38, 0.3, 0.42, 0.34];

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: padding,
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => IgnorePointer(
            child: Semantics(
              excludeSemantics: true,
              child: Padding(
                padding: EdgeInsets.only(bottom: gap),
                child: SizedBox(
                  height: art + 16,
                  child: Row(
                    children: [
                      SkeletonBox(width: art, height: art, radius: circle ? art : 10, circle: circle),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(fraction: _titles[i % _titles.length], height: 14),
                            const SizedBox(height: 8),
                            SkeletonBox(fraction: _subs[i % _subs.length], height: 11),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          childCount: count,
        ),
      ),
    );
  }
}
