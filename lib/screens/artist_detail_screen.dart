import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../models/album.dart'; // Import Album
import '../widgets/liquid_play_button.dart'; // Import LiquidPlayButton
import '../widgets/track_tile.dart';
import '../widgets/themed_playlist_detail_screen.dart'; // Use themed wrapper

class ArtistDetailScreen extends StatefulWidget {
  final String artistId;
  final String artistName;
  final String? artistImage;
  final bool searchByName; // New: search for artist by name instead of using ID

  const ArtistDetailScreen({
    super.key,
    required this.artistId,
    required this.artistName,
    this.artistImage,
    this.searchByName = false,
  });

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  bool _isLoading = true;
  List<Track> _topSongs = [];
  List<dynamic> _albums = []; // Using dynamic/Album
  List<dynamic> _singles = [];
  String? _error;
  String? _resolvedArtistId; // For search-by-name mode

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
        _topSongs = (details['tracks'] as List?)?.cast<Track>() ?? [];
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
    // Ensure we have a valid context
    if (!mounted) {
      return Container(color: Colors.black);
    }
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      floatingActionButton: (!_isLoading && _error == null && _topSongs.isNotEmpty) 
          ? LiquidPlayButton(
              onPressed: () {
                final provider = Provider.of<MusicProvider>(context, listen: false);
                provider.playTrack(_topSongs.first, playlistTracks: _topSongs);
              },
            ) 
          : null,
      body: SafeArea(
        child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(context),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: Color(0xFFFF1744))),
            )
          else if (_error != null)
             SliverFillRemaining(
               child: Center(
                 child: Padding(
                   padding: const EdgeInsets.all(32.0),
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Container(
                         padding: const EdgeInsets.all(20),
                         decoration: BoxDecoration(
                           color: Colors.white.withOpacity(0.05),
                           shape: BoxShape.circle,
                           border: Border.all(
                             color: Colors.white.withOpacity(0.1),
                           ),
                         ),
                         child: const Icon(
                           Icons.error_outline_rounded,
                           size: 48,
                           color: Color(0xFFFF1744),
                         ),
                       ),
                       const SizedBox(height: 24),
                       Text(
                         _error!,
                         textAlign: TextAlign.center,
                         style: GoogleFonts.splineSans(
                           color: Colors.white70,
                           fontSize: 16,
                           height: 1.5,
                         ),
                       ),
                       const SizedBox(height: 32),
                       ElevatedButton.icon(
                         onPressed: () {
                           setState(() {
                             _isLoading = true;
                             _error = null;
                           });
                           _fetchDetails();
                         },
                         icon: const Icon(Icons.refresh_rounded),
                         label: const Text('Retry'),
                         style: ElevatedButton.styleFrom(
                           backgroundColor: const Color(0xFFFF1744),
                           foregroundColor: Colors.white,
                           padding: const EdgeInsets.symmetric(
                             horizontal: 24,
                             vertical: 12,
                           ),
                         ),
                       ),
                     ],
                   ),
                 ),
               ),
             )
          else ...[
             if (_topSongs.isNotEmpty) _buildSectionTitle("Popular Songs"),
             _buildTopSongsList(context),
             if (_albums.isNotEmpty) _buildSectionTitle("Albums"),
             _buildHorizontalCarousel(_albums),
             if (_singles.isNotEmpty) _buildSectionTitle("Singles & EPs"),
             _buildHorizontalCarousel(_singles),
             const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ]
        ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 10),
        child: Text(
          title,
          style: GoogleFonts.splineSans(
            fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white
          ),
        ),
      ),
    );
  }

  Widget _buildTopSongsList(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final track = _topSongs[index];
          // Liquid List Item
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Consumer<MusicProvider>(
                    builder: (context, provider, child) {
                      final isPlaying = provider.currentTrack?.id == track.id && provider.isPlaying;
                      return TrackTile(
                        track: track,
                        isPlaying: isPlaying,
                        onTap: () {
                          provider.playTrack(track, playlistTracks: _topSongs);
                        },
                        backgroundColor: Colors.transparent, // Override to transparent
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
        childCount: _topSongs.length > 5 ? 5 : _topSongs.length, 
      ),
    );
  }

  Widget _buildHorizontalCarousel(List<dynamic> items) {
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
             final name = item.name; 
             final imageUrl = item.imageUrl;
             final id = item.id;
             
             return GestureDetector(
               onTap: () async {
                 // Fetch album tracks before navigating
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
                       cachedTracks: tracks, // Pass fetched album tracks
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
                     Container(
                       decoration: BoxDecoration(
                         borderRadius: BorderRadius.circular(16),
                         boxShadow: [
                           BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
                         ]
                       ),
                       child: ClipRRect(
                         borderRadius: BorderRadius.circular(16),
                         child: Image.network(
                           imageUrl, 
                           width: 140, height: 140, 
                           fit: BoxFit.cover,
                           errorBuilder: (_,__,___) => Container(color: Colors.grey[900]),
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
                         style: GoogleFonts.splineSans(
                           color: Colors.white.withOpacity(0.9), 
                           fontWeight: FontWeight.w600, 
                           fontSize: 13,
                           height: 1.2
                         ),
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

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 340,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          // percentage: 1.0 = expanded, 0.0 = collapsed
          final double percentage = ((constraints.maxHeight - kToolbarHeight) / (340 - kToolbarHeight)).clamp(0.0, 1.0);
          final double blur = (1 - percentage) * 20; // Blurs up to 20px
          final double overlayOpacity = (1 - percentage) * 0.5; // Darkens up to 0.5

          return ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
                centerTitle: false,
                title: Text(
                  widget.artistName,
                  style: GoogleFonts.splineSans(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16 + (8 * percentage), // Smooth scale 16 -> 24
                    shadows: [Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 20)],
                  ),
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
                        errorBuilder: (_,__,___) => Container(color: const Color(0xFF1E1E1E)),
                      )
                    else
                      Container(
                        color: const Color(0xFF1E1E1E),
                        child: const Center(child: Icon(Icons.person, size: 80, color: Colors.white24)),
                      ),

                    // Gradient Overlay (fades out slightly on collapse to let liquid glass take over)
                    Opacity(
                      opacity: percentage,
                      child: Container(
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
                    ),

                    // Liquid Glass Overlay (Darkens as it collapses)
                    Container(
                      color: Colors.black.withOpacity(overlayOpacity),
                    ),
                    
                    // Subtle Border when fully collapsed
                    if (percentage < 0.05)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.1),
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
