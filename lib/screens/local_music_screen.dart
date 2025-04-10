// lib/screens/local_music_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../services/local_music_service.dart'; // Keep for SortCriteria Enum
import '../widgets/track_tile.dart'; // Use the standard TrackTile

class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({Key? key}) : super(key: key);

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Ensure data is loaded when the screen is first displayed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
      // Load only if the list is empty AND not already loading
      if (musicProvider.localTracks.isEmpty && !musicProvider.isLoadingLocal) {
        musicProvider.loadLocalMusicFiles();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- Actions call Provider ---
  Future<void> _refreshLocalMusic() async {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    await musicProvider.loadLocalMusicFiles(forceRescan: true);
  }

  void _sortTracks(SortCriteria criteria) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    musicProvider.sortLocalTracks(criteria);
  }

  void _addFolder() async {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    await musicProvider.addLocalMusicFolder();
    // Provider notifies listeners, UI will update
  }

  @override
  Widget build(BuildContext context) {
    // Use Consumer to react to provider changes
    return Consumer<MusicProvider>(
        builder: (context, musicProvider, child) {
          // Get data directly from provider
          final allTracks = musicProvider.localTracks;
          final isLoading = musicProvider.isLoadingLocal;
          final currentCriteria = musicProvider.localTracksSortCriteria;

          // Grouping happens here based on the provider's list
          // Ensure it runs only when needed, maybe cache slightly if performance intensive
          // For now, recalculate on each build relying on provider update frequency
          final folderGroupedTracks = isLoading ? <String, List<Track>>{} : LocalMusicService.groupTracksByFolder(allTracks);

          return Scaffold(
            backgroundColor: const Color(0xFF121212),
            appBar: AppBar(
              backgroundColor: const Color(0xFF1D1D1D),
              leading: IconButton( // Add back button
                icon: Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: const Text('Local Music'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.play_arrow, color: Colors.white),
                  tooltip: "Play All",
                  // Disable if loading or no tracks
                  onPressed: isLoading || allTracks.isEmpty ? null : () => musicProvider.playAllLocalTracks(),
                ),
                IconButton(
                  // Toggle icon based on provider state
                  icon: Icon(musicProvider.shuffleEnabled ? Icons.shuffle_on : Icons.shuffle, color: Colors.white),
                  tooltip: "Shuffle All",
                  onPressed: isLoading || allTracks.isEmpty ? null : () => musicProvider.playAllLocalTracks(shuffle: !musicProvider.shuffleEnabled),
                ),
                IconButton(
                  icon: const Icon(Icons.sort, color: Colors.white),
                  tooltip: "Sort",
                  // Disable sort button while loading
                  onPressed: isLoading ? null : () => _showSortOptions(context, currentCriteria),
                ),
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined, color: Colors.white),
                  tooltip: "Add Folder to Scan",
                  // Disable add folder while loading
                  onPressed: isLoading ? null : _addFolder,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: "Refresh",
                  // Disable refresh while loading
                  onPressed: isLoading ? null : _refreshLocalMusic,
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: Colors.deepPurple,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey[400],
                tabs: const [
                  Tab(text: 'Tracks'), // Renamed for clarity
                  Tab(text: 'Folders'),
                ],
              ),
              elevation: 0,
            ),
            body: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
            // Check if NOT loading AND list is empty for the empty state
                : !isLoading && allTracks.isEmpty
                ? _buildEmptyState()
                : TabBarView(
              controller: _tabController,
              children: [
                _buildTracksTab(allTracks, musicProvider), // Pass sorted list
                _buildFoldersTab(folderGroupedTracks, musicProvider), // Pass grouped map
              ],
            ),
          );
        }
    );
  }

  Widget _buildTracksTab(List<Track> tracks, MusicProvider musicProvider) {
    // No Consumer needed here, data passed directly
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
        // Use the standard TrackTile!
        return TrackTile(
          track: track,
          isPlaying: isPlaying, // Pass playing state
          onTap: () => musicProvider.playOfflineTrack(track), // Use specific play method
          // You might want to disable the like button for local tracks if not supported
          // showLikeButton: false,
        );
      },
    );
  }

  Widget _buildFoldersTab(Map<String, List<Track>> groupedTracks, MusicProvider musicProvider) {
    // No Consumer needed here
    final folders = groupedTracks.keys.toList()
      ..sort((a,b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ListView.builder(
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folderName = folders[index];
        final tracks = groupedTracks[folderName] ?? [];
        // Sort tracks within the folder according to the global sort criteria
        final sortedTracksInFolder = LocalMusicService.sortTracks(tracks, musicProvider.localTracksSortCriteria);

        return ExpansionTile(
          title: Text(folderName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          subtitle: Text('${tracks.length} track${tracks.length == 1 ? "" : "s"}', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          leading: const Icon(Icons.folder_open, color: Colors.amberAccent),
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white70,
          childrenPadding: const EdgeInsets.only(left: 16.0), // Indent tracks slightly
          children: sortedTracksInFolder.map((track) { // Use sorted tracks
            final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
            // Use the standard TrackTile!
            return TrackTile(
              track: track,
              isPlaying: isPlaying, // Pass playing state
              onTap: () => musicProvider.playOfflineTrack(track),
              // showLikeButton: false,
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_off_outlined, size: 70, color: Colors.grey[600]),
            const SizedBox(height: 20),
            const Text(
              'No Local Music Found',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Tap the folder icon (+) in the top bar to add folders containing music from your device storage.',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white, // Text/Icon color
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: _addFolder, // Action points to add folder
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Add Music Folder'),
            ),
          ],
        ),
      ),
    );
  }

  // Show sort options, highlighting the current selection
  void _showSortOptions(BuildContext context, SortCriteria currentCriteria) {
    Color getTileColor(SortCriteria criteria) {
      return currentCriteria == criteria ? Colors.deepPurple.withOpacity(0.3) : Colors.transparent;
    }
    Icon getLeadingIcon(SortCriteria criteria) {
      final isSelected = currentCriteria == criteria;
      final color = isSelected ? Colors.deepPurple : Colors.white70;
      switch(criteria) {
        case SortCriteria.nameAsc:
        case SortCriteria.nameDesc: return Icon(Icons.sort_by_alpha, color: color);
        case SortCriteria.artistAsc:
        case SortCriteria.artistDesc: return Icon(Icons.person_search, color: color);
        case SortCriteria.albumAsc:
        case SortCriteria.albumDesc: return Icon(Icons.album, color: color);
        case SortCriteria.durationAsc:
        case SortCriteria.durationDesc: return Icon(Icons.timer, color: color);
        case SortCriteria.folderAsc:
        case SortCriteria.folderDesc: return Icon(Icons.folder_copy_outlined, color: color);
        case SortCriteria.dateAddedAsc:
        case SortCriteria.dateAddedDesc: return Icon(Icons.event_note, color: color);
      }
    }

    // Build items based on updated SortCriteria enum
    final items = [
      MapEntry(SortCriteria.nameAsc, 'Name (A-Z)'),
      MapEntry(SortCriteria.nameDesc, 'Name (Z-A)'),
      MapEntry(SortCriteria.artistAsc, 'Artist (A-Z)'),
      MapEntry(SortCriteria.artistDesc, 'Artist (Z-A)'),
      MapEntry(SortCriteria.albumAsc, 'Album (A-Z)'),
      MapEntry(SortCriteria.albumDesc, 'Album (Z-A)'),
      MapEntry(SortCriteria.durationAsc, 'Duration (Shortest)'),
      MapEntry(SortCriteria.durationDesc, 'Duration (Longest)'),
      MapEntry(SortCriteria.folderAsc, 'Folder (A-Z)'),
      MapEntry(SortCriteria.folderDesc, 'Folder (Z-A)'),
      MapEntry(SortCriteria.dateAddedAsc, 'Date Added (Oldest)'),
      MapEntry(SortCriteria.dateAddedDesc, 'Date Added (Newest)'),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1D1D1D),
      builder: (context) => SafeArea( // Ensure content avoids notches etc.
        child: SingleChildScrollView( // Allow scrolling if many options
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: items.map((entry) {
              final criteria = entry.key;
              final title = entry.value;
              return ListTile(
                tileColor: getTileColor(criteria),
                title: Text(title, style: const TextStyle(color: Colors.white)),
                leading: getLeadingIcon(criteria),
                onTap: () {
                  Navigator.pop(context);
                  _sortTracks(criteria); // Call provider sort
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}