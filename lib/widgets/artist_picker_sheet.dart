import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/themed_artist_detail_screen.dart';
import 'glass_snackbar.dart';

/// A glassmorphic bottom sheet that allows users to select from multiple artists
class ArtistPickerSheet extends StatelessWidget {
  final List<String> artists;
  final BuildContext parentContext; // Store parent context for post-pop navigation
  
  const ArtistPickerSheet({
    super.key,
    required this.artists,
    required this.parentContext,
  });

  /// Parses an artist string and returns a list of individual artists
  static List<String> parseArtists(String artistString) {
    // Normalize the string
    String normalized = artistString
        .replaceAll(RegExp(r'\s+feat\.?\s+', caseSensitive: false), ', ')
        .replaceAll(RegExp(r'\s+ft\.?\s+', caseSensitive: false), ', ')
        .replaceAll(RegExp(r'\s+featuring\s+', caseSensitive: false), ', ')
        .replaceAll(RegExp(r'\s+&\s+'), ', ')
        .replaceAll(RegExp(r'\s+and\s+', caseSensitive: false), ', ')
        .replaceAll(RegExp(r'\s+x\s+'), ', ');
    
    // Split by comma and clean up
    return normalized
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Returns true if the artist string contains multiple artists
  static bool hasMultipleArtists(String artistString) {
    return parseArtists(artistString).length > 1;
  }

  /// Shows the picker sheet if multiple artists, or navigates directly if single artist
  static Future<void> showIfNeeded(
    BuildContext context,
    MusicProvider provider,
    String artistString,
  ) async {
    final artists = parseArtists(artistString);
    
    if (artists.length <= 1) {
      // Single artist - navigate directly
      await _navigateToArtist(context, provider, artistString.trim());
    } else {
      // Multiple artists - show picker
      HapticFeedback.selectionClick();
      provider.setHideMiniPlayer(true);
      
      // Show sheet and wait for result
      final selectedArtist = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => ArtistPickerSheet(
          artists: artists,
          parentContext: context,
        ),
      );
      
      provider.setHideMiniPlayer(false);
      
      // Navigate using the PARENT context
      if (selectedArtist != null && context.mounted) {
        await _navigateToArtist(context, provider, selectedArtist);
      }
    }
  }

  static Future<void> _navigateToArtist(
    BuildContext context, 
    MusicProvider provider, 
    String artistName,
  ) async {
    showGlassSnackBar(context, 'Loading $artistName...', duration: const Duration(milliseconds: 500));
    await provider.navigateToArtist(artistName);
    if (context.mounted && provider.currentArtistDetails != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ThemedArtistDetailScreen(
        artistId: provider.currentArtistDetails!.id,
        artistName: provider.currentArtistDetails!.name,
        artistImage: provider.currentArtistDetails!.imageUrl,
      )));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1E1E1E) : Colors.white).withOpacity(0.8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle Bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        color: isDark ? Colors.white70 : Colors.black54,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Select Artist',
                        style: GoogleFonts.splineSans(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Divider(height: 1, thickness: 0.5),
                
                // Artist List
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      children: artists.map((artist) => _buildArtistOption(
                        context,
                        artist,
                        isDark,
                      )).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtistOption(BuildContext context, String artist, bool isDark) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Icon(
        Icons.person_outline_rounded,
        color: isDark ? Colors.white : Colors.black,
        size: 24, // Consistent icon size
      ),
      title: Text(
        artist,
        style: GoogleFonts.splineSans(
          color: isDark ? Colors.white : Colors.black,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: isDark ? Colors.white30 : Colors.black38,
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.pop(context, artist);
      },
    );
  }
}
