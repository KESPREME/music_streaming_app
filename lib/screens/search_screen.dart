import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../search_tab_content.dart'; // This will also need redesigning
import '../widgets/track_tile.dart';
import '../models/track.dart'; // Keep Track model import

// Example placeholder for a more visual artist tile
class ArtistSearchTile extends StatelessWidget {
  final String artistName;
  final String? artistImageUrl; // Optional image URL
  final VoidCallback onTap;

  const ArtistSearchTile({
    Key? key,
    required this.artistName,
    this.artistImageUrl,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        radius: 25,
        backgroundColor: theme.colorScheme.surfaceVariant,
        // backgroundImage: artistImageUrl != null && artistImageUrl!.isNotEmpty
        //     ? NetworkImage(artistImageUrl!) // Consider CachedNetworkImage here
        //     : null,
        child: artistImageUrl == null || artistImageUrl!.isEmpty
            ? Icon(Icons.person, color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      title: Text(artistName, style: theme.textTheme.titleMedium),
      // subtitle: Text("Artist", style: theme.textTheme.bodySmall), // Optional
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    );
  }
}


class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // Tracks, Artists, Playlists
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    if (query.trim().isEmpty) return;
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    // Depending on the active tab, call different search methods
    // For now, let's assume SearchTabContent handles track search based on query
    // and _buildArtistsTab will filter/fetch based on query.
    // MusicProvider might need more specific search methods like searchArtists(query), searchPlaylists(query)
    if (_tabController.index == 0) { // Tracks
        // SearchTabContent will use the new provider.searchTracks method internally via its searchQuery prop
        // Triggering it here might be redundant if SearchTabContent handles it, but ensures data is fetched.
        musicProvider.searchTracks(query);
    } else if (_tabController.index == 1) { // Artists
        // This was `musicProvider.fetchArtistTracks(query);` which fetches tracks BY an artist.
        // For a search screen, you'd typically search FOR artists.
        // Assuming a new/different method in MusicProvider or ApiService is needed for "searching artists".
        // For now, to fix the direct error, we'll keep it if it's intended to show top tracks of a *specific* artist search.
        // If the intent is to search *for* artists, this needs a different backend call.
        // Let's assume for now the current behavior of fetching tracks for a searched artist name is what's desired for this tab.
        musicProvider.fetchArtistTracks(query);
    }
    // Add playlist search logic if needed
    print("Performing search for: $query on tab ${_tabController.index}");
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // final musicProvider = Provider.of<MusicProvider>(context, listen: false); // if needed directly

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // Assuming it's a main tab
        toolbarHeight: 70, // Increased height for search bar
        title: Padding(
          padding: const EdgeInsets.only(top: 8.0), // Adjust padding for better alignment
          child: TextField(
            controller: _searchController,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: 'Search songs, artists, playlists...',
              hintStyle: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.5)),
              filled: true,
              fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25.0), // More rounded
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25.0),
                borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
              ),
              prefixIcon: Icon(Icons.search, color: theme.iconTheme.color?.withOpacity(0.7)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: theme.iconTheme.color?.withOpacity(0.7)),
                      onPressed: () {
                        _searchController.clear();
                        // Optionally clear search results in provider
                        // musicProvider.clearSearchResults();
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
            ),
            onSubmitted: _performSearch,
            textInputAction: TextInputAction.search,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Tracks'),
            Tab(text: 'Artists'),
            Tab(text: 'Playlists'), // Added Playlists tab
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tracks Tab - SearchTabContent needs to be refactored to accept/use query
          // For now, assuming SearchTabContent is adapted to use _searchQuery or a provider state
          SearchTabContent(searchQuery: _searchQuery), // Pass query
          _buildArtistsTab(context, _searchQuery),
          _buildPlaylistsTab(context, _searchQuery), // Placeholder for playlists
        ],
      ),
    );
  }

  Widget _buildArtistsTab(BuildContext context, String query) {
    final theme = Theme.of(context);
    // This should ideally fetch a list of *artists*, not just tracks by one artist.
    // For this example, we'll continue using fetchArtistTracks and assume it returns tracks
    // by the searched artist. A better approach would be musicProvider.searchArtists(query).
    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        // If query is empty, show suggestions or recent searches
        if (query.trim().isEmpty && provider.artistTracks.isEmpty) {
          return Center(
            child: Text(
              'Search for artists.',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6)),
            ),
          );
        }

        // If there's a query but no results yet (or loading state)
        // Provider should have an isLoading flag for artist search
        // if (provider.isLoadingArtists && provider.artistTracks.isEmpty) {
        //   return Center(child: CircularProgressIndicator());
        // }

        if (provider.artistTracks.isEmpty && query.trim().isNotEmpty) {
          return Center(
            child: Text(
              'No artists found for "$query".',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.8)),
            ),
          );
        }

        // Group tracks by artist to simulate a list of artists
        // This is a workaround. Ideally, the API returns a list of artists.
        final Map<String, List<Track>> tracksByArtist = {};
        for (var track in provider.artistTracks) {
          tracksByArtist.putIfAbsent(track.artistName, () => []).add(track);
        }
        final uniqueArtists = tracksByArtist.keys.toList();


        // Display results
        // This should be a list of ArtistSearchTile or similar
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          itemCount: uniqueArtists.length, // provider.searchedArtists.length
          itemBuilder: (context, index) {
            final artistName = uniqueArtists[index];
            // final artist = provider.searchedArtists[index]; // Ideal
            // For now, just showing the name as a simple text tile
            return ArtistSearchTile(
              artistName: artistName, // artist.name
              // artistImageUrl: artist.imageUrl, // If available
              onTap: () {
                // Navigate to artist detail screen
                // Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artist: artist)));
                 ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Navigate to $artistName's screen (not implemented)")),
                  );
                // For now, we can play the first track of this artist as an example
                if (tracksByArtist[artistName]!.isNotEmpty) {
                  provider.playTrack(tracksByArtist[artistName]!.first, playlistTracks: tracksByArtist[artistName]);
                }
              }
            );
          },
        );
      },
    );
  }

  Widget _buildPlaylistsTab(BuildContext context, String query) {
     final theme = Theme.of(context);
    // Placeholder - implement similar to artists tab with playlist-specific search and tiles
    return Center(
      child: Text(
        'Playlist search coming soon!',
        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6)),
      ),
    );
  }
}