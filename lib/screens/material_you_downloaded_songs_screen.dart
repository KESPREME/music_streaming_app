import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouDownloadedSongsScreen extends StatefulWidget {
  const MaterialYouDownloadedSongsScreen({super.key});

  @override
  State<MaterialYouDownloadedSongsScreen> createState() => _MaterialYouDownloadedSongsScreenState();
}

class _MaterialYouDownloadedSongsScreenState extends State<MaterialYouDownloadedSongsScreen> {
  List<Track> _downloadedTracks = [];
  bool _isLoading = true;
  late ScrollController _scrollController;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadDownloadedSongs();
  }

  void _onScroll() {
    final isScrolled = _scrollController.hasClients && _scrollController.offset > 10;
    if (isScrolled != _isScrolled) {
      setState(() {
        _isScrolled = isScrolled;
      });
    }
  }

  Future<void> _loadDownloadedSongs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
      final tracks = await musicProvider.getDownloadedTracks();

      setState(() {
        _downloadedTracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading downloaded songs: $e'),
            backgroundColor: MaterialYouTokens.surfaceContainerDark,
          ),
        );
      }
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
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: MaterialYouTokens.primaryVibrant,
                ),
              )
            : Consumer<MusicProvider>(
                builder: (context, musicProvider, child) {
                  final downloadingTracks = musicProvider.currentlyDownloadingTracks;

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
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: colorScheme.onSurface,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        flexibleSpace: FlexibleSpaceBar(
                          titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
                          title: Text(
                            'Downloaded',
                            style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
                          ),
                        ),
                      ),
                      if (_downloadedTracks.isEmpty && downloadingTracks.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.download_done_rounded,
                                  size: 80,
                                  color: colorScheme.onSurface.withOpacity(0.1),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No downloaded songs yet',
                                  style: MaterialYouTypography.titleMedium(
                                    colorScheme.onSurface.withOpacity(0.6)
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Download songs to listen offline',
                                  style: MaterialYouTypography.bodyMedium(
                                    colorScheme.onSurfaceVariant
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        // Currently downloading section
                        if (downloadingTracks.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                'Downloading',
                                style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
                              ),
                            ),
                          ),
                        if (downloadingTracks.isNotEmpty)
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final track = downloadingTracks[index];
                                final progress = musicProvider.downloadProgress[track.id] ?? 0.0;
                                return _buildDownloadingItem(track, progress, musicProvider, colorScheme);
                              },
                              childCount: downloadingTracks.length,
                            ),
                          ),

                        // Downloaded section
                        if (_downloadedTracks.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                              child: Text(
                                'Downloaded',
                                style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
                              ),
                            ),
                          ),
                        if (_downloadedTracks.isNotEmpty)
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final track = _downloadedTracks[index];
                                return _buildDownloadedItem(track, musicProvider, colorScheme);
                              },
                              childCount: _downloadedTracks.length,
                            ),
                          ),
                      ],
                      const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildDownloadingItem(Track track, double progress, MusicProvider musicProvider, ColorScheme colorScheme) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
        child: Image.network(
          track.albumArtUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 56,
            height: 56,
            color: MaterialYouTokens.surfaceContainerDark,
            child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
      title: Text(
        track.trackName,
        style: MaterialYouTypography.titleMedium(colorScheme.onSurface),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: colorScheme.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(MaterialYouTokens.accentGreen),
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 4),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(Icons.cancel_rounded, color: colorScheme.onSurfaceVariant),
        onPressed: () {
          musicProvider.cancelDownload(track.id);
        },
      ),
    );
  }

  Widget _buildDownloadedItem(Track track, MusicProvider musicProvider, ColorScheme colorScheme) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
        child: Image.network(
          track.albumArtUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 56,
            height: 56,
            color: MaterialYouTokens.surfaceContainerDark,
            child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
      title: Text(
        track.trackName,
        style: MaterialYouTypography.titleMedium(colorScheme.onSurface),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artistName,
        style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.play_arrow_rounded, color: colorScheme.onSurface),
            onPressed: () {
              musicProvider.playOfflineTrack(track, contextList: _downloadedTracks);
            },
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: colorScheme.onSurfaceVariant),
            onPressed: () async {
              await musicProvider.deleteDownloadedTrack(track.id);
              _loadDownloadedSongs();
            },
          ),
        ],
      ),
      onTap: () => musicProvider.playOfflineTrack(track, contextList: _downloadedTracks),
    );
  }
}
