// lib/widgets/mix_overlays.dart
//
// What the Now Playing screen does while one song is mixing into the next.
//
// THE RULE: the interface moves on the same timeline as the sound. Every number
// here is the engine's own progress (0..1 across the overlap) - the number that
// sets the audio gains - so the picture and the sound cannot drift apart, and a
// pause freezes both.
//
// THE SHAPE: the metadata (title, queue, lyrics) flips once, at the midpoint,
// because text cannot be half of one song. The artwork and the wash behind it
// finish their dissolve by that same moment, so when the screen's state changes
// there is nothing left to change - the incoming art is already fully showing.
// The overlays stay mounted until the mix ends (progress 1), covering the base
// layer while IT catches up, so the handoff is never a visible event.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../theme/app_font.dart';

import '../models/track.dart';
import '../services/transition/transition_engine.dart';
import 'blurred_backdrop.dart';
import 'transition_glyph.dart';

/// How far the visual dissolve has got: eased, and finished at the handoff.
double dissolveAt(double progress) => Curves.easeInOut
    .transform((progress / TransitionEngine.handoffAt).clamp(0.0, 1.0));

bool _showing(TransitionUiState s) =>
    s.phase == TransitionPhase.fading && s.incomingId != null;

/// The incoming song's artwork, dissolving in over the current one.
class MixIncomingArt extends StatelessWidget {
  const MixIncomingArt({
    super.key,
    required this.state,
    required this.trackFor,
    required this.buildArt,
  });

  final ValueListenable<TransitionUiState> state;
  final Track? Function(String id) trackFor;
  final Widget Function(Track track) buildArt;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TransitionUiState>(
      valueListenable: state,
      builder: (context, s, _) {
        if (!_showing(s)) return const SizedBox.shrink();
        final track = trackFor(s.incomingId!);
        if (track == null) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: dissolveAt(s.progress),
              child: SizedBox.expand(child: buildArt(track)),
            ),
          ),
        );
      },
    );
  }
}

/// The incoming song's blurred wash, dissolving in over the current one.
class MixIncomingBackdrop extends StatelessWidget {
  const MixIncomingBackdrop({
    super.key,
    required this.state,
    required this.trackFor,
  });

  final ValueListenable<TransitionUiState> state;
  final Track? Function(String id) trackFor;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TransitionUiState>(
      valueListenable: state,
      builder: (context, s, _) {
        if (!_showing(s)) return const SizedBox.shrink();
        final track = trackFor(s.incomingId!);
        final image =
            track == null ? null : backdropArtProvider(track.albumArtUrl);
        if (image == null) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: dissolveAt(s.progress),
              // Its own fade is off: the dissolve IS the progress.
              child: BlurredBackdrop(
                image: image,
                sigma: 60,
                scale: 1.6,
                alignment: Alignment.topCenter,
                fade: Duration.zero,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "AutoMix" on the scrubber while a REAL mix (not a plain fade) is running.
/// A crossfade needs no announcement; a mix the listener did not ask for
/// moment-by-moment is worth one quiet word.
class MixBadge extends StatelessWidget {
  const MixBadge({super.key, required this.state});

  final ValueListenable<TransitionUiState> state;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<TransitionUiState>(
      valueListenable: state,
      builder: (context, s, _) {
        final show = _showing(s) && s.isMix;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(anim),
              child: child,
            ),
          ),
          child: show
              ? Semantics(
                  liveRegion: true,
                  label: 'AutoMix in progress',
                  child: Container(
                    key: const ValueKey<String>('mix-badge'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: accent.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomPaint(
                          size: const Size.square(14),
                          painter: TransitionGlyphPainter(
                            Colors.white,
                            overlap: Curves.easeInOut.transform(s.progress),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'AutoMix',
                          style: AppFont.style(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey<String>('no-mix-badge')),
        );
      },
    );
  }
}

/// Shows [value], but when it jumps by more than [threshold] in one update
/// (the scrubber when the session moves to the incoming song's position)
/// glides there instead of snapping. Ordinary movement - a position creeping
/// forward - passes through untouched.
class JumpSmoother extends StatefulWidget {
  const JumpSmoother({
    super.key,
    required this.value,
    required this.builder,
    this.enabled = true,
    this.threshold = 0.2,
    this.duration = const Duration(milliseconds: 380),
  });

  final double value;
  final Widget Function(BuildContext context, double smoothed) builder;

  /// False while the listener is dragging: their finger is the animation.
  final bool enabled;
  final double threshold;
  final Duration duration;

  @override
  State<JumpSmoother> createState() => _JumpSmootherState();
}

class _JumpSmootherState extends State<JumpSmoother>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late double _from = widget.value;
  late double _to = widget.value;

  double get _shown => _controller.isAnimating
      ? _from + (_to - _from) * Curves.easeOutCubic.transform(_controller.value)
      : _to;

  @override
  void didUpdateWidget(covariant JumpSmoother old) {
    super.didUpdateWidget(old);
    final target = widget.value;
    if (!widget.enabled || MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _to = target;
      return;
    }
    if (_controller.isAnimating) {
      // Retarget from where the glide has got to, so a second jump (or the
      // position creeping on) bends the motion instead of restarting it.
      if ((target - _to).abs() > 1e-6) {
        _from = _shown;
        _to = target;
        _controller.forward(from: 0);
      }
      return;
    }
    if ((target - _to).abs() > widget.threshold) {
      _from = _to;
      _to = target;
      _controller.forward(from: 0);
    } else {
      _to = target;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(context, _shown),
    );
  }
}
