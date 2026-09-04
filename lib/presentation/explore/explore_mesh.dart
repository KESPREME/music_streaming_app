import 'package:flutter/material.dart';

import '../../services/explore/explore_palette.dart';
import 'explore_tokens.dart';

/// Palette-driven liquid atmosphere: three drifting radial blobs
/// (vibrant / background / accent) + center ambient glow + base depth +
/// luminance-reactive scrim. Colors AND drift targets tween over 600ms
/// ease-out on every active-item change — never a hard snap.
/// Single RepaintBoundary; transform/opacity-free (gradient fills only).
class LiquidMeshBackground extends StatefulWidget {
  const LiquidMeshBackground(
      {super.key, required this.palette, required this.seed});

  final ExplorePalette palette;

  /// Active item id — drives the drift layout pick.
  final String seed;

  @override
  State<LiquidMeshBackground> createState() => _LiquidMeshBackgroundState();
}

class _LiquidMeshBackgroundState extends State<LiquidMeshBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _mesh = AnimationController(
      vsync: this, duration: ExploreTokens.meshTransition);
  late ExplorePalette _from;
  late ExplorePalette _to;
  late List<Alignment> _fromAlign;
  late List<Alignment> _toAlign;

  static const _layouts = [
    [Alignment(-0.9, -0.9), Alignment(0.9, 0.9), Alignment(0.7, -0.2)],
    [Alignment(0.9, -0.8), Alignment(-0.8, 0.9), Alignment(-0.6, 0.3)],
    [Alignment(0.0, -1.0), Alignment(0.2, 1.0), Alignment(0.0, 0.0)],
  ];

  static List<Alignment> _layoutFor(String seed) =>
      _layouts[seed.hashCode.abs() % _layouts.length];

  @override
  void initState() {
    super.initState();
    _from = _to = widget.palette;
    _fromAlign = _toAlign = _layoutFor(widget.seed);
    _mesh.value = 1.0;
  }

  @override
  void didUpdateWidget(LiquidMeshBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.seed != oldWidget.seed) {
      _from = _to;
      _to = widget.palette;
      _fromAlign = _toAlign;
      _toAlign = _layoutFor(widget.seed);
      _mesh.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _mesh.dispose();
    super.dispose();
  }

  Alignment _lerpAlign(int i, double v) => Alignment.lerp(
      _fromAlign[i], _toAlign[i], Curves.easeOut.transform(v))!;

  Widget _blob(Alignment at, Color color, double radius) {
    return Align(
      alignment: at,
      child: Container(
        width: 430,
        height: 430,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: radius,
            colors: [
              color.withValues(alpha: 0.5),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _mesh,
        builder: (context, _) {
          final v = Curves.easeOut.transform(_mesh.value);
          final bg = Color.lerp(_from.background, _to.background, v)!;
          final vib = Color.lerp(_from.vibrant, _to.vibrant, v)!;
          final deep = Color.lerp(_from.deep, _to.deep, v)!;
          final acc = Color.lerp(_from.accent, _to.accent, v)!;
          // Brighter artwork → stronger scrim keeps text readable.
          final scrimTop =
              0.55 + 0.3 * vib.computeLuminance().clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: deep)),
              Positioned.fill(
                child: Opacity(
                  opacity: 0.9,
                  child: ColoredBox(color: bg.withValues(alpha: 0.55)),
                ),
              ),
              _blob(_lerpAlign(0, v), vib, 1.1),
              _blob(_lerpAlign(1, v), bg, 1.2),
              _blob(_lerpAlign(2, v), acc, 1.0),
              // Ambient aura behind the centered item.
              _blob(Alignment.center, acc, 0.9),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: scrimTop),
                        Colors.black.withValues(
                            alpha: ExploreTokens.scrimBottom),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
