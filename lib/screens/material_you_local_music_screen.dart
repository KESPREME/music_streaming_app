import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../services/local_music_service.dart';
import '../widgets/material_you_track_tile.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouLocalMusicScreen extends StatefulWidget {
  const MaterialYouLocalMusicScreen({super.key});

  @override
  State<MaterialYouLocalMusicScreen> createState() => _MaterialYouLocalMusicScreenState();
}

class _MaterialYouLocalMusicScreenState extends State<MaterialYouLocalMusicScreen> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _scrollController;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
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
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final allTracks = musicProvider.localTracks;
        final isLoading = musicProvider.isLoadingLocal;
        final currentCriteria = musicProvider.localTracksSortCriteria;
        final folderGroupedTracks = isLoading 
            ? <String, List<Track>>{} 
            : LocalMusicService.groupTracksByFolder(allTracks);

        return Scaffold(
          backgroundColor: MaterialYouTokens.surfaceDark,
          body: SafeArea(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  backgroundColor: innerBoxIsScrolled 
                      ? MaterialYouTokens.surfaceContainerDark 
                      : MaterialYouTokens.surfaceDark,
                  surfaceTintColor: Colors.transparent,
                  floating: true,
                  pinned: true,
                  elevation: innerBoxIsScrolled ? 2 : 0,
                  expandedHeight: 120,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: colorScheme.onSurface,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 56, bottom: 50),
                    title: Text(
                      'Local Music',
                      style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.create_new_folder_outlined),
                      tooltip: "Add Folder",
                      color: colorScheme.onSurface,
                      onPressed: isLoading ? null : _addFolder,
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: "Refresh",
                      color: colorScheme.onSurface,
                      onPressed: isLoading ? null : _refreshLocalMusic,
                    ),
                    IconButton(
                      icon: const Icon(Icons.sort_rounded),
                      tooltip: "Sort",
                      color: colorScheme.onSurface,
                      onPressed: isLoading ? null : () => _showSortOptions(context, currentCriteria, colorScheme),
                    ),
                  ],
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(48),
                    child: Container(
                      color: Colors.transparent,
                      child: TabBar(
                        controller: _tabController,
                        indicatorColor: MaterialYouTokens.primaryVibrant,
                        labelColor: MaterialYouTokens.primaryVibrant,
                        unselectedLabelColor: colorScheme.onSurfaceVariant,
                        labelStyle: MaterialYouTypography.titleMedium(MaterialYouTokens.primaryVibrant),
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
                  ? Center(
                      child: CircularProgressIndicator(
                        color: MaterialYouTokens.primaryVibrant,
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTracksTab(allTracks, musicProvider, colorScheme),
                        _buildFoldersTab(folderGroupedTracks, musicProvider, colorScheme),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTracksTab(List<Track> tracks, MusicProvider musicProvider, ColorScheme colorScheme) {
    if (tracks.isEmpty) return _buildEmptyState(colorScheme);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
        return MaterialYouTrackTile(
          track: track,
          isPlaying: isPlaying,
          onTap: () => musicProvider.playOfflineTrack(track),
        );
      },
    );
  }

  Widget _buildFoldersTab(Map<String, List<Track>> groupedTracks, MusicProvider musicProvider, ColorScheme colorScheme) {
    if (groupedTracks.isEmpty) return _buildEmptyState(colorScheme);
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
          collapsedIconColor: colorScheme.onSurfaceVariant,
          iconColor: MaterialYouTokens.primaryVibrant,
          leading: Icon(Icons.folder_open_rounded, color: MaterialYouTokens.primaryVibrant),
          title: Text(
            folderName, 
            style: MaterialYouTypography.titleMedium(colorScheme.onSurface)
          ),
          subtitle: Text(
            '${tracks.length} tracks', 
            style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant)
          ),
          children: sortedTracksInFolder.map((track) {
            final isPlaying = musicProvider.currentTrack?.id == track.id && musicProvider.isPlaying;
            return MaterialYouTrackTile(
              track: track,
              isPlaying: isPlaying,
              onTap: () => musicProvider.playOfflineTrack(track),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_off_rounded, 
            size: 70, 
            color: colorScheme.onSurface.withOpacity(0.2)
          ),
          const SizedBox(height: 20),
          Text(
            'No Local Music Found',
            style: MaterialYouTypography.titleLarge(
              colorScheme.onSurface.withOpacity(0.6)
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tap the folder icon (+) to add music folders.',
            style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 30),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: MaterialYouTokens.primaryVibrant,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
              ),
            ),
            onPressed: _addFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add Folder'),
          ),
        ],
      ),
    );
  }

  void _showSortOptions(BuildContext context, SortCriteria currentCriteria, ColorScheme colorScheme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MaterialYouTokens.surfaceContainerDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MaterialYouTokens.shapeLarge)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var item in [
                const MapEntry(SortCriteria.nameAsc, 'Name (A-Z)'),
                const MapEntry(SortCriteria.nameDesc, 'Name (Z-A)'),
                const MapEntry(SortCriteria.dateAddedDesc, 'Date Added (Newest)'),
                const MapEntry(SortCriteria.dateAddedAsc, 'Date Added (Oldest)'),
              ])
                ListTile(
                  title: Text(
                    item.value, 
                    style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)
                  ),
                  leading: Icon(
                    Icons.sort, 
                    color: currentCriteria == item.key 
                        ? MaterialYouTokens.primaryVibrant 
                        : colorScheme.onSurfaceVariant
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _sortTracks(item.key);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
