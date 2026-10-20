// lib/widgets/eq/eq_preset_strip.dart
//
// The preset carousel: every card shows the SHAPE of its curve, drawn from the
// same maths as the main graph on this phone's own bands, so choosing a preset
// is choosing a picture, not reading a name.
//
// Order: Custom (only while the listener's own curve is in force), the presets
// they saved, then the built-ins. The selected card is ringed in the accent, and
// scrolls to the middle when it changes from somewhere else (reset, per-output
// switch). Cards rise in one after another the first time the strip appears.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/eq/eq_curves.dart';
import '../../services/eq/eq_models.dart';
import '../../services/eq/eq_presets.dart';
import '../../theme/app_font.dart';
import '../jelly_press.dart';

class _Entry {
  const _Entry(this.id, this.name, this.gains, {this.user = false, this.custom = false});
  final String id;
  final String name;
  final List<double> gains;
  final bool user;
  final bool custom;
}

class EqPresetStrip extends StatefulWidget {
  const EqPresetStrip({
    super.key,
    required this.bands,
    required this.minDb,
    required this.maxDb,
    required this.selectedId,
    required this.currentGains,
    required this.userPresets,
    required this.onSelect,
    required this.onUserLongPress,
    this.enabled = true,
    this.accent,
  });

  final List<EqBand> bands;
  final double minDb;
  final double maxDb;
  final String selectedId;

  /// The listener's curve in force; shown on the Custom card.
  final List<double> currentGains;
  final List<UserEqPreset> userPresets;
  final ValueChanged<String> onSelect;
  final ValueChanged<UserEqPreset> onUserLongPress;
  final bool enabled;
  final Color? accent;

  @override
  State<EqPresetStrip> createState() => _EqPresetStripState();
}

class _EqPresetStripState extends State<EqPresetStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  final Map<String, GlobalKey> _keys = {};

  @override
  void didUpdateWidget(EqPresetStrip old) {
    super.didUpdateWidget(old);
    if (old.selectedId != widget.selectedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[widget.selectedId]?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  List<_Entry> _entries() {
    final centers = [for (final b in widget.bands) b.centerHz];
    return [
      if (widget.selectedId == 'custom')
        _Entry('custom', 'Custom', widget.currentGains, custom: true),
      for (final u in widget.userPresets)
        _Entry(u.presetId, u.name, resamplePoints(u.points, centers), user: true),
      for (final p in kEqPresets) _Entry(p.id, p.name, p.gainsFor(centers)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? Theme.of(context).colorScheme.primary;
    final entries = _entries();
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final e = entries[i];
          final key = _keys.putIfAbsent(e.id, GlobalKey.new);
          final start = (i * 0.045).clamp(0.0, 0.6);
          final anim = CurvedAnimation(
            parent: _intro,
            curve: Interval(start, (start + 0.4).clamp(0.0, 1.0),
                curve: Curves.easeOutCubic),
          );
          return AnimatedBuilder(
            animation: anim,
            builder: (context, child) => Opacity(
              opacity: anim.value,
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - anim.value)),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: key,
              child: _PresetCard(
                entry: e,
                bands: widget.bands,
                minDb: widget.minDb,
                maxDb: widget.maxDb,
                selected: e.id == widget.selectedId,
                accent: accent,
                enabled: widget.enabled,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onSelect(e.id);
                },
                onLongPress: e.user
                    ? () {
                        HapticFeedback.mediumImpact();
                        widget.onUserLongPress(
                            widget.userPresets.firstWhere((u) => u.presetId == e.id));
                      }
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.entry,
    required this.bands,
    required this.minDb,
    required this.maxDb,
    required this.selected,
    required this.accent,
    required this.enabled,
    required this.onTap,
    this.onLongPress,
  });

  final _Entry entry;
  final List<EqBand> bands;
  final double minDb;
  final double maxDb;
  final bool selected;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final samples = [
      for (final p in responseCurve(bands, entry.gains, count: 40))
        (p.$2 / 12).clamp(-1.0, 1.0).toDouble()
    ];
    final tone = enabled ? accent : Colors.white54;
    return Semantics(
      button: true,
      selected: selected,
      label: '${entry.name} preset',
      child: JellyPress(
        onTap: onTap,
        onLongPress: onLongPress,
        profile: JellyProfile.pill,
        haptic: JellyHaptic.none,
        borderRadius: 22,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: 112,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withValues(alpha: selected ? 0.1 : 0.05),
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.08),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: tone.withValues(alpha: 0.28), blurRadius: 18)]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _MiniCurvePainter(
                    samples: samples,
                    color: tone,
                    selected: selected,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (entry.user) ...[
                    Icon(Icons.bookmark_rounded, size: 12, color: tone),
                    const SizedBox(width: 3),
                  ],
                  Expanded(
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.style(
                        color: Colors.white.withValues(alpha: selected ? 1 : 0.78),
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniCurvePainter extends CustomPainter {
  _MiniCurvePainter({
    required this.samples,
    required this.color,
    required this.selected,
  });

  final List<double> samples;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.12),
    );
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * i / (samples.length - 1);
      final y = mid - samples[i] * (size.height * 0.46);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, mid)
      ..lineTo(0, mid)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = color.withValues(alpha: selected ? 0.26 : 0.14),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.2 : 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: selected ? 1 : 0.8),
    );
  }

  @override
  bool shouldRepaint(_MiniCurvePainter old) =>
      old.selected != selected || old.color != color || old.samples != samples;
}
