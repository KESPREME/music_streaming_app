import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../widgets/material_you_track_tile.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';
import '../widgets/material_you_options_sheet.dart';

class MaterialYouPlaylistDetailScreen extends StatefulWidget {
  final String playlistId;
  final String playlistName;
  final String? playlistImage;
  final List<Track>? cachedTracks;
  final bool searchAlbumByName;
  final String? artistNameHint;

  const MaterialYouPlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.playlistName,
    this.playlistImage,
    this.cachedTracks,
    this.searchAlbumByName = false,
    this.artistNameHint,
  });

  @override
  State<MaterialYouPlaylistDetailScreen> createState() => _MaterialYouPlaylistDetailScreenState();
}

class _MaterialYouPlaylistDetailScreenState extends State<MaterialYouPlaylistDetailScreen> {
  bool _isLoading = true;
  List<Track> _tracks = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.cachedTracks != null && widget.cachedTracks!.isNotEmpty) {
      _tracks = widget.cachedTracks!;
      _isLoading = false;
    } else {
      _fetchDetails();
    }
  }

  Future<void> _fetchDetails() async {
    try {
      final provider = Provider.of<MusicProvider>(context, listen: false);
      List<Track> tracks = [];
      
      if (widget.searchAlbumByName && widget.playlistId.isEmpty) {
        final searchQuery = widget.artistNameHint != null 
            ? '${widget.playlistName} ${widget.artistNameHint}'
            : widget.playlistName;
        
        await provider.navigateToAlbum(widget.playlistName, widget.artistNameHint ?? '');
        
        if (provider.currentAlbumDetails != null) {
          tracks = provider.currentAlbumDetails!.tracks;
        }
      } else if (widget.playlistId.isNotEmpty) {
        if (widget.playlistId.startsWith('MPREb_') || widget.playlistId.startsWith('OLAK')) {
          tracks = await provider.fetchAlbumTracks(widget.playlistId);
        } else {
          tracks = await provider.fetchPlaylistDetails(widget.playlistId);
        }
      }
      
      if (mounted) {
        if (tracks.isEmpty && widget.searchAlbumByName) {
          setState(() {
            _error = 'Could not find album: ${widget.playlistName}';
            _isLoading = false;
          });
        } else {
          setState(() {
            _tracks = tracks;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load playlist';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      floatingActionButton: _tracks.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                final provider = Provider.of<MusicProvider>(context, listen: false);
                provider.playTrack(_tracks.first, playlistTracks: _tracks);
              },
              backgroundColor: MaterialYouTokens.primaryVibrant,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play'),
            )
          : null,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(colorScheme),
          if (_isLoading)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: MaterialYouTokens.primaryVibrant),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  _error!,
                  style: MaterialYouTypography.bodyLarge(colorScheme.error),
                ),
              ),
            )
          else
            _buildTracksList(),
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(ColorScheme colorScheme) {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      stretch: true,
      backgroundColor: MaterialYouTokens.surfaceContainerDark,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: MaterialYouTokens.surfaceContainerDark,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          padding: EdgeInsets.zero, // Remove padding to center icon
          constraints: const BoxConstraints(), // reset constraints
          onPressed: () => Navigator.pop(context),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: MaterialYouTokens.surfaceContainerDark,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(Icons.more_vert_rounded, color: colorScheme.onSurface),
            onPressed: () async {
               final provider = Provider.of<MusicProvider>(context, listen: false);
               provider.setMiniPlayerVisible(false);
               await showModalBottomSheet(
                 context: context,
                 backgroundColor: Colors.transparent,
                 isScrollControlled: true,
                 builder: (context) => MaterialYouOptionsSheet(
                   track: _tracks.isNotEmpty ? _tracks.first : null, // Fallback if empty
                   playlistId: widget.playlistId,
                   playlistName: widget.playlistName,
                   isAlbum: true,
                 ),
               );
               provider.setMiniPlayerVisible(true);
            },
          ),
        ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final double percentage = ((constraints.maxHeight - kToolbarHeight) / 
                                     (300 - kToolbarHeight)).clamp(0.0, 1.0);

          return FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
            centerTitle: false,
            title: Text(
              widget.playlistName,
              style: MaterialYouTypography.headlineSmall(colorScheme.onSurface)
                  .copyWith(fontSize: 16 + (6 * percentage)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.playlistImage != null)
                  Image.network(
                    widget.playlistImage!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: MaterialYouTokens.surfaceContainerDark,
                    ),
                  )
                else
                  Container(
                    color: MaterialYouTokens.surfaceContainerDark,
                    child: Center(
                      child: Icon(
                        Icons.music_note,
                        size: 80,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.transparent,
                        Colors.black.withOpacity(0.6),
                        Colors.black,
                      ],
                      stops: const [0.0, 0.4, 0.8, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTracksList() {
    if (_tracks.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(50),
          child: Center(
            child: Text(
              "Empty playlist",
              style: MaterialYouTypography.bodyLarge(
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final track = _tracks[index];
          final provider = Provider.of<MusicProvider>(context, listen: false);
          final isPlaying = provider.currentTrack?.id == track.id && provider.isPlaying;
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: MaterialYouTrackTile(
              track: track,
              isPlaying: isPlaying,
              onTap: () {
                provider.playTrack(track, playlistTracks: _tracks);
              },
            ),
          );
        },
        childCount: _tracks.length,
      ),
    );
  }
}
