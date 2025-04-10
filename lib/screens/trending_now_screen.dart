import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';

class TrendingNowScreen extends StatelessWidget {
  const TrendingNowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D1D1D),
        title: const Text(
          'Trending Now',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: musicProvider.fullTrendingTracks.isEmpty
          ? const Center(
        child: Text(
          'No trending tracks available',
          style: TextStyle(color: Colors.white70, fontSize: 18),
        ),
      )
          : ListView.builder(
        itemCount: musicProvider.fullTrendingTracks.length,
        itemBuilder: (context, index) {
          final track = musicProvider.fullTrendingTracks[index];
          return TrackTile(track: track);
        },
      ),
    );
  }
}