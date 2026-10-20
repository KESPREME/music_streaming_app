// lib/widgets/bitchord_detail/detail_glass.dart
//
// Liquid-glass chrome for the album and artist pages (plan:
// docs/PLAN-glass-detail-pages.md). Material behaviour and numbers after
// BitChord's DetailScreen top bar and action row (GPLv3; no code copied).
//
// WHY THESE ARE THE SAME AS THE BOTTOM BAR. The bottom bar's jelly (the press
// that inflates, the squash when dragged, the specular glow that follows the
// finger) is liquid_glass_widgets' GlassButton / GlassTabBar physics, and the
// settings below are LiquidGlassNavBar's, so a pill here has the same material
// and the same spring. Nothing is re-implemented: the physics is the package's.
//
// QUALITY. Standard everywhere ([DetailGlass.quality]): the package keeps
// premium for static, non-scrolling surfaces, and this chrome floats over a
// scrolling photo. One constant to flip if a device shows it can afford more.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import '../../theme/app_font.dart';

abstract final class DetailGlass {
  /// A bar button / one slot of the top-right capsule.
  static const double barSize = 44;

  /// A circle in the action row, and the Play pill's height.
  static const double actionSize = 56;

  static const lgw.GlassQuality quality = lgw.GlassQuality.standard;

  /// The nav bar's glass, tinted a little by the cover.
  static lgw.LiquidGlassSettings material(Color accent) => lgw.LiquidGlassSettings(
        thickness: 24,
        blur: 24,
        chromaticAberration: 0.04,
        lightIntensity: 0.85,
        refractiveIndex: 1.18,
        saturation: 1.15,
        ambientStrength: 0.9,
        glassColor: Color.lerp(const Color(0x0EFFFFFF), accent.withValues(alpha: 0.08), 0.35) ??
            const Color(0x0EFFFFFF),
      );

  /// The Play pill: the same glass, frosted white. `prominent` multiplies this
  /// colour's alpha by 2.5 (clamped to 0.4..0.9), so 0.34 lands near 0.85.
  static lgw.LiquidGlassSettings playMaterial() => lgw.LiquidGlassSettings(
        thickness: 24,
        blur: 24,
        chromaticAberration: 0.04,
        lightIntensity: 0.85,
        refractiveIndex: 1.18,
        saturation: 1.15,
        ambientStrength: 0.9,
        glassColor: Colors.white.withValues(alpha: 0.34),
      );

  static Color glow(Color accent) => accent.withValues(alpha: 0.38);

  /// How hard a drag across a pill stretches it. The package's default is 0.5
  /// ("balanced"); these chrome buttons are small and meant to feel alive.
  static const double stretch = 0.7;
}

/// The shared glass layer for a group of pills.
class DetailGlassScope extends StatelessWidget {
  const DetailGlassScope({super.key, required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) => lgw.AdaptiveLiquidGlassLayer(
        settings: DetailGlass.material(accent),
        quality: DetailGlass.quality,
        child: child,
      );
}

/// Touch-down tick (iOS 26 plays one as the glass is pressed); the release
/// click is the button's own.
Widget _withTick(Widget child) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => HapticFeedback.selectionClick(),
      child: child,
    );

/// A glass circle: back, shuffle, download. Press inflates it, a drag stretches
/// it, hold keeps it inflated (the package's `persistPressOnDrag`).
class DetailGlassCircle extends StatelessWidget {
  const DetailGlassCircle({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.child,
    this.size = DetailGlass.barSize,
    this.accent = Colors.white,
    this.iconColor = Colors.white,
  }) : assert(icon != null || child != null);

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  /// Replaces the icon (a progress ring while downloading).
  final Widget? child;
  final double size;
  final Color accent;
  final Color iconColor;

  void _tap() {
    HapticFeedback.lightImpact();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final glow = DetailGlass.glow(accent);
    final button = child != null
        ? lgw.GlassButton.custom(
            width: size,
            height: size,
            onTap: _tap,
            label: label,
            glowColor: glow,
            stretch: DetailGlass.stretch,
            excludeFromSemantics: true,
            child: Center(child: child),
          )
        : lgw.GlassButton(
            icon: Icon(icon),
            iconSize: size * 0.46,
            iconColor: iconColor,
            width: size,
            height: size,
            onTap: _tap,
            label: label,
            glowColor: glow,
            stretch: DetailGlass.stretch,
            excludeFromSemantics: true,
          );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: _withTick(button),
    );
  }
}

/// The Play pill: frosted white glass with a dark label.
class DetailGlassPill extends StatelessWidget {
  const DetailGlassPill({
    super.key,
    required this.onTap,
    this.label = 'Play',
    this.width,
    this.height = DetailGlass.actionSize,
  }) : iconOnly = false;

  /// The same frosted glass as a circle with just the play glyph (the artist
  /// page's big Play).
  const DetailGlassPill.disc({
    super.key,
    required this.onTap,
    this.label = 'Play',
    double size = 70,
  })  : width = size,
        height = size,
        iconOnly = true;

  final VoidCallback onTap;
  final String label;
  final double? width;
  final double height;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final button = lgw.GlassButton.custom(
      width: width,
      height: height,
      shape: lgw.LiquidRoundedSuperellipse(borderRadius: height / 2),
      style: lgw.GlassButtonStyle.prominent,
      useOwnLayer: true,
      settings: DetailGlass.playMaterial(),
      quality: DetailGlass.quality,
      glowColor: Colors.white.withValues(alpha: 0.5),
      stretch: DetailGlass.stretch,
      label: label,
      excludeFromSemantics: true,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, color: Colors.black, size: iconOnly ? 40 : 28),
          if (!iconOnly) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: AppFont.style(
                color: Colors.black,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(button: true, label: label, excludeSemantics: true, child: _withTick(button));
  }
}

/// [ leading ]  [ ▶ Play ]  [ trailing ] - the action row of both pages.
class DetailActionRow extends StatelessWidget {
  const DetailActionRow({
    super.key,
    required this.leading,
    required this.onPlay,
    required this.trailing,
    required this.accent,
    this.playLabel = 'Play',
  });

  final Widget leading;
  final Widget trailing;
  final VoidCallback onPlay;
  final String playLabel;
  final Color accent;

  static const double gap = 14;
  static const double maxPillWidth = 240;

  @override
  Widget build(BuildContext context) {
    return DetailGlassScope(
      accent: accent,
      child: Padding(
        // Room for the press to inflate without being clipped by the sliver.
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
        child: LayoutBuilder(
          builder: (context, c) {
            final room = c.maxWidth - DetailGlass.actionSize * 2 - gap * 2;
            final pill = room.clamp(120.0, maxPillWidth);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                leading,
                const SizedBox(width: gap),
                DetailGlassPill(onTap: onPlay, label: playLabel, width: pill),
                const SizedBox(width: gap),
                trailing,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One tap target in a [DetailGlassCapsule].
@immutable
class DetailGlassSlot {
  const DetailGlassSlot({
    required this.label,
    this.icon,
    this.child,
    this.onTap,
    this.menuItems,
    this.menuWidth = 224,
  })  : assert(icon != null || child != null),
        assert(onTap != null || menuItems != null);

  final String label;
  final IconData? icon;

  /// Replaces the icon (the account picture).
  final Widget? child;
  final VoidCallback? onTap;

  /// When set, the slot opens this liquid menu (GlassMenuItem / dividers)
  /// instead of calling [onTap].
  final List<Widget>? menuItems;
  final double menuWidth;
}

/// The top-right capsule of both pages: ONE glass body that inflates, stretches
/// and glows as a whole under the finger (the bottom bar's behaviour), with
/// each icon its own tap target that pops under the finger.
///
/// The body's own tap does nothing; the slots sit above it and win the tap
/// (the innermost recogniser takes the arena). The body's physics listens with
/// a raw pointer listener, so it moves whether or not a slot takes the tap.
class DetailGlassCapsule extends StatelessWidget {
  const DetailGlassCapsule({super.key, required this.slots, this.accent = Colors.white});

  final List<DetailGlassSlot> slots;
  final Color accent;

  static const double slotWidth = 46;
  static const double padding = 4;

  /// The capsule's width, for layouts that must leave room for it.
  static double widthFor(int slots) => slots * slotWidth + padding * 2;

  @override
  Widget build(BuildContext context) {
    final w = widthFor(slots.length);
    const h = DetailGlass.barSize;
    return lgw.GlassButton.custom(
      width: w,
      height: h,
      shape: const lgw.LiquidRoundedSuperellipse(borderRadius: h / 2),
      onTap: () {},
      label: '',
      glowColor: DetailGlass.glow(accent),
      stretch: 0.6,
      excludeFromSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: padding),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [for (final s in slots) _CapsuleSlot(slot: s)],
        ),
      ),
    );
  }
}

class _CapsuleSlot extends StatefulWidget {
  const _CapsuleSlot({required this.slot});

  final DetailGlassSlot slot;

  @override
  State<_CapsuleSlot> createState() => _CapsuleSlotState();
}

class _CapsuleSlotState extends State<_CapsuleSlot> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    final icon = slot.child ?? Icon(slot.icon, color: Colors.white, size: 22);

    Widget tappable(VoidCallback onTap) => Semantics(
          button: true,
          label: slot.label,
          excludeSemantics: true,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              HapticFeedback.selectionClick();
              _set(true);
            },
            onPointerUp: (_) => _set(false),
            onPointerCancel: (_) => _set(false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                onTap();
              },
              // Pops under the finger and settles with a small overshoot.
              child: AnimatedScale(
                scale: _down ? 1.18 : 1.0,
                duration: Duration(milliseconds: _down ? 110 : 260),
                curve: _down ? Curves.easeOutCubic : Curves.easeOutBack,
                child: SizedBox(
                  width: DetailGlassCapsule.slotWidth,
                  height: DetailGlass.barSize,
                  child: Center(child: icon),
                ),
              ),
            ),
          ),
        );

    final items = slot.menuItems;
    if (items != null) {
      return lgw.GlassMenu(
        menuWidth: slot.menuWidth,
        triggerBuilder: (context, toggle) => tappable(toggle),
        items: items,
      );
    }
    return tappable(slot.onTap!);
  }
}

/// The overlay bar over a detail page: a back circle on the left, the glass
/// capsule on the right, and the page title between them once the header has
/// scrolled away. Sits ABOVE the scroll view (never inside it).
class DetailTopBar extends StatelessWidget {
  const DetailTopBar({
    super.key,
    required this.controller,
    required this.title,
    required this.background,
    required this.slots,
    this.accent = Colors.white,
    this.titleAppearsAt = 240,
    this.onBack,
  });

  final ScrollController controller;
  final String title;

  /// The page's darkest colour; the scrim under the bar is made of it.
  final Color background;
  final List<DetailGlassSlot> slots;
  final Color accent;

  /// Scroll offset at which the title starts to appear.
  final double titleAppearsAt;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final side = DetailGlassCapsule.widthFor(slots.length) + 20;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final off = controller.hasClients && controller.position.hasPixels ? controller.offset : 0.0;
          final scrim = (off / titleAppearsAt).clamp(0.0, 1.0);
          final titleOpacity = ((off - titleAppearsAt) / 60).clamp(0.0, 1.0);
          return Stack(
            children: [
              // Gradient-only: content scrolling under the bar is dimmed, not
              // blurred, and there is no edge to see.
              IgnorePointer(
                child: Container(
                  height: top + 76,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        background.withValues(alpha: 0.92 * scrim),
                        background.withValues(alpha: 0.55 * scrim),
                        background.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(12, top + 8, 12, 0),
                child: DetailGlassScope(
                  accent: accent,
                  child: SizedBox(
                    height: DetailGlass.barSize,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: titleOpacity,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: side),
                                child: Center(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppFont.style(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            DetailGlassCircle(
                              icon: Icons.arrow_back_rounded,
                              label: 'Back',
                              accent: accent,
                              onTap: onBack ?? () => Navigator.maybePop(context),
                            ),
                            const Spacer(),
                            DetailGlassCapsule(slots: slots, accent: accent),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
