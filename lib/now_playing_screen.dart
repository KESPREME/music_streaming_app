import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
// import 'package:palette_generator/palette_generator.dart'; // Removed: Handled by Provider
import 'dart:math' as math;

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../widgets/playlist_selection_dialog.dart';
import '../screens/album_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/queue_screen.dart';
import '../screens/lyrics_screen.dart';

class NowPlayingScreen extends StatefulWidget {
  final Track track;

  const NowPlayingScreen({required this.track, super.key});

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
        
        List<Color> bgColors = [
           const Color(0xFF1E1B4B), // Top default
           const Color(0xFF111827), // Mid default
           const Color(0xFF0A0A0A), // Bot default
        ];
        Color accentColor = _defaultPrimaryColor;

        if (palette != null) {
            final darkVibrant = palette.darkVibrantColor?.color;
            final vibrant = palette.vibrantColor?.color;
            final muted = palette.mutedColor?.color;
            final darkMuted = palette.darkMutedColor?.color;
            final dominant = palette.dominantColor?.color;

            final topColor = darkVibrant ?? darkMuted ?? dominant ?? const Color(0xFF1E1B4B);
            final middleColor = vibrant?.withOpacity(0.4) ?? muted?.withOpacity(0.4) ?? const Color(0xFF111827);
            const bottomColor = Color(0xFF0A0A0A);

            bgColors = [topColor, middleColor, bottomColor];
            accentColor = vibrant ?? dominant ?? _defaultPrimaryColor;
        }

        final isPlaying = musicProvider.isPlaying;
        final duration = musicProvider.duration;

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

  Widget _buildAmbientGlows(List<Color> bgColors, Color accentColor) {
    return Stack(
      children: [
        Positioned(
          top: -100,
          left: -100,
          child: AnimatedContainer(
             duration: const Duration(seconds: 1),
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColors.first.withOpacity(0.4), 
            ),
          )
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scale(duration: 4.seconds, begin: const Offset(1,1), end: const Offset(1.2,1.2)),
        ),
        Positioned(
          bottom: -100,
          right: -100,
          child: AnimatedContainer(
             duration: const Duration(seconds: 1),
            width: 350,
            height: 350,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withOpacity(0.2),
            ),
          )
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scale(duration: 5.seconds, begin: const Offset(1,1), end: const Offset(1.1,1.1)),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
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
            onPressed: () => Navigator.pop(context),
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
                ? Image.network(track.albumArtUrl, fit: BoxFit.cover)
                : Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.music_note_rounded, size: 80, color: Colors.white24),
                  ),
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
                  Text(
                    track.artistName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                           ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Track already downloaded')),
                          );
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
        IconButton(
          onPressed: provider.skipToPrevious,
          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 40),
        ),

        // Play/Pause FAB
        // Play/Pause FAB (Refined Liquid Glass)
        ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 72,
              width: 72,
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
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.2),
                    blurRadius: 25,
                    spreadRadius: -5,
                    offset: const Offset(0, 10),
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
                  size: 36,
                ),
              ),
            ),
          ),
        ),

        // Next
        IconButton(
          onPressed: provider.skipToNext,
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 40),
        ),

        // Repeat
        IconButton(
          onPressed: provider.cycleRepeatMode,
          icon: Icon(
            provider.repeatMode == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
             color: provider.repeatMode != RepeatMode.off ? accentColor : Colors.white.withOpacity(0.6),
             size: 26,
            ),
        ),
      ],
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
                     onTap: () async {
                       Navigator.pop(context);
                       await musicProvider.navigateToAlbum(track.albumName, track.artistName);
                       if (context.mounted && musicProvider.currentAlbumDetails != null) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(albumName: track.albumName, artistName: track.artistName)));
                       }
                     }
                   ),
                    _buildOptionTile(
                     icon: Icons.person_rounded, 
                     title: 'Go to Artist', 
                     onTap: () async {
                       Navigator.pop(context);
                       await musicProvider.navigateToArtist(track.artistName);
                       if (context.mounted && musicProvider.currentArtistDetails != null) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artistName: track.artistName)));
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
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('Sleep Timer', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTimerOption(context, musicProvider, '15 Minutes', 15),
              _buildTimerOption(context, musicProvider, '30 Minutes', 30),
              _buildTimerOption(context, musicProvider, '1 Hour', 60),
              _buildTimerOption(context, musicProvider, 'End of Track', 0),
            ],
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
}

// -----------------------------------------------------------------------------
// WAVY PROGRESS BAR IMPLEMENTATION
// -----------------------------------------------------------------------------

class WavyProgressBar extends StatefulWidget {
  final MusicProvider provider;
  final Color accentColor;

  const WavyProgressBar({required this.provider, required this.accentColor, super.key});

  @override
  State<WavyProgressBar> createState() => _WavyProgressBarState();
}

class _WavyProgressBarState extends State<WavyProgressBar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    // Continuous animation for the wave phase
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.provider.positionStream,
      builder: (context, snapshot) {
        final duration = widget.provider.duration;
        final position = _isDragging ? Duration(seconds: _dragValue.toInt()) : (snapshot.data ?? Duration.zero);
        final maxSeconds = duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0;
        final currentSeconds = position.inSeconds.toDouble().clamp(0.0, maxSeconds);
        final progress = currentSeconds / maxSeconds;

        return Column(
          children: [
             SizedBox(
              height: 40,
              child: GestureDetector(
                onHorizontalDragStart: (details) {
                  setState(() { _isDragging = true; _dragValue = currentSeconds; });
                },
                onHorizontalDragUpdate: (details) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final width = box.size.width;
                  final dx = details.localPosition.dx.clamp(0.0, width);
                  final newProgress = dx / width;
                  setState(() { _dragValue = newProgress * maxSeconds; });
                },
                onHorizontalDragEnd: (details) {
                  widget.provider.seekTo(Duration(seconds: _dragValue.toInt()));
                  setState(() { _isDragging = false; });
                },
                onTapDown: (details) {
                   final RenderBox box = context.findRenderObject() as RenderBox;
                   final width = box.size.width;
                   final dx = details.localPosition.dx.clamp(0.0, width);
                   final newProgress = dx / width;
                   widget.provider.seekTo(Duration(seconds: (newProgress * maxSeconds).toInt()));
                },
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: WavySliderPainter(
                        progress: progress,
                        color: widget.accentColor,
                        phase: widget.provider.isPlaying ? _controller.value * 2 * math.pi : 0, 
                      ),
                      size: Size.infinite,
                    );
                  },
                ),
              ),
            ),
             // Time Labels
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(position),
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class WavySliderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double phase;

  WavySliderPainter({required this.progress, required this.color, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final centerY = size.height / 2;
    
    // Config
    const double waveAmplitude = 4.0;
    const double waveFrequency = 0.05; 

    // Draw Inactive Line (Straight & Gray)
    // Starts from the current progress point to the end
    // Logic: In the reference, the "remaining" part is a straight line.
    
    final activeWidth = size.width * progress;
    
    // Inactive Path (Straight Line)
    paint.color = Colors.white.withOpacity(0.2);
    final inactivePath = Path();
    inactivePath.moveTo(activeWidth, centerY);
    inactivePath.lineTo(size.width, centerY);
    canvas.drawPath(inactivePath, paint);

    // active Path (Wavy Line)
    final activePath = Path();
    paint.color = color;
    activePath.moveTo(0, centerY);
    
    double lastX = 0;
    double lastY = centerY;

    // Draw waves only up to the active width
    for (double x = 0; x <= activeWidth; x++) {
      final y = centerY + math.sin((x * waveFrequency) + phase) * waveAmplitude;
      activePath.lineTo(x, y);
      lastX = x;
      lastY = y;
    }
    canvas.drawPath(activePath, paint);

    // Draw Thumb at the tip of the wave
    final thumbPaint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), 8.0, thumbPaint);
    
    // Thumb Glow
    final glowPaint = Paint()..color = color.withOpacity(0.4)..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), 16.0, glowPaint);
  }

  @override
  bool shouldRepaint(covariant WavySliderPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.phase != phase || oldDelegate.color != color;
  }
}
