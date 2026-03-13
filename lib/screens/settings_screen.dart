import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/music_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../models/music_source.dart';
import '../screens/login_screen.dart';
import '../services/update_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final isDark = theme.brightness == Brightness.dark;

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
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                surfaceTintColor: Colors.transparent,
                backgroundColor: Colors.transparent,
                floating: true,
                pinned: true,
                elevation: 0,
                expandedHeight: 100,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  color: isDark ? Colors.white : Colors.black,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                flexibleSpace: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      child: FlexibleSpaceBar(
                        titlePadding: const EdgeInsets.only(left: 50, bottom: 16),
                        title: Text(
                          'Settings',
                          style: GoogleFonts.splineSans(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 20,
                          ),
                        ),
                        background: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildSectionTitle('Appearance', isDark),
                    const SizedBox(height: 12),
                    _buildGlassCard(isDark, children: [
                      _buildSwitchTile(
                        icon: Icons.palette_rounded, title: 'Material You Theme', subtitle: 'Toggle Material 3 UI Style',
                        value: themeProvider.isMaterialYou, isDark: isDark, onChanged: (val) => themeProvider.toggleTheme(),
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.color_lens_rounded, title: 'Dynamic Colors', subtitle: 'Extract colors from album art',
                        value: themeProvider.isDynamicColorEnabled, isDark: isDark, onChanged: (val) => themeProvider.setDynamicColorEnabled(val),
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.animation_rounded, title: 'Enable Animations', subtitle: 'Toggle UI animations',
                        value: settingsProvider.enableAnimations, isDark: isDark, onChanged: (val) => settingsProvider.setEnableAnimations(val),
                      ),
                      _buildDivider(isDark),
                      _buildSliderTile(
                        icon: Icons.blur_on_rounded, title: 'Blur Intensity', value: settingsProvider.blurIntensity,
                        min: 0, max: 20, isDark: isDark, onChanged: (val) => settingsProvider.setBlurIntensity(val),
                      ),
                    ]),

                    const SizedBox(height: 32),
                    _buildSectionTitle('Playback', isDark),
                    const SizedBox(height: 12),
                    _buildGlassCard(isDark, children: [
                      _buildSwitchTile(
                        icon: Icons.skip_next_rounded, title: 'Gapless Playback', subtitle: 'Seamless transition between tracks',
                        value: settingsProvider.gaplessPlayback, isDark: isDark, onChanged: (val) => settingsProvider.setGaplessPlayback(val),
                      ),
                      _buildDivider(isDark),
                      _buildSliderTile(
                        icon: Icons.compare_arrows_rounded, title: 'Crossfade Duration', value: settingsProvider.crossfadeDuration,
                        min: 0, max: 12, isDark: isDark, onChanged: (val) => settingsProvider.setCrossfadeDuration(val),
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.volume_up_rounded, title: 'Normalize Volume', subtitle: 'Keep volume consistent',
                        value: settingsProvider.normalizeVolume, isDark: isDark, onChanged: (val) => settingsProvider.setNormalizeVolume(val),
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.playlist_play_rounded, title: 'Auto-play Next', subtitle: 'Keep playing when queue ends',
                        value: settingsProvider.autoPlayNext, isDark: isDark, onChanged: (val) => settingsProvider.setAutoPlayNext(val),
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.headphones_rounded, title: 'Pause on Disconnect', subtitle: 'Pause when headphones unplugged',
                        value: settingsProvider.pauseOnHeadphoneDisconnect, isDark: isDark, onChanged: (val) => settingsProvider.setPauseOnHeadphoneDisconnect(val),
                      ),
                    ]),
                    
                    const SizedBox(height: 32),
                    _buildSectionTitle('Audio & Quality', isDark),
                    const SizedBox(height: 12),
                    _buildGlassCard(isDark, children: [
                      _buildSettingTile(
                        icon: Icons.high_quality_rounded, title: 'Audio Quality', subtitle: settingsProvider.audioQuality.name.toUpperCase(), isDark: isDark,
                        onTap: () {
                           final current = settingsProvider.audioQuality;
                           final next = AudioQuality.values[(current.index + 1) % AudioQuality.values.length];
                           settingsProvider.setAudioQuality(next);
                        }
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.download_done_rounded, title: 'Prefer Cache', subtitle: 'Play cached version if available',
                        value: settingsProvider.preferCache, isDark: isDark, onChanged: (val) => settingsProvider.setPreferCache(val),
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.electric_bolt_rounded, title: 'Preload Audio', subtitle: 'Preload next track for zero delay',
                        value: settingsProvider.enableAudioPreloading, isDark: isDark, onChanged: (val) => settingsProvider.setEnableAudioPreloading(val),
                      ),
                    ]),

                    const SizedBox(height: 32),
                    _buildSectionTitle('Downloads / Offline', isDark),
                    const SizedBox(height: 12),
                    _buildGlassCard(isDark, children: [
                      _buildSwitchTile(
                        icon: Icons.wifi_rounded, title: 'Download over Wi-Fi Only', subtitle: 'Save cellular data',
                        value: settingsProvider.downloadOverWifiOnly, isDark: isDark, onChanged: (val) => settingsProvider.setDownloadOverWifiOnly(val),
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.delete_sweep_rounded, title: 'Auto-delete Failed', subtitle: 'Remove failed downloads automatically',
                        value: settingsProvider.autoDeleteFailedDownloads, isDark: isDark, onChanged: (val) => settingsProvider.setAutoDeleteFailedDownloads(val),
                      ),
                    ]),

                    const SizedBox(height: 32),
                    _buildSectionTitle('Library', isDark),
                    const SizedBox(height: 12),
                    _buildGlassCard(isDark, children: [
                      _buildSwitchTile(
                        icon: Icons.folder_shared_rounded, title: 'Auto-scan Local Music', subtitle: 'Scan device storage automatically',
                        value: settingsProvider.autoScanLocalMusic, isDark: isDark, onChanged: (val) => settingsProvider.setAutoScanLocalMusic(val),
                      ),
                      _buildDivider(isDark),
                      _buildSwitchTile(
                        icon: Icons.visibility_off_rounded, title: 'Hide Unavailable', subtitle: 'Hide songs that cannot be played',
                        value: settingsProvider.hideUnavailableTracks, isDark: isDark, onChanged: (val) => settingsProvider.setHideUnavailableTracks(val),
                      ),
                    ]),

                     const SizedBox(height: 32),
                    _buildSectionTitle('Notifications', isDark),
                    const SizedBox(height: 12),
                    _buildGlassCard(isDark, children: [
                      _buildSwitchTile(
                        icon: Icons.screen_lock_portrait_rounded, title: 'Lock Screen Controls', subtitle: 'Show player on lock screen',
                        value: settingsProvider.lockScreenControls, isDark: isDark, onChanged: (val) => settingsProvider.setLockScreenControls(val),
                      ),
                    ]),

                    const SizedBox(height: 32),
                    _buildSectionTitle('Import & Services', isDark),
                    const SizedBox(height: 12),
                    _buildGlassCard(isDark, children: [
                      _buildSwitchTile(
                        icon: Icons.youtube_searched_for_rounded, title: 'Auto Search YouTube', subtitle: 'For Spotify matching',
                        value: settingsProvider.autoSearchYouTubeForImports, isDark: isDark, onChanged: (val) => settingsProvider.setAutoSearchYouTubeForImports(val),
                      ),
                    ]),

                    const SizedBox(height: 32),
                    _buildSectionTitle('Account', isDark),
                    const SizedBox(height: 12),
                    _buildAccountCard(context, authService, isDark),

                    const SizedBox(height: 32),
                     _buildSectionTitle('About', isDark),
                    const SizedBox(height: 12),
                    _buildGlassCard(isDark, children: [
                      _buildSettingTile(
                        icon: Icons.system_update_rounded, title: 'Check for Updates', subtitle: 'Check GitHub for new releases', isDark: isDark,
                        onTap: () => _checkForUpdates(context, isDark),
                      ),
                      _buildDivider(isDark),
                      _buildSettingTile(
                        icon: Icons.info_outline_rounded, title: 'Version', subtitle: '1.0.5 (Mine Music)', isDark: isDark,
                        onTap: () {
                           settingsProvider.toggleDeveloperMode();
                        }
                      ),
                      _buildDivider(isDark),
                      _buildSettingTile(
                        icon: Icons.code_rounded, title: 'Source', subtitle: 'Powered by InnerTube', isDark: isDark,
                      ),
                    ]),

                    if (settingsProvider.developerModeEnabled) ...[
                      const SizedBox(height: 32),
                      _buildSectionTitle('Developer Options', isDark),
                      const SizedBox(height: 12),
                      _buildGlassCard(isDark, children: [
                        _buildSwitchTile(
                          icon: Icons.bug_report_rounded, title: 'Enable Debug Logs', subtitle: 'Print extra info to console',
                          value: settingsProvider.enableDebugLogs, isDark: isDark, onChanged: (val) => settingsProvider.setEnableDebugLogs(val),
                        ),
                        _buildDivider(isDark),
                        _buildSettingTile(
                          icon: Icons.cleaning_services_rounded, title: 'Clear Cache', subtitle: 'Force wipe local cache', isDark: isDark,
                          onTap: () async {
                              await musicProvider.clearAllCaches();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache Cleared')));
                          }
                        ),
                      ]),
                    ],

                    const SizedBox(height: 32),
                    _buildMadeByFooter(isDark),
                    const SizedBox(height: 50),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMadeByFooter(bool isDark) {
    return Column(
      children: [
        Image.asset('assets/images/app_logo.png', height: 60, width: 60),
        const SizedBox(height: 16),
        InkWell(
          onTap: () async {
            final uri = Uri.parse('https://github.com/KESPREME');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.splineSans(color: isDark ? Colors.white54 : Colors.black54, fontSize: 14),
                children: [
                  const TextSpan(text: 'Made with ❤️ using Flutter by '),
                  TextSpan(
                    text: 'KESPREME',
                    style: GoogleFonts.splineSans(color: const Color(0xFFEA80FC), fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.splineSans(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildGlassCard(bool isDark, {required List<Widget> children}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
         child: Container(
           decoration: BoxDecoration(
             color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
             borderRadius: BorderRadius.circular(24),
             border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
           ),
           child: Column(children: children),
         ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(height: 1, thickness: 1, color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08), indent: 56);
  }

  Widget _buildSettingTile({required IconData icon, required String title, String? subtitle, VoidCallback? onTap, required bool isDark}) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05), shape: BoxShape.circle),
        child: Icon(icon, color: isDark ? Colors.white : Colors.black, size: 20),
      ),
      title: Text(title, style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: subtitle != null ? Text(subtitle, style: GoogleFonts.splineSans(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13)) : null,
      trailing: Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white30 : Colors.black.withOpacity(0.3)),
    );
  }

  Widget _buildSwitchTile({required IconData icon, required String title, required String subtitle, required bool value, required Function(bool) onChanged, required bool isDark}) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05), shape: BoxShape.circle),
        child: Icon(icon, color: isDark ? Colors.white : Colors.black, size: 20),
      ),
      title: Text(title, style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: Text(subtitle, style: GoogleFonts.splineSans(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13)),
      activeColor: const Color(0xFFEA80FC),
      inactiveThumbColor: isDark ? Colors.grey : Colors.white,
      inactiveTrackColor: isDark ? Colors.grey[800] : Colors.grey[300],
    );
  }

  Widget _buildSliderTile({required IconData icon, required String title, required double value, required double min, required double max, required Function(double) onChanged, required bool isDark}) {
     return Padding(
       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Row(
             children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05), shape: BoxShape.circle),
                  child: Icon(icon, color: isDark ? Colors.white : Colors.black, size: 20),
                ),
                const SizedBox(width: 16),
                Text(title, style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600, fontSize: 16)),
                const Spacer(),
                Text(value.toStringAsFixed(1), style: GoogleFonts.splineSans(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13)),
             ],
           ),
           Slider(
             value: value,
             min: min,
             max: max,
             activeColor: const Color(0xFFEA80FC),
             onChanged: onChanged,
           )
         ],
       ),
     );
  }

  Widget _buildAccountCard(BuildContext context, AuthService authService, bool isDark) {
    bool isLoggedIn = authService.isLoggedIn;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
      ),
      child: InkWell(
        onTap: isLoggedIn ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
        child: Row(
          children: [
             CircleAvatar(
               radius: 24,
               backgroundColor: isLoggedIn ? Colors.redAccent.withOpacity(0.2) : (isDark ? Colors.white10 : Colors.black12),
               child: Icon(isLoggedIn ? Icons.g_mobiledata_rounded : Icons.person_outline_rounded, color: isLoggedIn ? Colors.redAccent : (isDark ? Colors.white : Colors.black), size: 28),
             ),
             const SizedBox(width: 16),
             Expanded(
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text(isLoggedIn ? 'YouTube Account' : 'Log In to YouTube', style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                   const SizedBox(height: 2),
                   Text(isLoggedIn ? 'Connected' : 'Sync your personalized mix', style: GoogleFonts.splineSans(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
                 ],
               ),
             ),
             if (isLoggedIn) IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.redAccent), onPressed: () => authService.logout())
             else Icon(Icons.arrow_forward_ios_rounded, color: isDark ? Colors.white30 : Colors.black.withOpacity(0.3), size: 16),
          ],
        ),
      ),
    );
  }

  void _checkForUpdates(BuildContext context, bool isDark) async {
    final updateService = UpdateService();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Row(
          children: [
            const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEA80FC))),
            const SizedBox(width: 16),
            Text('Checking for updates...', style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black, fontSize: 16)),
          ],
        ),
      ),
    );

    final info = await updateService.checkForUpdate();
    if (!context.mounted) return;
    
    // pop loading
    Navigator.pop(context);

    if (info.isAvailable) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text('Update Available!', style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version ${info.version} is now available.', style: GoogleFonts.splineSans(color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(height: 16),
              Text('Changelog:', style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(info.changelog, style: GoogleFonts.splineSans(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Later', style: GoogleFonts.splineSans(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showDownloadProgress(context, updateService, info.downloadUrl, isDark);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA80FC)),
              child: Text('Download', style: GoogleFonts.splineSans(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text('Up to date', style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
          content: Text('You are using the latest version of Mine Music.', style: GoogleFonts.splineSans(color: isDark ? Colors.white70 : Colors.black87)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK', style: GoogleFonts.splineSans(color: const Color(0xFFEA80FC))),
            ),
          ],
        ),
      );
    }
  }

  void _showDownloadProgress(BuildContext context, UpdateService service, String url, bool isDark) {
    service.downloadAndInstallUpdate(url);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StreamBuilder<double>(
        stream: service.downloadProgress,
        builder: (context, snapshot) {
          final progress = snapshot.data ?? 0.0;
          final isError = progress < 0;
          final isDone = progress >= 1.0;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            title: Text(isError ? 'Download Failed' : (isDone ? 'Installing...' : 'Downloading Update'), style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isError && !isDone) ...[
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEA80FC)),
                  ),
                  const SizedBox(height: 16),
                  Text('${(progress * 100).toStringAsFixed(1)}%', style: GoogleFonts.splineSans(color: isDark ? Colors.white70 : Colors.black87)),
                ],
                if (isError) Text('An error occurred while downloading the update.', style: GoogleFonts.splineSans(color: Colors.redAccent)),
                if (isDone) Text('Opening installer...', style: GoogleFonts.splineSans(color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            actions: [
              if (isError || isDone)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    service.dispose();
                  },
                  child: Text('Close', style: GoogleFonts.splineSans(color: const Color(0xFFEA80FC))),
                ),
            ],
          );
        },
      ),
    );
  }
}
