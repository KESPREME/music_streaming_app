import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/music_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../models/music_source.dart';
import '../screens/login_screen.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';
import '../widgets/material_you_elevated_card.dart';
import '../services/update_service.dart';

class MaterialYouSettingsScreen extends StatelessWidget {
  const MaterialYouSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final musicProvider = Provider.of<MusicProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      appBar: AppBar(
        backgroundColor: MaterialYouTokens.surfaceDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: colorScheme.onSurface,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Settings', style: MaterialYouTypography.headlineMedium(colorScheme.onSurface)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildSectionTitle('Appearance', colorScheme),
            const SizedBox(height: 12),
            MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 20,
              child: Column(
                children: [
                   _buildListTile(
                     context, icon: Icons.palette_rounded, title: 'Material You Theme', subtitle: 'Toggle Material 3 UI Style',
                     trailing: Switch(value: themeProvider.isMaterialYou, onChanged: (val) => themeProvider.toggleTheme(), activeColor: MaterialYouTokens.primaryVibrant),
                   ),
                   _buildDivider(colorScheme),
                   _buildListTile(
                     context, icon: Icons.color_lens_rounded, title: 'Dynamic Colors', subtitle: 'Extract colors from album art',
                     trailing: Switch(value: themeProvider.isDynamicColorEnabled, onChanged: (val) => themeProvider.setDynamicColorEnabled(val), activeColor: MaterialYouTokens.primaryVibrant),
                   ),
                   _buildDivider(colorScheme),
                   _buildListTile(
                     context, icon: Icons.animation_rounded, title: 'Enable Animations', subtitle: 'Toggle UI animations',
                     trailing: Switch(value: settingsProvider.enableAnimations, onChanged: (val) => settingsProvider.setEnableAnimations(val), activeColor: MaterialYouTokens.primaryVibrant),
                   ),
                   _buildDivider(colorScheme),
                   _buildSliderTile(
                     context, icon: Icons.blur_on_rounded, title: 'Blur Intensity', value: settingsProvider.blurIntensity,
                     min: 0, max: 20, onChanged: (val) => settingsProvider.setBlurIntensity(val),
                   ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            _buildSectionTitle('Playback', colorScheme),
            const SizedBox(height: 12),
            MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 20,
              child: Column(
                children: [
                  _buildSwitchTile(
                    context, icon: Icons.skip_next_rounded, title: 'Gapless Playback', subtitle: 'Seamless transition between tracks',
                    value: settingsProvider.gaplessPlayback, onChanged: (val) => settingsProvider.setGaplessPlayback(val)
                  ),
                  _buildDivider(colorScheme),
                  _buildSliderTile(
                    context, icon: Icons.compare_arrows_rounded, title: 'Crossfade Duration', value: settingsProvider.crossfadeDuration,
                     min: 0, max: 12, onChanged: (val) => settingsProvider.setCrossfadeDuration(val),
                  ),
                  _buildDivider(colorScheme),
                  _buildSwitchTile(
                    context, icon: Icons.volume_up_rounded, title: 'Normalize Volume', subtitle: 'Keep volume consistent',
                    value: settingsProvider.normalizeVolume, onChanged: (val) => settingsProvider.setNormalizeVolume(val)
                  ),
                  _buildDivider(colorScheme),
                  _buildSwitchTile(
                    context, icon: Icons.playlist_play_rounded, title: 'Auto-play Next', subtitle: 'Keep playing when queue ends',
                    value: settingsProvider.autoPlayNext, onChanged: (val) => settingsProvider.setAutoPlayNext(val)
                  ),
                  _buildDivider(colorScheme),
                  _buildSwitchTile(
                    context, icon: Icons.headphones_rounded, title: 'Pause on Disconnect', subtitle: 'Pause when headphones unplugged',
                    value: settingsProvider.pauseOnHeadphoneDisconnect, onChanged: (val) => settingsProvider.setPauseOnHeadphoneDisconnect(val)
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            _buildSectionTitle('Audio & Quality', colorScheme),
            const SizedBox(height: 12),
            MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 20,
              child: Column(
                children: [
                   _buildListTile(
                     context, icon: Icons.high_quality_rounded, title: 'Audio Quality', subtitle: settingsProvider.audioQuality.name.toUpperCase(),
                     onTap: () {
                         final current = settingsProvider.audioQuality;
                         final next = AudioQuality.values[(current.index + 1) % AudioQuality.values.length];
                         settingsProvider.setAudioQuality(next);
                     }
                   ),
                   _buildDivider(colorScheme),
                   _buildSwitchTile(
                     context, icon: Icons.download_done_rounded, title: 'Prefer Cache', subtitle: 'Play cached version if available',
                     value: settingsProvider.preferCache, onChanged: (val) => settingsProvider.setPreferCache(val)
                   ),
                   _buildDivider(colorScheme),
                   _buildSwitchTile(
                     context, icon: Icons.electric_bolt_rounded, title: 'Preload Audio', subtitle: 'Preload next track for zero delay',
                     value: settingsProvider.enableAudioPreloading, onChanged: (val) => settingsProvider.setEnableAudioPreloading(val)
                   ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            _buildSectionTitle('Downloads / Offline', colorScheme),
            const SizedBox(height: 12),
            MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 20,
              child: Column(
                children: [
                  _buildSwitchTile(
                    context, icon: Icons.wifi_rounded, title: 'Download over Wi-Fi Only', subtitle: 'Save cellular data',
                    value: settingsProvider.downloadOverWifiOnly, onChanged: (val) => settingsProvider.setDownloadOverWifiOnly(val)
                  ),
                  _buildDivider(colorScheme),
                  _buildSwitchTile(
                    context, icon: Icons.delete_sweep_rounded, title: 'Auto-delete Failed', subtitle: 'Remove failed downloads automatically',
                    value: settingsProvider.autoDeleteFailedDownloads, onChanged: (val) => settingsProvider.setAutoDeleteFailedDownloads(val)
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            _buildSectionTitle('Library', colorScheme),
            const SizedBox(height: 12),
            MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 20,
              child: Column(
                children: [
                  _buildSwitchTile(
                    context, icon: Icons.folder_shared_rounded, title: 'Auto-scan Local Music', subtitle: 'Scan device storage automatically',
                    value: settingsProvider.autoScanLocalMusic, onChanged: (val) => settingsProvider.setAutoScanLocalMusic(val)
                  ),
                  _buildDivider(colorScheme),
                  _buildSwitchTile(
                    context, icon: Icons.visibility_off_rounded, title: 'Hide Unavailable', subtitle: 'Hide songs that cannot be played',
                    value: settingsProvider.hideUnavailableTracks, onChanged: (val) => settingsProvider.setHideUnavailableTracks(val)
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            _buildSectionTitle('Notifications', colorScheme),
            const SizedBox(height: 12),
            MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 20,
              child: Column(
                children: [
                  _buildSwitchTile(
                    context, icon: Icons.screen_lock_portrait_rounded, title: 'Lock Screen Controls', subtitle: 'Show player on lock screen',
                    value: settingsProvider.lockScreenControls, onChanged: (val) => settingsProvider.setLockScreenControls(val)
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            _buildSectionTitle('Import & Services', colorScheme),
            const SizedBox(height: 12),
            MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 20,
              child: Column(
                children: [
                   _buildSwitchTile(
                    context, icon: Icons.youtube_searched_for_rounded, title: 'Auto Search YouTube', subtitle: 'For Spotify matching',
                    value: settingsProvider.autoSearchYouTubeForImports, onChanged: (val) => settingsProvider.setAutoSearchYouTubeForImports(val)
                   ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            _buildSectionTitle('Account', colorScheme),
            const SizedBox(height: 12),
            _buildAccountCard(context, authService, colorScheme),

            const SizedBox(height: 32),
            _buildSectionTitle('About', colorScheme),
            const SizedBox(height: 12),
            MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 20,
              child: Column(
                children: [
                   _buildListTile(
                     context, icon: Icons.system_update_rounded, title: 'Check for Updates', subtitle: 'Check GitHub for new releases',
                     onTap: () => _checkForUpdates(context, colorScheme),
                   ),
                   _buildDivider(colorScheme),
                  _buildListTile(
                    context, icon: Icons.info_outline_rounded, title: 'Version', subtitle: '1.0.4 (Mine Music)',
                    onTap: () {
                       settingsProvider.toggleDeveloperMode();
                    }
                  ),
                  _buildDivider(colorScheme),
                  _buildListTile(context, icon: Icons.code_rounded, title: 'Source', subtitle: 'Powered by InnerTube'),
                ],
              ),
            ),

            if (settingsProvider.developerModeEnabled) ...[
              const SizedBox(height: 32),
              _buildSectionTitle('Developer Options', colorScheme),
              const SizedBox(height: 12),
              MaterialYouElevatedCard(
                elevation: 1,
                borderRadius: 20,
                child: Column(
                  children: [
                    _buildSwitchTile(
                      context, icon: Icons.bug_report_rounded, title: 'Enable Debug Logs', subtitle: 'Print extra info to console',
                      value: settingsProvider.enableDebugLogs, onChanged: (val) => settingsProvider.setEnableDebugLogs(val)
                    ),
                    _buildDivider(colorScheme),
                    _buildListTile(
                      context, icon: Icons.cleaning_services_rounded, title: 'Clear Cache', subtitle: 'Force wipe local cache',
                      onTap: () async {
                         await musicProvider.clearAllCaches();
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                           content: const Text('Cache cleared'),
                           backgroundColor: MaterialYouTokens.primaryVibrant,
                         ));
                      }
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),
            _buildMadeByFooter(colorScheme),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title.toUpperCase(),
        style: MaterialYouTypography.labelSmall(colorScheme.onSurfaceVariant).copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant, indent: 68);
  }

  Widget _buildListTile(BuildContext context, {required IconData icon, required String title, String? subtitle, VoidCallback? onTap, Widget? trailing}) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: MaterialYouTokens.primaryVibrant.withOpacity(0.15), shape: BoxShape.circle),
        child: Icon(icon, color: MaterialYouTokens.primaryVibrant, size: 20),
      ),
      title: Text(title, style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
      subtitle: subtitle != null ? Text(subtitle, style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant)) : null,
      trailing: trailing ?? (onTap != null ? Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant) : null),
    );
  }

  Widget _buildSwitchTile(BuildContext context, {required IconData icon, required String title, required String subtitle, required bool value, required Function(bool) onChanged}) {
    final colorScheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      secondary: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: MaterialYouTokens.primaryVibrant.withOpacity(0.15), shape: BoxShape.circle),
        child: Icon(icon, color: MaterialYouTokens.primaryVibrant, size: 20),
      ),
      title: Text(title, style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
      subtitle: Text(subtitle, style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant)),
      activeColor: MaterialYouTokens.primaryVibrant,
      activeTrackColor: MaterialYouTokens.primaryVibrant.withOpacity(0.3),
    );
  }

   Widget _buildSliderTile(BuildContext context, {required IconData icon, required String title, required double value, required double min, required double max, required Function(double) onChanged}) {
     final colorScheme = Theme.of(context).colorScheme;
     return Padding(
       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Row(
             children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: MaterialYouTokens.primaryVibrant.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(icon, color: MaterialYouTokens.primaryVibrant, size: 20),
                ),
                const SizedBox(width: 16),
                Text(title, style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
                const Spacer(),
                Text(value.toStringAsFixed(1), style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant)),
             ],
           ),
           Slider(
             value: value,
             min: min,
             max: max,
             activeColor: MaterialYouTokens.primaryVibrant,
             onChanged: onChanged,
           )
         ],
       ),
     );
  }

  Widget _buildAccountCard(BuildContext context, AuthService authService, ColorScheme colorScheme) {
    bool isLoggedIn = authService.isLoggedIn;
    return MaterialYouElevatedCard(
      elevation: 1, borderRadius: 20,
      onTap: isLoggedIn ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: isLoggedIn ? MaterialYouTokens.primaryVibrant.withOpacity(0.2) : colorScheme.surfaceVariant,
            child: Icon(isLoggedIn ? Icons.g_mobiledata_rounded : Icons.person_outline_rounded, color: isLoggedIn ? MaterialYouTokens.primaryVibrant : colorScheme.onSurfaceVariant, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isLoggedIn ? 'YouTube Account' : 'Log In to YouTube', style: MaterialYouTypography.titleMedium(colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text(isLoggedIn ? 'Connected' : 'Sync your personalized mix', style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (isLoggedIn) IconButton(icon: Icon(Icons.logout_rounded, color: MaterialYouTokens.primaryVibrant), onPressed: () async => await authService.logout())
          else Icon(Icons.arrow_forward_ios_rounded, color: colorScheme.onSurfaceVariant, size: 16),
        ],
      ),
    );
  }

  Widget _buildMadeByFooter(ColorScheme colorScheme) {
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
                style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                children: [
                  const TextSpan(text: 'Made with ❤️ using Flutter by '),
                  TextSpan(
                    text: 'KESPREME',
                    style: MaterialYouTypography.bodyMedium(MaterialYouTokens.primaryVibrant).copyWith(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _checkForUpdates(BuildContext context, ColorScheme colorScheme) async {
    final updateService = UpdateService();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: MaterialYouTokens.surfaceContainerDark,
        title: Row(
          children: [
            SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: MaterialYouTokens.primaryVibrant)),
            const SizedBox(width: 16),
            Text('Checking for updates...', style: MaterialYouTypography.titleMedium(colorScheme.onSurface)),
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
          backgroundColor: MaterialYouTokens.surfaceContainerDark,
          title: Text('Update Available!', style: MaterialYouTypography.headlineSmall(colorScheme.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version ${info.version} is now available.', style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Text('Changelog:', style: MaterialYouTypography.titleMedium(colorScheme.onSurface)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(info.changelog, style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Later', style: MaterialYouTypography.labelLarge(colorScheme.onSurfaceVariant)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showDownloadProgress(context, updateService, info.downloadUrl, colorScheme);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: MaterialYouTokens.primaryVibrant,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: const Text('Download'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: MaterialYouTokens.surfaceContainerDark,
          title: Text('Up to date', style: MaterialYouTypography.headlineSmall(colorScheme.onSurface)),
          content: Text('You are using the latest version of Mine Music.', style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK', style: MaterialYouTypography.labelLarge(MaterialYouTokens.primaryVibrant)),
            ),
          ],
        ),
      );
    }
  }

  void _showDownloadProgress(BuildContext context, UpdateService service, String url, ColorScheme colorScheme) {
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
            backgroundColor: MaterialYouTokens.surfaceContainerDark,
            title: Text(isError ? 'Download Failed' : (isDone ? 'Installing...' : 'Downloading Update'), style: MaterialYouTypography.headlineSmall(colorScheme.onSurface)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isError && !isDone) ...[
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    backgroundColor: colorScheme.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(MaterialYouTokens.primaryVibrant),
                  ),
                  const SizedBox(height: 16),
                  Text('${(progress * 100).toStringAsFixed(1)}%', style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant)),
                ],
                if (isError) Text('An error occurred while downloading the update.', style: MaterialYouTypography.bodyMedium(colorScheme.error)),
                if (isDone) Text('Opening installer...', style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant)),
              ],
            ),
            actions: [
              if (isError || isDone)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    service.dispose();
                  },
                  child: Text('Close', style: MaterialYouTypography.labelLarge(MaterialYouTokens.primaryVibrant)),
                ),
            ],
          );
        },
      ),
    );
  }
}
