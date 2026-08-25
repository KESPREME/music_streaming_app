import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/accent_controller.dart';

/// Accent color control block: preset swatches, custom hex, and the
/// album-art adaptive toggle.
class AccentSettingsCard extends StatelessWidget {
  const AccentSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AccentController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACCENT COLOR',
          style: GoogleFonts.splineSans(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            children: [
              // Preset swatches
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final preset in AccentPreset.values.where(
                      (p) => p != AccentPreset.custom))
                    _AccentDot(
                      color: AccentColors.of(preset),
                      selected: controller.preset == preset &&
                          !controller.isAlbumAdaptive,
                      onTap: () => controller.setPreset(preset),
                    ),
                  _AccentDot(
                    color: controller.preset == AccentPreset.custom
                        ? controller.accent
                        : Colors.grey.shade700,
                    selected: controller.preset == AccentPreset.custom &&
                        !controller.isAlbumAdaptive,
                    isCustom: true,
                    onTap: () => _pickCustomColor(context, controller),
                  ),
                ],
              ),
              const Divider(height: 22, color: Colors.white12),
              // Album-adaptive toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Album-Art Adaptive',
                  style: GoogleFonts.splineSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  'Accent follows the playing song\'s artwork',
                  style: GoogleFonts.outfit(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                value: controller.isAlbumAdaptive,
                onChanged: (v) => controller.setAlbumAdaptive(v),
                activeThumbColor: controller.accent,
                activeTrackColor: controller.accent.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickCustomColor(
      BuildContext context, AccentController controller) async {
    final textController = TextEditingController(
      text: controller.preset == AccentPreset.custom
          ? controller.accent.toARGB32().toRadixString(16).toUpperCase()
          : '',
    );
    final color = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Custom Accent', style: GoogleFonts.outfit()),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'FFCBA4',
            labelText: 'Hex (RRGGBB or AARRGGBB)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed =
                  AccentController.tryParseHex(textController.text);
              if (parsed != null) Navigator.pop(context, parsed);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (color != null) {
      await controller.setCustomColor(color);
    }
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.isCustom = false,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        width: selected ? 38 : 32,
        height: selected ? 38 : 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)]
              : null,
        ),
        child: isCustom
            ? const Icon(Icons.colorize_rounded,
                color: Colors.white, size: 16)
            : null,
      ),
    );
  }
}
