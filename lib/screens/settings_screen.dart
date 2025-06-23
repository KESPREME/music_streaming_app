import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart'; // For bitrate settings, offline mode etc.
import '../services/auth_service.dart'; // For sign out

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context);
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: theme.textTheme.headlineSmall),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          _buildSectionTitle('Playback', theme),
          ListTile(
            leading: Icon(Icons.wifi_tethering, color: theme.iconTheme.color),
            title: Text('Wi-Fi Streaming Quality', style: theme.textTheme.titleMedium),
            subtitle: Text('${musicProvider.wifiBitrate} kbps', style: theme.textTheme.bodySmall),
            onTap: () => _showBitrateOptions(context, musicProvider, true),
          ),
          ListTile(
            leading: Icon(Icons.signal_cellular_alt, color: theme.iconTheme.color),
            title: Text('Cellular Streaming Quality', style: theme.textTheme.titleMedium),
            subtitle: Text('${musicProvider.cellularBitrate} kbps', style: theme.textTheme.bodySmall),
            onTap: () => _showBitrateOptions(context, musicProvider, false),
          ),
          SwitchListTile(
            title: Text('Low Data Mode', style: theme.textTheme.titleMedium),
            subtitle: Text('Reduces data usage by lowering streaming quality', style: theme.textTheme.bodySmall),
            value: musicProvider.isLowDataMode,
            onChanged: (bool value) {
              musicProvider.toggleLowDataMode();
            },
            activeColor: theme.colorScheme.primary,
            secondary: Icon(Icons.data_saver_off_outlined, color: theme.iconTheme.color),
          ),
          const Divider(),
          _buildSectionTitle('Account', theme),
          ListTile(
            leading: Icon(Icons.offline_bolt_outlined, color: theme.iconTheme.color),
            title: Text('Offline Mode', style: theme.textTheme.titleMedium),
            trailing: Switch(
              value: musicProvider.isOfflineMode,
              onChanged: (bool value) {
                musicProvider.toggleOfflineMode();
              },
              activeColor: theme.colorScheme.primary,
            ),
            onTap: () => musicProvider.toggleOfflineMode(), // Allow tapping whole tile
          ),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Sign Out', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error)),
            onTap: () async {
              // Confirmation dialog
              final confirm = await showDialog<bool>(
                context: context,
                builder: (BuildContext dialogContext) => AlertDialog(
                  title: Text('Sign Out?', style: theme.dialogTheme.titleTextStyle),
                  content: Text('Are you sure you want to sign out?', style: theme.dialogTheme.contentTextStyle),
                  actions: <Widget>[
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.pop(dialogContext, false),
                    ),
                    TextButton(
                      child: Text('Sign Out', style: TextStyle(color: theme.colorScheme.error)),
                      onPressed: () => Navigator.pop(dialogContext, true),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await authService.signOut();
                // Potentially navigate to login screen or show a message
                // For now, just pop this screen if successful
                if (context.mounted && Navigator.canPop(context)) {
                  // Pop settings screen, then potentially pop further if on auth-gated content,
                  // or main.dart should handle navigation based on auth state stream.
                  Navigator.pop(context);
                }
              }
            },
          ),
          const Divider(),
           _buildSectionTitle('About', theme),
          ListTile(
            leading: Icon(Icons.info_outline, color: theme.iconTheme.color),
            title: Text('Version', style: theme.textTheme.titleMedium),
            subtitle: Text('1.0.0 (Simulated)', style: theme.textTheme.bodySmall), // Replace with actual version later
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showBitrateOptions(BuildContext context, MusicProvider musicProvider, bool isWifi) {
    final theme = Theme.of(context);
    final currentBitrate = isWifi ? musicProvider.wifiBitrate : musicProvider.cellularBitrate;
    final List<int> options = isWifi ? [64, 128, 256, 320] : [32, 64, 128];

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Select ${isWifi ? "Wi-Fi" : "Cellular"} Quality', style: theme.dialogTheme.titleTextStyle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map((bitrate) {
                return RadioListTile<int>(
                  title: Text('$bitrate kbps', style: theme.textTheme.bodyLarge),
                  value: bitrate,
                  groupValue: currentBitrate,
                  onChanged: (int? value) {
                    if (value != null) {
                      if (isWifi) {
                        musicProvider.setWifiBitrate(value);
                      } else {
                        musicProvider.setCellularBitrate(value);
                      }
                      Navigator.pop(dialogContext);
                    }
                  },
                  activeColor: theme.colorScheme.primary,
                );
              }).toList(),
            ),
          ),
          actions: [
             TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.pop(dialogContext);
              },
            ),
          ],
        );
      },
    );
  }
}
