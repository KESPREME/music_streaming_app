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
class TransformDisc extends StatefulWidget {
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
  State<TransformDisc> createState() => _TransformDiscState();
}

class _TransformDiscState extends State<TransformDisc> {
  late double _discAlpha = widget.active ? 0.34 : 0.18;

  @override
  void didUpdateWidget(covariant TransformDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    // The disc's own alpha moves on its own spec, rather than snapping with the
    // glyph.
    //
    // It used to be read straight off `active` at build time, which meant the
    // disc and the icon inside it changed on different frames - and both
    // `lyricsDiscFadeIn` and `lyricsDiscFadeOut` were declared below for exactly
    // this and referenced zero times. The reference tweens this on the disc's
    // default spring (`PlayerLyrics.kt:1258, 1309`); a short tween is close
    // enough and cannot overshoot.
    setState(() {
      _discAlpha = widget.active ? 0.34 : 0.18;
    });
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    final semanticLabel = widget.semanticLabel;
    final state = widget.state;
    final active = widget.active;
    final onTap = widget.onTap;

    // 0.42 is the "there is nothing to do here" tint and is deliberately dimmer
    // than the idle 0.78: a romanization of an English lyric is still a button,
    // because hiding it makes the feature undiscoverable, but tapping it should
    // not look like it will do something.
    final tint = switch (state) {
      TransformButtonState.sameLanguage => Colors.white.withValues(alpha: 0.42),
      _ when active => Colors.white,
      _ => Colors.white.withValues(alpha: 0.78),
    };

    // NOT disabled by `sameLanguage`.
    //
    // It was, and that defeated the whole feature: the disc went dim AND stopped
    // responding, so tapping it did nothing at all - a silently dead control,
    // which reads as broken rather than as an answer. The reference taps through
    // and shows the message (`PlayerLyrics.kt:2791-2794`). Dimming is the signal
    // that there is nothing to do; tapping is how the reader finds out WHAT.
    final disabled = onTap == null;

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
                onTap();
              },
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: _discAlpha),
          duration: _discAlpha > 0.18 ? lyricsDiscFadeIn : lyricsDiscFadeOut,
          curve: Curves.easeOut,
          builder: (context, alpha, _) => Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: alpha),
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
      ),
    );
  }
}

/// How long the player stands under the lyrics untouched before the discs leave.
const Duration lyricsDiscIdleTimeout = Duration(seconds: 5);

/// How long the discs take to arrive and to leave.
const Duration lyricsDiscFadeIn = Duration(milliseconds: 220);
const Duration lyricsDiscFadeOut = Duration(milliseconds: 160);
/// Fades and scales a disc in and out with the player's controls.
///
/// The discs belong to the controls: they arrive with the deck and leave with it,
/// on one decision (see `now_playing_screen.dart`), not on a timer of their own.
/// Before this they popped in and out with no animation, a beat apart from a
/// deck that slid over 300ms, so they read as appearing "when the controls hide".
///
/// An alpha is safe HERE and nowhere near the deck: a disc is a flat translucent
/// circle, not a backdrop lens, so there is no glass for a translucent layer to
/// flatten.
class LyricsDiscReveal extends StatelessWidget {
  const LyricsDiscReveal({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = visible ? lyricsDiscFadeIn : lyricsDiscFadeOut;
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedScale(
          scale: visible ? 1.0 : 0.92,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: duration,
            curve: Curves.easeOut,
            child: child,
          ),
        ),
      ),
    );
  }
}