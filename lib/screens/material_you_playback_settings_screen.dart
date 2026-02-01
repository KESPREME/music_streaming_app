import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouPlaybackSettingsScreen extends StatelessWidget {
  const MaterialYouPlaybackSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      appBar: AppBar(
        backgroundColor: MaterialYouTokens.surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Playback Settings',
          style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSectionHeader('Playback', colorScheme),
          SwitchListTile(
            title: Text('Shuffle', style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
            subtitle: Text(
              'Play tracks in random order',
              style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
            ),
            value: musicProvider.shuffleEnabled,
            activeColor: MaterialYouTokens.primaryVibrant,
            onChanged: (value) {
              musicProvider.toggleShuffle();
            },
          ),
          ListTile(
            title: Text('Repeat Mode', style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
            subtitle: Text(
              _getRepeatModeText(musicProvider.repeatMode),
              style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
            ),
            trailing: IconButton(
              icon: Icon(
                _getRepeatModeIcon(musicProvider.repeatMode),
                color: musicProvider.repeatMode != RepeatMode.off 
                    ? MaterialYouTokens.primaryVibrant 
                    : colorScheme.onSurfaceVariant,
              ),
              onPressed: () {
                musicProvider.cycleRepeatMode();
              },
            ),
          ),
          Divider(color: colorScheme.surfaceVariant),
          _buildSectionHeader('Audio Quality', colorScheme),
          ListTile(
            title: Text('WiFi Streaming', style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
            subtitle: Text(
              '${musicProvider.wifiBitrate} kbps',
              style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
            ),
            trailing: DropdownButton<int>(
              value: musicProvider.wifiBitrate,
              dropdownColor: MaterialYouTokens.surfaceContainerDark,
              underline: Container(),
              items: [
                DropdownMenuItem(value: 64, child: Text('64 kbps', style: MaterialYouTypography.bodyMedium(colorScheme.onSurface))),
                DropdownMenuItem(value: 128, child: Text('128 kbps', style: MaterialYouTypography.bodyMedium(colorScheme.onSurface))),
                DropdownMenuItem(value: 192, child: Text('192 kbps', style: MaterialYouTypography.bodyMedium(colorScheme.onSurface))),
                DropdownMenuItem(value: 256, child: Text('256 kbps', style: MaterialYouTypography.bodyMedium(colorScheme.onSurface))),
              ],
              onChanged: (value) {
                if (value != null) {
                  musicProvider.setWifiBitrate(value);
                }
              },
            ),
          ),
          ListTile(
            title: Text('Mobile Data Streaming', style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
            subtitle: Text(
              '${musicProvider.cellularBitrate} kbps',
              style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
            ),
            trailing: DropdownButton<int>(
              value: musicProvider.cellularBitrate,
              dropdownColor: MaterialYouTokens.surfaceContainerDark,
              underline: Container(),
              items: [
                DropdownMenuItem(value: 32, child: Text('32 kbps', style: MaterialYouTypography.bodyMedium(colorScheme.onSurface))),
                DropdownMenuItem(value: 64, child: Text('64 kbps', style: MaterialYouTypography.bodyMedium(colorScheme.onSurface))),
                DropdownMenuItem(value: 96, child: Text('96 kbps', style: MaterialYouTypography.bodyMedium(colorScheme.onSurface))),
                DropdownMenuItem(value: 128, child: Text('128 kbps', style: MaterialYouTypography.bodyMedium(colorScheme.onSurface))),
              ],
              onChanged: (value) {
                if (value != null) {
                  musicProvider.setCellularBitrate(value);
                }
              },
            ),
          ),
          SwitchListTile(
            title: Text('Low Data Mode', style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
            subtitle: Text(
              'Reduce data usage by lowering audio quality',
              style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
            ),
            value: musicProvider.isLowDataMode,
            activeColor: MaterialYouTokens.primaryVibrant,
            onChanged: (value) {
              musicProvider.toggleLowDataMode();
            },
          ),
          Divider(color: colorScheme.surfaceVariant),
          _buildSectionHeader('Network', colorScheme),
          SwitchListTile(
            title: Text('Offline Mode', style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
            subtitle: Text(
              'Only play downloaded tracks',
              style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
            ),
            value: musicProvider.isOfflineMode,
            activeColor: MaterialYouTokens.primaryVibrant,
            onChanged: (value) {
              if (value) {
                musicProvider.goOffline();
              } else {
                musicProvider.goOnline();
              }
            },
          ),
          ListTile(
            title: Text('Network Diagnostics', style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
            trailing: Icon(Icons.arrow_forward_ios, color: colorScheme.onSurfaceVariant, size: 16),
            onTap: () {
              _showNetworkDiagnostics(context);
            },
          ),
          ListTile(
            title: Text('Clear Cache', style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
            trailing: Icon(Icons.cleaning_services, color: colorScheme.onSurfaceVariant),
            onTap: () {
              musicProvider.clearAllCaches();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        title,
        style: MaterialYouTypography.titleMedium(MaterialYouTokens.primaryVibrant),
      ),
    );
  }

  String _getRepeatModeText(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return 'No repeat';
      case RepeatMode.all:
        return 'Repeat all tracks';
      case RepeatMode.one:
        return 'Repeat current track';
    }
  }

  IconData _getRepeatModeIcon(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return Icons.repeat;
      case RepeatMode.all:
        return Icons.repeat;
      case RepeatMode.one:
        return Icons.repeat_one;
    }
  }

  Future<void> _showNetworkDiagnostics(BuildContext context) async {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: MaterialYouTokens.surfaceContainerDark,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: MaterialYouTokens.primaryVibrant),
            const SizedBox(height: 16),
            Text(
              'Running network diagnostics...',
              style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );

    final diagnostics = await musicProvider.runNetworkDiagnostics();

    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MaterialYouTokens.surfaceContainerDark,
        title: Text('Network Diagnostics', style: MaterialYouTypography.titleLarge(colorScheme.onSurface)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDiagnosticItem('Connected', diagnostics['isConnected'] ? 'Yes' : 'No', colorScheme),
              _buildDiagnosticItem('Network Quality', diagnostics['networkQuality'], colorScheme),
              _buildDiagnosticItem('Connection Type', diagnostics['connectionType'], colorScheme),
              if (diagnostics['downloadSpeed'] != null)
                _buildDiagnosticItem('Download Speed', diagnostics['downloadSpeed'], colorScheme),
              if (diagnostics['pingTime'] != null)
                _buildDiagnosticItem('Ping Time', diagnostics['pingTime'], colorScheme),
              _buildDiagnosticItem('Optimal Bitrate', '${diagnostics['optimalBitrate']} kbps', colorScheme),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: Text('Close', style: MaterialYouTypography.labelLarge(MaterialYouTokens.primaryVibrant)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticItem(String label, dynamic value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: MaterialYouTypography.bodyMedium(colorScheme.onSurface).copyWith(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
