import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../widgets/material_you_track_tile.dart';
import '../widgets/material_you_elevated_card.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouArtistDetailScreen extends StatefulWidget {
  final String artistId;
  final String artistName;
  final String? artistImage;
  final bool searchByName;

  const MaterialYouArtistDetailScreen({
    super.key,
    required this.artistId,
    required this.artistName,
    this.artistImage,
    this.searchByName = false,
  });

  @override
  State<MaterialYouArtistDetailScreen> createState() => _MaterialYouArtistDetailScreenState();
}

class _MaterialYouArtistDetailScreenState extends State<MaterialYouArtistDetailScreen> {
  bool _isLoading = true;
  List<Track> _topSongs = [];
  List<dynamic> _albums = [];
  List<dynamic> _singles = [];
  String? _error;
  String? _resolvedArtistId;

  @override
  void initState() {
    super.initState();
    
    // Capture Flutter errors
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        print('Flutter Error: ${details.exception}');
        print('Stack trace: ${details.stack}');
      }
    };
    
    // Delay fetch to ensure widget is fully mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchDetails();
      }
    });
  }

  Future<void> _fetchDetails() async {
    if (!mounted) return;
    
    try {
      final provider = Provider.of<MusicProvider>(context, listen: false);
      
      String artistIdToFetch = widget.artistId;
      
      // Always search by name if ID is invalid or searchByName is true
      if (widget.searchByName || 
          widget.artistId.isEmpty || 
          widget.artistId.startsWith('artist_') ||
          !widget.artistId.contains('UC')) { // YouTube channel IDs start with UC
        
        if (kDebugMode) {
          print('Searching for artist: ${widget.artistName}');
        }
        
        await provider.fetchArtistTracks(widget.artistName)
            .timeout(const Duration(seconds: 10));
        
        final results = provider.artistTracks;
        if (results.isNotEmpty) {
          // Find the best match - prefer exact name match
          final exactMatch = results.firstWhere(
            (track) => track.artistName.toLowerCase() == widget.artistName.toLowerCase(),
            orElse: () => results.first,
          );
          artistIdToFetch = exactMatch.id;
          _resolvedArtistId = artistIdToFetch;
          
          if (kDebugMode) {
            print('Found artist ID: $artistIdToFetch');
          }
        } else {
          if (mounted) {
            setState(() {
              _error = 'Could not find artist: ${widget.artistName}';
              _isLoading = false;
            });
          }
          return;
        }
      }
      
      if (artistIdToFetch.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'Could not find artist: ${widget.artistName}';
            _isLoading = false;
          });
        }
        return;
      }
      
      if (kDebugMode) {
        print('Fetching artist details for ID: $artistIdToFetch');
      }
      
      final details = await provider.fetchArtistDetails(artistIdToFetch)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('Artist details fetch timed out');
            },
          );
      
      if (!mounted) return;
      
      setState(() {
        _topSongs = (details['tracks'] as List?)?.map((item) {
          if (item is Track) return item;
          if (item is Map) {
             return Track(
               id: item['videoId'] ?? item['id'] ?? '',
               trackName: item['title'] ?? item['name'] ?? 'Unknown',
               artistName: item['artist'] ?? item['artistName'] ?? widget.artistName,
               albumName: item['album'] ?? item['albumName'] ?? 'Unknown Album',
               previewUrl: '',
               albumArtUrl: item['thumbnail'] ?? item['albumArtUrl'] ?? '',
               source: 'youtube',
             );
          }
          return null;
        }).whereType<Track>().toList() ?? [];
        
        _albums = details['albums'] ?? [];
        _singles = details['singles'] ?? [];
        _isLoading = false;
        _error = null; // Clear any previous errors
      });
    } on TimeoutException catch (e, stackTrace) {
      if (kDebugMode) {
        print('Timeout loading artist details: $e');
        print('Stack trace: $stackTrace');
      }
      if (mounted) {
        setState(() {
          _error = 'Request timed out. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Error loading artist details: $e');
        print('Stack trace: $stackTrace');
      }
      if (mounted) {
        setState(() {
          _error = 'Failed to load artist details.\nPlease check your connection and try again.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // Ensure we have a valid context
    if (!mounted) {
      return Container(color: MaterialYouTokens.surfaceDark);
    }
    
    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      floatingActionButton: (!_isLoading && _error == null && _topSongs.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: () {
                final provider = Provider.of<MusicProvider>(context, listen: false);
                provider.playTrack(_topSongs.first, playlistTracks: _topSongs);
              },
              backgroundColor: MaterialYouTokens.primaryVibrant,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play'),
            )
          : null,
      body: SafeArea(
        child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(context, colorScheme),
          if (_isLoading)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: MaterialYouTokens.primaryVibrant),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 64,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: MaterialYouTypography.bodyLarge(colorScheme.error),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _error = null;
                          });
                          _fetchDetails();
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                        style: FilledButton.styleFrom(
                          backgroundColor: MaterialYouTokens.primaryVibrant,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            if (_topSongs.isNotEmpty) ...[
               _buildSectionTitle("Popular Songs", colorScheme),
               _buildTopSongsList(context),
            ],
            if (_albums.isNotEmpty) ...[
               _buildSectionTitle("Albums", colorScheme),
               _buildHorizontalCarousel(_albums, context),
            ],
            if (_singles.isNotEmpty) ...[
               _buildSectionTitle("Singles & EPs", colorScheme),
               _buildHorizontalCarousel(_singles, context),
            ],
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ]
        ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, ColorScheme colorScheme) {
    return SliverAppBar(
      expandedHeight: 340,
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
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final double percentage = ((constraints.maxHeight - kToolbarHeight) / 
                                     (340 - kToolbarHeight)).clamp(0.0, 1.0);

          return FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
            centerTitle: false,
            title: Text(
              widget.artistName,
              style: MaterialYouTypography.headlineSmall(colorScheme.onSurface)
                  .copyWith(fontSize: 16 + (8 * percentage)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.artistImage != null)
                  Image.network(
                    widget.artistImage!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: MaterialYouTokens.surfaceContainerDark,
                    ),
                  )
                else
                  Container(
                    color: MaterialYouTokens.surfaceContainerDark,
                    child: Center(
                      child: Icon(Icons.person, size: 80, color: colorScheme.onSurfaceVariant),
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

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 10),
        child: Text(
          title,
          style: MaterialYouTypography.titleLarge(colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _buildTopSongsList(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final track = _topSongs[index];
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Consumer<MusicProvider>(
              builder: (context, provider, child) {
                final isPlaying = provider.currentTrack?.id == track.id && provider.isPlaying;
                return MaterialYouTrackTile(
                  track: track,
                  isPlaying: isPlaying,
                  onTap: () {
                    provider.playTrack(track, playlistTracks: _topSongs);
                  },
                );
              },
            ),
          );
        },
        childCount: _topSongs.length > 5 ? 5 : _topSongs.length,
      ),
    );
  }

  Widget _buildHorizontalCarousel(List<dynamic> items, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 190,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            
            // Handle both Map and Object types robustly
            String name = 'Unknown';
            String imageUrl = '';
            String id = '';

            try {
               if (item is Map) {
                  name = item['title'] ?? item['name'] ?? 'Unknown';
                  imageUrl = item['thumbnail'] ?? item['imageUrl'] ?? '';
                  id = item['browseId'] ?? item['id'] ?? '';
               } else {
                  // Assume object with properties
                  name = (item as dynamic).name ?? 'Unknown';
                  imageUrl = (item as dynamic).imageUrl ?? '';
                  id = (item as dynamic).id ?? '';
               }
            } catch (e) {
               print("Error parsing artist item: $e");
            }

            return GestureDetector(
              onTap: () async {
                final provider = Provider.of<MusicProvider>(context, listen: false);
                final tracks = await provider.fetchAlbumTracks(id);

                if (!context.mounted) return;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ThemedPlaylistDetailScreen(
                      playlistId: id,
                      playlistName: name,
                      playlistImage: imageUrl,
                      cachedTracks: tracks,
                    ),
                  ),
                );
              },
              child: Container(
                width: 140,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Material(
                      elevation: 2,
                      surfaceTintColor: Colors.transparent, // FIX: No white tint
                      borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
                        child: Image.network(
                          imageUrl,
                          width: 140,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 140,
                            height: 140,
                            color: MaterialYouTokens.surfaceContainerDark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MaterialYouTypography.bodyMedium(colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
