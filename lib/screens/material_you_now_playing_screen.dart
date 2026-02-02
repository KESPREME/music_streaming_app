import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../widgets/material_you_options_sheet.dart';
import '../widgets/artist_picker_sheet.dart';
import '../widgets/material_you_wavy_progress_bar.dart';
import '../widgets/themed_queue_screen.dart';
import '../widgets/themed_lyrics_screen.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

/// Material You (Material 3) Now Playing Screen
/// Flat design with NO blur globs, NO gradients - clean Material 3 surfaces
class MaterialYouNowPlayingScreen extends StatelessWidget {
  final Track track;
  final VoidCallback? onMinimize;

  const MaterialYouNowPlayingScreen({
    required this.track,
    this.onMinimize,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final currentTrack = musicProvider.currentTrack ?? track;
        final colorScheme = Theme.of(context).colorScheme;
        final accentColor = MaterialYouTokens.primaryVibrant; // Light blue accent
        final isPlaying = musicProvider.isPlaying;

        // Extract dynamic color if available
        final palette = musicProvider.paletteGenerator;
        final dominantColor = palette?.dominantColor?.color ?? MaterialYouTokens.surfaceDark;
        final vibrantColor = palette?.vibrantColor?.color ?? MaterialYouTokens.primaryVibrant;

        return Scaffold(
          backgroundColor: MaterialYouTokens.surfaceDark, // Fallback
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  dominantColor.withOpacity(0.6),
                  MaterialYouTokens.surfaceDark,
                  MaterialYouTokens.surfaceDark,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                 // Optional: Add drag-to-dismiss visual feedback here
              },
              onVerticalDragEnd: (details) {
                // Lower threshold for easier dismissal
                if (details.primaryVelocity! > 300) { 
                   if (onMinimize != null) {
                     onMinimize!();
                   } else if (Navigator.canPop(context)) {
                     Navigator.pop(context);
                   }
                }
              },
              child: SafeArea(
                child: Column(
                  children: [
                    // Header
                    _buildHeader(context, currentTrack, musicProvider, colorScheme),
                    
                    // Body (Art + Controls)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildAlbumArt(currentTrack, colorScheme),
                            const SizedBox(height: 24),
                            _buildNowPlayingInfo(context, currentTrack, musicProvider, vibrantColor, colorScheme),
                            
                            // Wavy Progress Bar
                            MaterialYouWavyProgressBar(
                              provider: musicProvider,
                              accentColor: vibrantColor,
                            ),
    
                            _buildPlayerControls(context, musicProvider, isPlaying, vibrantColor, colorScheme),
                            _buildFooterActions(context, musicProvider, vibrantColor, colorScheme),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, Track track, MusicProvider provider, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Material(
            elevation: 1,
            surfaceTintColor: Colors.transparent, // FIX: No white tint
            color: colorScheme.surfaceContainerHighest ?? colorScheme.surfaceVariant,
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: () {
                if (onMinimize != null) {
                  onMinimize!();
                } else {
                  if (Navigator.canPop(context)) Navigator.pop(context);
                }
              },
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: colorScheme.onSurface, size: 32),
            ),
          ),
          
          Text(
            'NOW PLAYING',
            style: GoogleFonts.plusJakartaSans(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          
          Row(
            children: [
              Material(
                elevation: 1,
                surfaceTintColor: Colors.transparent, // FIX: No white tint
                color: colorScheme.surfaceContainerHighest ?? colorScheme.surfaceVariant,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const ThemedLyricsScreen(),
                    );
                  },
                  icon: Icon(Icons.lyrics_rounded, color: colorScheme.onSurface, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Material(
                elevation: 1,
                surfaceTintColor: Colors.transparent, // FIX: No white tint
                color: colorScheme.surfaceContainerHighest ?? colorScheme.surfaceVariant,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => _showOptionsBottomSheet(context, track, provider),
                  icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurface, size: 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(Track track, ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 80% of screen width (increased from 70%)
        final size = MediaQuery.of(context).size.width * 0.80;
        return Center(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              // Add subtle colored glow around album art
              boxShadow: [
                BoxShadow(
                  color: MaterialYouTokens.primaryVibrant.withOpacity(0.15), // Reduced opacity for subtler glow
                  blurRadius: 40,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Material(
              elevation: 0, // Remove default elevation to prevent white shadow artifacts
              color: Colors.transparent, // Completely transparent material
              borderRadius: BorderRadius.circular(24), // Larger corners (24dp vs 16dp)
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Hero(
                  tag: 'albumArt_${track.id}',
                  child: track.albumArtUrl.isNotEmpty
                      ? (File(track.albumArtUrl).existsSync() 
                          ? Image.file(File(track.albumArtUrl), fit: BoxFit.cover)
                          : Image.network(track.albumArtUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => _buildArtPlaceholder(colorScheme)))
                      : _buildArtPlaceholder(colorScheme),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNowPlayingInfo(BuildContext context, Track track, MusicProvider provider, Color accentColor, ColorScheme colorScheme) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Track Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.trackName,
                    style: GoogleFonts.plusJakartaSans(
                      color: colorScheme.onSurface,
                      fontSize: 28, // Increased from 24sp to 28sp
                      fontWeight: FontWeight.w800, // Bolder (800 vs 700)
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 2, // Allow 2 lines for longer titles
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8), // Increased spacing
                  GestureDetector(
                    onTap: () => _navigateToArtist(context, track.artistName, provider),
                    child: Text(
                      track.artistName,
                      style: GoogleFonts.plusJakartaSans(
                        color: accentColor, // Dynamic palette color
                        fontSize: 18, 
                        fontWeight: FontWeight.w600, 
                        decoration: TextDecoration.underline,
                        decorationColor: accentColor.withOpacity(0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            
            // Actions: Download & Like
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Download Button
                FutureBuilder<bool>(
                  future: provider.isTrackDownloaded(track.id),
                  builder: (context, snapshot) {
                    final isDownloaded = snapshot.data ?? false;
                    final isDownloading = provider.isDownloading[track.id] ?? false;

                    if (isDownloading) {
                      return Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 24, 
                          height: 24, 
                          child: CircularProgressIndicator(strokeWidth: 2, color: accentColor)
                        ),
                      );
                    }

                    return IconButton(
                      onPressed: () async {
                        if (!isDownloaded) {
                          await provider.downloadTrack(track);
                        }
                      },
                      icon: Icon(
                        isDownloaded ? Icons.download_done_rounded : Icons.download_rounded,
                        color: isDownloaded ? accentColor : colorScheme.onSurfaceVariant,
                        size: 28,
                      ),
                    );
                  },
                ),

                // Like Button
                Material(
                  elevation: 2,
                  surfaceTintColor: Colors.transparent, // FIX: No white tint
                  color: provider.isSongLiked(track.id) 
                      ? accentColor.withOpacity(0.2) 
                      : colorScheme.surfaceContainerHighest ?? colorScheme.surfaceVariant,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () => provider.toggleLike(track),
                    icon: Icon(
                      provider.isSongLiked(track.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: provider.isSongLiked(track.id) ? accentColor : colorScheme.onSurface,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildPlayerControls(BuildContext context, MusicProvider provider, bool isPlaying, Color accentColor, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Shuffle
        IconButton(
          onPressed: provider.toggleShuffle,
          icon: Icon(Icons.shuffle_rounded, 
            color: provider.shuffleEnabled ? accentColor : colorScheme.onSurfaceVariant, 
            size: 26
          ),
        ),
        
        // Previous
        _buildControlButton(
          icon: Icons.skip_previous_rounded,
          onTap: provider.skipToPrevious,
          colorScheme: colorScheme,
        ),

        // Play/Pause FAB - Large and prominent
        Material(
          elevation: 6, // Increased elevation for prominence
          surfaceTintColor: Colors.transparent, // FIX: No white tint
          color: accentColor,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: () {
              if (provider.isPlaying) {
                provider.pauseTrack();
              } else {
                provider.resumeTrack();
              }
            },
            customBorder: const CircleBorder(),
            child: Container(
              height: 72, // Increased from 64dp to 72dp for more prominence
              width: 72,
              alignment: Alignment.center,
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 40, // Increased icon size from 32 to 40
              ),
            ),
          ),
        ),

        // Next
        _buildControlButton(
          icon: Icons.skip_next_rounded,
          onTap: provider.skipToNext,
          colorScheme: colorScheme,
        ),

        // Repeat
        IconButton(
          onPressed: provider.cycleRepeatMode,
          icon: Icon(
            provider.repeatMode == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            color: provider.repeatMode != RepeatMode.off ? accentColor : colorScheme.onSurfaceVariant,
            size: 24,
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return Material(
      elevation: 1,
      surfaceTintColor: Colors.transparent, // FIX: No white tint
      color: colorScheme.surfaceContainerHighest ?? colorScheme.surfaceVariant,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          height: 48,
          width: 48,
          alignment: Alignment.center,
          child: Icon(icon, color: colorScheme.onSurface, size: 26),
        ),
      ),
    );
  }

  Widget _buildFooterActions(BuildContext context, MusicProvider provider, Color accentColor, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: () => _showCastDevicesSheet(context, provider, accentColor, colorScheme),
            icon: Icon(
              provider.isCasting ? Icons.cast_connected_rounded : Icons.cast_rounded,
              color: provider.isCasting ? accentColor : colorScheme.onSurfaceVariant,
              size: 20
            ),
            label: Text(
              provider.isCasting ? 'Casting' : 'Devices',
              style: GoogleFonts.plusJakartaSans(
                color: provider.isCasting ? accentColor : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ThemedQueueScreen()),
              );
            },
            icon: Icon(Icons.playlist_play_rounded, color: colorScheme.onSurfaceVariant, size: 20),
            label: Text(
              'Up Next',
              style: GoogleFonts.plusJakartaSans(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToArtist(BuildContext context, String artistString, MusicProvider provider) async {
    // Handle multiple artists using robust parsing
    final artists = ArtistPickerSheet.parseArtists(artistString);
    
    if (artists.isEmpty) return;
    
    if (artists.length == 1) {
      // Single artist - navigate directly
      await _performArtistNavigation(context, provider, artists[0]);
    } else {
      // Multiple artists - show picker sheet
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final colorScheme = Theme.of(context).colorScheme;
          return Container(
            decoration: BoxDecoration(
              color: MaterialYouTokens.surfaceContainerDark,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: Text(
                      'Select Artist',
                      style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
                    ),
                  ),
                  
                  // Divider
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant,
                  ),
                  
                  // Artist list
                  ...artists.map((artist) {
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _performArtistNavigation(context, provider, artist);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: MaterialYouTokens.primaryVibrant.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.person_rounded,
                                  color: MaterialYouTokens.primaryVibrant,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  artist,
                                  style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      );
    }
  }
  
  Future<void> _performArtistNavigation(BuildContext context, MusicProvider provider, String artistName) async {
    // Show loading snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loading $artistName...'),
        backgroundColor: MaterialYouTokens.primaryVibrant,
        duration: const Duration(milliseconds: 500),
      ),
    );
    
    await provider.navigateToArtist(artistName);
    
    if (context.mounted && provider.currentArtistDetails != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ThemedArtistDetailScreen(
            artistId: provider.currentArtistDetails!.id,
            artistName: artistName,
            searchByName: false,
          ),
        ),
      );
    }
  }

  void _showCastDevicesSheet(BuildContext context, MusicProvider provider, Color accentColor, ColorScheme colorScheme) {
    provider.startCastingDiscovery();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: MaterialYouTokens.surfaceContainerDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: SizedBox(
              height: 400,
              child: Column(
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Connect to a Device',
                          style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
                        ),
                        if (provider.isCasting)
                          TextButton(
                            onPressed: () {
                              provider.disconnectCastDevice();
                              Navigator.pop(context);
                            },
                            child: Text(
                              'Disconnect',
                              style: MaterialYouTypography.labelLarge(Colors.redAccent),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Divider
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant,
                  ),
                  
                  const SizedBox(height: 10),
                  
                  // Loading indicator
                  if (provider.isSearchingDevices && provider.castDevices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(color: accentColor),
                    ),
                  
                  // Device list
                  Expanded(
                    child: Consumer<MusicProvider>(
                      builder: (context, provider, _) {
                        if (provider.castDevices.isEmpty && !provider.isSearchingDevices) {
                          return Center(
                            child: Text(
                              'No devices found',
                              style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
                            ),
                          );
                        }
                        
                        return ListView.builder(
                          itemCount: provider.castDevices.length,
                          itemBuilder: (context, index) {
                            final device = provider.castDevices[index];
                            final isConnected = provider.castService.connectedDevice?.host == device.host;
                            
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  provider.connectToCastDevice(device);
                                  Navigator.pop(context);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: isConnected 
                                              ? accentColor.withOpacity(0.15)
                                              : colorScheme.surfaceContainerHighest,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.tv_rounded,
                                          color: isConnected ? accentColor : colorScheme.onSurface,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          device.name,
                                          style: MaterialYouTypography.bodyLarge(
                                            isConnected ? accentColor : colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      if (isConnected)
                                        Icon(
                                          Icons.check_rounded,
                                          color: accentColor,
                                          size: 24,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      provider.stopCastingDiscovery();
    });
  }

  void _showOptionsBottomSheet(BuildContext context, Track track, MusicProvider musicProvider) {
    // FIX 5: Hide mini player when showing options sheet
    // FIX 5: Hide mini player when showing options sheet
    MaterialYouOptionsSheet.show(context, track: track);
  }

  Widget _buildArtPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceVariant,
      child: Icon(
        Icons.music_note_rounded,
        size: 80,
        color: colorScheme.onSurfaceVariant.withOpacity(0.3),
      ),
    );
  }
}
