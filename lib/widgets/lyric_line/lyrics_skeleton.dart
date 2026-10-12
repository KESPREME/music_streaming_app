// lib/widgets/lyric_line/lyrics_skeleton.dart
// The placeholder while a lookup that has nothing to show yet is in flight.
//
// BitChord draws skeleton bars rather than a spinner: 26dp tall, 15dp apart in a
// block, 35dp between blocks, with a shimmer over 1400ms. A spinner says "wait";
// bars say "lyrics are about to be here, and this is the shape they take", which
// is why the list does not appear to jump when they land.

import 'package:flutter/widgets.dart';

class LyricsSkeleton extends StatefulWidget {
  const LyricsSkeleton({super.key});

  @override
  State<LyricsSkeleton> createState() => _LyricsSkeletonState();
}

class _LyricsSkeletonState extends State<LyricsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  // Fractions of the available width: a believable ragged paragraph.
  static const List<List<double>> _blocks = [
    [0.86, 0.62],
    [0.74, 0.9, 0.48],
    [0.82, 0.58],
    [0.7, 0.88],
  ];

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading lyrics',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _shimmer,
          builder: (context, _) {
            // 0.10 -> 0.22 -> 0.10: a slow breath, not a sweep.
            final t = _shimmer.value;
            final breath = 0.16 + 0.06 * (1 - (2 * t - 1).abs());
            return Padding(
              padding: const EdgeInsets.fromLTRB(30, 0, 30, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var b = 0; b < _blocks.length; b++) ...[
                    if (b > 0) const SizedBox(height: 35),
                    for (var i = 0; i < _blocks[b].length; i++) ...[
                      if (i > 0) const SizedBox(height: 15),
                      FractionallySizedBox(
                        widthFactor: _blocks[b][i],
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 26,
                          decoration: BoxDecoration(
                            color: Color.fromRGBO(255, 255, 255, breath),
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
