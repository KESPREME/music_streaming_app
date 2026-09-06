import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/music_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/accent_controller.dart';
import '../services/auth_service.dart';
import '../models/music_source.dart';
import '../screens/login_screen.dart';
import '../widgets/accent_settings_card.dart';
import '../widgets/glass_surface.dart';
import '../widgets/liquid_switch.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = context.watch<MusicProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final accentController = context.watch<AccentController>();
    final authService = Provider.of<AuthService>(context, listen: false);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF121212), const Color(0xFF1E1E1E), const Color(0xFF000000)]
                : [const Color(0xFFF7F7F7), const Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              // Large header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Setup',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),

              // Profile card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ProfileCard(authService: authService),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),

              // Quick tiles
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(child: _QuickTile(icon: Icons.equalizer_rounded, title: 'Quality', subtitle: 'HIGH', accent: accent, onTap: () => _showBitrateDialog(context, musicProvider, true, isDark))),
                      const SizedBox(width: 12),
                      Expanded(child: _QuickTile(icon: Icons.tune_rounded, title: 'Equalizer', subtitle: 'Audio EQ', accent: accent, onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Equalizer coming soon'))))),
                      const SizedBox(width: 12),
                      Expanded(child: _QuickTile(icon: Icons.apps_rounded, title: 'App Icon', subtitle: 'Logos', accent: accent, onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('App icon picker coming soon'))))),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              // Preferences header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'PREFERENCES',
                    style: GoogleFonts.plusJakartaSans(color: accent.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // Appearance group — grounded elevated, only switches are glass
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                    ),
                    child: Column(
                      children: [
                        _GlassRow(
                          icon: Icons.palette_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Theme',
                          subtitle: '${themeProvider.getThemeName()} · ${themeProvider.getThemeDescription()}',
                          trailing: LiquidSwitch(value: themeProvider.isMaterialYou, onChanged: (_) => themeProvider.toggleTheme()),
                        ),
                        _divider(),
                        _GlassRow(
                          icon: Icons.color_lens_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Dynamic Colors',
                          subtitle: themeProvider.isDynamicColorEnabled ? 'Enabled' : 'Disabled',
                          trailing: LiquidSwitch(value: themeProvider.isDynamicColorEnabled, onChanged: (v) => themeProvider.setDynamicColorEnabled(v)),
                        ),
                        _divider(),
                        _GlassNavRow(
                          icon: Icons.auto_awesome_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Album-Art Adaptive',
                          subtitle: accentController.isAlbumAdaptive ? 'Accent follows artwork' : 'Manual accent',
                          trailing: LiquidSwitch(value: accentController.isAlbumAdaptive, onChanged: (v) => accentController.setAlbumAdaptive(v)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Accent swatches (keep existing card but wrap in glass)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GlassSurface(
                    tier: GlassTier.card,
                    borderRadius: 22,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: const AccentSettingsCard(),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Player & Playback — grounded
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                    ),
                    child: Column(
                      children: [
                        _GlassRow(
                          icon: Icons.play_circle_filled_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Auto Queue',
                          subtitle: 'Keep music going when queue ends',
                          trailing: LiquidSwitch(value: musicProvider.isAutoQueueEnabled, onChanged: (v) => musicProvider.setAutoQueueEnabled(v)),
                        ),
                        _divider(),
                        _GlassRow(
                          icon: Icons.data_saver_on_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Low Data Mode',
                          subtitle: 'Reduces quality to save data',
                          trailing: LiquidSwitch(value: musicProvider.isLowDataMode, onChanged: (_) => musicProvider.toggleLowDataMode()),
                        ),
                        _divider(),
                        _GlassRow(
                          icon: Icons.offline_bolt_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Offline Mode',
                          subtitle: 'Play only downloaded songs',
                          trailing: LiquidSwitch(value: musicProvider.isOfflineMode, onChanged: (_) => musicProvider.toggleOfflineMode()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Music source pill
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _MusicSourcePill(musicProvider: musicProvider, isDark: isDark),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Streaming quality — grounded
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                    ),
                    child: Column(
                      children: [
                        _NavTile(icon: Icons.wifi_rounded, title: 'Wi-Fi Quality', subtitle: '${musicProvider.wifiBitrate} kbps', badge: musicProvider.wifiBitrate >= 256 ? 'HIGH' : null, onTap: () => _showBitrateDialog(context, musicProvider, true, isDark)),
                        _divider(),
                        _NavTile(icon: Icons.signal_cellular_alt_rounded, title: 'Cellular Quality', subtitle: '${musicProvider.cellularBitrate} kbps', badge: musicProvider.cellularBitrate >= 128 ? 'HIGH' : null, onTap: () => _showBitrateDialog(context, musicProvider, false, isDark)),
                        _divider(),
                        _GlassRow(
                          icon: Icons.graphic_eq_rounded,
                          iconBg: Colors.white.withValues(alpha: 0.08),
                          iconColor: Colors.white70,
                          title: 'Clear Cache',
                          subtitle: 'Free up storage space',
                          trailing: IconButton(
                            icon: const Icon(Icons.cleaning_services_rounded, size: 20, color: Colors.white70),
                            onPressed: () async {
                              await musicProvider.clearAllCaches();
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cache cleared', style: GoogleFonts.plusJakartaSans(color: Colors.white)), backgroundColor: Colors.grey[900]));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              // Motion Artwork & Lyrics header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'MOTION ARTWORK & LYRICS',
                    style: GoogleFonts.plusJakartaSans(
                      color: accent.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // Motion Artwork & Lyrics group
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                    child: Column(
                      children: [
                        _GlassRow(
                          icon: Icons.movie_filter_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Animated Cover Art',
                          subtitle: 'Play looping canvas video on normal screen',
                          trailing: LiquidSwitch(
                            value: musicProvider.animatedCanvasEnabled,
                            onChanged: (v) =>
                                musicProvider.setAnimatedCanvasEnabled(v),
                          ),
                        ),
                        _divider(),
                        _GlassRow(
                          icon: Icons.cell_tower_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Stream Over Mobile Data',
                          subtitle:
                              'Allow video covers over cellular connections',
                          trailing: LiquidSwitch(
                            value: musicProvider.canvasOverCellular,
                            onChanged: (v) =>
                                musicProvider.setCanvasOverCellular(v),
                          ),
                        ),
                        _divider(),
                        _GlassRow(
                          icon: Icons.fullscreen_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Full-Bleed Artwork',
                          subtitle: 'Bleed artwork to screen edges like BitChord',
                          trailing: LiquidSwitch(
                            value: musicProvider.fullBleedArtwork,
                            onChanged: (v) =>
                                musicProvider.setFullBleedArtwork(v),
                          ),
                        ),
                        _divider(),
                        _GlassRow(
                          icon: Icons.lyrics_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Synced Lyrics',
                          subtitle: 'Real-time time-synced vocal tracking',
                          trailing: LiquidSwitch(
                            value: musicProvider.syncedLyricsEnabled,
                            onChanged: (v) =>
                                musicProvider.setSyncedLyricsEnabled(v),
                          ),
                        ),
                        _divider(),
                        _GlassRow(
                          icon: Icons.text_fields_rounded,
                          iconBg: accent.withValues(alpha: 0.18),
                          iconColor: accent,
                          title: 'Prioritize Word Sync',
                          subtitle:
                              'Prefer Apple Music syllable sync over line sync',
                          trailing: LiquidSwitch(
                            value: musicProvider.prioritizeSyllableSync,
                            onChanged: (v) =>
                                musicProvider.setPrioritizeSyllableSync(v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text('COMMUNITY & SUPPORT', style: GoogleFonts.plusJakartaSans(color: accent.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                    ),
                    child: Column(
                      children: [
                        _NavTile(icon: Icons.person_outline_rounded, title: 'Account', subtitle: Provider.of<AuthService>(context, listen: false).isLoggedIn ? 'Connected' : 'Log in to YouTube', onTap: () { final a = Provider.of<AuthService>(context, listen: false); if (!a.isLoggedIn) Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())); }),
                        _divider(),
                        _NavTile(icon: Icons.info_outline_rounded, title: 'Version', subtitle: '1.0.4 (Mine Music)'),
                        _divider(),
                        _NavTile(icon: Icons.code_rounded, title: 'Source', subtitle: 'Powered by InnerTube'),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              SliverToBoxAdapter(child: _MadeByFooter(isDark: isDark)),
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => Divider(height: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.06), indent: 62);

  void _showBitrateDialog(BuildContext context, MusicProvider musicProvider, bool isWifi, bool isDark) {
    final accent = Theme.of(context).colorScheme.primary;
    final List<int> options = isWifi ? [64, 128, 256, 320] : [32, 64, 128];
    showDialog(
      context: context,
      builder: (_) => Consumer<MusicProvider>(builder: (context, provider, __) {
        final isAuto = provider.isAutoBitrate;
        final current = isWifi ? provider.wifiBitrate : provider.cellularBitrate;
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('${isWifi ? "Wi-Fi" : "Cellular"} Quality', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('Auto', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: isAuto ? Text('Adjusts automatically', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12)) : null,
                leading: Icon(isAuto ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isAuto ? accent : Colors.white38),
                onTap: () { provider.setAutoBitrate(true); Navigator.pop(context); },
              ),
              const Divider(color: Colors.white12),
              ...options.map((b) {
                final sel = !isAuto && b == current;
                return ListTile(
                  title: Text('$b kbps', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
                  leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: sel ? accent : Colors.white38),
                  onTap: () { if (isWifi) provider.setWifiBitrate(b); else provider.setCellularBitrate(b); Navigator.pop(context); },
                );
              }),
            ],
          ),
        );
      }),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.authService});
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final isLoggedIn = authService.isLoggedIn;
    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isLoggedIn ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.22),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Center(child: Text(isLoggedIn ? 'Y' : 'U', style: GoogleFonts.plusJakartaSans(color: accent, fontWeight: FontWeight.w900, fontSize: 22))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(isLoggedIn ? 'YouTube Account' : 'User Profile', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8), border: Border.all(color: accent.withValues(alpha: 0.35))),
                        child: Text('PROFILE', style: GoogleFonts.plusJakartaSans(color: accent, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(isLoggedIn ? 'Connected' : 'Mine Music Account & Media', style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 12.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white30),
          ],
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.title, required this.subtitle, required this.accent, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: GlassSurface(
        tier: GlassTier.card,
        borderRadius: 18,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10), border: Border.all(color: accent.withValues(alpha: 0.22))),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white24),
              ],
            ),
            const SizedBox(height: 18),
            Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Text(subtitle, style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _GlassRow extends StatelessWidget {
  const _GlassRow({required this.icon, required this.iconBg, required this.iconColor, required this.title, required this.subtitle, required this.trailing});
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 18, color: iconColor)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)), const SizedBox(height: 2), Text(subtitle, style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)])),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _GlassNavRow extends StatelessWidget {
  const _GlassNavRow({required this.icon, required this.iconBg, required this.iconColor, required this.title, required this.subtitle, required this.trailing});
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  @override
  Widget build(BuildContext context) => _GlassRow(icon: icon, iconBg: iconBg, iconColor: iconColor, title: title, subtitle: subtitle, trailing: trailing);
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.title, this.subtitle, this.badge, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap == null ? null : () { HapticFeedback.lightImpact(); onTap!(); },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 18, color: Colors.white70)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)), if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 12))]])),
            if (badge != null) ...[
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: badge == 'LIVE' ? Colors.blue.withValues(alpha: 0.18) : accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8), border: Border.all(color: badge == 'LIVE' ? Colors.blue.withValues(alpha: 0.4) : accent.withValues(alpha: 0.32))), child: Text(badge!, style: GoogleFonts.plusJakartaSans(color: badge == 'LIVE' ? Colors.blue[300] : accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6))),
              const SizedBox(width: 10),
            ],
            Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.28), size: 20),
          ],
        ),
      ),
    );
  }
}

class _MusicSourcePill extends StatelessWidget {
  const _MusicSourcePill({required this.musicProvider, required this.isDark});
  final MusicProvider musicProvider;
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    final current = musicProvider.currentMusicSource;
    final accent = Theme.of(context).colorScheme.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        height: 56,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
        child: Stack(children: [
          AnimatedAlign(duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic, alignment: current == MusicSource.youtube ? Alignment.centerLeft : Alignment.centerRight, child: FractionallySizedBox(widthFactor: 0.5, child: Container(margin: const EdgeInsets.all(4), decoration: BoxDecoration(gradient: RadialGradient(center: Alignment.center, radius: 2.5, colors: [accent.withValues(alpha: 0.28), accent.withValues(alpha: 0.10)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: accent.withValues(alpha: 0.38)), boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.15), blurRadius: 12)])))),
          Row(children: [
            Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => musicProvider.setMusicSource(MusicSource.youtube), child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cloud_queue_rounded, size: 18, color: current == MusicSource.youtube ? accent : Colors.white54), const SizedBox(width: 8), Text('Stream', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15, color: current == MusicSource.youtube ? accent : Colors.white54))])))),
            Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => musicProvider.setMusicSource(MusicSource.local), child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.folder_open_rounded, size: 18, color: current == MusicSource.local ? accent : Colors.white54), const SizedBox(width: 8), Text('Local', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15, color: current == MusicSource.local ? accent : Colors.white54))])))),
          ]),
        ]),
      ),
      Padding(padding: const EdgeInsets.only(left: 16, top: 10, right: 16), child: Text(current == MusicSource.youtube ? 'Streaming from YouTube Music (InnerTube).' : 'Playing files from your device storage.', style: GoogleFonts.plusJakartaSans(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic))),
    ]);
  }
}

class _MadeByFooter extends StatelessWidget {
  const _MadeByFooter({required this.isDark});
  final bool isDark;
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Image.asset('assets/images/app_logo.png', height: 56, width: 56, errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded, color: Colors.white24, size: 40)),
      const SizedBox(height: 14),
      InkWell(
        onTap: () async { final uri = Uri.parse('https://github.com/KESPREME'); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); },
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: RichText(textAlign: TextAlign.center, text: TextSpan(style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 13), children: [const TextSpan(text: 'Made with ❤️ using Flutter by '), TextSpan(text: 'KESPREME', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFB388FF), fontWeight: FontWeight.w800, decoration: TextDecoration.underline))]))),
      ),
    ]);
  }
}
