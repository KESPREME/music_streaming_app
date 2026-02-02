import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../widgets/track_tile.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/glass_options_sheet.dart'; // For GlassPlaylistOptionsSheet

import '../widgets/liquid_play_button.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;
  final String playlistName;
  final String? playlistImage;
  final List<Track>? cachedTracks;
  final bool searchAlbumByName; // New: search for album by name instead of ID
  final String? artistNameHint; // New: artist name to help narrow album search

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.playlistName,
    this.playlistImage,
    this.cachedTracks,
    this.searchAlbumByName = false,
    this.artistNameHint,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
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
      
      // Handle search-by-album-name mode
      if (widget.searchAlbumByName && widget.playlistId.isEmpty) {
        // Search for album by name + artist hint
        final searchQuery = widget.artistNameHint != null 
            ? '${widget.playlistName} ${widget.artistNameHint}'
            : widget.playlistName;
        
        // Use navigateToAlbum to search and get album details
        await provider.navigateToAlbum(widget.playlistName, widget.artistNameHint ?? '');
        
        if (provider.currentAlbumDetails != null) {
          tracks = provider.currentAlbumDetails!.tracks;
        }
      } else if (widget.playlistId.isNotEmpty) {
        // Normal mode: fetch by ID
        // Check if it's an album ID (starts with MPREb_ or OLAK)
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
    return PlayerAwarePopScope(
      child: Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      floatingActionButton: _tracks.isNotEmpty ? LiquidPlayButton(
        onPressed: () {
            final provider = Provider.of<MusicProvider>(context, listen: false);
            provider.playTrack(_tracks.first, playlistTracks: _tracks);
        },
      ) : null,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: Color(0xFFFF1744))),
            )
          else if (_error != null)
             SliverFillRemaining(
               child: Center(child: Text(_error!, style: GoogleFonts.splineSans(color: Colors.white54))),
             )
          else
            _buildTracksList(),
        ],
      ),
    ));
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 300,
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
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            padding: EdgeInsets.zero,
            onPressed: () {
               if (_tracks.isNotEmpty) {
                  GlassPlaylistOptionsSheet.show(
                    context, 
                    playlistName: widget.playlistName, 
                    playlistImage: widget.playlistImage,
                    tracks: _tracks
                  );
               }
            },
          ),
        ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final double percentage = ((constraints.maxHeight - kToolbarHeight) / (300 - kToolbarHeight)).clamp(0.0, 1.0);
          final double blur = (1 - percentage) * 20;
          final double overlayOpacity = (1 - percentage) * 0.5;

          return ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
                centerTitle: false,
                title: Text(
                  widget.playlistName,
                  style: GoogleFonts.splineSans(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16 + (6 * percentage), // 16 -> 22
                    shadows: [Shadow(color: Colors.black.withOpacity(0.8), blurRadius: 20)],
                  ),
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
                        errorBuilder: (_,__,___) => Container(color: const Color(0xFF1E1E1E)),
                      )
                    else
                      Container(
                        color: const Color(0xFF1E1E1E),
                        child: const Center(child: Icon(Icons.music_note, size: 80, color: Colors.white24)),
                      ),
                      
                     // Gradient Overlay
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
                    
                    // Liquid Overlay
                    Container(
                      color: Colors.black.withOpacity(overlayOpacity),
                    ),
                    
                    if (percentage < 0.05)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(height: 1, color: Colors.white.withOpacity(0.1)),
                      ),
                  ],
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildTracksList() {
    if (_tracks.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(50),
          child: Center(child: Text("Empty playlist", style: GoogleFonts.splineSans(color: Colors.white54))),
        ),
      );
    }
  
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final track = _tracks[index];
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
                       provider.playTrack(track, playlistTracks: _tracks);
                    },
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ),
          );
        },
        childCount: _tracks.length,
      ),
    );
  }
}
