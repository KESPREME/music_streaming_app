import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_font.dart';

import '../screens/song_transitions_screen.dart';
import '../services/transition/transition_settings.dart';
import 'transition_glyph.dart';

/// The queue's song-transition control: a capsule that names the current state
/// and steps through it.
///
///   tap        Off -> Crossfade -> AutoMix -> Off
///   long-press the full Song Transitions screen
///
/// It names its state rather than showing an on/off glow, because there are
/// three states and the listener should never have to open a screen to learn
/// which one they are in.
class TransitionChip extends StatelessWidget {
  const TransitionChip({super.key, required this.settings});

  final TransitionSettings settings;

  /// What a tap does next, as pure data.
  static ({bool enabled, TransitionStyle style}) next(TransitionSettings s) {
    if (!s.enabled) return (enabled: true, style: TransitionStyle.crossfade);
    if (s.style == TransitionStyle.crossfade) {
      return (enabled: true, style: TransitionStyle.automix);
    }
    return (enabled: false, style: s.style);
  }

  static String label(TransitionSettings s) {
    if (!s.enabled) return 'Transitions';
    return s.style == TransitionStyle.automix
        ? 'AutoMix'
        : 'Crossfade · ${s.crossfadeSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final on = settings.enabled;
        final text = label(settings);
        return Semantics(
          button: true,
          selected: on,
          label: 'Song transitions: ${on ? text : 'off'}. Tap to change, '
              'long press for settings.',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              final n = next(settings);
              settings.setStyle(n.style);
              settings.setEnabled(n.enabled);
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SongTransitionsScreen(settings: settings),
              ));
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: on
                    ? accent.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: on
                      ? accent.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.18),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TransitionGlyph(
                    size: 16,
                    color: on ? accent : Colors.white.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.25),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Text(
                      text,
                      key: ValueKey<String>(text),
                      style: AppFont.style(
                        color: on
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
