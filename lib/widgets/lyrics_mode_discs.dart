// lib/widgets/lyrics_mode_discs.dart
// The two discs that switch a lyric between its original, a romanization and a
// translation.
//
// WHY TWO DISCS AND NOT ONE CYCLER
//
// They are two independent toggles, not one control with three positions. Tapping
// either one either turns THAT transform on or off - never advances to the next
// mode. With a cycler, getting back to the original takes three taps from
// translated, and the most-tapped transition by far is "I changed my mind".
//
// They also exclude each other. Showing a romanization and a translation at once
// puts two scripts in the gap under the same line, and the reader has no way to
// know which is which.
//
// WHY THEY FLOAT
//
// Drawn over the foot of the lyric panel rather than in a row beneath it, and
// only while the reader is actually interacting. A row reserved its own height,
// which came straight off the panel above and cost the lyric a line. Floating
// costs the panel nothing.
//
// That makes them capable of sitting over the last line - which is why they fade
// out when the reader stops touching anything. A control parked on top of the
// words when nobody asked for it is one more thing between a reader and them.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a transform button can be in.
enum TransformButtonState {
  /// Never asked, or asked and cleared.
  idle,

  /// A request is in flight.
  loading,

  /// Asked, and the answer is on screen.
  ready,

  /// Asked, and the text was already in the requested script.
  sameLanguage,
}

/// The 34dp disc both buttons are drawn on.
///
/// Sized and tinted to the reference: 34dp, a white disc at 0.18 alpha rising to
/// 0.34 when active, a 19dp glyph, and a 16dp spinner that REPLACES the glyph
/// rather than sitting beside it.
class TransformDisc extends StatelessWidget {
  const TransformDisc({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.state,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final TransformButtonState state;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 0.42 is the "there is nothing to do here" tint and is deliberately dimmer
    // than the idle 0.78: a romanization of an English lyric is still a button,
    // because hiding it makes the feature undiscoverable, but tapping it should
    // not look like it will do something.
    final tint = switch (state) {
      TransformButtonState.sameLanguage => Colors.white.withValues(alpha: 0.42),
      _ when active => Colors.white,
      _ => Colors.white.withValues(alpha: 0.78),
    };
    final disabled = state == TransformButtonState.sameLanguage || onTap == null;
    final discAlpha = active ? 0.34 : 0.18;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: discAlpha),
          ),
          child: Center(
            child: state == TransformButtonState.loading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.7,
                      valueColor: AlwaysStoppedAnimation(tint),
                    ),
                  )
                : Icon(icon, size: 19, color: tint),
          ),
        ),
      ),
    );
  }
}

/// How long the player stands under the lyrics untouched before the discs leave.
const Duration lyricsDiscIdleTimeout = Duration(seconds: 5);

/// How long the discs take to arrive and to leave.
const Duration lyricsDiscFadeIn = Duration(milliseconds: 220);
const Duration lyricsDiscFadeOut = Duration(milliseconds: 160);