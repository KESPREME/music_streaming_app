import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../design/tokens/motion.dart';
import '../design/tokens/type.dart' as type_tokens;
import 'glass_surface.dart';

/// Shared Home section pieces. Everything here is grounded and quiet:
/// open artwork, flat rows, glass reserved for interactive controls.

/// Section title + optional quiet view-all affordance.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({super.key, required this.title, this.onViewAll});

  final String title;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title, style: type_tokens.Type.section(context)),
          if (onViewAll != null)
            GestureDetector(
              onTap: onViewAll,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  'See all',
                  style: type_tokens.Type.caption(context).copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pressable wrapper: 0.98 compression while the finger is down.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.onTap, this.onLongPress});

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
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 1,
                child: artUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: artUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 240,
                        fadeInDuration: const Duration(milliseconds: 200),
                        errorWidget: (_, __, ___) => Container(
                            color: Colors.white.withValues(alpha: 0.06)),
                      )
                    : Container(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type_tokens.Type.label(context),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type_tokens.Type.metadata(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact list row for For You: artwork, two text lines, glass play chip.
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: PressableScale(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: artUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: artUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 120,
                          fadeInDuration: const Duration(milliseconds: 180),
                          errorWidget: (_, __, ___) => Container(
                              color: Colors.white.withValues(alpha: 0.06)),
                        )
                      : Container(
                          color: Colors.white.withValues(alpha: 0.06),
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
                      style: type_tokens.Type.body(context).copyWith(
                            color: isPlaying ? accent : null,
                            fontWeight:
                                isPlaying ? FontWeight.w600 : FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type_tokens.Type.metadata(context),
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
                  width: 38,
                  height: 38,
                  child: Icon(
                    isPlaying
                        ? Icons.graphic_eq_rounded
                        : Icons.play_arrow_rounded,
                    size: 20,
                    color: isPlaying ? accent : Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular artist portrait with name beneath.
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
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              backgroundImage:
                  imageUrl.isNotEmpty ? CachedNetworkImageProvider(imageUrl) : null,
              child: imageUrl.isEmpty
                  ? const Icon(Icons.person_rounded, size: 32, color: Colors.white24)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: type_tokens.Type.caption(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet typographic genre chip — no color gradients (artwork owns color).
class GenreChip extends StatelessWidget {
  const GenreChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: GlassSurface(
        tier: GlassTier.card,
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Text(label, style: type_tokens.Type.label(context)),
          ],
        ),
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
        style: type_tokens.Type.metadata(context)
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
