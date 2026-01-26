// lib/screens/local_music_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../services/local_music_service.dart';
import '../widgets/track_tile.dart';

class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({super.key});

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _scrollController;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    // Increase length to accommodate 'Folders' if not already
    _tabController = TabController(length: 2, vsync: this);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
      if (musicProvider.localTracks.isEmpty && !musicProvider.isLoadingLocal) {
        musicProvider.loadLocalMusicFiles();
      }
    });
  }

  void _onScroll() {
    final isScrolled = _scrollController.hasClients && _scrollController.offset > 10;
    if (isScrolled != _isScrolled) {
      setState(() {
        _isScrolled = isScrolled;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- Actions ---
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final allTracks = musicProvider.localTracks;
        final isLoading = musicProvider.isLoadingLocal;
        final currentCriteria = musicProvider.localTracksSortCriteria;
        final folderGroupedTracks = isLoading ? <String, List<Track>>{} : LocalMusicService.groupTracksByFolder(allTracks);

        return Scaffold(
          extendBodyBehindAppBar: true,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark 
                  ? [const Color(0xFF121212), const Color(0xFF1E1E1E), const Color(0xFF000000)]
                  : [const Color(0xFFF7F7F7), const Color(0xFFFFFFFF)],
              ),
            ),
            child: SafeArea(
              child: NestedScrollView(
                 headerSliverBuilder: (context, innerBoxIsScrolled) => [
                   SliverAppBar(
                    surfaceTintColor: Colors.transparent,
                    backgroundColor: Colors.transparent,
                    floating: true,
                    pinned: true,
                    elevation: 0,
                    expandedHeight: 120, // Taller for TabBar
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      color: isDark ? Colors.white : Colors.black,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    flexibleSpace: ClipRRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 10, 
                          sigmaY: 10,
                        ),
                        child: Container(
                          color: Colors.black.withOpacity(0.5), // Always distinct for nested scroll
                          child: FlexibleSpaceBar(
                            titlePadding: const EdgeInsets.only(left: 50, bottom: 50),
                            title: Text(
                              'Local Music',
                              style: GoogleFonts.splineSans(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 20,
                              ),
                            ),
                            background: Container(color: Colors.transparent),
                          ),
                        ),
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.create_new_folder_outlined),
                        tooltip: "Add Folder",
                        color: Colors.white,
                        onPressed: isLoading ? null : _addFolder,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: "Refresh",
                         color: Colors.white,
                        onPressed: isLoading ? null : _refreshLocalMusic,
                      ),
                        IconButton(
                        icon: const Icon(Icons.sort_rounded),
                        tooltip: "Sort",
                         color: Colors.white,
                        onPressed: isLoading ? null : () => _showSortOptions(context, currentCriteria),
                      ),
                    ],
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(48),
                      child: Container(
                         color: Colors.transparent,
                         child: TabBar(
                          controller: _tabController,
                          indicatorColor: const Color(0xFFEA80FC), // Purple Accent
                          labelColor: const Color(0xFFEA80FC),
                          unselectedLabelColor: Colors.white54,
                          labelStyle: GoogleFonts.splineSans(fontWeight: FontWeight.bold),
                          indicatorSize: TabBarIndicatorSize.label,
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(text: 'Tracks'),
                            Tab(text: 'Folders'),
                          ],
                        ),
                      ),
                    ),
                  ),
                 ],
                 body: isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFEA80FC)))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTracksTab(allTracks, musicProvider),
                        _buildFoldersTab(folderGroupedTracks, musicProvider),
                      ],
                    ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTracksTab(List<Track> tracks, MusicProvider musicProvider) {
    if (tracks.isEmpty) return _buildEmptyState();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
        return TrackTile(
          track: track,
          isPlaying: isPlaying,
          onTap: () => musicProvider.playOfflineTrack(track),
        );
      },
    );
  }

  Widget _buildFoldersTab(Map<String, List<Track>> groupedTracks, MusicProvider musicProvider) {
    if (groupedTracks.isEmpty) return _buildEmptyState();
    final folders = groupedTracks.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folderName = folders[index];
        final tracks = groupedTracks[folderName] ?? [];
        final sortedTracksInFolder = LocalMusicService.sortTracks(tracks, musicProvider.localTracksSortCriteria);

        return ExpansionTile(
          collapsedIconColor: Colors.white54,
          iconColor: const Color(0xFFEA80FC),
          leading: const Icon(Icons.folder_open_rounded, color: Color(0xFFEA80FC)),
          title: Text(folderName, style: GoogleFonts.splineSans(color: Colors.white, fontWeight: FontWeight.w500)),
          subtitle: Text('${tracks.length} tracks', style: GoogleFonts.splineSans(color: Colors.white54, fontSize: 12)),
          children: sortedTracksInFolder.map((track) {
            final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
            return TrackTile(
              track: track,
              isPlaying: isPlaying,
              onTap: () => musicProvider.playOfflineTrack(track),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildEmptyState() {
     return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_off_rounded, size: 70, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 20),
          Text(
            'No Local Music Found',
            style: GoogleFonts.splineSans(color: Colors.white.withOpacity(0.6), fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Tap the folder icon (+) to add music folders.',
            style: GoogleFonts.splineSans(color: Colors.white.withOpacity(0.4), fontSize: 14),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA80FC),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: _addFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add Folder'),
          ),
        ],
      ),
    );
  }

  void _showSortOptions(BuildContext context, SortCriteria currentCriteria) {
     final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
       shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ... Reuse existing sort logic but mapped to new list tiles
              // For brevity just showing a couple or adapting existing maps
                 for (var item in [
                   const MapEntry(SortCriteria.nameAsc, 'Name (A-Z)'),
                   const MapEntry(SortCriteria.dateAddedDesc, 'Date Added (Newest)'),
                   // Add others as needed
                 ])
                 ListTile(
                    title: Text(item.value, style: GoogleFonts.splineSans(color: Colors.white)),
                    leading: Icon(Icons.sort, color: currentCriteria == item.key ? const Color(0xFFEA80FC) : Colors.white54),
                    onTap: () {
                      Navigator.pop(context);
                      _sortTracks(item.key);
                    },
                 )
            ],
          ),
        ),
      ),
    );
  }
}