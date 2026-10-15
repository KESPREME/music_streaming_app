// lib/widgets/queue_transition_connector.dart
//
// The queue's one line about HOW the playing song will meet the next one:
//
//   ───────  ⧉ AutoMix · on the beat  ───────
//
// It sits between the song that is playing and the list that follows it, where
// the join actually is, and says only what the engine's planner has decided.
// Nothing here is a promise the planner has not made: before the two songs have
// been analysed an AutoMix line says it is still listening, and an album that
// stays gapless says so - the explanation for why nothing is blending.
//
// It appears with a short height-and-fade, and its words change with the same
// vertical exchange as the title on the player (track_swap.dart), so the two
// read as one system.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/song_transitions_screen.dart';
import '../services/transition/transition_engine.dart';
import '../services/transition/transition_planner.dart';
import '../services/transition/transition_settings.dart';
import 'transition_glyph.dart';

/// What to say about [u], or null when there is nothing worth saying.
({String label, String? detail})? describeUpcoming(
    UpcomingMix u, TransitionSettings s) {
  final secs = (u.fadeMs / 1000).round();
  switch (u.kind) {
    case PlanKind.none:
      return u.reason == 'album-gapless'
          ? (label: 'Gapless', detail: 'Album tracks play straight through')
          : null;
    case PlanKind.crossfade:
      if (u.reason == 'automix-fallback') {
        return (
          label: 'AutoMix · $secs s',
          detail: u.analysed
              ? 'No clear ending to mix over, so a plain fade'
              : 'Listening to both songs first',
        );
      }
      return (label: 'Crossfade · $secs s', detail: null);
    case PlanKind.smart:
      return (
        label: 'AutoMix · $secs s',
        detail: 'Over the song\'s own ending, silence skipped',
      );
    case PlanKind.beatmatched:
      final pct = (u.incomingRate - 1) * 100;
      final detail = pct.abs() < 0.05
          ? 'Same tempo, bar lines together'
          : 'Tempo matched (${pct > 0 ? '+' : '−'}${pct.abs().toStringAsFixed(1)} %), '
              'bar lines together';
      return (label: 'AutoMix · on the beat', detail: detail);
  }
}

class QueueTransitionConnector extends StatelessWidget {
  const QueueTransitionConnector({
    super.key,
    required this.upcoming,
    required this.settings,
  });

  final ValueListenable<UpcomingMix?> upcoming;
  final TransitionSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[upcoming, settings]),
      builder: (context, _) {
        final u = upcoming.value;
        final text = (u == null || !settings.enabled) ? null : describeUpcoming(u, settings);
        // Transitions are off by default: until the listener has met them once,
        // the line where the join would be offers them.
        final tip = !settings.enabled && settings.loaded && !settings.tipSeen;
        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: tip
              ? _Tip(settings: settings)
              : text == null
                  ? const SizedBox(width: double.infinity)
                  : _Line(label: text.label, detail: text.detail, mix: u!.isMix),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.detail, required this.mix});

  final String label;
  final String? detail;
  final bool mix;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final color = mix ? accent : Colors.white.withValues(alpha: 0.62);
    final rule = Expanded(
      child: Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.09),
      ),
    );
    return Semantics(
      container: true,
      label: 'Transition to the next song: $label${detail == null ? '' : '. $detail'}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
          child: Row(
            children: [
              rule,
              const SizedBox(width: 12),
              Flexible(
                flex: 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  reverseDuration: const Duration(milliseconds: 120),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.3),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey<String>('$label|$detail'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TransitionGlyph(size: 14, color: color),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: GoogleFonts.plusJakartaSans(
                              color: color,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                      if (detail != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white.withValues(alpha: 0.42),
                            fontSize: 11,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              rule,
            ],
          ),
        ),
      ),
    );
  }
}

/// The one-time offer. Tapping it opens Song Transitions; the cross dismisses
/// it. Either way it never comes back.
class _Tip extends StatelessWidget {
  const _Tip({required this.settings});

  final TransitionSettings settings;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      key: const ValueKey<String>('transition-tip'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Semantics(
        button: true,
        label: 'Blend your songs. Crossfade or AutoMix, in Song Transitions.',
        child: Material(
          color: accent.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: accent.withValues(alpha: 0.28)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              settings.setTipSeen(true);
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SongTransitionsScreen(settings: settings),
              ));
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
              child: Row(
                children: [
                  TransitionGlyph(size: 22, color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Blend your songs',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Crossfade or AutoMix, so one song flows into the next.',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      settings.setTipSeen(true);
                    },
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}