import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/accent_controller.dart';
import '../services/lyrics/lyrics_service.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';
import 'liquid_switch.dart';

/// Modal sheet for customizing lyric provider priority order and enabled sources.
class LyricProvidersSheet extends StatefulWidget {
  final bool isMaterialYou;

  const LyricProvidersSheet({
    super.key,
    this.isMaterialYou = false,
  });

  static Future<void> show(BuildContext context, {bool isMaterialYou = false}) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LyricProvidersSheet(isMaterialYou: isMaterialYou),
    );
  }

  @override
  State<LyricProvidersSheet> createState() => _LyricProvidersSheetState();
}

class _LyricProvidersSheetState extends State<LyricProvidersSheet> {
  final LyricsService _lyricsService = LyricsService();
  late List<LyricsProvider> _providers;
  late Set<LyricsProvider> _enabled;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  void _loadProviders() {
    _providers = List.from(_lyricsService.providerOrder);
    _enabled = Set.from(_lyricsService.enabledProviders);
  }

  void _onReorder(int oldIndex, int newIndex) {
    HapticFeedback.selectionClick();
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _providers.removeAt(oldIndex);
      _providers.insert(newIndex, item);
    });
    _lyricsService.updateProviderOrder(_providers);
  }

  void _onToggle(LyricsProvider provider, bool value) {
    if (!value && _enabled.length <= 1 && _enabled.contains(provider)) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least one lyric provider must remain active.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      if (value) {
        _enabled.add(provider);
      } else {
        _enabled.remove(provider);
      }
    });
    _lyricsService.setProviderEnabled(provider, value);
  }

  void _onReset() {
    HapticFeedback.mediumImpact();
    _lyricsService.resetProvidersToDefault().then((_) {
      if (mounted) {
        setState(() {
          _loadProviders();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accentController = Provider.of<AccentController>(context, listen: false);
    final accentColor = accentController.accent;

    if (widget.isMaterialYou) {
      return _buildMaterialYouLayout(context, accentColor);
    }
    return _buildLiquidGlassLayout(context, accentColor);
  }

  Widget _buildLiquidGlassLayout(BuildContext context, Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF14151C).withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 32,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pull handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title and Reset action
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lyric Providers',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Highest enabled source is queried first',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: _onReset,
                    icon: Icon(Icons.restart_alt_rounded, size: 16, color: accentColor),
                    label: Text(
                      'Reset',
                      style: GoogleFonts.plusJakartaSans(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      backgroundColor: accentColor.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Reorderable list
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.07),
                        width: 0.6,
                      ),
                    ),
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _providers.length,
                      onReorder: _onReorder,
                      proxyDecorator: (child, index, animation) => Material(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        elevation: 6,
                        child: child,
                      ),
                      itemBuilder: (context, index) {
                        final provider = _providers[index];
                        final isEnabled = _enabled.contains(provider);

                        return Container(
                          key: ValueKey(provider),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            border: index < _providers.length - 1
                                ? Border(
                                    bottom: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      width: 0.6,
                                    ),
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              // Drag Handle
                              ReorderableDragStartListener(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Icon(
                                    Icons.drag_indicator_rounded,
                                    color: Colors.white.withValues(alpha: 0.4),
                                    size: 22,
                                  ),
                                ),
                              ),

                              // Provider Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          provider.displayName,
                                          style: GoogleFonts.plusJakartaSans(
                                            color: isEnabled
                                                ? Colors.white
                                                : Colors.white.withValues(alpha: 0.4),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (index == 0 && isEnabled) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: accentColor.withValues(alpha: 0.18),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'PRIMARY',
                                              style: GoogleFonts.plusJakartaSans(
                                                color: accentColor,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      provider.description,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: isEnabled
                                            ? Colors.white.withValues(alpha: 0.5)
                                            : Colors.white.withValues(alpha: 0.25),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Enable/Disable Toggle
                              LiquidSwitch(
                                value: isEnabled,
                                onChanged: (val) => _onToggle(provider, val),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialYouLayout(BuildContext context, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: MaterialYouTokens.surfaceContainerDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lyric Providers',
                        style: MaterialYouTypography.headlineMedium(colorScheme.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Drag handles to prioritize order',
                        style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _onReset,
                    child: Text('Reset', style: TextStyle(color: colorScheme.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _providers.length,
                    onReorder: _onReorder,
                    itemBuilder: (context, index) {
                      final provider = _providers[index];
                      final isEnabled = _enabled.contains(provider);

                      return ListTile(
                        key: ValueKey(provider),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_indicator_rounded,
                              color: colorScheme.onSurfaceVariant),
                        ),
                        title: Text(
                          provider.displayName,
                          style: TextStyle(
                            color: isEnabled ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: 0.38),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          provider.description,
                          style: TextStyle(
                            color: isEnabled ? colorScheme.onSurfaceVariant : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
                            fontSize: 12,
                          ),
                        ),
                        trailing: Switch(
                          value: isEnabled,
                          activeThumbColor: MaterialYouTokens.primaryVibrant,
                          onChanged: (val) => _onToggle(provider, val),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
