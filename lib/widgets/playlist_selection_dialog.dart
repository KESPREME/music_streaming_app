import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import 'glass_snackbar.dart';

Future<void> showPlaylistSelectionDialog(BuildContext context, Track trackToAdd) async {
  final musicProvider = Provider.of<MusicProvider>(context, listen: false);
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  // TextEditingController for the new playlist name
  final TextEditingController newPlaylistNameController = TextEditingController();

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true, // Allow it to be taller if needed
    builder: (BuildContext bottomSheetContext) {
      return Container(
         decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1E1E1E) : Colors.white).withOpacity(0.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, -5)),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
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
                            width: 40, height: 4,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.black12,
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
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                          
                          // Create New Playlist Option
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: _buildGlassOption(
                              context,
                              icon: Icons.add_circle_outline_rounded,
                              label: 'Create New Playlist',
                              isDark: isDark,
                              isAccent: true,
                              onTap: () async {
                                Navigator.pop(bottomSheetContext);
                                final String? createdPlaylistName = await showDialog<String>(
                                  context: context,
                                  builder: (BuildContext dialogContext) => _buildGlassInputDialog(context, newPlaylistNameController, isDark),
                                );

                                if (createdPlaylistName != null) {
                                   if (context.mounted) showGlassSnackBar(context, '"${trackToAdd.trackName}" added to "$createdPlaylistName"');
                                }
                              },
                            ),
                          ),
                          
                          const Padding(
                           padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 24),
                           child: Divider(height: 1, thickness: 0.5),
                          ),
                          
                          if (userPlaylists.isEmpty)
                             Padding(
                                padding: const EdgeInsets.all(30.0),
                                child: Text(
                                  'No playlists found.',
                                  style: GoogleFonts.splineSans(color: isDark ? Colors.white54 : Colors.black54),
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
                                    child: _buildGlassOption(
                                      context,
                                      icon: trackExists ? Icons.check_circle_rounded : Icons.playlist_add_rounded,
                                      label: playlist.name,
                                      subtitle: '${playlist.tracks.length} tracks',
                                      isDark: isDark,
                                      isAccent: trackExists,
                                      onTap: () async {
                                        if (!trackExists) {
                                          await musicProvider.addTrackToPlaylist(playlist.id, trackToAdd);
                                          if (context.mounted) showGlassSnackBar(context, '"${trackToAdd.trackName}" added to "${playlist.name}"');
                                        } else {
                                          if (context.mounted) showGlassSnackBar(context, 'Already in "${playlist.name}"');
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
            ),
          ),
      );
    },
  );
}

Widget _buildGlassOption(BuildContext context, {
  required IconData icon, 
  required String label, 
  String? subtitle,
  required VoidCallback onTap, 
  required bool isDark,
  bool isAccent = false,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isAccent ? const Color(0xFFFF1744).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isAccent ? Border.all(color: const Color(0xFFFF1744).withOpacity(0.3)) : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isAccent ? const Color(0xFFFF1744).withOpacity(0.2) : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isAccent ? const Color(0xFFFF1744) : (isDark ? Colors.white : Colors.black), size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.splineSans(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: GoogleFonts.splineSans(
                        color: isDark ? Colors.white54 : Colors.black54,
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

Widget _buildGlassInputDialog(BuildContext context, TextEditingController controller, bool isDark) {
  return Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1E1E1E) : Colors.white).withOpacity(0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
             mainAxisSize: MainAxisSize.min,
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Text(
                 'New Playlist',
                 style: GoogleFonts.splineSans(
                   fontSize: 20, fontWeight: FontWeight.bold,
                   color: isDark ? Colors.white : Colors.black,
                 ),
               ),
               const SizedBox(height: 20),
               TextField(
                 controller: controller,
                 autofocus: true,
                 style: GoogleFonts.splineSans(color: isDark ? Colors.white : Colors.black),
                 cursorColor: const Color(0xFFFF1744),
                 decoration: InputDecoration(
                   hintText: 'Playlist Name',
                   hintStyle: GoogleFonts.splineSans(color: isDark ? Colors.white38 : Colors.black38),
                   filled: true,
                   fillColor: isDark ? Colors.black26 : Colors.black12,
                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                   focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF1744), width: 1.5)),
                   contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                 ),
               ),
               const SizedBox(height: 24),
               Row(
                 mainAxisAlignment: MainAxisAlignment.end,
                 children: [
                   TextButton(
                     onPressed: () => Navigator.pop(context),
                     child: Text('Cancel', style: GoogleFonts.splineSans(color: isDark ? Colors.white60 : Colors.black54)),
                   ),
                   const SizedBox(width: 8),
                   ElevatedButton(
                     onPressed: () {
                        final name = controller.text.trim();
                        if (name.isNotEmpty) {
                           final provider = Provider.of<MusicProvider>(context, listen: false);
                           // Placeholder for track arg, handled in callback
                           provider.createPlaylist(name); // Track added in parent
                           Navigator.pop(context, name);
                        }
                     },
                     style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF1744),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                     ),
                     child: Text('Create', style: GoogleFonts.splineSans(color: Colors.white, fontWeight: FontWeight.bold)),
                   ),
                 ],
               )
             ],
          ),
        ),
      ),
    ),
  );
}
