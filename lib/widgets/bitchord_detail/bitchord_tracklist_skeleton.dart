import 'package:flutter/material.dart';

/// Shimmer skeleton loader for BitChord tracklists across Album, Artist & Playlist screens.
class BitchordTracklistSkeleton extends StatefulWidget {
  final int itemCount;
  final bool hasLeadingThumb;
  final Color? baseColor;

  const BitchordTracklistSkeleton({
    super.key,
    this.itemCount = 6,
    this.hasLeadingThumb = false,
    this.baseColor,
  });

  @override
  State<BitchordTracklistSkeleton> createState() => _BitchordTracklistSkeletonState();
}

class _BitchordTracklistSkeletonState extends State<BitchordTracklistSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _opacityAnim = Tween<double>(begin: 0.12, end: 0.32).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.baseColor ?? Colors.white;

    return AnimatedBuilder(
      animation: _opacityAnim,
      builder: (context, _) {
        final shimmerColor = color.withValues(alpha: _opacityAnim.value);
        return Column(
          children: List.generate(widget.itemCount, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Row(
                children: [
                  if (widget.hasLeadingThumb)
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: shimmerColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    )
                  else
                    Container(
                      width: 24,
                      height: 18,
                      decoration: BoxDecoration(
                        color: shimmerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: index.isEven ? 180 : 130,
                          height: 15,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: index.isEven ? 100 : 80,
                          height: 12,
                          decoration: BoxDecoration(
                            color: shimmerColor.withValues(
                              alpha: (_opacityAnim.value * 0.75).clamp(0.0, 1.0),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}
