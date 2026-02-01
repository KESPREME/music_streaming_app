import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/themed_genre_songs_screen.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouAllGenresScreen extends StatelessWidget {
  const MaterialYouAllGenresScreen({super.key});

  static final List<Map<String, dynamic>> _genres = [
    {'name': 'Pop', 'color': MaterialYouTokens.primaryVibrant, 'icon': Icons.music_note},
    {'name': 'Rock', 'color': MaterialYouTokens.secondaryVibrant, 'icon': Icons.album},
    {'name': 'Hip-Hop', 'color': MaterialYouTokens.accentTeal, 'icon': Icons.mic_external_on},
    {'name': 'Electronic', 'color': MaterialYouTokens.accentCyan, 'icon': Icons.headphones},
    {'name': 'Jazz', 'color': MaterialYouTokens.accentOrange, 'icon': Icons.speaker},
    {'name': 'Classical', 'color': MaterialYouTokens.accentLightBlue, 'icon': Icons.piano},
    {'name': 'R&B', 'color': MaterialYouTokens.tertiaryVibrant, 'icon': Icons.person_search_rounded},
    {'name': 'Indie', 'color': MaterialYouTokens.accentGreen, 'icon': Icons.flare},
    {'name': 'Metal', 'color': const Color(0xFF607D8B), 'icon': Icons.bolt},
    {'name': 'Folk', 'color': const Color(0xFF4CAF50), 'icon': Icons.eco},
    {'name': 'Blues', 'color': const Color(0xFF3F51B5), 'icon': Icons.nightlife},
    {'name': 'Reggae', 'color': const Color(0xFFF44336), 'icon': Icons.beach_access},
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      appBar: AppBar(
        backgroundColor: MaterialYouTokens.surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'All Genres', 
          style: MaterialYouTypography.headlineSmall(colorScheme.onSurface)
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 16 / 7,
        ),
        itemCount: _genres.length,
        itemBuilder: (context, index) {
          final genre = _genres[index];
          final genreName = genre['name'] as String;
          final genreColor = genre['color'] as Color;
          final genreIcon = genre['icon'] as IconData?;

          return Material(
            elevation: 2,
            surfaceTintColor: Colors.transparent, // FIX: No white tint
            color: MaterialYouTokens.surfaceContainerDark,
            borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
            child: InkWell(
              onTap: () async {
                await musicProvider.fetchGenreTracks(genreName);
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ThemedGenreSongsScreen(genre: genreName),
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
                  border: Border.all(
                    color: genreColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (genreIcon != null)
                        Icon(genreIcon, color: genreColor, size: 24),
                      if (genreIcon != null)
                        const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          genreName,
                          style: MaterialYouTypography.titleMedium(colorScheme.onSurface)
                              .copyWith(color: genreColor),
                          textAlign: genreIcon == null ? TextAlign.center : TextAlign.start,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
