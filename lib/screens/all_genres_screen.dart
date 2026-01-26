import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import 'genre_songs_screen.dart'; // Import this
import 'home_screen.dart'; // For GenreSongsScreen, assuming it's still there or moved

class AllGenresScreen extends StatelessWidget {
  const AllGenresScreen({super.key});

  // Using the same genre list as in HomeScreen for consistency
  static final List<Map<String, dynamic>> _genres = [
    {'name': 'Pop', 'color': Colors.pinkAccent, 'icon': Icons.music_note},
    {'name': 'Rock', 'color': Colors.lightBlueAccent, 'icon': Icons.album },
    {'name': 'Hip-Hop', 'color': Colors.tealAccent, 'icon': Icons.mic_external_on},
    {'name': 'Electronic', 'color': Colors.cyanAccent, 'icon': Icons.headphones},
    {'name': 'Jazz', 'color': Colors.orangeAccent, 'icon': Icons.speaker},
    {'name': 'Classical', 'color': Colors.deepPurpleAccent, 'icon': Icons.piano},
    {'name': 'R&B', 'color': Colors.brown, 'icon': Icons.person_search_rounded},
    {'name': 'Indie', 'color': Colors.limeAccent, 'icon': Icons.flare},
    {'name': 'Metal', 'color': Colors.blueGrey, 'icon': Icons.bolt},
    {'name': 'Folk', 'color': Colors.green, 'icon': Icons.eco},
    {'name': 'Blues', 'color': Colors.indigo, 'icon': Icons.nightlife},
    {'name': 'Reggae', 'color': Colors.red, 'icon': Icons.beach_access},
  ];


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text('All Genres', style: theme.textTheme.headlineSmall),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 16 / 7, // Adjust for desired height
        ),
        itemCount: _genres.length,
        itemBuilder: (context, index) {
          final genre = _genres[index];
          final genreName = genre['name'] as String;
          final genreColor = genre['color'] as Color;
          final genreIcon = genre['icon'] as IconData?;

          return InkWell(
            onTap: () async {
              await musicProvider.fetchGenreTracks(genreName);
              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    // Ensure GenreSongsScreen is defined and imported correctly
                    builder: (context) => GenreSongsScreen(genre: genreName),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [genreColor.withOpacity(0.7), genreColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                 boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center, // Center content
                  children: [
                    if (genreIcon != null)
                      Icon(genreIcon, color: Colors.white.withOpacity(0.9), size: 24),
                    if (genreIcon != null)
                      const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        genreName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: genreIcon == null ? TextAlign.center : TextAlign.start,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
