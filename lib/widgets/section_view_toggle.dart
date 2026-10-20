import 'package:flutter/material.dart';

import '../design/glass/glass_materials.dart' show GlassTier;
import '../design/glass/glass_surface.dart' as design;
import '../design/tokens/motion.dart';
import '../presentation/home/home_view_mode.dart';
import 'jelly_press.dart';

/// Switches one Home section between compact rows and large artwork cards.
///
/// Three decisions worth stating, because each was a way to get this wrong:
///
///  * **The icon shows the mode you are switching TO**, not the one you are in.
///    A button that depicts the current state asks the reader to remember which
///    way round the metaphor goes. The reference app does this too, and it is
///    the right call: in card mode you see cards, so a list icon is the only
///    thing that makes sense as "what happens if I tap this".
///  * **The icon morph scales, it does not cross-fade.** A cross-fade needs an
///    opacity layer, and an opacity layer isolates the backdrop the lens samples
///    - the glass goes flat for the length of the animation. This is the same
///    reason the package's own dialog transition is scale-only.
///  * **A selection haptic fires on toggle.** Not on every press: this is a
///    mode change, not a navigation, and `selectionClick` is the Android
///    vocabulary for exactly that. The reference app fires nothing here, while
///    firing `Select` on a pixel-identical button elsewhere - so this is the
///    better of the two.
class SectionViewToggle extends StatefulWidget {
  const SectionViewToggle({
    super.key,
    required this.mode,
    required this.onToggle,
    this.semanticLabel,
  });

  final HomeSectionViewMode mode;
  final VoidCallback onToggle;

  /// Overrides the announced label. The default names the destination, which is
  /// what the icon shows.
  final String? semanticLabel;

  @override
  State<SectionViewToggle> createState() => _SectionViewToggleState();
}

class _SectionViewToggleState extends State<SectionViewToggle> {
  HomeSectionViewMode get _destination => widget.mode.toggled;

  /// Identity of the glyph currently on screen. The departing glyph keeps the
  /// key it was built with, so comparing against this is what tells the morph
  /// which side each glyph is on.
  Key get _destinationKey => ValueKey<HomeSectionViewMode>(_destination);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      // Names the layout the tap PRODUCES, matching the icon above. These two
      // drifted once: the icon showed the destination while the label named the
      // current mode, so a screen-reader user was told the opposite of what
      // sighted users saw.
      label: widget.semanticLabel ??
          (_destination == HomeSectionViewMode.card
              ? 'Switch to card view'
              : 'Switch to list view'),
      child: JellyPress(
        // Deeper than a card's 0.97: this is a control, not content, and a
        // control that barely moves reads as having missed the tap. The jelly
        // circle profile also stretches toward the finger, which the old
        // fixed 0.90 scale could not.
        profile: JellyProfile.circle,
        haptic: JellyHaptic.selection,
        onTap: widget.onToggle,
        child: SizedBox(
          // 34 rather than the reference's 32: 34 clears the 48dp touch
          // guidance comfortably inside the header's line height without
          // making the heading look like it has a button stapled on.
          width: 34,
          height: 34,
          child: design.GlassSurface(
            tier: GlassTier.card,
            borderRadius: 17,
            padding: EdgeInsets.zero,
            child: Center(
              child: AnimatedSwitcher(
                duration: Motion.normal,
                // Monotonic, and NOT the overshooting spring curve. See
                // sectionLayoutTransition in home_layout_switch.dart: an
                // overshoot passes its target at ~60% of the clock, so the new
                // glyph was fully formed while the old one was still there.
                switchInCurve: Motion.enter,
                switchOutCurve: Motion.exit,
                transitionBuilder: (child, animation) {
                  // AnimatedSwitcher runs the arriving glyph 0 -> 1 and the
                  // departing one 1 -> 0, and reports the same status for
                  // both, so the role is read off the child's key instead of
                  // guessed from the animation. Guessing backwards shrank the
                  // new glyph to nothing while the old one sat at full size.
                  final isLeaving = child.key != _destinationKey;
                  final curve = isLeaving ? Motion.exit : Motion.enter;
                  return AnimatedBuilder(
                    animation: animation,
                    child: child,
                    builder: (context, child) {
                      // No inversion: for the departing glyph the value
                      // already runs 1 -> 0, so it shrinks out of existence
                      // rather than growing back to full size on the way.
                      final v = curve.transform(animation.value.clamp(0.0, 1.0));
                      return Transform.rotate(
                        // A quarter turn, so the change reads as the same
                        // control re-pointing rather than as one glyph
                        // replacing another. It turns out on the way too.
                        angle: (isLeaving ? 0.25 : -0.25) * (1 - v),
                        child: Transform.scale(
                          scale: isLeaving ? v : 0.6 + 0.4 * v,
                          child: child,
                        ),
                      );
                    },
                  );
                },
                child: Icon(
                  _destination == HomeSectionViewMode.card
                      ? Icons.grid_view_rounded
                      : Icons.view_agenda_outlined,
                  key: _destinationKey,
                  size: 17,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
