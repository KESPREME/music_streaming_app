// lib/widgets/transition_trace_card.dart
//
// "Last transition": the engine's account of the most recent mix, in words.
//
// The sound cannot be inspected from a phone, so this is how a mix that sounded
// wrong gets diagnosed: was it planned badly (the plan line), balanced badly
// (the level line), started late (the timing line), or off the beat (the beat
// line)? Tapping copies the raw MIX_TRACE line, which is what to send along.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_font.dart';

import '../services/transition/transition_engine.dart';
import '../services/transition/transition_planner.dart';

/// The lines of the card for [t]: plan, level, timing, beat (the last only for a
/// beat-matched mix).
List<({String label, String text})> describeMix(MixTrace t) {
  final plan = t.plan;
  final secs = (t.fadeMs / 1000).toStringAsFixed(1);
  final kind = switch (plan.kind) {
    PlanKind.beatmatched => 'AutoMix on the beat',
    PlanKind.smart => 'AutoMix over the ending',
    PlanKind.crossfade => plan.reason == 'automix-fallback'
        ? 'Plain fade (AutoMix had nothing to go on)'
        : 'Crossfade',
    PlanKind.none => 'No mix',
  };

  final level = t.level;
  final levelText = level.isNone
      ? 'The two songs were already close in loudness'
      : level.incomingDb < 0
          ? 'Incoming song was ${(-level.incomingDb).toStringAsFixed(1)} dB louder: held down, then let back up'
          : 'Incoming song was ${(-level.outgoingDb).toStringAsFixed(1)} dB quieter: the leaving song was brought down';

  final lines = <({String label, String text})>[
    (
      label: 'Plan',
      text: '$kind · $secs s${t.completed ? '' : ' · interrupted'}'
          '${(plan.incomingRate - 1).abs() > 1e-4 ? ' · tempo ${(plan.incomingRate - 1) >= 0 ? '+' : '−'}${((plan.incomingRate - 1).abs() * 100).toStringAsFixed(1)} %' : ''}',
    ),
    (label: 'Levels', text: levelText),
    (
      label: 'Timing',
      text: 'Started ${t.startedLateMs} ms after the plan · slowest step ${t.maxTickGapMs} ms',
    ),
  ];
  if (t.firstPhaseErrorMs != null) {
    final first = t.firstPhaseErrorMs!.toStringAsFixed(0);
    final last = t.lastPhaseErrorMs!.toStringAsFixed(0);
    lines.add((
      label: 'Beat',
      text: t.phaseReleased
          ? 'Off by $first ms; too far to correct, left as planned'
          : 'Off by $first ms at first, $last ms at the end'
              '${t.peakTrim > 0 ? ' (speed trimmed up to ${(t.peakTrim * 100).toStringAsFixed(1)} %)' : ''}',
    ));
  }
  return lines;
}

class TransitionTraceCard extends StatefulWidget {
  const TransitionTraceCard({super.key, required this.trace});

  final ValueListenable<MixTrace?> trace;

  @override
  State<TransitionTraceCard> createState() => _TransitionTraceCardState();
}

class _TransitionTraceCardState extends State<TransitionTraceCard> {
  bool _copied = false;

  Future<void> _copy(MixTrace t) async {
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: t.toString()));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<MixTrace?>(
      valueListenable: widget.trace,
      builder: (context, t, _) {
        final lines = t == null ? null : describeMix(t);
        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: t == null
              ? const SizedBox(width: double.infinity)
              : Semantics(
                  button: true,
                  label: 'Last transition details. Double tap to copy.',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _copy(t),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.07)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Last transition',
                                  style: AppFont.style(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 160),
                                child: Text(
                                  _copied ? 'Copied' : 'Tap to copy',
                                  key: ValueKey<bool>(_copied),
                                  style: AppFont.style(
                                    color: _copied
                                        ? accent
                                        : Colors.white38,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          for (final line in lines!)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 58,
                                    child: Text(
                                      line.label,
                                      style: AppFont.style(
                                        color: accent.withValues(alpha: 0.85),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      line.text,
                                      style: AppFont.style(
                                        color: Colors.white70,
                                        fontSize: 12.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
