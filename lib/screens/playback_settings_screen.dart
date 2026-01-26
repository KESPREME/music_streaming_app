// lib/screens/playback_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';

class PlaybackSettingsScreen extends StatelessWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D1D1D),
        title: const Text('Playback Settings'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          _buildSectionHeader('Playback'),
          SwitchListTile(
            title: const Text(
              'Shuffle',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Play tracks in random order',
              style: TextStyle(color: Colors.white70),
            ),
            value: musicProvider.shuffleEnabled,
            activeThumbColor: Colors.deepPurple,
            onChanged: (value) {
              musicProvider.toggleShuffle();
            },
          ),
          ListTile(
            title: const Text(
              'Repeat Mode',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _getRepeatModeText(musicProvider.repeatMode),
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: IconButton(
              icon: Icon(
                _getRepeatModeIcon(musicProvider.repeatMode),
                color: musicProvider.repeatMode != RepeatMode.off ? Colors.deepPurple : Colors.white70,
              ),
              onPressed: () {
                musicProvider.cycleRepeatMode();
              },
            ),
          ),
          const Divider(color: Colors.grey),
          _buildSectionHeader('Audio Quality'),
          ListTile(
            title: const Text(
              'WiFi Streaming',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              '${musicProvider.wifiBitrate} kbps',
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: DropdownButton<int>(
              value: musicProvider.wifiBitrate,
              dropdownColor: const Color(0xFF1D1D1D),
              underline: Container(),
              items: const [
                DropdownMenuItem(value: 64, child: Text('64 kbps', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 128, child: Text('128 kbps', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 192, child: Text('192 kbps', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 256, child: Text('256 kbps', style: TextStyle(color: Colors.white))),
              ],
              onChanged: (value) {
                if (value != null) {
                  musicProvider.setWifiBitrate(value);
                }
              },
            ),
          ),
          ListTile(
            title: const Text(
              'Mobile Data Streaming',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              '${musicProvider.cellularBitrate} kbps',
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: DropdownButton<int>(
              value: musicProvider.cellularBitrate,
              dropdownColor: const Color(0xFF1D1D1D),
              underline: Container(),
              items: const [
                DropdownMenuItem(value: 32, child: Text('32 kbps', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 64, child: Text('64 kbps', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 96, child: Text('96 kbps', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 128, child: Text('128 kbps', style: TextStyle(color: Colors.white))),
              ],
              onChanged: (value) {
                if (value != null) {
                  musicProvider.setCellularBitrate(value);
                }
              },
            ),
          ),
          SwitchListTile(
            title: const Text(
              'Low Data Mode',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Reduce data usage by lowering audio quality',
              style: TextStyle(color: Colors.white70),
            ),
            value: musicProvider.isLowDataMode,
            activeThumbColor: Colors.deepPurple,
            onChanged: (value) {
              musicProvider.toggleLowDataMode();
            },
          ),
          const Divider(color: Colors.grey),
          _buildSectionHeader('Network'),
          SwitchListTile(
            title: const Text(
              'Offline Mode',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Only play downloaded tracks',
              style: TextStyle(color: Colors.white70),
            ),
            value: musicProvider.isOfflineMode,
            activeThumbColor: Colors.deepPurple,
            onChanged: (value) {
              if (value) {
                musicProvider.goOffline();
              } else {
                musicProvider.goOnline();
              }
            },
          ),
          ListTile(
            title: const Text(
              'Network Diagnostics',
              style: TextStyle(color: Colors.white),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
            onTap: () {
              _showNetworkDiagnostics(context);
            },
          ),
          ListTile(
            title: const Text(
              'Clear Cache',
              style: TextStyle(color: Colors.white),
            ),
            trailing: const Icon(Icons.cleaning_services, color: Colors.white70),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.deepPurple,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
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

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF1D1D1D),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.deepPurple),
            SizedBox(height: 16),
            Text(
              'Running network diagnostics...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    // Run diagnostics
    final diagnostics = await musicProvider.runNetworkDiagnostics();

    // Close loading dialog
    Navigator.pop(context);

    // Show results
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1D1D),
        title: const Text('Network Diagnostics', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDiagnosticItem('Connected', diagnostics['isConnected'] ? 'Yes' : 'No'),
              _buildDiagnosticItem('Network Quality', diagnostics['networkQuality']),
              _buildDiagnosticItem('Connection Type', diagnostics['connectionType']),
              if (diagnostics['downloadSpeed'] != null)
                _buildDiagnosticItem('Download Speed', diagnostics['downloadSpeed']),
              if (diagnostics['pingTime'] != null)
                _buildDiagnosticItem('Ping Time', diagnostics['pingTime']),
              _buildDiagnosticItem('Optimal Bitrate', '${diagnostics['optimalBitrate']} kbps'),
              _buildDiagnosticItem('WiFi Bitrate', '${diagnostics['wifiBitrate']} kbps'),
              _buildDiagnosticItem('Cellular Bitrate', '${diagnostics['cellularBitrate']} kbps'),
              _buildDiagnosticItem('Offline Mode', diagnostics['isOfflineMode'] ? 'Enabled' : 'Disabled'),
              _buildDiagnosticItem('Low Data Mode', diagnostics['isLowDataMode'] ? 'Enabled' : 'Disabled'),
              _buildDiagnosticItem('Shuffle', diagnostics['shuffleEnabled'] ? 'Enabled' : 'Disabled'),
              _buildDiagnosticItem('Repeat Mode', diagnostics['repeatMode']),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Close', style: TextStyle(color: Colors.deepPurple)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticItem(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

