import 'package:flutter/material.dart';

import '../design/tokens/space.dart';
import '../design/tokens/type.dart' as type;

/// Slim prompt inviting the user to sign in, shown while anonymous.
///
/// Placed above the feed rather than as a modal: it is an invitation with a
/// consequence the user has not asked for yet, and a modal about it would be
/// louder than the thing it is asking for.
///
/// Not dismissible. A dismissible sign-in prompt is a prompt the user can make
/// disappear and never think about again, which is exactly the opposite of what
/// it is for. It leaves when they are signed in, which is the only state in
/// which it is no longer true.
///
/// The whole row is tappable, not just the button, so the target is the full
/// width of the card rather than a 90dp island.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Semantics(
        button: true,
        label: 'Sign in to YouTube Music',
        child: InkWell(
          onTap: onSignIn,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.md, Spacing.sm, Spacing.md),
            decoration: BoxDecoration(
              // Tinted with the app surface rather than the accent, so the row
              // reads as part of the feed instead of an advertisement for it.
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Sign in to YouTube Music',
                        style: type.Type.body(context)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      // Two lines' worth of room and ellipsis, rather than a
                      // hard one-line clamp: the old layout truncated this to
                      // "Get personali..." on a narrow screen, which says less
                      // than nothing.
                      Text(
                        'Get picks from your own listening',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.Type.metadata(context)
                            .copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg, vertical: Spacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    'Sign in',
                    style: type.Type.body(context).copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}