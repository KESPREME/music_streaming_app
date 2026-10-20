import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/test_environment.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_font.dart';

/// Settings > Appearance > Font: the typeface, and the weight of all text.
///
/// Every family is previewed in itself. Picking one downloads it first (the
/// device keeps it), so the app never redraws in a stand-in face; while that
/// happens the row shows a spinner, and if it fails nothing changes and the
/// sheet says why.
class FontPickerSheet extends StatefulWidget {
  const FontPickerSheet({super.key, this.preload});

  /// Test seam for [ThemeProvider.setFontFamily].
  final Future<bool> Function(String family)? preload;

  static Future<void> show(BuildContext context) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      isScrollControlled: true,
      sheetAnimationStyle: const AnimationStyle(
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
        duration: Duration(milliseconds: 320),
      ),
      builder: (_) => const FontPickerSheet(),
    );
  }

  static String weightLabel(int delta) => switch (delta) {
        < 0 => 'Lighter',
        > 0 => 'Bolder',
        _ => 'Default',
      };

  @override
  State<FontPickerSheet> createState() => _FontPickerSheetState();
}

class _FontPickerSheetState extends State<FontPickerSheet> {
  String? _loading;
  String? _failed;

  TextStyle _preview(String family, {double size = 17, FontWeight weight = FontWeight.w600}) {
    final w = AppFont.shift(weight);
    // Plus Jakarta Sans is bundled; the rest come from the Google Fonts cache.
    // No font downloads from widget tests.
    return family == AppFont.defaultFamily || TestEnvironment.isTesting
        ? GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: Colors.white)
        : GoogleFonts.getFont(family, fontSize: size, fontWeight: w, color: Colors.white);
  }

  Future<void> _pick(ThemeProvider theme, String family) async {
    if (_loading != null || family == theme.fontFamily) return;
    HapticFeedback.selectionClick();
    setState(() {
      _loading = family;
      _failed = null;
    });
    final ok = await theme.setFontFamily(family, preload: widget.preload);
    if (!mounted) return;
    setState(() {
      _loading = null;
      _failed = ok ? null : family;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final media = MediaQuery.of(context);
    final accent = Theme.of(context).colorScheme.primary;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text(
                  'Font',
                  style: AppFont.style(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Text(
                  'TEXT WEIGHT',
                  style: AppFont.style(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _WeightSegments(
                  value: theme.fontWeightDelta,
                  accent: accent,
                  onChanged: (d) {
                    HapticFeedback.selectionClick();
                    theme.setFontWeightDelta(d);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Text(
                  'TYPEFACE',
                  style: AppFont.style(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (_failed != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    "Couldn't download $_failed. Check your connection and try again.",
                    style: AppFont.style(color: const Color(0xFFFF8A80), fontSize: 13),
                  ),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: AppFont.families.length,
                  itemBuilder: (context, i) {
                    final f = AppFont.families[i];
                    final selected = f.name == theme.fontFamily;
                    final loading = f.name == _loading;
                    return Semantics(
                      selected: selected,
                      button: true,
                      label: '${f.name}. ${f.note}',
                      excludeSemantics: true,
                      child: InkWell(
                        key: ValueKey('font_${f.name}'),
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _pick(theme, f.name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(f.name, style: _preview(f.name)),
                                    const SizedBox(height: 2),
                                    Text(
                                      f.note,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _preview(f.name, size: 13, weight: FontWeight.w400)
                                          .copyWith(color: Colors.white.withValues(alpha: 0.6)),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: loading
                                    ? Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: CircularProgressIndicator(strokeWidth: 2.2, color: accent),
                                      )
                                    : selected
                                        ? Icon(Icons.check_rounded, color: accent)
                                        : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeightSegments extends StatelessWidget {
  const _WeightSegments({required this.value, required this.accent, required this.onChanged});

  final int value;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final d in const [-1, 0, 1])
            Expanded(
              child: Semantics(
                selected: d == value,
                button: true,
                label: 'Text weight ${FontPickerSheet.weightLabel(d)}',
                excludeSemantics: true,
                child: GestureDetector(
                  key: ValueKey('weight_$d'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: d == value ? accent.withValues(alpha: 0.22) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      FontPickerSheet.weightLabel(d),
                      style: AppFont.style(
                        color: Colors.white,
                        fontSize: 14,
                        // Each label previews its own step.
                        fontWeight: [FontWeight.w400, FontWeight.w600, FontWeight.w800][d + 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
