// lib/widgets/settings/settings_segmented.dart
//
// A choice between a few named options, as one pill with a thumb that slides to
// the pick: Glass rendering (Auto / Refraction / Frosted), streaming quality
// (Auto / 64 / 128 / 256 / 320), anything that used to be a dialog with radio
// buttons. One tap instead of three, and the whole set stays visible.
//
// The thumb springs rather than snaps, each segment flexes under the finger like
// the rest of the app's controls, and every segment is a real semantic button
// with a selected state.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_font.dart';
import '../jelly_press.dart';

class SettingsSegmented<T> extends StatelessWidget {
  const SettingsSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.height = 44,
    this.semanticPrefix,
  });

  /// (value, label) in display order.
  final List<(T, String)> options;

  /// The current value, or null when none of the options is in force.
  final T? selected;
  final ValueChanged<T> onChanged;
  final double height;

  /// Spoken before each label ("Wi-Fi quality").
  final String? semanticPrefix;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final index = options.indexWhere((o) => o.$1 == selected);
    final n = options.length;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Stack(
        children: [
          if (index >= 0)
            AnimatedAlign(
              duration: reduce ? Duration.zero : const Duration(milliseconds: 340),
              curve: Curves.easeOutBack,
              alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / n,
                heightFactor: 1,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(height / 2),
                    gradient: RadialGradient(
                      radius: 2.4,
                      colors: [
                        accent.withValues(alpha: 0.34),
                        accent.withValues(alpha: 0.12),
                      ],
                    ),
                    border: Border.all(color: accent.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(color: accent.withValues(alpha: 0.2), blurRadius: 12),
                    ],
                  ),
                ),
              ),
            ),
          Row(
            children: [
              for (final o in options)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: o.$1 == selected,
                    label: semanticPrefix == null ? o.$2 : '$semanticPrefix ${o.$2}',
                    excludeSemantics: true,
                    child: JellyPress(
                      profile: JellyProfile.icon,
                      haptic: JellyHaptic.none,
                      onTap: () {
                        if (o.$1 == selected) return;
                        HapticFeedback.selectionClick();
                        onChanged(o.$1);
                      },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 220),
                          style: AppFont.style(
                            fontSize: 13.5,
                            fontWeight:
                                o.$1 == selected ? FontWeight.w800 : FontWeight.w600,
                            color: o.$1 == selected ? Colors.white : Colors.white54,
                          ),
                          child: Text(o.$2, maxLines: 1, overflow: TextOverflow.fade),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
