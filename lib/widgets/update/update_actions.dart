// lib/widgets/update/update_actions.dart
//
// The one place that turns "the main button was pressed" into a call on the
// updater. The Software Update screen and the update sheet both use it, so a
// retry does the same thing from either.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_platform.dart';
import '../../services/update/update_models.dart';
import '../../services/update/update_service.dart';
import '../../theme/app_font.dart';
import '../jelly_press.dart';
import 'update_copy.dart';

Future<void> runUpdateAction(UpdateService service, UpdateAction action) async {
  switch (action) {
    case UpdateAction.check:
      await service.check(force: true);
    case UpdateAction.download:
      await service.download();
    case UpdateAction.cancel:
      service.cancel();
    case UpdateAction.install:
      await service.install();
    case UpdateAction.allow:
      await AppPlatform.openInstallSettings();
    case UpdateAction.retry:
      // Retry whichever step broke: an install that failed is installed again,
      // not downloaded again.
      if (service.state.failedDuring == UpdateStatus.installing) {
        await service.install();
      } else {
        await service.download();
      }
    case UpdateAction.none:
      break;
  }
}

/// The main button: its label, colour and shape follow the state, and they
/// morph rather than jump.
class UpdateActionButton extends StatelessWidget {
  const UpdateActionButton({
    super.key,
    required this.copy,
    required this.onPressed,
    this.progress,
  });

  final UpdateCopy copy;
  final VoidCallback onPressed;

  /// 0..1 draws a fill inside the button while downloading.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final cancel = copy.action == UpdateAction.cancel;
    final quiet = cancel || copy.busy;
    final fill = quiet ? Colors.white.withValues(alpha: 0.08) : accent;
    final onFill = quiet
        ? Colors.white
        : (ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black);
    final enabled = !copy.busy && copy.action != UpdateAction.none;

    return Semantics(
      button: true,
      enabled: enabled,
      label: copy.actionLabel,
      excludeSemantics: true,
      child: JellyPress(
        enabled: enabled,
        haptic: JellyHaptic.none,
        borderRadius: 28,
        onTap: () {
          HapticFeedback.mediumImpact();
          onPressed();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          height: 56,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: fill,
            border: quiet
                ? Border.all(color: Colors.white.withValues(alpha: 0.12))
                : null,
            boxShadow: quiet
                ? const []
                : [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8))],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (cancel && progress != null)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress!.clamp(0.0, 1.0),
                      child: Container(color: accent.withValues(alpha: 0.28)),
                    ),
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(anim), child: child),
                ),
                child: Row(
                  key: ValueKey('${copy.action}-${copy.actionLabel}-${copy.busy}'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (copy.busy) ...[
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: onFill),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Text(
                      copy.actionLabel,
                      style: AppFont.style(
                        color: onFill.withValues(alpha: enabled || cancel ? 1 : 0.7),
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
