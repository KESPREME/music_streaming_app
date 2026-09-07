import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../utils/color_utils.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/animated_equalizer_icon.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/liquid_play_button.dart';
import '../widgets/themed_artist_detail_screen.dart';

/// Ordering for the track list on an album page (BitChord parity).
enum AlbumSongSort {
  defaultOrder,
  titleAsc,
  titleDesc,
}

/// Sleeve ratio and sizing constants matching Apple Music & BitChord DetailScreen.kt
const double _kSleeveRatio = 0.92;
const double _kSleeveFraction = 0.80;

/// Apple-grade Liquid Glass Album Detail Screen.
class AlbumDetailScreen extends StatefulWidget {
  final String albumId;
  final String albumName;
  final String? artistName;
  final String? albumImage;
  final List<Track>? cachedTracks;
  final bool searchByName;

  const AlbumDetailScreen({
    super.key,
    required this.albumId,
    required this.albumName,
    this.artistName,
    this.albumImage,
    this.cachedTracks,
    this.searchByName = false,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  bool _isLoading = true;
  List<Track> _tracks = [];
  String? _error;
  String? _resolvedArtist;
  String? _resolvedYear;
  String? _resolvedImageUrl;

  // In-album search
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  AlbumSongSort _currentSort = AlbumSongSort.defaultOrder;

  @override
  void initState() {
    super.initState();
    _resolvedArtist = widget.artistName;
    _resolvedImageUrl = widget.albumImage;
    if (widget.cachedTracks != null && widget.cachedTracks!.isNotEmpty) {
      _tracks = widget.cachedTracks!;
      _isLoading = false;
      _extractMetadata();
    } else {
      _loadAlbumDetails();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _extractMetadata() {
    if (_tracks.isEmpty) return;
    if (_resolvedArtist == null || _resolvedArtist!.isEmpty) {
      _resolvedArtist = _tracks.first.artistName;
    }
    if (_resolvedImageUrl == null || _resolvedImageUrl!.isEmpty) {
      _resolvedImageUrl = _tracks.first.albumArtUrl;
    }
    final firstTrack = _tracks.first;
    if (firstTrack.albumName.isNotEmpty && _resolvedYear == null) {
      final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(firstTrack.albumName);
      if (match != null) _resolvedYear = match.group(0);
    }
  }

  Future<void> _loadAlbumDetails() async {
    try {
      final provider = Provider.of<MusicProvider>(context, listen: false);
      List<Track> loadedTracks = [];

      if (widget.albumId.isNotEmpty &&
          (widget.albumId.startsWith('MPREb_') || widget.albumId.startsWith('OLAK'))) {
        loadedTracks = await provider.fetchAlbumTracks(widget.albumId);
      } else if (widget.albumName.isNotEmpty) {
        await provider.navigateToAlbum(widget.albumName, widget.artistName ?? '');
        if (provider.currentAlbumDetails != null) {
          loadedTracks = provider.currentAlbumDetails!.tracks;
        }
      }

      if (mounted) {
        setState(() {
          _tracks = loadedTracks;
          _isLoading = false;
          _extractMetadata();
          if (loadedTracks.isEmpty) {
            _error = 'Could not find tracks for ${widget.albumName}';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load album';
          _isLoading = false;
        });
      }
    }
  }

  List<Track> _getFilteredAndSortedTracks() {
    var result = List<Track>.from(_tracks);
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((t) =>
          t.trackName.toLowerCase().contains(q) ||
          t.artistName.toLowerCase().contains(q)).toList();
    }
    switch (_currentSort) {
      case AlbumSongSort.titleAsc:
        result.sort((a, b) => a.trackName.compareTo(b.trackName));
        break;
      case AlbumSongSort.titleDesc:
        result.sort((a, b) => b.trackName.compareTo(a.trackName));
        break;
      case AlbumSongSort.defaultOrder:
        break;
    }
    return result;
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
    if (mins < 60) {
      return '$mins min';
    } else {
      final hrs = mins ~/ 60;
      final remMins = mins % 60;
      return '${hrs} hr ${remMins} min';
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final palette = musicProvider.paletteGenerator;
    final accentColor = ColorUtils.getVibrantAccent(
      palette,
      Theme.of(context).colorScheme.primary,
    );
    final displayedTracks = _getFilteredAndSortedTracks();

    return PlayerAwarePopScope(
      child: Scaffold(
        backgroundColor: const Color(0xFF08080A),
        body: Stack(
          children: [
            // 1. Ambient blurred background wash from album art
            if (_resolvedImageUrl != null && _resolvedImageUrl!.isNotEmpty)
              Positioned.fill(
                child: RepaintBoundary(
                  child: ClipRect(
                    child: Transform.scale(
                      scale: 1.35,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                        child: CachedNetworkImage(
                          imageUrl: ImageQualityUtils.getHighResArtwork(_resolvedImageUrl!),
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

            // 3. Main scrollable content
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
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.album_outlined,
                              size: 56,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isLoading = true;
                                  _error = null;
                                });
                                _loadAlbumDetails();
                              },
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  // Album Sleeve & Header
                  SliverToBoxAdapter(
                    child: _buildAlbumHeroHeader(context, accentColor),
                  ),

                  // Search field (if toggled open)
                  if (_isSearching)
                    SliverToBoxAdapter(
                      child: _buildSearchField(accentColor),
                    ),

                  // Numbered Tracklist
                  _buildTracklistSliver(
                    context,
                    displayedTracks,
                    musicProvider,
                    accentColor,
                  ),

                  // Footer: Editorial, Runtime, & Copyright
                  SliverToBoxAdapter(
                    child: _buildFooterSection(accentColor),
                  ),

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
          // Search toggle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: _isSearching
                  ? accentColor.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.35),
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
                  playlistName: widget.albumName,
                  playlistImage: _resolvedImageUrl,
                  tracks: _tracks,
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAlbumHeroHeader(BuildContext context, Color accentColor) {
    final screenWidth = MediaQuery.of(context).size.width;
    final sleeveWidth = screenWidth * _kSleeveFraction;
    final sleeveHeight = sleeveWidth / _kSleeveRatio;
    final durationText = _formatTotalDuration();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        children: [
          // Sleeve Artwork (0.80 page width, 0.92 ratio)
          Center(
            child: Container(
              width: sleeveWidth,
              height: sleeveHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
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
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_resolvedImageUrl != null && _resolvedImageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: ImageQualityUtils.getHighResArtwork(_resolvedImageUrl!),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildPlaceholderSleeve(),
                      )
                    else
                      _buildPlaceholderSleeve(),

                    // Subtle refractive glass sheen overlay
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.75,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.12),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.20),
                            ],
                            stops: const [0.0, 0.35, 1.0],
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

          // Title
          Text(
            widget.albumName,
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

          // Clickable Artist Link
          if (_resolvedArtist != null && _resolvedArtist!.isNotEmpty)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ThemedArtistDetailScreen(
                      artistId: "",
                      artistName: _resolvedArtist!,
                      searchByName: true,
                    ),
                  ),
                );
              },
              child: Text(
                _resolvedArtist!,
                style: GoogleFonts.plusJakartaSans(
                  color: accentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          const SizedBox(height: 6),

          // Metadata line: Album • Year • Count • Duration
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Album',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.50),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_resolvedYear != null) ...[
                Text(
                  ' • $_resolvedYear',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (_tracks.isNotEmpty) ...[
                Text(
                  ' • ${_tracks.length} ${_tracks.length == 1 ? "song" : "songs"}',
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

          // Action Buttons: Play Pill, Shuffle, Favorite, Download
          if (_tracks.isNotEmpty)
            _buildActionButtonsRow(context, accentColor),
        ],
      ),
    );
  }

  Widget _buildPlaceholderSleeve() {
    return Container(
      color: const Color(0xFF1C1C1E),
      child: const Center(
        child: Icon(Icons.album_rounded, size: 64, color: Colors.white24),
      ),
    );
  }

  Widget _buildActionButtonsRow(BuildContext context, Color accentColor) {
    final provider = Provider.of<MusicProvider>(context, listen: false);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. Shuffle
        _buildCircularActionButton(
          icon: Icons.shuffle_rounded,
          semanticLabel: 'Shuffle',
          onTap: () {
            HapticFeedback.mediumImpact();
            final shuffled = List<Track>.from(_tracks)..shuffle();
            provider.playTrack(shuffled.first, playlistTracks: shuffled);
          },
        ),

        const SizedBox(width: 12),

        // 2. Hero Play Pill Button
        GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            provider.playTrack(_tracks.first, playlistTracks: _tracks);
          },
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 28),
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

        const SizedBox(width: 12),

        // 3. Favorite Album Tracks
        _buildCircularActionButton(
          icon: Icons.favorite_border_rounded,
          semanticLabel: 'Favorite',
          onTap: () {
            HapticFeedback.lightImpact();
            showGlassSnackBar(context, 'Album saved to library');
          },
        ),

        const SizedBox(width: 12),

        // 4. Download All
        _buildCircularActionButton(
          icon: Icons.download_rounded,
          semanticLabel: 'Download All',
          onTap: () {
            HapticFeedback.lightImpact();
            provider.downloadTracks(_tracks);
            showGlassSnackBar(context, 'Downloading ${_tracks.length} tracks');
          },
        ),
      ],
    );
  }

  Widget _buildCircularActionButton({
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
                  hintText: 'Filter tracks...',
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
            final trackNumber = index + 1;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: isCurrent
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                leading: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: isCurrent
                        ? AnimatedEqualizerIcon(
                            isPlaying: isActuallyPlaying,
                            color: accentColor,
                            size: 16,
                          )
                        : Text(
                            '$trackNumber',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                title: Text(
                  track.trackName,
                  style: GoogleFonts.plusJakartaSans(
                    color: isCurrent ? accentColor : Colors.white,
                    fontSize: 15,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.artistName,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (track.durationMs != null && track.durationMs! > 0)
                      Text(
                        _formatTrackDuration(track.durationMs!),
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white.withValues(alpha: 0.40),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    IconButton(
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
                  ],
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

  String _formatTrackDuration(int ms) {
    final dur = Duration(milliseconds: ms);
    final minutes = dur.inMinutes;
    final seconds = dur.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, "0")}';
  }

  Widget _buildFooterSection(Color accentColor) {
    final year = _resolvedYear ?? DateTime.now().year.toString();
    final artist = _resolvedArtist ?? 'Artist';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Released $year',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '℗ $year $artist. Distributed via YouTube Music.',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
