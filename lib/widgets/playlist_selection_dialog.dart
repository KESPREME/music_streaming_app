import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../theme/glass_tokens.dart';
import 'glass_surface.dart';
import 'glass_snackbar.dart';

Future<void> showPlaylistSelectionDialog(
  BuildContext context,
  Track trackToAdd,
) async {
  // FIX: Get provider BEFORE showing dialog to avoid context issues
  final musicProvider = Provider.of<MusicProvider>(context, listen: false);
  final outerContext = context;

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true, // Allow it to be taller if needed
    builder: (BuildContext bottomSheetContext) {
      return GlassSurface(
        tier: GlassTier.sheet,
        borderRadius: GlassTokens.radiusSheet,
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
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Title
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Text(
                        'Add to Playlist',
                        style: GoogleFonts.splineSans(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),

                    // Create New Playlist Option
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: _buildGlassOption(
                        context,
                        icon: Icons.add_circle_outline_rounded,
                        label: 'Create New Playlist',
                        isAccent: true,
                        onTap: () async {
                          Navigator.pop(bottomSheetContext);
                          // Controller lives exactly as long as the dialog that
                          // owns its TextField - no dispose-after-pop race.
                          final newPlaylistNameController =
                              TextEditingController();
                          try {
                            // Pass musicProvider to the dialog builder; use the
                            // OUTER context which survives the sheet being popped.
                            await showDialog(
                              context: outerContext,
                              builder: (BuildContext dialogContext) =>
                                  _buildGlassInputDialog(
                                dialogContext,
                                newPlaylistNameController,
                                trackToAdd,
                                musicProvider, // Pass provider directly
                              ),
                            );
                          } finally {
                            newPlaylistNameController.dispose();
                          }
                        },
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 24,
                      ),
                      child: Divider(height: 1, thickness: 0.5),
                    ),

                    if (userPlaylists.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(30.0),
                        child: Text(
                          'No playlists found.',
                          style: GoogleFonts.splineSans(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
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
                            final bool trackExists = playlist.tracks.any(
                              (t) => t.id == trackToAdd.id,
                            );

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: _buildGlassOption(
                                context,
                                icon: trackExists
                                    ? Icons.check_circle_rounded
                                    : Icons.playlist_add_rounded,
                                label: playlist.name,
                                subtitle: '${playlist.tracks.length} tracks',
                                isAccent: trackExists,
                                onTap: () async {
                                  if (!trackExists) {
                                    await musicProvider.addTrackToPlaylist(
                                      playlist.id,
                                      trackToAdd,
                                    );
                                    if (context.mounted) {
                                      showGlassSnackBar(
                                        context,
                                        '"${trackToAdd.trackName}" added to "${playlist.name}"',
                                      );
                                    }
                                  } else {
                                    if (context.mounted) {
                                      showGlassSnackBar(
                                        context,
                                        'Already in "${playlist.name}"',
                                      );
                                    }
                                  }
                                  if (bottomSheetContext.mounted) {
                                    Navigator.pop(bottomSheetContext);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

Widget _buildGlassOption(
  BuildContext context, {
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
          color: isAccent
              ? colorScheme.onSurface.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isAccent
              ? Border.all(color: colorScheme.outline.withValues(alpha: 0.2))
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isAccent
                    ? colorScheme.onSurface.withValues(alpha: 0.08)
                    : colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isAccent ? colorScheme.onSurface : colorScheme.onSurface,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.splineSans(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: GoogleFonts.splineSans(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
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

Widget _buildGlassInputDialog(
  BuildContext context,
  TextEditingController controller,
  Track trackToAdd,
  MusicProvider musicProvider, // Add provider parameter
) {
  final colorScheme = Theme.of(context).colorScheme;
  return Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    child: GlassSurface(
      tier: GlassTier.floating,
      borderRadius: GlassTokens.radiusCard,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New Playlist',
            style: GoogleFonts.splineSans(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 20),
          Material(
            color: Colors.transparent,
            child: TextField(
              controller: controller,
              autofocus: true,
              style: GoogleFonts.splineSans(color: colorScheme.onSurface),
              cursorColor: colorScheme.primary,
              onSubmitted: (value) async {
                if (value.trim().isEmpty) {
                  return;
                }

                try {
                  await musicProvider.createPlaylist(
                    value.trim(),
                    initialTracks: [trackToAdd],
                    imageUrl: trackToAdd.albumArtUrl, // Use track's album art
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '"${trackToAdd.trackName}" added to "${value.trim()}"',
                        ),
                        backgroundColor: colorScheme.primary,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: colorScheme.error,
                      ),
                    );
                  }
                }
              },
              decoration: InputDecoration(
                hintText: 'Playlist Name',
                hintStyle: GoogleFonts.splineSans(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                filled: true,
                fillColor: colorScheme.onSurface.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(
                  'Cancel',
                  style: GoogleFonts.splineSans(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final name = controller.text.trim();

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a playlist name'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    // Create playlist AND add the track immediately
                    // Use the track's thumbnail as the playlist cover
                    await musicProvider.createPlaylist(
                      name,
                      initialTracks: [trackToAdd],
                      imageUrl: trackToAdd.albumArtUrl, // Use track's album art
                    );

                    // Close dialog
                    if (context.mounted) {
                      Navigator.pop(context);

                      // Show success message
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '"${trackToAdd.trackName}" added to "$name"',
                          ),
                          backgroundColor: colorScheme.primary,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (e) {
                    // Show error if something goes wrong
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: colorScheme.error,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Create',
                  style: GoogleFonts.splineSans(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
