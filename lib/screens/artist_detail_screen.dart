import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../models/album.dart'; // Import Album
import '../widgets/track_tile.dart';
import 'playlist_detail_screen.dart'; // Reuse for Album view

class ArtistDetailScreen extends StatefulWidget {
  final String artistId;
  final String artistName;
  final String? artistImage;

  const ArtistDetailScreen({
    super.key,
    required this.artistId,
    required this.artistName,
    this.artistImage,
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

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      final provider = Provider.of<MusicProvider>(context, listen: false);
      final details = await provider.fetchArtistDetails(widget.artistId);
      
      if (mounted) {
        setState(() {
          _topSongs = (details['tracks'] as List?)?.cast<Track>() ?? [];
          _albums = details['albums'] ?? [];
          _singles = details['singles'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load artist details';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      floatingActionButton: _topSongs.isNotEmpty ? FloatingActionButton(
        backgroundColor: const Color(0xFFFF1744),
        foregroundColor: Colors.white,
        child: const Icon(Icons.play_arrow_rounded, size: 32),
        onPressed: () {
           final provider = Provider.of<MusicProvider>(context, listen: false);
           provider.playTrack(_topSongs.first, playlistTracks: _topSongs);
        },
      ) : null,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(context),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: Color(0xFFFF1744))),
            )
          else if (_error != null)
             SliverFillRemaining(
               child: Center(child: Text(_error!, style: GoogleFonts.splineSans(color: Colors.white54))),
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
                  child: TrackTile(
                    track: track,
                    onTap: () {
                       final provider = Provider.of<MusicProvider>(context, listen: false);
                       provider.playTrack(track, playlistTracks: _topSongs);
                    },
                    backgroundColor: Colors.transparent, // Override to transparent
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
               onTap: () {
                 Navigator.push(
                   context,
                   MaterialPageRoute(
                     builder: (_) => PlaylistDetailScreen(
                       playlistId: id,
                       playlistName: name,
                       playlistImage: imageUrl,
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
