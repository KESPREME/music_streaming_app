import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/material_you_track_tile.dart';
import '../widgets/material_you_options_sheet.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouRecentlyPlayedScreen extends StatefulWidget {
  const MaterialYouRecentlyPlayedScreen({super.key});

  @override
  State<MaterialYouRecentlyPlayedScreen> createState() => _MaterialYouRecentlyPlayedScreenState();
}

class _MaterialYouRecentlyPlayedScreenState extends State<MaterialYouRecentlyPlayedScreen> {
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
        final recentlyPlayedTracks = musicProvider.recentlyPlayed;

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
                      'Recently Played',
                      style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
                    ),
                  ),
                ),
                if (recentlyPlayedTracks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history_rounded, 
                            size: 80, 
                            color: colorScheme.onSurface.withOpacity(0.1)
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No recently played tracks',
                            style: MaterialYouTypography.titleMedium(
                              colorScheme.onSurface.withOpacity(0.6)
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start listening to build your history!',
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
                        final track = recentlyPlayedTracks[index];
                        final isPlaying = musicProvider.currentTrack?.id == track.id && 
                                         musicProvider.isPlaying;
                        return MaterialYouTrackTile(
                          track: track,
                          isPlaying: isPlaying,
                          isRecentlyPlayedContext: true,
                          onTap: () {
                            musicProvider.playTrack(
                              track,
                              playlistTracks: recentlyPlayedTracks,
                            );
                          },
                          onOptionsPressed: () {
                             showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.transparent,
                                isScrollControlled: true,
                                elevation: 0,
                                builder: (context) => MaterialYouOptionsSheet(track: track),
                              );
                          },
                        );
                      },
                      childCount: recentlyPlayedTracks.length,
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
