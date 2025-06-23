import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:cached_network_image/cached_network_image.dart'; // Not used directly, ArtistTile might use it
import '../providers/music_provider.dart'; // For potential future use with a dedicated artist list
import '../services/api_service.dart'; // To fetch artists directly for this screen
import '../models/artist.dart'; // Assuming you might have an Artist model for richer data
import '../screens/artist_screen.dart'; // To navigate to individual artist pages

// A simple tile for displaying an artist
class ArtistListTile extends StatelessWidget {
  final String name;
  final String imageUrl;
  final VoidCallback onTap;

  const ArtistListTile({
    Key? key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: theme.colorScheme.surfaceVariant,
          backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
          child: imageUrl.isEmpty ? Icon(Icons.person, color: theme.colorScheme.onSurfaceVariant) : null,
        ),
        title: Text(name, style: theme.textTheme.titleMedium),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: theme.iconTheme.color?.withOpacity(0.6)),
        onTap: onTap,
      ),
    );
  }
}


class AllArtistsScreen extends StatefulWidget {
  const AllArtistsScreen({Key? key}) : super(key: key);

  @override
  State<AllArtistsScreen> createState() => _AllArtistsScreenState();
}

class _AllArtistsScreenState extends State<AllArtistsScreen> {
  late Future<List<Map<String, String>>> _artistsFuture;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _artistsFuture = _apiService.fetchTopArtists();
  }

  Future<void> _refreshArtists() async {
    setState(() {
      _artistsFuture = _apiService.fetchTopArtists(); // Re-fetch
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Top Artists', style: theme.textTheme.headlineSmall),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshArtists,
        backgroundColor: theme.colorScheme.surface,
        color: theme.colorScheme.primary,
        child: FutureBuilder<List<Map<String, String>>>(
          future: _artistsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Could not load artists: ${snapshot.error}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Text('No artists available right now.', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.7))),
              );
            }

            final artists = snapshot.data!;
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final artist = artists[index];
                final artistName = artist['name'] ?? 'Unknown Artist';
                final artistImageUrl = artist['image'] ?? '';

                return ArtistListTile(
                  name: artistName,
                  imageUrl: artistImageUrl,
                  onTap: () {
                    // Navigate to ArtistScreen, MusicProvider will handle fetching details
                    Provider.of<MusicProvider>(context, listen: false).navigateToArtist(artistName);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ArtistScreen(artistName: artistName)),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
