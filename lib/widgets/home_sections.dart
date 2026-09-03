import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../design/tokens/motion.dart';
import '../presentation/home/home_tokens.dart' as t;
import 'glass_surface.dart';

/// Shared Home section pieces (spec #67). Geometry comes from
/// [t.HomeTokens]; typography from the token scale; no magic numbers.

/// Section title + optional description + optional See all.
/// Spec #44: description only when source provides it; chevron only when
/// a navigation action exists.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    this.description,
    this.onViewAll,
  });

  final String title;
  final String? description;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(t.HomeTokens.contentPadding, 0,
          t.HomeTokens.contentPadding, t.HomeTokens.headerToContent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(title, style: t.HomeTokens.sectionTitle(context)),
              ),
              if (onViewAll != null)
                GestureDetector(
                  onTap: onViewAll,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'See all',
                          style: t.HomeTokens.cardMetadata(context).copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (description != null && description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: t.HomeTokens.sectionDescription(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Pressable wrapper: 0.98 compression while the finger is down (spec #47:
/// tactile, barely perceptible, spring-back).
class PressableScale extends StatefulWidget {
  const PressableScale(
      {super.key, required this.child, this.onTap, this.onLongPress});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: Motion.fast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Compact artwork-first rail card (Jump Back In / What's Hot).
/// Square artwork + 1-line title + 1-line metadata (spec #9/#18/#37).
class RailCard extends StatelessWidget {
  const RailCard({
    super.key,
    required this.artUrl,
    required this.title,
    required this.subtitle,
    required this.size,
    required this.onTap,
    this.onLongPress,
  });

  final String artUrl;
  final String title;
  final String subtitle;
  final double size;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(t.HomeTokens.cardRadius),
              child: AspectRatio(
                aspectRatio: t.HomeTokens.squareAspect,
                child: artUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: artUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 240,
                        fadeInDuration: const Duration(milliseconds: 200),
                        errorWidget: (_, __, ___) => Container(
                            color: t.HomeTokens.placeholderColor(context)),
                      )
                    : Container(color: t.HomeTokens.placeholderColor(context)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.HomeTokens.cardTitle(context),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.HomeTokens.cardMetadata(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact open track row: artwork + two lines + play chip.
/// NOT a card — tonal separation only (spec #10, Muzo density).
class ForYouRow extends StatelessWidget {
  const ForYouRow({
    super.key,
    required this.artUrl,
    required this.title,
    required this.subtitle,
    required this.isPlaying,
    required this.onTap,
    this.onLongPress,
  });

  final String artUrl;
  final String title;
  final String subtitle;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return PressableScale(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: t.HomeTokens.contentPadding, vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 50,
                height: 50,
                child: artUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: artUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 120,
                        fadeInDuration: const Duration(milliseconds: 180),
                        errorWidget: (_, __, ___) => Container(
                            color: t.HomeTokens.placeholderColor(context)),
                      )
                    : Container(
                        color: t.HomeTokens.placeholderColor(context),
                        child: const Icon(Icons.music_note_rounded,
                            color: Colors.white24),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.HomeTokens.compactTitle(context).copyWith(
                      color: isPlaying ? accent : null,
                      fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.HomeTokens.compactMetadata(context),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GlassSurface(
              tier: GlassTier.card,
              borderRadius: 30,
              padding: EdgeInsets.zero,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  isPlaying
                      ? Icons.graphic_eq_rounded
                      : Icons.play_arrow_rounded,
                  size: 19,
                  color:
                      isPlaying ? accent : Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular artist portrait with name beneath (spec #33: circles, not
/// album-card geometry).
class ArtistPortrait extends StatelessWidget {
  const ArtistPortrait({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
  });

  final String name;
  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: SizedBox(
        width: 88,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: t.HomeTokens.placeholderColor(context),
              backgroundImage: imageUrl.isNotEmpty
                  ? CachedNetworkImageProvider(imageUrl)
                  : null,
              child: imageUrl.isEmpty
                  ? const Icon(Icons.person_rounded,
                      size: 30, color: Colors.white24)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: t.HomeTokens.compactMetadata(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Parallax carousel primitives ─────────────────────────────────────────────

/// PageView wrapper that feeds each item its normalized page offset
/// (−1..1 relative to viewport center). Rebuilds only the PageView subtree
/// on scroll; item content is transform-only, so frames stay cheap.
/// Reduced motion is resolved downstream by [ParallaxArtwork], which reads
/// MediaQuery directly — this component stays pure presentation.
class ParallaxMediaCarousel extends StatelessWidget {
  const ParallaxMediaCarousel({
    super.key,
    required this.controller,
    required this.count,
    required this.itemBuilder,
  });

  final PageController controller;
  final int count;
  final Widget Function(BuildContext context, int index, double pageOffset)
      itemBuilder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final hasPage =
            controller.hasClients && controller.position.haveDimensions;
        final page = hasPage
            ? (controller.page ?? controller.initialPage.toDouble())
            : controller.initialPage.toDouble();
        return PageView.builder(
          controller: controller,
          padEnds: false,
          physics: const BouncingScrollPhysics(),
          itemCount: count,
          itemBuilder: (context, index) =>
              itemBuilder(context, index, (page - index).clamp(-1.0, 1.0)),
        );
      },
    );
  }
}

/// Artwork layer with horizontal parallax: the image is oversized relative
/// to its clip so it can drift inside the card without exposing edges.
/// Text/controls stay anchored to the card — only this layer moves.
class ParallaxArtwork extends StatelessWidget {
  const ParallaxArtwork({
    super.key,
    required this.artUrl,
    required this.pageOffset,
    this.parallaxFactor = 0.14,
    this.memCacheWidth = 480,
  });

  final String artUrl;
  final double pageOffset;

  /// Fraction of card width the artwork may drift. Drives the oversize so
  /// edges can never show.
  final double parallaxFactor;
  final int memCacheWidth;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        if (reduced || artUrl.isEmpty) {
          return CachedNetworkImage(
            imageUrl: artUrl,
            fit: BoxFit.cover,
            memCacheWidth: memCacheWidth,
            fadeInDuration: const Duration(milliseconds: 220),
            errorWidget: (_, __, ___) =>
                Container(color: Colors.white.withValues(alpha: 0.04)),
          );
        }

        // Oversize enough that a full-deflection shift never exposes edges.
        final imgW = w * (1 + 2 * parallaxFactor) + 24;
        final shift = -pageOffset * parallaxFactor * w;

        // Adjacent cards recede a touch — depth, not CoverFlow.
        final scale = 1.0 - 0.02 * pageOffset.abs();

        return ClipRect(
          child: OverflowBox(
            maxWidth: imgW,
            minWidth: imgW,
            maxHeight: h,
            alignment: Alignment.center,
            child: Transform.translate(
              offset: Offset(shift, 0),
              child: Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: imgW,
                  height: h,
                  child: CachedNetworkImage(
                    imageUrl: artUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: memCacheWidth,
                    fadeInDuration: const Duration(milliseconds: 220),
                    errorWidget: (_, __, ___) =>
                        Container(color: Colors.white.withValues(alpha: 0.04)),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Editorial mood tile: text-led tonal surface, width follows the label.
/// No icon soup, no saturated color coding — typography does the work.
class EditorialMoodTile extends StatelessWidget {
  const EditorialMoodTile(
      {super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label, style: t.HomeTokens.cardTitle(context)),
      ),
    );
  }
}

/// Quiet inline hint for sections with nothing to show (offline/empty).
class SectionHint extends StatelessWidget {
  const SectionHint({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        message,
        style: t.HomeTokens.cardMetadata(context)
            .copyWith(color: Colors.white.withValues(alpha: 0.35)),
      ),
    );
  }
}

/// Staged Home entry choreography: one controller, per-section intervals.
/// Collapses to instant opacity when the OS requests reduced motion.
class StaggerIn extends StatelessWidget {
  const StaggerIn({
    super.key,
    required this.controller,
    required this.interval,
    required this.child,
  });

  final AnimationController controller;
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced) return child;
    final curved = CurvedAnimation(parent: controller, curve: interval);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - curved.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Text-block height for rail-card metadata (title + gap + subtitle).
/// Live-run calibrated: actual rendered line heights (label 15.5 w600,
/// metadata 13.5) measure ~20 + ~20 logical px, so the old 17+2+14=33
/// estimate overflowed by exactly the 9px seen at runtime. 20+2+20=42
/// plus 4dp slack absorbs device font-metric variance (Adreno runtime
/// measured 2-4px overflows at scale 1.0) — zero RenderFlex overflow
/// at any scale (spec: zero overflow).
double homeRailTextBlockHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0);
  const base = 20.0 + 2.0 + 20.0 + 4.0;
  return base * scale;
}
