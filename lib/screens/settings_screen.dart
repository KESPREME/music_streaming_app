// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import 'playback_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D1D1D),
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _buildSettingsGroup(
            title: 'Playback',
            children: [
              ListTile(
                leading: const Icon(Icons.music_note, color: Colors.deepPurple),
                title: const Text('Playback Settings', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  'Shuffle: ${musicProvider.shuffleEnabled ? 'On' : 'Off'}, Repeat: ${_getRepeatModeText(musicProvider.repeatMode)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PlaybackSettingsScreen()),
                  );
                },
              ),
            ],
          ),
          _buildSettingsGroup(
            title: 'Network',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.offline_bolt, color: Colors.deepPurple),
                title: const Text('Offline Mode', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Only play downloaded tracks',
                  style: TextStyle(color: Colors.white70),
                ),
                value: musicProvider.isOfflineMode,
                activeColor: Colors.deepPurple,
                onChanged: (value) {
                  if (value) {
                    musicProvider.goOffline();
                  } else {
                    musicProvider.goOnline();
                  }
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.data_saver_off, color: Colors.deepPurple),
                title: const Text('Low Data Mode', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  'Reduce data usage by lowering audio quality',
                  style: TextStyle(color: Colors.white70),
                ),
                value: musicProvider.isLowDataMode,
                activeColor: Colors.deepPurple,
                onChanged: (value) {
                  musicProvider.toggleLowDataMode();
                },
              ),
            ],
          ),
          _buildSettingsGroup(
            title: 'Storage',
            children: [
              ListTile(
                leading: const Icon(Icons.cleaning_services, color: Colors.deepPurple),
                title: const Text('Clear Cache', style: TextStyle(color: Colors.white)),
                onTap: () {
                  musicProvider.clearAllCaches();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cache cleared')),
                  );
                },
              ),
            ],
          ),
          _buildSettingsGroup(
            title: 'About',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.deepPurple),
                title: const Text('App Version', style: TextStyle(color: Colors.white)),
                subtitle: const Text('1.0.0', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.deepPurple,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
        const Divider(color: Colors.grey),
      ],
    );
  }

  String _getRepeatModeText(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.off:
        return 'Off';
      case RepeatMode.all:
        return 'All';
      case RepeatMode.one:
        return 'One';
    }
  }
}
