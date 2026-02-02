import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';
import 'material_you_snackbar.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> showMaterialYouPlaylistSelectionDialog(BuildContext context, Track trackToAdd) async {
  // FIX: Get provider BEFORE showing dialog to avoid context issues
  final musicProvider = Provider.of<MusicProvider>(context, listen: false);
  final colorScheme = Theme.of(context).colorScheme;

  // TextEditingController for the new playlist name
  final TextEditingController newPlaylistNameController = TextEditingController();

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext bottomSheetContext) {
      return Container(
         decoration: BoxDecoration(
            color: MaterialYouTokens.surfaceContainerDark,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
             child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setStateModal) {
                final userPlaylists = musicProvider.userPlaylists;
                
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 16),
                        width: 32, height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      
                      // Title
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Text(
                          'Add to Playlist',
                          style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
                        ),
                      ),
                      
                      // Create New Playlist Option
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: _buildMaterialOption(
                          context,
                          icon: Icons.add_circle_outline_rounded,
                          label: 'Create New Playlist',
                          isAccent: true,
                          onTap: () async {
                            Navigator.pop(bottomSheetContext);
                            // Pass musicProvider to the dialog builder
                            await showDialog(
                              context: context,
                              builder: (BuildContext dialogContext) => _buildMaterialInputDialog(
                                dialogContext, 
                                newPlaylistNameController, 
                                trackToAdd,
                                musicProvider, // Pass provider directly
                              ),
                            );
                          },
                        ),
                      ),
                      
                      const Padding(
                       padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 24),
                       child: Divider(height: 1, thickness: 1),
                      ),
                      
                      if (userPlaylists.isEmpty)
                         Padding(
                            padding: const EdgeInsets.all(30.0),
                            child: Text(
                              'No playlists found.',
                              style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
                            ),
                         )
                      else
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            physics: const BouncingScrollPhysics(),
                            itemCount: userPlaylists.length,
                            itemBuilder: (context, index) {
                              final playlist = userPlaylists[index];
                              final bool trackExists = playlist.tracks.any((t) => t.id == trackToAdd.id);
                              
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: _buildMaterialOption(
                                  context,
                                  icon: trackExists ? Icons.check_circle_rounded : Icons.playlist_add_rounded,
                                  label: playlist.name,
                                  subtitle: '${playlist.tracks.length} tracks',
                                  isAccent: trackExists,
                                  onTap: () async {
                                    if (!trackExists) {
                                      await musicProvider.addTrackToPlaylist(playlist.id, trackToAdd);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Added "${trackToAdd.trackName}" to "${playlist.name}"'),
                                            backgroundColor: MaterialYouTokens.primaryVibrant,
                                          ),
                                        );
                                      }
                                    } else {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Already in "${playlist.name}"'),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    }
                                    Navigator.pop(bottomSheetContext);
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              }
             ),
          ),
      );
    },
  );
}

Widget _buildMaterialOption(BuildContext context, {
  required IconData icon, 
  required String label, 
  String? subtitle,
  required VoidCallback onTap, 
  bool isAccent = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isAccent ? MaterialYouTokens.primaryVibrant.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isAccent ? MaterialYouTokens.primaryVibrant : MaterialYouTokens.surfaceContainerHighestDark,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                 icon, 
                 color: isAccent ? Colors.black : colorScheme.onSurfaceVariant, 
                 size: 24
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: MaterialYouTypography.titleMedium(colorScheme.onSurface).copyWith(
                       color: isAccent ? MaterialYouTokens.primaryVibrant : colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildMaterialInputDialog(
  BuildContext context, 
  TextEditingController controller, 
  Track trackToAdd,
  MusicProvider musicProvider, // Add provider parameter
) {
  // FIX: Force White text for readability on dark background
  final textStyle = GoogleFonts.outfit(color: Colors.white, fontSize: 16);
  final hintStyle = GoogleFonts.outfit(color: Colors.white54, fontSize: 16);
  final titleStyle = GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold);

  return AlertDialog(
    backgroundColor: MaterialYouTokens.surfaceContainerHighestDark,
    title: Text('New Playlist', style: titleStyle),
    content: TextField(
      controller: controller,
      autofocus: true,
      style: textStyle,
      cursorColor: MaterialYouTokens.primaryVibrant,
      onSubmitted: (value) async {
        print('DEBUG: TextField submitted with value: "$value"');
        if (value.trim().isEmpty) {
          print('DEBUG: Submitted value is empty');
          return;
        }
        
        try {
          print('DEBUG: Creating playlist from onSubmitted...');
          
          await musicProvider.createPlaylist(
            value.trim(), 
            initialTracks: [trackToAdd],
            imageUrl: trackToAdd.albumArtUrl, // Use track's album art
          );
          print('DEBUG: Playlist created from onSubmitted!');
          
            if (context.mounted) {
            Navigator.pop(context);
            showMaterialYouSnackBar(
              context, 
              'Added "${trackToAdd.trackName}" to "${value.trim()}"'
            );
          }
        } catch (e) {
          print('DEBUG: Error in onSubmitted: $e');
          if (context.mounted) {
            showMaterialYouSnackBar(context, 'Error: $e', isError: true);
          }
        }
      },
      decoration: InputDecoration(
        hintText: 'Playlist Name',
        hintStyle: hintStyle,
        filled: true,
        fillColor: MaterialYouTokens.surfaceContainerDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: MaterialYouTokens.primaryVibrant, width: 2)),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          print('DEBUG: Cancel button pressed');
          Navigator.pop(context);
        },
        child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white70)),
      ),
      FilledButton(
        onPressed: () async {
           print('DEBUG: Create button pressed!');
           try {
             final name = controller.text.trim();
             print('DEBUG: Playlist name: "$name"');
             
             if (name.isEmpty) {
               print('DEBUG: Name is empty, returning');
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(
                   content: Text('Please enter a playlist name'),
                   backgroundColor: Colors.orange,
                 ),
               );
               return;
             }
             
             print('DEBUG: Creating playlist with provider...');
             
             // Create playlist AND add the track immediately
             // Use the track's thumbnail as the playlist cover
             await musicProvider.createPlaylist(
               name, 
               initialTracks: [trackToAdd],
               imageUrl: trackToAdd.albumArtUrl, // Use track's album art
             ); 
             print('DEBUG: Playlist created successfully!');
             
             // Close dialog
             if (context.mounted) {
               Navigator.pop(context);
               print('DEBUG: Dialog closed');
               
               // Show success message
               showMaterialYouSnackBar(
                 context, 
                 'Added "${trackToAdd.trackName}" to "$name"'
               );
               print('DEBUG: Success message shown');
             }
           } catch (e, stack) {
             print('DEBUG: Error occurred: $e');
             print('DEBUG: Stack trace: $stack');
             // Show error if something goes wrong
             if (context.mounted) {
               showMaterialYouSnackBar(context, 'Error: $e', isError: true);
             }
           }
        },
        style: FilledButton.styleFrom(
           backgroundColor: MaterialYouTokens.primaryVibrant,
           foregroundColor: Colors.black,
        ),
        child: const Text('Create'),
      ),
    ],
  );
}
