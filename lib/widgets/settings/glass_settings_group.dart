import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../liquid_switch.dart';

/// A grouped card of settings rows - the same look as the groups on the main
/// settings screen (a 5% white fill, a 22dp radius, a hairline border), as
/// public widgets so a second screen can use them without copying.
class GlassSettingsGroup extends StatelessWidget {
  const GlassSettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const GlassSettingsDivider());
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class GlassSettingsDivider extends StatelessWidget {
  const GlassSettingsDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: Colors.white.withValues(alpha: 0.06),
      );
}

/// One row: icon chip, title + subtitle, a trailing control.
class GlassSettingsRow extends StatelessWidget {
  const GlassSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.badge,
    this.onTap,
  });

  /// A switch row, the common case.
  GlassSettingsRow.toggle({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? badge,
  }) : this(
          key: key,
          icon: icon,
          title: title,
          subtitle: subtitle,
          badge: badge,
          trailing: LiquidSwitch(value: value, onChanged: onChanged),
          onTap: () => onChanged(!value),
        );

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.32)),
                        ),
                        child: Text(
                          badge!,
                          style: GoogleFonts.plusJakartaSans(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                      color: Colors.white54, fontSize: 12),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );

    return Semantics(
      container: true,
      label: title,
      child: onTap == null
          ? content
          : InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                onTap!();
              },
              child: content,
            ),
    );
  }
}
