import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Scroll-interpolated frosted top bar matching BitChord's FrostedTopBar and TopFadeBlur.
///
/// At rest (scrollOffset = 0), the bar is completely transparent allowing the full-bleed
/// hero artwork to show behind the circular back and action buttons.
/// As the list scrolls and hero title leaves the view, the bar smoothly transitions to
/// frosted glass with backdrop blur and fades in the centered title, preventing any
/// text collisions with list items like "Top songs" or "About the album".
class BitchordSliverAppBar extends StatelessWidget {
  final String title;
  final double scrollOffset;
  final ScrollController? scrollController;
  final double artHeight;
  final Color backgroundColor;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  const BitchordSliverAppBar({
    super.key,
    required this.title,
    this.scrollOffset = 0.0,
    this.scrollController,
    required this.artHeight,
    required this.backgroundColor,
    this.onBack,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    if (scrollController != null) {
      return AnimatedBuilder(
        animation: scrollController!,
        builder: (context, _) {
          final offset = scrollController!.hasClients ? scrollController!.offset : scrollOffset;
          return _buildAppBar(context, offset);
        },
      );
    }
    return _buildAppBar(context, scrollOffset);
  }

  Widget _buildAppBar(BuildContext context, double currentOffset) {
    final topPadding = MediaQuery.of(context).padding.top;
    final threshold = (artHeight - kToolbarHeight - topPadding).clamp(0.0, double.infinity);
    final fadeProgress = ((currentOffset - threshold) / 50.0).clamp(0.0, 1.0);

    final blurSigma = 20.0 * fadeProgress;

    return SliverAppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      forceMaterialTransparency: true,
      elevation: 0,
      pinned: true,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_rounded,
          color: Colors.white,
          size: 24,
        ),
        onPressed: onBack ?? () => Navigator.maybePop(context),
      ),
      actions: actions,
      flexibleSpace: fadeProgress <= 0.001
          ? const SizedBox.expand()
          : RepaintBoundary(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [
                          0.0, 0.09, 0.18, 0.27, 0.36, 0.45, 0.55, 0.64, 0.73, 0.82, 0.91, 1.0,
                        ],
                        colors: [
                          backgroundColor.withValues(alpha: 0.82 * fadeProgress),
                          backgroundColor.withValues(alpha: 0.76 * fadeProgress),
                          backgroundColor.withValues(alpha: 0.69 * fadeProgress),
                          backgroundColor.withValues(alpha: 0.61 * fadeProgress),
                          backgroundColor.withValues(alpha: 0.52 * fadeProgress),
                          backgroundColor.withValues(alpha: 0.42 * fadeProgress),
                          backgroundColor.withValues(alpha: 0.31 * fadeProgress),
                          backgroundColor.withValues(alpha: 0.21 * fadeProgress),
                          backgroundColor.withValues(alpha: 0.12 * fadeProgress),
                          backgroundColor.withValues(alpha: 0.05 * fadeProgress),
                          backgroundColor.withValues(alpha: 0.01 * fadeProgress),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      title: Opacity(
        opacity: fadeProgress,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}
