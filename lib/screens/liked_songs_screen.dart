import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';

class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final likedSongs = musicProvider.likedSongs;

        return Scaffold(
          extendBodyBehindAppBar: true,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                 colors: isDark 
                  ? [const Color(0xFF121212), const Color(0xFF1E1E1E), const Color(0xFF000000)]
                  : [const Color(0xFFF7F7F7), const Color(0xFFFFFFFF)],
              ),
            ),
            child: SafeArea(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverAppBar(
                    surfaceTintColor: Colors.transparent,
                    backgroundColor: Colors.transparent,
                    floating: true,
                    pinned: true,
                    elevation: 0,
                    expandedHeight: 100,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: isDark ? Colors.white : Colors.black,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    flexibleSpace: ClipRRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: _isScrolled ? 10 : 0,
                          sigmaY: _isScrolled ? 10 : 0,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          color: _isScrolled ? Colors.black.withOpacity(0.5) : Colors.transparent,
                          child: FlexibleSpaceBar(
                            titlePadding: const EdgeInsets.only(left: 50, bottom: 16),
                            title: Text(
                              'Liked Songs',
                              style: GoogleFonts.splineSans(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 20, // Slightly smaller for pinned state app bar
                              ),
                            ),
                            background: Container(color: Colors.transparent),
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      if (likedSongs.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.play_circle_fill_rounded),
                          color: const Color(0xFFFF1744), // Accent color
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
                            musicProvider.shuffleEnabled ? Icons.shuffle_on_rounded : Icons.shuffle_rounded,
                            color: isDark ? Colors.white : Colors.black,
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
                            Icon(Icons.favorite_rounded, size: 80, color: Colors.white.withOpacity(0.1)),
                            const SizedBox(height: 16),
                            Text(
                              'Songs you like will appear here',
                              style: GoogleFonts.splineSans(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 18, 
                                fontWeight: FontWeight.w500
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap the heart icon to save music.',
                              style: GoogleFonts.splineSans(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 14
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
                          final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
                          return TrackTile(
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
                    const SliverPadding(padding: EdgeInsets.only(bottom: 120)), // Bottom padding
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}