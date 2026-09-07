import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/music_provider.dart';
import '../models/track.dart';
import '../utils/color_utils.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/track_tile.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/animated_equalizer_icon.dart';
import '../widgets/glass_snackbar.dart';
import 'album_detail_screen.dart';

/// Song ordering options (BitChord parity)
enum SongSort {
  defaultOrder,
  titleAsc,
  titleDesc,
}

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;
  final String playlistName;
  final String? playlistImage;
  final List<Track>? cachedTracks;
  final bool searchAlbumByName;
  final String? artistNameHint;

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

  SongSort _sort = SongSort.defaultOrder;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    try {
      final provider = Provider.of<MusicProvider>(context, listen: false);
      List<Track> tracks = [];

      if (widget.searchAlbumByName && widget.playlistId.isEmpty) {
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
        setState(() {
          _tracks = tracks;
          _isLoading = false;
          if (tracks.isEmpty) {
            _error = 'No songs found in this playlist';
          }
        });
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

  List<Track> _getSortedAndFilteredTracks() {
    var list = List<Track>.from(_tracks);
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) =>
          t.trackName.toLowerCase().contains(q) ||
          t.artistName.toLowerCase().contains(q)).toList();
    }
    switch (_sort) {
      case SongSort.titleAsc:
        list.sort((a, b) => a.trackName.compareTo(b.trackName));
        break;
      case SongSort.titleDesc:
        list.sort((a, b) => b.trackName.compareTo(a.trackName));
        break;
      case SongSort.defaultOrder:
        break;
    }
    return list;
  }

  String _formatTotalDuration() {
    int totalSec = 0;
    for (final t in _tracks) {
      if (t.durationMs != null && t.durationMs! > 0) {
        totalSec += (t.durationMs! / 1000).round();
      }
    }
    if (totalSec <= 0) return '';
    final mins = (totalSec / 60).round();
    if (mins < 60) return '$mins min';
    final hrs = mins ~/ 60;
    final remMins = mins % 60;
    return '${hrs} hr ${remMins} min';
  }

  @override
  Widget build(BuildContext context) {
    // If this is an album, delegate to dedicated Apple-grade AlbumDetailScreen
    final isAlbum = widget.searchAlbumByName ||
        widget.playlistId.startsWith('MPREb_') ||
        widget.playlistId.startsWith('OLAK');
    if (isAlbum) {
      return AlbumDetailScreen(
        albumId: widget.playlistId,
        albumName: widget.playlistName,
        artistName: widget.artistNameHint,
        albumImage: widget.playlistImage,
        cachedTracks: widget.cachedTracks,
        searchByName: widget.searchAlbumByName,
      );
    }

    final musicProvider = Provider.of<MusicProvider>(context);
    final palette = musicProvider.paletteGenerator;
    final accentColor = ColorUtils.getVibrantAccent(
      palette,
      Theme.of(context).colorScheme.primary,
    );
    final displayedTracks = _getSortedAndFilteredTracks();

    return PlayerAwarePopScope(
      child: Scaffold(
        backgroundColor: const Color(0xFF08080A),
        body: Stack(
          children: [
            // 1. Ambient blurred background wash
            if (widget.playlistImage != null && widget.playlistImage!.isNotEmpty)
              Positioned.fill(
                child: RepaintBoundary(
                  child: ClipRect(
                    child: Transform.scale(
                      scale: 1.35,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 75, sigmaY: 75),
                        child: CachedNetworkImage(
                          imageUrl: ImageQualityUtils.getHighResArtwork(widget.playlistImage!),
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 2. Liquid gradient merge overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.65),
                      const Color(0xFF08080A).withValues(alpha: 0.95),
                      const Color(0xFF08080A),
                    ],
                    stops: const [0.0, 0.35, 0.70, 1.0],
                  ),
                ),
              ),
            ),

            // 3. Scrollable content
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildSliverAppBar(context, accentColor),
                if (_isLoading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    ),
                  )
                else if (_error != null && _tracks.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.queue_music_rounded, size: 56, color: Colors.white.withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isLoading = true;
                                  _error = null;
                                });
                                _fetchDetails();
                              },
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  // Playlist Hero Header
                  SliverToBoxAdapter(
                    child: _buildPlaylistHero(context, accentColor),
                  ),

                  // Search field (if toggled open)
                  if (_isSearching)
                    SliverToBoxAdapter(
                      child: _buildSearchField(accentColor),
                    ),

                  // Tracks list
                  _buildTracklistSliver(context, displayedTracks, musicProvider, accentColor),

                  const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, Color accentColor) {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.5),
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      actions: [
        if (_tracks.isNotEmpty) ...[
          // Search toggle button
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: _isSearching ? accentColor.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.5),
            ),
            child: IconButton(
              icon: Icon(
                _isSearching ? Icons.close_rounded : Icons.search_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchQuery = '';
                    _searchController.clear();
                  }
                });
              },
            ),
          ),

          // Sort Menu
          PopupMenuButton<SongSort>(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.5),
              ),
              child: const Icon(Icons.sort_rounded, color: Colors.white, size: 20),
            ),
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (val) {
              HapticFeedback.selectionClick();
              setState(() => _sort = val);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: SongSort.defaultOrder,
                child: Row(
                  children: [
                    Icon(Icons.format_list_numbered_rounded, color: _sort == SongSort.defaultOrder ? accentColor : Colors.white70, size: 18),
                    const SizedBox(width: 10),
                    Text('Default Order', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: _sort == SongSort.defaultOrder ? FontWeight.bold : FontWeight.w500)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: SongSort.titleAsc,
                child: Row(
                  children: [
                    Icon(Icons.arrow_downward_rounded, color: _sort == SongSort.titleAsc ? accentColor : Colors.white70, size: 18),
                    const SizedBox(width: 10),
                    Text('Title (A to Z)', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: _sort == SongSort.titleAsc ? FontWeight.bold : FontWeight.w500)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: SongSort.titleDesc,
                child: Row(
                  children: [
                    Icon(Icons.arrow_upward_rounded, color: _sort == SongSort.titleDesc ? accentColor : Colors.white70, size: 18),
                    const SizedBox(width: 10),
                    Text('Title (Z to A)', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: _sort == SongSort.titleDesc ? FontWeight.bold : FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),

          // Options menu
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8, right: 12, left: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.5),
            ),
            child: IconButton(
              icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20),
              onPressed: () {
                HapticFeedback.lightImpact();
                GlassPlaylistOptionsSheet.show(
                  context,
                  playlistName: widget.playlistName,
                  playlistImage: widget.playlistImage,
                  tracks: _tracks,
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlaylistHero(BuildContext context, Color accentColor) {
    final durationText = _formatTotalDuration();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          // Playlist Artwork Card
          Center(
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.60),
                    blurRadius: 28,
                    spreadRadius: -4,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.25),
                    blurRadius: 36,
                    spreadRadius: -6,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.playlistImage != null && widget.playlistImage!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: ImageQualityUtils.getHighResArtwork(widget.playlistImage!),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildArtPlaceholder(),
                      )
                    else
                      _buildArtPlaceholder(),

                    // Sheen overlay
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.75,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.12),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Playlist Title
          Text(
            widget.playlistName,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 6),

          // Metadata
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Playlist',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_tracks.isNotEmpty) ...[
                Text(
                  ' • ${_tracks.length} ${_tracks.length == 1 ? "track" : "tracks"}',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (durationText.isNotEmpty) ...[
                Text(
                  ', $durationText',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 18),

          // Action buttons: Play Pill & Shuffle
          if (_tracks.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Shuffle
                _buildCircleButton(
                  icon: Icons.shuffle_rounded,
                  semanticLabel: 'Shuffle',
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    final shuffled = List<Track>.from(_tracks)..shuffle();
                    final provider = Provider.of<MusicProvider>(context, listen: false);
                    provider.playTrack(shuffled.first, playlistTracks: shuffled);
                  },
                ),

                const SizedBox(width: 14),

                // Play Pill
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    final provider = Provider.of<MusicProvider>(context, listen: false);
                    provider.playTrack(_tracks.first, playlistTracks: _tracks);
                  },
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
                        const SizedBox(width: 6),
                        Text(
                          'Play',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                // Download All
                _buildCircleButton(
                  icon: Icons.download_rounded,
                  semanticLabel: 'Download All',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final provider = Provider.of<MusicProvider>(context, listen: false);
                    provider.downloadTracks(_tracks);
                    showGlassSnackBar(context, 'Downloading ${_tracks.length} tracks');
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildArtPlaceholder() {
    return Container(
      color: const Color(0xFF1C1C1E),
      child: const Center(
        child: Icon(Icons.queue_music_rounded, size: 64, color: Colors.white24),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildSearchField(Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.4), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Filter songs...',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.5), size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTracklistSliver(
    BuildContext context,
    List<Track> tracks,
    MusicProvider provider,
    Color accentColor,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final track = tracks[index];
            final isCurrent = provider.currentTrack?.id == track.id;
            final isActuallyPlaying = isCurrent && provider.isPlaying;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: isCurrent ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: CachedNetworkImage(
                      imageUrl: ImageQualityUtils.getHighResArtwork(
                        track.albumArtUrl.isNotEmpty ? track.albumArtUrl : (widget.playlistImage ?? ''),
                      ),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[900],
                        child: const Icon(Icons.music_note, color: Colors.white24, size: 20),
                      ),
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    if (isCurrent) ...[
                      AnimatedEqualizerIcon(
                        isPlaying: isActuallyPlaying,
                        color: accentColor,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        track.trackName,
                        style: GoogleFonts.plusJakartaSans(
                          color: isCurrent ? accentColor : Colors.white,
                          fontSize: 15,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  track.artistName,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white.withValues(alpha: 0.5),
                    size: 20,
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    GlassOptionsSheet.show(context, track: track);
                  },
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  provider.playTrack(track, playlistTracks: _tracks);
                },
              ),
            );
          },
          childCount: tracks.length,
        ),
      ),
    );
  }
}
