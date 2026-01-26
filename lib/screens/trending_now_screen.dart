import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';
import '../models/track.dart';

class TrendingNowScreen extends StatelessWidget {
  const TrendingNowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final musicProvider = Provider.of<MusicProvider>(context);
    final List<Track> trendingTracks = musicProvider.fullTrendingTracks;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
              ? [const Color(0xFF141414), const Color(0xFF1E1E1E), const Color(0xFF000000)]
              : [const Color(0xFFF7F7F7), const Color(0xFFFFFFFF)],
          ),
        ),
        child: RefreshIndicator(
          color: const Color(0xFFFF1744),
          backgroundColor: const Color(0xFF1E1E1E),
          onRefresh: () => musicProvider.fetchTrendingTracks(forceRefresh: true),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildLiquidAppBar(context, isDark),
              
              if (trendingTracks.isEmpty)
                 SliverFillRemaining(
                  child: Center(
                    child: musicProvider.errorMessage != null && musicProvider.errorMessage!.toLowerCase().contains("trending")
                    ? Text('Could not load trending tracks', style: GoogleFonts.splineSans(color: Colors.white54))
                    : (musicProvider.tracks.isEmpty && !musicProvider.isLoadingLocal)
                        ? Text('No trending tracks available', style: GoogleFonts.splineSans(color: Colors.white54))
                        : const CircularProgressIndicator(color: Color(0xFFFF1744)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = trendingTracks[index];
                        final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildLiquidTrackTile(context, track, isPlaying, () {
                            musicProvider.playTrack(track, playlistTracks: trendingTracks);
                          }),
                        );
                      },
                      childCount: trendingTracks.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiquidAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      pinned: true,
      expandedHeight: 120,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final double percentage = ((constraints.maxHeight - kToolbarHeight) / (120 - kToolbarHeight)).clamp(0.0, 1.0);
          final double blur = (1 - percentage) * 15;
          final double overlayOpacity = (1 - percentage) * 0.5;

          return ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
                title: Text(
                  'Trending Now',
                  style: GoogleFonts.splineSans(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontSize: 20 + (8 * percentage),
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.transparent),
                    Container(color: Colors.black.withOpacity(overlayOpacity)),
                    if (percentage < 0.05)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(height: 1, color: Colors.white.withOpacity(0.1)),
                      ),
                  ],
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildLiquidTrackTile(BuildContext context, Track track, bool isPlaying, VoidCallback onTap) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: TrackTile(
            track: track,
            isPlaying: isPlaying,
            onTap: onTap,
            backgroundColor: Colors.transparent, // Ensure tile has transparent bg
          ),
        ),
      ),
    );
  }
}