import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/material_you_track_tile.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouLikedSongsScreen extends StatefulWidget {
  const MaterialYouLikedSongsScreen({super.key});

  @override
  State<MaterialYouLikedSongsScreen> createState() => _MaterialYouLikedSongsScreenState();
}

class _MaterialYouLikedSongsScreenState extends State<MaterialYouLikedSongsScreen> {
  late ScrollController _scrollController;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final isScrolled = _scrollController.hasClients && _scrollController.offset > 10;
    if (isScrolled != _isScrolled) {
      setState(() {
        _isScrolled = isScrolled;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final likedSongs = musicProvider.likedSongs;

        return Scaffold(
          backgroundColor: MaterialYouTokens.surfaceDark,
          body: SafeArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  backgroundColor: _isScrolled 
                      ? MaterialYouTokens.surfaceContainerDark 
                      : MaterialYouTokens.surfaceDark,
                  surfaceTintColor: Colors.transparent,
                  floating: true,
                  pinned: true,
                  elevation: _isScrolled ? 2 : 0,
                  expandedHeight: 100,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: colorScheme.onSurface,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
                    title: Text(
                      'Liked Songs',
                      style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
                    ),
                  ),
                  actions: [
                    if (likedSongs.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.play_circle_rounded),
                        color: MaterialYouTokens.primaryVibrant,
                        iconSize: 32,
                        tooltip: "Play Liked Songs",
                        onPressed: () {
                          musicProvider.playTrack(
                            likedSongs.first,
                            playlistTracks: likedSongs,
                          );
                        },
                      ),
                    if (likedSongs.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          musicProvider.shuffleEnabled 
                              ? Icons.shuffle_on_rounded 
                              : Icons.shuffle_rounded,
                          color: colorScheme.onSurface,
                        ),
                        tooltip: "Shuffle Liked Songs",
                        onPressed: () {
                          musicProvider.playTrack(
                            likedSongs.first,
                            playlistTracks: likedSongs,
                          );
                          if (!musicProvider.shuffleEnabled) {
                            musicProvider.toggleShuffle();
                          }
                        },
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
                if (likedSongs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.favorite_rounded, 
                            size: 80, 
                            color: colorScheme.onSurface.withOpacity(0.1)
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Songs you like will appear here',
                            style: MaterialYouTypography.titleMedium(
                              colorScheme.onSurface.withOpacity(0.6)
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap the heart icon to save music.',
                            style: MaterialYouTypography.bodyMedium(
                              colorScheme.onSurfaceVariant
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = likedSongs[index];
                        final isPlaying = musicProvider.currentTrack?.id == track.id && 
                                         musicProvider.isPlaying;
                        return MaterialYouTrackTile(
                          track: track,
                          isPlaying: isPlaying,
                          onTap: () {
                            musicProvider.playTrack(
                              track,
                              playlistTracks: likedSongs,
                            );
                          },
                        );
                      },
                      childCount: likedSongs.length,
                    ),
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
              ],
            ),
          ),
        );
      },
    );
  }
}
