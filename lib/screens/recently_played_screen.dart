import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';
import '../widgets/global_music_overlay.dart';

class RecentlyPlayedScreen extends StatefulWidget {
  const RecentlyPlayedScreen({super.key});

  @override
  State<RecentlyPlayedScreen> createState() => _RecentlyPlayedScreenState();
}

class _RecentlyPlayedScreenState extends State<RecentlyPlayedScreen> {
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
        final recentlyPlayedTracks = musicProvider.recentlyPlayed;

        return PlayerAwarePopScope(
          child: Scaffold(
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
                              'Recently Played',
                              style: GoogleFonts.splineSans(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 20,
                              ),
                            ),
                            background: Container(color: Colors.transparent),
                          ),
                        ),
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
                            Icon(Icons.history_rounded, size: 80, color: Colors.white.withOpacity(0.1)),
                            const SizedBox(height: 16),
                            Text(
                              'No recently played tracks',
                              style: GoogleFonts.splineSans(
                                color: Colors.white.withOpacity(0.6), 
                                fontSize: 18,
                                fontWeight: FontWeight.w500
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start listening to build your history!',
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
                          final track = recentlyPlayedTracks[index];
                          final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
                          return TrackTile(
                            track: track,
                            isPlaying: isPlaying,
                            isRecentlyPlayedContext: true,
                            onTap: () {
                              musicProvider.playTrack(
                                track,
                                playlistTracks: recentlyPlayedTracks,
                              );
                            },
                          );
                        },
                        childCount: recentlyPlayedTracks.length,
                      ),
                    ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 120)), // Bottom padding
                ],
              ),
            ),
            ),
          ),
        );
      },
    );
  }
}