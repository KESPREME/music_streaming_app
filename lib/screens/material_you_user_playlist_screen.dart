import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/playlist.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';
import '../widgets/material_you_elevated_card.dart';

class MaterialYouUserPlaylistScreen extends StatefulWidget {
  const MaterialYouUserPlaylistScreen({super.key});

  @override
  State<MaterialYouUserPlaylistScreen> createState() => _MaterialYouUserPlaylistScreenState();
}

class _MaterialYouUserPlaylistScreenState extends State<MaterialYouUserPlaylistScreen> {
  late ScrollController _scrollController;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      body: SafeArea(
        child: Consumer<MusicProvider>(
          builder: (context, musicProvider, child) {
            final playlists = musicProvider.userPlaylists;

            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  backgroundColor: _isScrolled 
                      ? MaterialYouTokens.surfaceContainerDark 
                      : MaterialYouTokens.surfaceDark,
                  surfaceTintColor: Colors.transparent,
                  floating: true,
                  pinned: true,
                  elevation: _isScrolled ? 2 : 0,
                  expandedHeight: 100,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
                    title: Text(
                      'Your Playlists',
                      style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.add_rounded, size: 28),
                      color: MaterialYouTokens.primaryVibrant,
                      onPressed: () => _showCreatePlaylistDialog(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                if (playlists.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.queue_music_rounded,
                            size: 80,
                            color: colorScheme.onSurface.withOpacity(0.1),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No playlists yet',
                            style: MaterialYouTypography.titleMedium(
                              colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create or import playlists to get started',
                            style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: MaterialYouTokens.primaryVibrant,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            onPressed: () => _showCreatePlaylistDialog(context),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Create Playlist'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final playlist = playlists[index];
                          return _buildPlaylistCard(context, playlist, colorScheme);
                        },
                        childCount: playlists.length,
                      ),
                    ),
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaylistCard(BuildContext context, Playlist playlist, ColorScheme colorScheme) {
    return MaterialYouElevatedCard(
      elevation: 2,
      borderRadius: MaterialYouTokens.shapeMedium,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ThemedPlaylistDetailScreen(
              playlistId: playlist.id,
              playlistName: playlist.name,
              playlistImage: playlist.imageUrl,
              cachedTracks: playlist.tracks,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(MaterialYouTokens.shapeMedium),
              ),
              child: playlist.imageUrl.isNotEmpty
                  ? Image.network(
                      playlist.imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: MaterialYouTokens.surfaceContainerDark,
                        child: Center(
                          child: Icon(
                            Icons.music_note,
                            color: colorScheme.onSurfaceVariant,
                            size: 40,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      color: MaterialYouTokens.surfaceContainerDark,
                      child: Center(
                        child: Icon(
                          Icons.music_note,
                          color: colorScheme.onSurfaceVariant,
                          size: 40,
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name,
                  style: MaterialYouTypography.titleMedium(colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${playlist.tracks.length} tracks',
                  style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurfaceVariant, size: 20),
              onPressed: () => _showPlaylistOptions(context, playlist, colorScheme),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final nameController = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MaterialYouTokens.surfaceContainerDark,
        title: Text(
          'Create Playlist',
          style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
        ),
        content: TextField(
          controller: nameController,
          style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Playlist Name',
            hintStyle: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: MaterialYouTokens.primaryVibrant.withOpacity(0.5)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: MaterialYouTokens.primaryVibrant),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: MaterialYouTypography.labelLarge(colorScheme.onSurfaceVariant),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MaterialYouTokens.primaryVibrant,
              foregroundColor: Colors.black,
            ),
            child: const Text('Create'),
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                final musicProvider = Provider.of<MusicProvider>(context, listen: false);
                musicProvider.createPlaylist(nameController.text.trim(), initialTracks: []);
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showPlaylistOptions(BuildContext context, Playlist playlist, ColorScheme colorScheme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MaterialYouTokens.surfaceContainerDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MaterialYouTokens.shapeLarge)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_rounded, color: colorScheme.onSurface),
              title: Text('Rename', style: MaterialYouTypography.bodyLarge(colorScheme.onSurface)),
              onTap: () {
                Navigator.pop(context);
                _showRenamePlaylistDialog(context, playlist, colorScheme);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: Text('Delete', style: MaterialYouTypography.bodyLarge(Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(context, playlist, colorScheme);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenamePlaylistDialog(BuildContext context, Playlist playlist, ColorScheme colorScheme) {
    final nameController = TextEditingController(text: playlist.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MaterialYouTokens.surfaceContainerDark,
        title: Text('Rename Playlist', style: MaterialYouTypography.titleLarge(colorScheme.onSurface)),
        content: TextField(
          controller: nameController,
          style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: MaterialYouTypography.labelLarge(colorScheme.onSurfaceVariant)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('Save', style: MaterialYouTypography.labelLarge(MaterialYouTokens.primaryVibrant)),
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Playlist playlist, ColorScheme colorScheme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MaterialYouTokens.surfaceContainerDark,
        title: Text('Delete Playlist', style: MaterialYouTypography.titleLarge(colorScheme.onSurface)),
        content: Text(
          'Are you sure you want to delete "${playlist.name}"?',
          style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: MaterialYouTypography.labelLarge(colorScheme.onSurfaceVariant)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('Delete', style: MaterialYouTypography.labelLarge(Colors.redAccent)),
            onPressed: () {
              final musicProvider = Provider.of<MusicProvider>(context, listen: false);
              musicProvider.deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
