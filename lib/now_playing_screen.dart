import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:palette_generator/palette_generator.dart';
import 'dart:math' as math;

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../widgets/playlist_selection_dialog.dart';
import '../screens/playlist_detail_screen.dart'; // Unified for Album View
import '../screens/artist_detail_screen.dart'; // Unified Screen
import '../screens/queue_screen.dart';
import '../screens/lyrics_screen.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/artist_picker_sheet.dart'; // Multi-artist selection

import '../widgets/wavy_progress_bar.dart'; // Import shared widget
import '../main.dart'; // Import rootNavigatorKey
import '../utils/color_utils.dart';
import '../screens/equalizer_screen.dart'; // Equalizer

class NowPlayingScreen extends StatefulWidget {
  final Track track;
  final VoidCallback? onMinimize;

  const NowPlayingScreen({required this.track, this.onMinimize, super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  // Colors from the design (Default Fallbacks)
  static const Color _defaultPrimaryColor = Color(0xFF6200EE);

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final currentTrack = musicProvider.currentTrack ?? widget.track;
        
        // Colors from Provider Palette
        final palette = musicProvider.paletteGenerator;
        final bgColors = ColorUtils.getLiquidBgColors(palette);
        final accentColor = ColorUtils.getVibrantAccent(palette, _defaultPrimaryColor);

        final isPlaying = musicProvider.isPlaying;

        // If onMinimize is provided, we assume we are managed by a parent stack (MainScreen), 
        // effectively disabling the PopScope's ability to block system back unless we handle it upstream.
        // For now, allowPop is true to let system back work if not managed.
        return Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: const Color(0xFF121212), // Fallback dark
            body: Stack(
              children: [
                // 1. Immersive Gradient Background
                AnimatedContainer(
                  duration: const Duration(seconds: 1),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: bgColors,
                       stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                ),
                
                // 2. Blurred Ambient Globs
                _buildAmbientGlows(bgColors, accentColor),

                // 3. Main Content
                SafeArea(
                  child: Column(
                    children: [
                      // Header
                      _buildHeader(context, currentTrack, musicProvider),
                      
                      // Body (Art + Controls)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildAlbumArt(currentTrack),
                              const SizedBox(height: 24),
                              _buildNowPlayingInfo(context, currentTrack, musicProvider, accentColor),
                              
                              // Wavy Progress Bar
                              WavyProgressBar(
                                provider: musicProvider,
                                accentColor: accentColor,
                              ),

                              _buildPlayerControls(context, musicProvider, isPlaying, accentColor),
                              _buildFooterActions(context, musicProvider, accentColor),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          );
      },
    );
  }

  Widget _buildAmbientGlows(List<Color> colors, Color accent) {
    // Generate derived harmonized colors for the "liquid" feel
    final highlight = ColorUtils.boostColor(accent, hueShift: 30, saturation: 0.2);
    final secondary = ColorUtils.boostColor(colors[0], hueShift: -20, saturation: 0.1);

    return Stack(
      children: [
        // Top Left Glob
        Positioned(
          top: -150,
          left: -100,
          child: _LiquidGlob(
            color: colors[0].withOpacity(0.4),
            size: 450,
            duration: 15.seconds,
          ),
        ),
        
        // Bottom Right Glob
        Positioned(
          bottom: -150,
          right: -100,
          child: _LiquidGlob(
            color: highlight?.withOpacity(0.2) ?? accent.withOpacity(0.2),
            size: 500,
            duration: 20.seconds,
          ),
        ),

        // Center Floating Glob (Subtle)
        Center(
          child: _LiquidGlob(
            color: secondary?.withOpacity(0.1) ?? colors[1].withOpacity(0.1),
            size: 600,
            duration: 25.seconds,
          ),
        ),

        // Deep Blur Layer
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
          child: Container(color: Colors.transparent),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, Track track, MusicProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () {
              if (widget.onMinimize != null) {
                widget.onMinimize!();
              } else {
                if (Navigator.canPop(context)) Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              padding: const EdgeInsets.all(8),
            ),
          ),
          
          Text(
            'NOW PLAYING',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          
          Row(
            children: [
              IconButton(
                onPressed: () {
                   showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const LyricsScreen(),
                  );
                },
                icon: const Icon(Icons.lyrics_rounded, color: Colors.white, size: 24),
                style: IconButton.styleFrom(
                   backgroundColor: Colors.white.withOpacity(0.1),
                   padding: const EdgeInsets.all(8),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => _showOptionsBottomSheet(context, track, provider),
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 24),
                 style: IconButton.styleFrom(
                   backgroundColor: Colors.white.withOpacity(0.1),
                   padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(Track track) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
             BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Hero(
            tag: 'albumArt_${track.id}',
            child: track.albumArtUrl.isNotEmpty
                ? (File(track.albumArtUrl).existsSync() 
                    ? Image.file(File(track.albumArtUrl), fit: BoxFit.cover)
                    : Image.network(track.albumArtUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => _buildArtPlaceholder()))
                : _buildArtPlaceholder(),
          ),
        ),
      ),
    );
  }

  Widget _buildNowPlayingInfo(BuildContext context, Track track, MusicProvider provider, Color accentColor) {
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
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // FIX: Make artist name tappable to navigate to artist
                  GestureDetector(
                    onTap: () async {
                      if (track.artistName.isNotEmpty && track.artistName != 'Unknown Artist') {
                        await ArtistPickerSheet.showIfNeeded(context, provider, track.artistName);
                      }
                    },
                    child: Text(
                      track.artistName,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white.withOpacity(0.3),
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
                        if (isDownloaded) {
                           showGlassSnackBar(context, 'Track already downloaded');
                        } else {
                          await provider.downloadTrack(track);
                        }
                      },
                      icon: Icon(
                        isDownloaded ? Icons.download_done_rounded : Icons.download_rounded,
                        color: isDownloaded ? accentColor : Colors.white.withOpacity(0.6),
                        size: 28,
                      ),
                    );
                  },
                ),

                // Like Button (Refined Liquid Glass)
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.25),
                            Colors.white.withOpacity(0.05),
                          ],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: () => provider.toggleLike(track),
                        icon: Icon(
                          provider.isSongLiked(track.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: provider.isSongLiked(track.id) ? accentColor.withOpacity(0.9) : Colors.white.withOpacity(0.9),
                          size: 28, 
                        ),
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
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

  // --- REPLACED: Simple ProgressBar with WavyProgressBar (Below) ---
  
  Widget _buildPlayerControls(BuildContext context, MusicProvider provider, bool isPlaying, Color accentColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Shuffle
        IconButton(
          onPressed: provider.toggleShuffle,
          icon: Icon(Icons.shuffle_rounded, 
            color: provider.shuffleEnabled ? accentColor : Colors.white.withOpacity(0.6), 
            size: 26
          ),
        ),
        
        // Previous
        _buildGlassActionButton(
          icon: Icons.skip_previous_rounded,
          onTap: provider.skipToPrevious,
        ),

        // Play/Pause FAB
        // Play/Pause FAB (Refined Liquid Glass - Slightly Smaller)
        ClipRRect(
          borderRadius: BorderRadius.circular(35), // Adjusted radius
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), // Slightly reduced blur for sharpness
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 64, // Reduced from 72
              width: 64,  // Reduced from 72
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accentColor.withOpacity(0.5),
                    accentColor.withOpacity(0.2),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.2), // Thinner border
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: -5,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () {
                   if (provider.isPlaying) {
                     provider.pauseTrack();
                   } else {
                     provider.resumeTrack();
                   }
                },
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white.withOpacity(0.95),
                  size: 32, // Reduced from 36
                ),
              ),
            ),
          ),
        ),

        // Next
        _buildGlassActionButton(
          icon: Icons.skip_next_rounded,
          onTap: provider.skipToNext,
        ),

        // Repeat
        IconButton(
          onPressed: provider.cycleRepeatMode,
          icon: Icon(
            provider.repeatMode == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
             color: provider.repeatMode != RepeatMode.off ? accentColor : Colors.white.withOpacity(0.6),
             size: 24, // Slightly smaller Icon
            ),
        ),
      ],
    );
  }

  Widget _buildGlassActionButton({required IconData icon, required VoidCallback onTap}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24), // Adjusted radius
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 48, // Reduced from 56
          width: 48,  // Reduced from 56
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.12), // Slightly more transparent
                Colors.white.withOpacity(0.04),
              ],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.8), // Thinner border
          ),
          child: IconButton(
            onPressed: onTap,
            icon: Icon(icon, color: Colors.white, size: 26), // Reduced from 30
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  Widget _buildFooterActions(BuildContext context, MusicProvider provider, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
           TextButton.icon(
            onPressed: () {
               _showDevicesSheet(context, provider, accentColor);
            },
            icon: Icon(
              provider.isCasting ? Icons.cast_connected_rounded : Icons.cast_rounded,
               color: provider.isCasting ? accentColor : Colors.white60,
               size: 20
            ),
            label: Text(
              provider.isCasting ? 'Casting' : 'Devices',
              style: GoogleFonts.plusJakartaSans(
                color: provider.isCasting ? accentColor : Colors.white60,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.push(
               context,
               MaterialPageRoute(builder: (context) => const QueueScreen()),
             );
            },
            icon: const Icon(Icons.playlist_play_rounded, color: Colors.white60, size: 20),
            label: Text(
              'Up Next',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white60,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showOptionsBottomSheet(BuildContext context, Track track, MusicProvider musicProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Transparent for glass effect
      isScrollControlled: true, // Allow custom height/styling
      elevation: 0,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withOpacity(0.7), // Semi-transparent
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1), // Glass edge
          boxShadow: [
             BoxShadow(
               color: Colors.black.withOpacity(0.3),
               blurRadius: 20,
               offset: const Offset(0, -5),
             ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), // Liquid blur effect
            child: SafeArea(
              child: Wrap(
                children: [
                    // Handle Bar for visual affordance
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                   _buildOptionTile(
                    icon: Icons.playlist_add_rounded,
                    title: 'Add to Playlist',
                    onTap: () {
                      Navigator.pop(context);
                      showPlaylistSelectionDialog(context, track);
                    }
                   ),
                   _buildOptionTile(
                     icon: Icons.share_rounded, 
                     title: 'Share', 
                     onTap: () async {
                        Navigator.pop(context);
                        String shareText = 'Listening to: ${track.trackName} by ${track.artistName}';
                        await Share.share(shareText);
                     }
                   ),
                   _buildOptionTile(
                     icon: Icons.album_rounded, 
                     title: 'Go to Album', 
                     onTap: () {
                       Navigator.pop(context); // Close sheet
                       
                       // Minimize Player First
                       if (widget.onMinimize != null) widget.onMinimize!();

                       // Navigate immediately - PlaylistDetailScreen will fetch data
                       // FIX: No await, single tap navigation
                       final albumName = track.albumName.isNotEmpty ? track.albumName : track.trackName;
                       rootNavigatorKey.currentState?.push(MaterialPageRoute(
                         builder: (_) => PlaylistDetailScreen(
                           playlistId: '', // Will search by name
                           playlistName: albumName,
                           playlistImage: track.albumArtUrl,
                           searchAlbumByName: true, // New flag to indicate search-by-name mode
                           artistNameHint: track.artistName,
                         ),
                       ));
                     }
                   ),
                    _buildOptionTile(
                     icon: Icons.person_rounded, 
                     title: 'Go to Artist', 
                     onTap: () async {
                       Navigator.pop(context); // Close sheet
                       
                       // Minimize Player First
                       if (widget.onMinimize != null) widget.onMinimize!();

                       // FIX: Use the static method which handles mini player hiding
                       final musicProvider = Provider.of<MusicProvider>(context, listen: false);
                       if (rootNavigatorKey.currentContext != null) {
                         await ArtistPickerSheet.showIfNeeded(
                           rootNavigatorKey.currentContext!,
                           musicProvider,
                           track.artistName,
                         );
                       }
                     }
                   ),
                   _buildOptionTile(
                     icon: Icons.graphic_eq_rounded, 
                     title: 'Equalizer', 
                     onTap: () async {
                       Navigator.pop(context); // Close the menu sheet
                       
                       // Small delay to let sheet close, then navigate
                       await Future.delayed(const Duration(milliseconds: 100));
                       
                       // FIX: Push to local navigator (not root) for proper back handling
                       if (context.mounted) {
                         Navigator.of(context, rootNavigator: false).push(
                           MaterialPageRoute(builder: (_) => const EqualizerScreen()),
                         );
                       }
                     }
                   ),
                   _buildOptionTile(
                     icon: Icons.timer_rounded, 
                     title: 'Sleep Timer', 
                     onTap: () {
                       Navigator.pop(context);
                       _showSleepTimerDialog(context, musicProvider);
                     }
                   ),
                   const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({required IconData icon, required String title, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }

  void _showSleepTimerDialog(BuildContext context, MusicProvider musicProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withOpacity(0.7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            boxShadow: [
               BoxShadow(
                 color: Colors.black.withOpacity(0.3),
                 blurRadius: 20,
                 offset: const Offset(0, -5),
               ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
               filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
               child: SafeArea(
                 child: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          "Sleep Timer", 
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white, 
                            fontSize: 18, 
                            fontWeight: FontWeight.bold
                          )
                        ),
                      ),
                      _buildTimerOption(context, musicProvider, '15 Minutes', 15),
                      _buildTimerOption(context, musicProvider, '30 Minutes', 30),
                      _buildTimerOption(context, musicProvider, '1 Hour', 60),
                      _buildTimerOption(context, musicProvider, 'End of Track', 0), // 0 means end of track
                      const SizedBox(height: 20),
                   ],
                 ),
               ),
            ),
          ),
        );
      },
    );
  }

  void _showDevicesSheet(BuildContext context, MusicProvider provider, Color accentColor) {
    provider.startCastingDiscovery();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withOpacity(0.7), // Semi-transparent
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
             border: Border.all(color: Colors.white.withOpacity(0.1), width: 1), // Glass edge
             boxShadow: [
               BoxShadow(
                 color: Colors.black.withOpacity(0.3),
                 blurRadius: 20,
                 offset: const Offset(0, -5),
               ),
             ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
               filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), // Liquid blur effect
               child: Container(
                 height: 400,
                 child: Column(
                   children: [
                      Container(
                       margin: const EdgeInsets.only(top: 12, bottom: 20),
                       width: 40,
                       height: 4,
                       decoration: BoxDecoration(
                         color: Colors.white.withOpacity(0.2),
                         borderRadius: BorderRadius.circular(2),
                       ),
                     ),
                     Padding(
                       padding: const EdgeInsets.symmetric(horizontal: 24.0),
                       child: Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                           Text('Connect to a Device', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                           if (provider.isCasting)
                              TextButton(
                                onPressed: () {
                                  provider.disconnectCastDevice();
                                  Navigator.pop(context);
                                },
                                child: Text('Disconnect', style: GoogleFonts.plusJakartaSans(color: Colors.redAccent)),
                              )
                         ],
                       ),
                     ),
                     const SizedBox(height: 10),
                     if (provider.isSearchingDevices && provider.castDevices.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20.0),
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                     
                     Expanded(
                       child: Consumer<MusicProvider>(
                         builder: (context, provider, _) { 
                           if (provider.castDevices.isEmpty && !provider.isSearchingDevices) {
                             return Center(child: Text("No devices found", style: GoogleFonts.plusJakartaSans(color: Colors.white60)));
                           }
                           return ListView.builder(
                           itemCount: provider.castDevices.length,
                           itemBuilder: (context, index) {
                             final device = provider.castDevices[index];
                             final isConnected = provider.castService.connectedDevice?.host == device.host;
                             
                             return ListTile(
                               leading: Icon(Icons.tv_rounded, color: isConnected ? accentColor : Colors.white),
                               title: Text(device.name, style: GoogleFonts.plusJakartaSans(color: isConnected ? accentColor : Colors.white)),
                               trailing: isConnected ? Icon(Icons.check_rounded, color: accentColor) : null,
                               onTap: () {
                                 provider.connectToCastDevice(device);
                                 Navigator.pop(context);
                               },
                             );
                           },
                         );
                         }
                       ),
                     ),
                   ],
                 ),
               ),
            ),
          ),
        );
      }
    ).whenComplete(() {
      provider.stopCastingDiscovery();
    });
  }

  Widget _buildTimerOption(BuildContext context, MusicProvider provider, String title, int minutes) {
    return ListTile(
      title: Text(title, style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
      onTap: () {
        provider.setSleepTimer(minutes);
        Navigator.pop(context);
      },
    );
  }

  // --- UI Helpers ---

  Color middleColorForPalette(PaletteGenerator palette) {
    final darkMuted = palette.darkMutedColor?.color;
    final muted = palette.mutedColor?.color;
    final dominant = palette.dominantColor?.color;

    return darkMuted?.withOpacity(0.5) ?? 
           muted?.withOpacity(0.3) ?? 
           dominant?.withOpacity(0.2) ?? 
           const Color(0xFF020617);
  }

  Widget _buildArtPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: const Icon(Icons.music_note_rounded, size: 80, color: Colors.white24),
    );
  }
}

/// A custom widget that renders a slow-moving, liquid-like glob.
class _LiquidGlob extends StatefulWidget {
  final Color color;
  final double size;
  final Duration duration;

  const _LiquidGlob({required this.color, required this.size, required this.duration});

  @override
  State<_LiquidGlob> createState() => _LiquidGlobState();
}

class _LiquidGlobState extends State<_LiquidGlob> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.9, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine)
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              widget.color,
              widget.color.withOpacity(0),
            ],
          ),
        ),
      ),
    );
  }
}


