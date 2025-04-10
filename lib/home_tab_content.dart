import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../screens/recently_played_screen.dart';
import '../screens/trending_now_screen.dart';

class HomeTabContent extends StatelessWidget {
  const HomeTabContent({super.key});

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _buildTrendingSection(context, musicProvider.trendingTracks),
          const SizedBox(height: 16),
          _buildRecentlyPlayed(context, musicProvider.recentlyPlayed),
        ],
      ),
    );
  }

  Widget _buildTrendingSection(BuildContext context, List<Track> trendingTracks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Trending Now',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TrendingNowScreen(),
                    ),
                  );
                },
                child: const Text(
                  'See All',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: trendingTracks.isEmpty
              ? const Center(
            child: Text(
              'No trending tracks available',
              style: TextStyle(color: Colors.white70),
            ),
          )
              : ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: trendingTracks.length,
            itemBuilder: (context, index) {
              final track = trendingTracks[index];
              return _SongTile(track: track, allowRemove: false);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentlyPlayed(BuildContext context, List<Track> recentlyPlayed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recently Played',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RecentlyPlayedScreen(),
                    ),
                  );
                },
                child: const Text(
                  'See All',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: recentlyPlayed.isEmpty
              ? const Center(
            child: Text(
              'No recently played tracks',
              style: TextStyle(color: Colors.white70),
            ),
          )
              : ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: recentlyPlayed.length,
            itemBuilder: (context, index) {
              final track = recentlyPlayed[index];
              return _SongTile(track: track, allowRemove: true);
            },
          ),
        ),
      ],
    );
  }
}

class _SongTile extends StatefulWidget {
  final Track track;
  final bool allowRemove;

  const _SongTile({required this.track, this.allowRemove = false});

  @override
  _SongTileState createState() => _SongTileState();
}

class _SongTileState extends State<_SongTile> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);

    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: GestureDetector(
        onLongPress: widget.allowRemove
            ? () {
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF1D1D1D),
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.white70),
                    title: const Text(
                      'Remove from Recently Played',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      musicProvider.removeFromRecentlyPlayed(widget.track.id);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Removed from Recently Played')),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        }
            : null,
        child: InkWell(
          onTap: _isLoading
              ? null
              : () async {
            setState(() {
              _isLoading = true;
            });
            try {
              await musicProvider.playTrack(widget.track);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error playing track: $e')),
                );
              }
            } finally {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade700, width: 1),
                      image: DecorationImage(
                        image: NetworkImage(widget.track.albumArtUrl),
                        fit: BoxFit.cover,
                        onError: (exception, stackTrace) => const Image(
                          image: NetworkImage('https://via.placeholder.com/50'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        musicProvider.isSongLiked(widget.track.id) ? Icons.favorite : Icons.favorite_border,
                        color: musicProvider.isSongLiked(widget.track.id) ? Colors.red : Colors.white70,
                        size: 20,
                      ),
                      onPressed: () {
                        if (musicProvider.isSongLiked(widget.track.id)) {
                          musicProvider.unlikeSong(widget.track.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Removed from Liked Songs')),
                          );
                        } else {
                          musicProvider.likeSong(widget.track);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Added to Liked Songs')),
                          );
                        }
                      },
                    ),
                  ),
                  if (_isLoading)
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 120,
                child: Text(
                  widget.track.trackName,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}