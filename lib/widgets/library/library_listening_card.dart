// lib/widgets/library/library_listening_card.dart
//
// The Library's one authored moment: how long you listened this year.
//
// A single measured number (see ListeningStats), set large in tabular figures,
// over ribbons of light tinted by what is playing. The number counts up to its
// value when the card arrives and when the value grows; the ribbons ease from
// flat to their shape with it, so the card "fills" with the year. Nothing loops:
// once settled it is a static picture, and with reduce-motion it is static from
// the first frame.
//
// One sentence of context under the number comes from real data - the artist you
// have played most lately - and is left out when there is nothing to say.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../../services/listening_stats.dart';
import '../home_sections.dart' show PressableScale;

/// "1513" -> "1,513".
String groupThousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// The artist with the most plays among [recents] (newest first), or null when
/// no artist appears at least twice - one play is not a pattern.
String? topRecentArtist(List<Track> recents, {int window = 50}) {
  final counts = <String, int>{};
  for (final t in recents.take(window)) {
    final a = t.artistName.trim();
    if (a.isEmpty) continue;
    counts[a] = (counts[a] ?? 0) + 1;
  }
  String? best;
  var bestCount = 1;
  counts.forEach((artist, count) {
    if (count > bestCount) {
      best = artist;
      bestCount = count;
    }
  });
  return best;
}

class LibraryListeningCard extends StatelessWidget {
  const LibraryListeningCard({
    super.key,
    required this.stats,
    this.onTap,
    this.horizontalPadding = 20,
  });

  final ListeningStats stats;
  final VoidCallback? onTap;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final accent = context.select<MusicProvider, Color?>(
          (p) => p.currentPaletteColor,
        ) ??
        Theme.of(context).colorScheme.primary;
    final recents = context.select<MusicProvider, List<Track>>(
      (p) => p.recentlyPlayed,
    );
    final topArtist = topRecentArtist(recents);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final year = DateTime.now().year;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: ListenableBuilder(
        listenable: stats,
        builder: (context, _) {
          final minutes = stats.minutesThisYear;
          final empty = minutes < 1;
          final label = empty
              ? 'Your $year in music starts with the next song.'
              : '${groupThousands(minutes)} minutes listened in $year'
                  '${topArtist == null ? '' : '. Lately, mostly $topArtist.'}';

          return Semantics(
            button: onTap != null,
            label: label,
            excludeSemantics: true,
            child: PressableScale(
              onTap: onTap == null
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      onTap!();
                    },
              child: _CardBody(
                accent: accent,
                minutes: minutes,
                empty: empty,
                year: year,
                topArtist: topArtist,
                reduceMotion: reduceMotion,
                showChevron: onTap != null,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.accent,
    required this.minutes,
    required this.empty,
    required this.year,
    required this.topArtist,
    required this.reduceMotion,
    required this.showChevron,
  });

  final Color accent;
  final int minutes;
  final bool empty;
  final int year;
  final String? topArtist;
  final bool reduceMotion;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // From 0 on arrival; from the shown value when it grows.
      tween: Tween<double>(begin: 0, end: minutes.toDouble()),
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 1100),
      curve: Curves.easeOutExpo,
      builder: (context, shown, _) {
        // How far along the fill is, for the ribbons. Empty still breathes a
        // little so the card is never a dead rectangle.
        final fill = minutes == 0 ? 0.35 : (shown / minutes).clamp(0.0, 1.0);
        return Container(
          // A floor, not a fixed height: large text grows the card instead of
          // clipping it.
          constraints: const BoxConstraints(minHeight: 136),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF101219), Color(0xFF07080B)],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: RibbonPainter(color: accent, fill: fill),
                  ),
                ),
              ),
              // Legibility: the ribbons live on the right; the words on the left.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xF207080B), Color(0x0007080B)],
                      stops: [0.38, 0.78],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: empty
                          ? _EmptyCopy(year: year)
                          : _Figure(
                              shown: shown.round(),
                              year: year,
                              topArtist: topArtist,
                              accent: accent,
                            ),
                    ),
                    if (showChevron)
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.55),
                        size: 26,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.shown,
    required this.year,
    required this.topArtist,
    required this.accent,
  });

  final int shown;
  final int year;
  final String? topArtist;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            groupThousands(shown),
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 44,
              height: 1.0,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.6,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'minutes listened in $year',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (topArtist != null) ...[
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Lately, mostly '),
              TextSpan(
                text: topArtist,
                style: TextStyle(
                  color: Color.lerp(accent, Colors.white, 0.45),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyCopy extends StatelessWidget {
  const _EmptyCopy({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your $year in music',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Starts with the next song. Every minute you play is counted here.',
          maxLines: 2,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Three ribbons of light across the right of the card. [fill] 0..1 lifts them
/// from a flat line to their full swell.
class RibbonPainter extends CustomPainter {
  RibbonPainter({required this.color, required this.fill});

  final Color color;
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const ribbons = [
      // phase, amplitude (fraction of height), vertical centre, alpha, stroke
      (0.0, 0.34, 0.62, 0.55, 1.6),
      (1.3, 0.26, 0.55, 0.32, 1.1),
      (2.4, 0.42, 0.70, 0.20, 0.9),
    ];
    for (final (phase, amp, centre, alpha, stroke) in ribbons) {
      final path = Path();
      const steps = 48;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final x = w * (0.30 + 0.75 * t);
        // Rises toward the right, like a year accumulating.
        final envelope = math.pow(t, 1.4).toDouble() * fill;
        final y = h * centre -
            h * amp * envelope * (0.55 + 0.45 * math.sin(t * 5.2 + phase));
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0),
          Color.lerp(color, Colors.white, 0.35)!.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.6),
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(w * 0.3, 0, w * 0.7, h));

      // Soft glow under a crisp line.
      canvas.drawPath(
        path,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(
        path,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke,
      );
    }
  }

  @override
  bool shouldRepaint(RibbonPainter old) =>
      old.fill != fill || old.color != color;
}
