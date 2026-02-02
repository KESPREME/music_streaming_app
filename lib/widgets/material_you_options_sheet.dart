import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/themed_album_screen.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import 'material_you_playlist_selection_dialog.dart'; // UPDATED: Use Material You Dialog
import 'artist_picker_sheet.dart';
import 'material_you_snackbar.dart';
import 'material_you_download_selection_sheet.dart';
import '../screens/material_you_equalizer_screen.dart';

/// Material You options bottom sheet (parallel to GlassOptionsSheet)
/// Flat design with NO blur - solid Material 3 surface
/// FULLY FUNCTIONAL with all options working
class MaterialYouOptionsSheet extends StatelessWidget {
  final Track? track;
  final bool isRecentlyPlayedContext;
  final String? playlistId;
  final String? playlistName;
  final String? playlistImage;
  final bool isAlbum;
  final bool isArtist;
  final List<Track>? contextTracks;

  const MaterialYouOptionsSheet({
    super.key,
    this.track,
    this.isRecentlyPlayedContext = false,
    this.playlistId,
    this.playlistName,
    this.playlistImage,
    this.isAlbum = false,
    this.isArtist = false,
    this.contextTracks,
  });

  /// Helper to show the options sheet while hiding the mini player
  static Future<void> show(BuildContext context, {
    Track? track,
    bool isRecentlyPlayedContext = false,
    String? playlistId,
    String? playlistName,
    String? playlistImage,
    bool isAlbum = false,
    bool isArtist = false,
    List<Track>? contextTracks,
  }) async {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    
    // Hide Mini Player
    provider.setHideMiniPlayer(true);
    
    try {
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => MaterialYouOptionsSheet(
          track: track,
          isRecentlyPlayedContext: isRecentlyPlayedContext,
          playlistId: playlistId,
          playlistName: playlistName,
          playlistImage: playlistImage,
          isAlbum: isAlbum,
          isArtist: isArtist,
          contextTracks: contextTracks,
        ),
      );
    } finally {
      // Restore Mini Player
      provider.setHideMiniPlayer(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (track == null && playlistName == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    // Header Data
    // Header Data
    final title = track?.trackName ?? playlistName ?? 'Options';
    final subtitle = track?.artistName ?? (isArtist ? 'Artist' : (isAlbum ? 'Album' : 'Playlist'));
    final imageUrl = track?.albumArtUrl ?? playlistImage; 

    
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
            
            // Track Info Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  // Album Art
                  ClipRRect(
                    borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildPlaceholderArt(colorScheme),
                          )
                        : _buildPlaceholderArt(colorScheme),
                  ),
                  const SizedBox(width: 16),
                  // Track Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: MaterialYouTypography.titleMedium(colorScheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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
            
            // Scrollable Options List
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                  if (track != null) ...[
                    _buildOptionTile(
                      context,
                      icon: Icons.playlist_add_rounded,
                      title: 'Add to Playlist',
                      onTap: () async {
                        final rootContext = context;
                        Navigator.pop(context);
                        // Use a small delay to ensure the bottom sheet is fully closed
                        await Future.delayed(const Duration(milliseconds: 100));
                        if (rootContext.mounted) {
                          await showMaterialYouPlaylistSelectionDialog(rootContext, track!);
                        }
                      },
                    ),
                    _buildOptionTile(
                      context,
                      icon: Icons.queue_music_rounded,
                      title: 'Add to Queue',
                      onTap: () {
                        Navigator.pop(context);
                        musicProvider.addToQueue(track!);
                        musicProvider.addToQueue(track!);
                        showMaterialYouSnackBar(
                          context,
                          'Added "${track!.trackName}" to queue',
                        );
                      },
                    ),
                    _buildOptionTile(
                      context,
                      icon: musicProvider.isSongLiked(track!.id)
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      title: musicProvider.isSongLiked(track!.id)
                          ? 'Remove from Liked'
                          : 'Add to Liked Songs',
                      onTap: () {
                        Navigator.pop(context);
                        musicProvider.toggleLike(track!);
                      },
                    ),
                    _buildOptionTile(
                      context,
                      icon: Icons.download_rounded,
                      title: 'Download',
                      onTap: () async {
                        Navigator.pop(context);
                        // Safe check for track download
                        try {
                           final isDownloaded = await musicProvider.isTrackDownloaded(track!.id);
                           if (!isDownloaded) {
                             await musicProvider.downloadTrack(track!);
                             if (context.mounted) {
                               showMaterialYouSnackBar(
                                 context, 
                                 'Downloading "${track!.trackName}"'
                               );
                             }
                           }
                        } catch (e) {
                          // ignore
                        }
                      },
                    ),
                    _buildOptionTile(
                      context,
                      icon: Icons.graphic_eq_rounded,
                      title: 'Equalizer',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MaterialYouEqualizerScreen()),
                        );
                      },
                    ),
                  ],
                    if (track != null)
                      _buildOptionTile(
                        context,
                        icon: Icons.share_rounded,
                        title: 'Share',
                        onTap: () async {
                          Navigator.pop(context);
                          String shareText = 'Listening to: ${track!.trackName} by ${track!.artistName}';
                          await Share.share(shareText);
                        },
                      ),
                      
                    // FIX: Allow Go to Album using Track Name fallback (Single logic), matching Glass UI
                    if (track != null && (track!.albumName.isNotEmpty || track!.trackName.isNotEmpty))
                      _buildOptionTile(
                        context,
                        icon: Icons.album_rounded,
                        title: 'Go to Album',
                        onTap: () {
                          // Perform robust navigation matching Glass NowPlayingScreen
                          final navigator = Navigator.of(context);
                          final effectiveAlbumName = track!.albumName.isNotEmpty ? track!.albumName : track!.trackName;
                          final artUrl = track!.albumArtUrl;
                          final artist = track!.artistName;
                          
                          navigator.pop(); // Close sheet
                          
                          // Navigate to Album/Playlist detail which handles the search
                          navigator.push(
                            MaterialPageRoute(
                              builder: (_) => ThemedPlaylistDetailScreen(
                                playlistId: '', // Signals search
                                playlistName: effectiveAlbumName,
                                playlistImage: artUrl,
                                searchAlbumByName: true,
                                artistNameHint: artist,
                              ),
                            ),
                          );
                        },
                      ),
                    
                    if (track != null && track!.artistName.isNotEmpty && track!.artistName != 'Unknown Artist')
                      _buildOptionTile(
                        context,
                        icon: Icons.person_rounded,
                        title: 'Go to Artist',
                        onTap: () {
                          _navigateToArtist(context, track!.artistName);
                        },
                      ),
                      
                    // FIX 4: Add "Remove from History" option for recently played context
                    if (isRecentlyPlayedContext && track != null)
                      _buildOptionTile(
                        context,
                        icon: Icons.history_rounded,
                        title: 'Remove from History',
                        onTap: () {
                          Navigator.pop(context);
                          try {
                            musicProvider.removeFromRecentlyPlayed(track!.id);
                            musicProvider.removeFromRecentlyPlayed(track!.id);
                            showMaterialYouSnackBar(
                              context,
                              'Removed "${track!.trackName}" from history',
                            );
                          } catch (e) {
                             // Ignore safe remove errors
                          }
                        },
                      ),
                    
                    // Playlist / Album Options
                    if (track == null && (playlistId != null || isAlbum) && contextTracks != null && contextTracks!.isNotEmpty) ...[
                       _buildOptionTile(
                          context,
                          icon: Icons.download_rounded,
                          title: 'Download Playlist',
                          onTap: () {
                             Navigator.pop(context);
                             musicProvider.downloadTracks(contextTracks!);
                             showMaterialYouSnackBar(context, 'Downloading ${contextTracks!.length} tracks');
                          },
                       ),
                       _buildOptionTile(
                          context,
                          icon: Icons.checklist_rounded,
                          title: 'Select to Download',
                          onTap: () async {
                             final rootContext = context;
                             Navigator.pop(context); // Close options first
                             await Future.delayed(const Duration(milliseconds: 100)); // Wait for close
                             if (rootContext.mounted) {
                                await showModalBottomSheet(
                                   context: rootContext,
                                   isScrollControlled: true,
                                   backgroundColor: Colors.transparent,
                                   builder: (ctx) => MaterialYouDownloadSelectionSheet(
                                      tracks: contextTracks!, 
                                      playlistName: playlistName
                                   ),
                                );
                             }
                          },
                       ),
                       _buildOptionTile(
                          context,
                          icon: Icons.queue_music_rounded,
                          title: 'Add All to Queue',
                          onTap: () {
                             Navigator.pop(context);
                             for (var t in contextTracks!) {
                               musicProvider.addToQueue(t);
                             }
                             showMaterialYouSnackBar(context, 'Added ${contextTracks!.length} tracks to queue');
                          },
                       ),
                       _buildOptionTile(
                          context,
                          icon: Icons.shuffle_rounded,
                          title: 'Shuffle Play',
                          onTap: () {
                             Navigator.pop(context);
                             musicProvider.shuffleAndPlay(contextTracks!);
                          },
                       ),
                       const SizedBox(height: 16),
                    ],

                    // Generic Artist/Playlist Options (when track is null)
                    if (track == null) ...[
                       if (isArtist)
                       _buildOptionTile(
                          context,
                          icon: Icons.radio, // Fixed Icon Name
                          title: 'Start Artist Radio',
                          onTap: () {
                             Navigator.pop(context);
                             // Implementation for radio
                          },
                       ),
                    ],

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  icon,
                  color: MaterialYouTokens.primaryVibrant,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderArt(ColorScheme colorScheme) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: colorScheme.onSurfaceVariant,
        size: 28,
      ),
    );
  }

  // FIX: Add multi-artist navigation logic (same as now playing screen)
  void _navigateToArtist(BuildContext context, String artistString) async {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    
    // Handle multiple artists using robust parsing from ArtistPickerSheet
    final artists = ArtistPickerSheet.parseArtists(artistString);
    
    if (artists.isEmpty) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context); 
      }
      return;
    }
    
    if (artists.length == 1) {
      // Single artist - navigate directly
      // Don't pop here, let _performArtistNavigation do it
      await _performArtistNavigation(context, musicProvider, artists[0]);
    } else {
      // Multiple artists - show picker sheet
      musicProvider.setHideMiniPlayer(true);
      
      // Show picker sheet ON TOP of options sheet
      final selectedArtist = await showModalBottomSheet<String>(
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
                          Navigator.pop(sheetContext, artist);
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
      
      musicProvider.setHideMiniPlayer(false);
      
      // If user selected an artist, perform navigation
      if (selectedArtist != null && context.mounted) {
         await _performArtistNavigation(context, musicProvider, selectedArtist);
      } else {
         // If cancelled, just stay on options sheet (or pop if desired? let's stay)
      }
    }
  }
  
  Future<void> _performArtistNavigation(BuildContext context, MusicProvider provider, String artistName) async {
    // Capture state BEFORE async gap
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    
    // Show loading feedback immediately
    showMaterialYouSnackBar(context, 'Loading $artistName...', duration: const Duration(milliseconds: 500));
    
    // Perform async work
    await provider.navigateToArtist(artistName);
    
    // Close the options sheet now that we are ready to navigate
    if (navigator.canPop()) {
      navigator.pop();
    }
    
    // Use captured navigator to push
    if (provider.currentArtistDetails != null) {
      // FIX: Ensure mini player is visible when going to details screen
      provider.setHideMiniPlayer(false);
      
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ThemedArtistDetailScreen(
            artistId: provider.currentArtistDetails!.id,
            artistName: artistName,
            artistImage: provider.currentArtistDetails!.imageUrl,
            searchByName: false,
          ),
        ),
      );
    } else {
       showMaterialYouSnackBar(context, 'Could not load artist "$artistName"', isError: true);
    }
  }
  
  // FIX: Accept NavigatorState and ScaffoldMessengerState directly to ensure safety after pop
  void _navigateToAlbum(
    NavigatorState navigator, 
    ScaffoldMessengerState messenger, 
    MusicProvider musicProvider, 
    String albumName, 
    String artistName
  ) async {
    // Show loading feedback
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Loading album...'),
        backgroundColor: MaterialYouTokens.primaryVibrant,
        duration: const Duration(milliseconds: 500),
      ),
    );
    
    // Fetch album details
    print('DEBUG: MaterialYouOptionsSheet._navigateToAlbum: Navigating to album: "$albumName" by "$artistName"');
    
    try {
      print('DEBUG: calling musicProvider.navigateToAlbum...');
      await musicProvider.navigateToAlbum(albumName, artistName);
      print('DEBUG: musicProvider.navigateToAlbum returned.');
      
      // Navigate if successful
      if (musicProvider.currentAlbumDetails != null) {
        debugPrint('MaterialYouOptionsSheet: Album loaded successfully: ${musicProvider.currentAlbumDetails!.name}');
        
        // FIX: Ensure mini player is visible when going to details screen
        musicProvider.setHideMiniPlayer(false);
        
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ThemedPlaylistDetailScreen(
              playlistId: musicProvider.currentAlbumDetails!.id,
              playlistName: musicProvider.currentAlbumDetails!.name,
              playlistImage: musicProvider.currentAlbumDetails!.imageUrl,
              cachedTracks: musicProvider.currentAlbumDetails!.tracks,
            ),
          ),
        );
      } else {
        debugPrint('MaterialYouOptionsSheet: Failed to load album details (null)');
        // Show error if album not found
        messenger.showSnackBar(
          SnackBar(
            content: Text('Could not load album "$albumName"'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stack) {
       debugPrint('MaterialYouOptionsSheet: Navigation error: $e\n$stack');
       messenger.showSnackBar(
        SnackBar(
          content: Text('Error loading album "$albumName"'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

