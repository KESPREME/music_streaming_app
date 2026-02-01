import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/music_provider.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../models/music_source.dart';
import '../screens/login_screen.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';
import '../widgets/material_you_elevated_card.dart';

/// Material You Settings Screen - NO BLUR, solid colors, Material 3 design
class MaterialYouSettingsScreen extends StatelessWidget {
  const MaterialYouSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final musicProvider = Provider.of<MusicProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
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
        title: Text(
          'Settings',
          style: MaterialYouTypography.headlineMedium(colorScheme.onSurface),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // APPEARANCE SECTION
            _buildSectionTitle('Appearance', colorScheme),
            const SizedBox(height: 12),
            MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 20,
              child: Column(
                children: [
                  _buildListTile(
                    context,
                    icon: Icons.palette_rounded,
                    title: 'Theme',
                    subtitle: themeProvider.getThemeName(),
                    trailing: Switch(
                      value: themeProvider.isMaterialYou,
                      onChanged: (value) => themeProvider.toggleTheme(),
                      activeColor: MaterialYouTokens.primaryVibrant,
                    ),
                  ),
                  _buildDivider(colorScheme),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Text(
                      themeProvider.getThemeDescription(),
                      style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
                    ),
                  ),
                  _buildDivider(colorScheme),
                  _buildListTile(
                    context,
                    icon: Icons.color_lens_rounded,
                    title: 'Dynamic Colors',
                    subtitle: themeProvider.isDynamicColorEnabled ? 'Enabled' : 'Disabled',
                    trailing: Switch(
                      value: themeProvider.isDynamicColorEnabled,
                      onChanged: (value) => themeProvider.setDynamicColorEnabled(value),
                      activeColor: MaterialYouTokens.primaryVibrant,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            _buildSectionTitle('Music Source', colorScheme),
            const SizedBox(height: 12),
            _buildMusicSourceCard(context, musicProvider, colorScheme),

            const SizedBox(height: 32),
            _buildSectionTitle('Playback Quality', colorScheme),
            const SizedBox(height: 12),
            MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 20,
              child: Column(
                children: [
                  _buildListTile(
                    context,
                    icon: Icons.wifi_rounded,
                    title: 'Wi-Fi Quality',
                    subtitle: '${musicProvider.wifiBitrate} kbps',
                    onTap: () => _showBitrateDialog(context, musicProvider, true, colorScheme),
                  ),
                  _buildDivider(colorScheme),
                  _buildListTile(
                    context,
                    icon: Icons.signal_cellular_alt_rounded,
                    title: 'Cellular Quality',
                    subtitle: '${musicProvider.cellularBitrate} kbps',
                    onTap: () => _showBitrateDialog(context, musicProvider, false, colorScheme),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            _buildSectionTitle('Data & Storage', colorScheme),
            const SizedBox(height: 12),
            MaterialYouElevatedCard(
              elevation: 1,
              borderRadius: 20,
              child: Column(
                children: [
                  _buildSwitchTile(
                    context,
                    icon: Icons.data_saver_on_rounded,
                    title: 'Low Data Mode',
                    subtitle: 'Reduces quality to save data',
                    value: musicProvider.isLowDataMode,
                    onChanged: (val) => musicProvider.toggleLowDataMode(),
                  ),
                  _buildDivider(colorScheme),
                  _buildSwitchTile(
                    context,
                    icon: Icons.offline_bolt_rounded,
                    title: 'Offline Mode',
                    subtitle: 'Play only downloaded songs',
                    value: musicProvider.isOfflineMode,
                    onChanged: (val) => musicProvider.toggleOfflineMode(),
                  ),
                  _buildDivider(colorScheme),
                  _buildListTile(
                    context,
                    icon: Icons.cleaning_services_rounded,
                    title: 'Clear Cache',
                    subtitle: 'Free up storage space',
                    onTap: () async {
                      await musicProvider.clearAllCaches();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Cache cleared'),
                            backgroundColor: MaterialYouTokens.primaryVibrant,
                          ),
                        );
                      }
                    },
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
                    context,
                    icon: Icons.info_outline_rounded,
                    title: 'Version',
                    subtitle: '1.0.4 (Mine Music)',
                  ),
                  _buildDivider(colorScheme),
                  _buildListTile(
                    context,
                    icon: Icons.code_rounded,
                    title: 'Source',
                    subtitle: 'Powered by InnerTube',
                  ),
                ],
              ),
            ),

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
        style: MaterialYouTypography.labelSmall(colorScheme.onSurfaceVariant).copyWith(
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Divider(
      height: 1,
      thickness: 1,
      color: colorScheme.outlineVariant,
      indent: 68,
    );
  }

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: MaterialYouTokens.primaryVibrant.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: MaterialYouTokens.primaryVibrant, size: 20),
      ),
      title: Text(
        title,
        style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
            )
          : null,
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right_rounded, color: colorScheme.onSurfaceVariant)
              : null),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      secondary: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: MaterialYouTokens.primaryVibrant.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: MaterialYouTokens.primaryVibrant, size: 20),
      ),
      title: Text(
        title,
        style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
      ),
      subtitle: Text(
        subtitle,
        style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
      ),
      activeColor: MaterialYouTokens.primaryVibrant,
      activeTrackColor: MaterialYouTokens.primaryVibrant.withOpacity(0.3),
    );
  }

  Widget _buildMusicSourceCard(BuildContext context, MusicProvider musicProvider, ColorScheme colorScheme) {
    final currentSource = musicProvider.currentMusicSource;

    return MaterialYouElevatedCard(
      elevation: 1,
      borderRadius: 20,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => musicProvider.setMusicSource(MusicSource.youtube),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: currentSource == MusicSource.youtube
                      ? MaterialYouTokens.primaryVibrant.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_queue_rounded,
                      size: 20,
                      color: currentSource == MusicSource.youtube
                          ? MaterialYouTokens.primaryVibrant
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Stream',
                      style: MaterialYouTypography.labelLarge(
                        currentSource == MusicSource.youtube
                            ? MaterialYouTokens.primaryVibrant
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => musicProvider.setMusicSource(MusicSource.local),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: currentSource == MusicSource.local
                      ? MaterialYouTokens.primaryVibrant.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 20,
                      color: currentSource == MusicSource.local
                          ? MaterialYouTokens.primaryVibrant
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Local',
                      style: MaterialYouTypography.labelLarge(
                        currentSource == MusicSource.local
                            ? MaterialYouTokens.primaryVibrant
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context, AuthService authService, ColorScheme colorScheme) {
    bool isLoggedIn = authService.isLoggedIn;

    return MaterialYouElevatedCard(
      elevation: 1,
      borderRadius: 20,
      onTap: isLoggedIn
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: isLoggedIn
                ? MaterialYouTokens.primaryVibrant.withOpacity(0.2)
                : colorScheme.surfaceVariant,
            child: Icon(
              isLoggedIn ? Icons.g_mobiledata_rounded : Icons.person_outline_rounded,
              color: isLoggedIn ? MaterialYouTokens.primaryVibrant : colorScheme.onSurfaceVariant,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoggedIn ? 'YouTube Account' : 'Log In to YouTube',
                  style: MaterialYouTypography.titleMedium(colorScheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  isLoggedIn ? 'Connected' : 'Sync your personalized mix',
                  style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (isLoggedIn)
            IconButton(
              icon: Icon(Icons.logout_rounded, color: MaterialYouTokens.primaryVibrant),
              onPressed: () async {
                await authService.logout();
              },
            )
          else
            Icon(Icons.arrow_forward_ios_rounded, color: colorScheme.onSurfaceVariant, size: 16),
        ],
      ),
    );
  }

  Widget _buildMadeByFooter(ColorScheme colorScheme) {
    return Column(
      children: [
        Image.asset(
          'assets/images/app_logo.png',
          height: 60,
          width: 60,
        ),
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
                    style: MaterialYouTypography.bodyMedium(MaterialYouTokens.primaryVibrant).copyWith(
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showBitrateDialog(BuildContext context, MusicProvider musicProvider, bool isWifi, ColorScheme colorScheme) {
    final currentBitrate = isWifi ? musicProvider.wifiBitrate : musicProvider.cellularBitrate;
    final List<int> options = isWifi ? [64, 128, 256, 320] : [32, 64, 128];

    showDialog(
      context: context,
      builder: (context) {
        return Consumer<MusicProvider>(
          builder: (context, provider, _) {
            final currentBitrate = isWifi ? provider.wifiBitrate : provider.cellularBitrate;
            final isAuto = provider.isAutoBitrate;

            return AlertDialog(
              backgroundColor: MaterialYouTokens.surfaceContainerDark,
              title: Text(
                '${isWifi ? "Wi-Fi" : "Cellular"} Quality',
                style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Auto Option
                  ListTile(
                    title: Text('Auto', style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
                    subtitle: isAuto
                        ? Text(
                            'Adjusts automatically based on network',
                            style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
                          )
                        : null,
                    leading: Icon(
                      isAuto ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: isAuto ? MaterialYouTokens.primaryVibrant : colorScheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      provider.setAutoBitrate(true);
                      Navigator.pop(context);
                    },
                  ),
                  Divider(color: colorScheme.outlineVariant),

                  // Manual Options
                  ...options.map((bitrate) {
                    final isSelected = !isAuto && bitrate == currentBitrate;
                    return ListTile(
                      title: Text('$bitrate kbps', style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: isSelected ? MaterialYouTokens.primaryVibrant : colorScheme.onSurfaceVariant,
                      ),
                      onTap: () {
                        if (isWifi) {
                          provider.setWifiBitrate(bitrate);
                        } else {
                          provider.setCellularBitrate(bitrate);
                        }
                        Navigator.pop(context);
                      },
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
