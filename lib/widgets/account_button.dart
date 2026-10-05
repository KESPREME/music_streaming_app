import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens/motion.dart';
import '../services/auth_service.dart';
import 'glass_circle_button.dart';

/// Header avatar: opens the account quick-switch, or steps between channels.
///
/// Tapping opens [onTap]. Dragging vertically steps to the adjacent channel in
/// the same account, with elastic overshoot past the ends so the gesture has a
/// physical "there is nothing further" cue instead of simply doing nothing.
///
/// That cue matters: without it a swipe to the last channel reads as a dropped
/// gesture, and the user tries again harder.
///
/// The drag only claims the gesture once it has clearly become vertical, so it
/// cannot steal the list's scroll.
class AccountButton extends StatefulWidget {
  const AccountButton({
    super.key,
    required this.auth,
    required this.onTap,
  });

  final AuthService auth;
  final VoidCallback onTap;

  /// How far a drag must travel before it counts as a step.
  static const double swipeThreshold = 26;

  /// Maximum visual displacement while dragging, in logical pixels.
  static const double maxOvershoot = 8;

  @override
  State<AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<AccountButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Settles the elastic return without a second gesture.
    duration: Motion.normal,
  );

  Animation<double>? _return;

  double _dragOffset = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_identities.length < 2) return;
    setState(() => _dragOffset =
        (_dragOffset + details.primaryDelta!).clamp(-_overshoot, _overshoot));
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_identities.length < 2) {
      _settle();
      return;
    }
    final travelled = _dragOffset;
    if (travelled.abs() < AccountButton.swipeThreshold) {
      _settle();
      return;
    }
    // Up steps forward, down steps back, matching the visual drag direction so
    // the list moves the way the finger did.
    final forward = travelled < 0;
    final auth = widget.auth;
    final next = auth.adjacentIdentity(
      forward: forward,
      accountId: auth.activeAccountId,
      profileId: auth.activeAccount?.activeProfileId,
    );
    // No wraparound: stepping past the end is a no-op with a haptic bump, not a
    // jump to the other end of a list the user cannot see.
    if (next != null) {
      HapticFeedback.lightImpact();
      unawaited(auth.selectIdentity(next.$1, next.$2));
    }
    _settle();
  }

  void _settle() {
    _return = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Motion.springCurve),
    );
    _controller
      ..removeListener(_applyReturn)
      ..addListener(_applyReturn)
      ..forward(from: 0);
    setState(() => _dragOffset = 0);
  }

  void _applyReturn() {
    final value = _return?.value;
    if (value == null || !mounted) return;
    setState(() => _dragOffset = value);
  }

  List<(String, String)> get _identities => widget.auth.allIdentities;

  double get _overshoot => AccountButton.maxOvershoot;

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final account = auth.activeAccount;
    final signedIn = auth.isLoggedIn;
    final avatarUrl = account?.bestAvatarUrl;
    final name = account?.displayName ?? '';

    return GestureDetector(
      // Only claim the gesture once it is clearly vertical, so the list keeps
      // its own horizontal panning.
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: GlassCircleButton(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          semanticLabel: signedIn ? 'Account: $name' : 'Sign in',
          child: _Avatar(url: avatarUrl, name: name, signedIn: signedIn),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.name,
    required this.signedIn,
  });

  final String? url;
  final String name;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!signedIn) {
      return Icon(Icons.person_outline_rounded,
          size: 22, color: theme.colorScheme.onSurfaceVariant);
    }

    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
      return Text(
        initial,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return ClipOval(
      child: Image.network(
        trimmed,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        // Falls back to the same glyph an absent URL renders, so a 404 and a
        // missing picture are indistinguishable rather than one looking broken.
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.person_rounded,
          size: 22,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}