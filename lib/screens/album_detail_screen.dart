import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../services/canvas_video_manager.dart';
import '../utils/color_utils.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/animated_equalizer_icon.dart';
import '../widgets/bitchord_detail/bitchord_detail.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/themed_artist_detail_screen.dart';

/// Sleeve aspect ratio matching BitChord's SLEEVE_RATIO in DetailScreen.kt
const double _kSleeveRatio = 0.92;
const double _kHeaderDrop = 44.0;

/// BitChord 1:1 Parity Album Detail Screen (Screenshots 1 & 2)
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
  String? _resolvedArtistId;
  String? _resolvedYear;
  String? _resolvedImageUrl;
  String? _resolvedDescription;

  // In-album search
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Scroll tracking for MergeBand & Canvas
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _resolvedArtist = widget.artistName;
    _resolvedImageUrl = widget.albumImage;

    _scrollController.addListener(() {
      if (mounted) {
        setState(() {
          _scrollOffset = _scrollController.offset;
        });
      }
    });

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
    _scrollController.dispose();
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

      if (widget.albumId.isNotEmpty &&
          (widget.albumId.startsWith('MPREb_') || widget.albumId.startsWith('OLAK'))) {
        // 1. Fetch rich BitChord AlbumPageData (title, artist, year, cover, description, tracks)
        final pageData = await provider.fetchAlbumPageData(widget.albumId);
        if (pageData.tracks.isNotEmpty && mounted) {
          setState(() {
            _tracks = pageData.tracks;
            if (pageData.artistName.isNotEmpty) _resolvedArtist = pageData.artistName;
            if (pageData.artistBrowseId != null) _resolvedArtistId = pageData.artistBrowseId;
            if (pageData.year != null) _resolvedYear = pageData.year;
            if (pageData.coverUrl.isNotEmpty) _resolvedImageUrl = pageData.coverUrl;
            if (pageData.description != null && pageData.description!.isNotEmpty) {
              _resolvedDescription = pageData.description;
            }
            _isLoading = false;
            _extractMetadata();
          });
          return;
        }

        // Fallback to fetchAlbumTracks
        final loadedTracks = await provider.fetchAlbumTracks(widget.albumId);
        if (mounted) {
          setState(() {
            _tracks = loadedTracks;
            _isLoading = false;
            _extractMetadata();
          });
        }
      } else if (widget.albumName.isNotEmpty) {
        await provider.navigateToAlbum(widget.albumName, widget.artistName ?? '');
        if (mounted) {
          setState(() {
            _tracks = provider.currentAlbumDetails?.tracks ?? [];
            _isLoading = false;
            _extractMetadata();
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Album not found';
            _isLoading = false;
          });
        }
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

  List<Track> _getFilteredTracks() {
    if (_searchQuery.trim().isEmpty) return _tracks;
    final q = _searchQuery.toLowerCase();
    return _tracks.where((t) =>
        t.trackName.toLowerCase().contains(q) ||
        t.artistName.toLowerCase().contains(q)).toList();
  }

  String _formatTotalDuration() {
    int totalSec = 0;
    for (final t in _tracks) {
      if (t.durationMs != null && t.durationMs! > 0) {
        totalSec += (t.durationMs! / 1000).round();
      }
    }
    if (totalSec <= 0) return '${_tracks.length} songs';
    final mins = (totalSec / 60).round();
    if (mins < 60) {
      return '${_tracks.length} songs, $mins min';
    } else {
      final hrs = mins ~/ 60;
      final remMins = mins % 60;
      return '${_tracks.length} songs, $hrs hr $remMins min';
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final palette = musicProvider.paletteGenerator;
    final accentColor = ColorUtils.getVibrantAccent(
      palette,
      const Color(0xFFFF5252), // Vibrant coral fallback matching Tems screenshot
    );
    final darkBg = ColorUtils.getBackgroundWash(palette);
    final washColor = ColorUtils.getDominantWash(palette);

    final screenWidth = MediaQuery.of(context).size.width;
    final artHeight = screenWidth / _kSleeveRatio;
    final displayedTracks = _getFilteredTracks();

    // Year display
    final yearText = _resolvedYear ?? '2024';
    final metadataLine = 'ALBUM • $yearText • ${_tracks.length} TRACKS';

    return Scaffold(
      backgroundColor: darkBg,
      body: Stack(
        children: [
          // 1. Layer 1: PageBackground with ArtworkWash
          ArtworkWash(
            backgroundColor: darkBg,
            washColor: washColor,
            accentColor: accentColor,
            elevatedColor: Colors.white.withValues(alpha: 0.14),
            washFraction: (artHeight / MediaQuery.of(context).size.height).clamp(0.40, 0.70),
          ),

          // 2. Layer 2: Full-bleed Immersive Artwork at top with scroll offset
          Positioned(
            top: -_scrollOffset.clamp(0.0, artHeight * 1.5),
            left: 0,
            right: 0,
            height: artHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Still Image
                if (_resolvedImageUrl != null && _resolvedImageUrl!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: ImageQualityUtils.getHighQualityUrl(_resolvedImageUrl!),
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black38),
                  ),

                // Optional Video Canvas if active
                if (_tracks.isNotEmpty && CanvasVideoManager.instance.hasActiveController)
                  CanvasVideoManager.instance.buildVideoPlayer(fit: BoxFit.cover),

                // Top shadow under navigation bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 120,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          darkBg.withValues(alpha: 0.70),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom fade settling onto the wash
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: artHeight * 0.45,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          washColor.withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Layer 3: MergeBand Glass Blur across the join
          MergeBand(
            topOffset: (artHeight - 160.0 - _scrollOffset).clamp(-320.0, double.infinity),
            height: 320.0,
            washColor: washColor,
          ),

          // 4. Layer 4: Scrollable content (Titles, Pills, Bio, Tracklist)
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Clear SliverAppBar with circular buttons
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
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
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 8, right: 12),
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
              ),

              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white70),
                  ),
                )
              else if (_error != null && _tracks.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.album_outlined, size: 56, color: Colors.white.withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text(_error!, style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 16)),
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
                )
              else ...[
                // Spacer matching artHeight + HEADER_DROP so text sits cleanly below the picture
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: (artHeight - kToolbarHeight - MediaQuery.of(context).padding.top) + _kHeaderDrop,
                  ),
                ),

                // Album Header (Title, Accent Artist, Uppercase Metadata, Action Bar)
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // Album Title
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          widget.albumName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Artist Credit in Accent Color
                      if (_resolvedArtist != null && _resolvedArtist!.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ThemedArtistDetailScreen(
                                  artistId: _resolvedArtistId ?? 'artist_${widget.albumName}',
                                  artistName: _resolvedArtist!,
                                  artistImage: _resolvedImageUrl,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Text(
                              _resolvedArtist!,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                color: accentColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),

                      // Metadata (ALBUM • 2024 • 18 TRACKS)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          metadataLine,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Action Pills: [ 🔀 ]  [ ▶ Play ]  [ 🔍 ]  [ ••• ]
                      BitchordActionBar(
                        onPlay: () {
                          if (_tracks.isNotEmpty) {
                            musicProvider.playTrackList(_tracks, initialIndex: 0);
                          }
                        },
                        onShuffle: () {
                          if (_tracks.isNotEmpty) {
                            final shuffled = List<Track>.from(_tracks)..shuffle();
                            musicProvider.playTrackList(shuffled, initialIndex: 0);
                          }
                        },
                        searching: _isSearching,
                        onSearch: () {
                          setState(() {
                            _isSearching = !_isSearching;
                            if (!_isSearching) {
                              _searchQuery = '';
                              _searchController.clear();
                            }
                          });
                        },
                        onMore: () {
                          GlassPlaylistOptionsSheet.show(
                            context,
                            playlistName: widget.albumName,
                            playlistImage: _resolvedImageUrl,
                            tracks: _tracks,
                          );
                        },
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),

                // In-album Search field
                if (_isSearching)
                  SliverToBoxAdapter(
                    child: DetailSearchField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      onClose: () {
                        setState(() {
                          _isSearching = false;
                          _searchQuery = '';
                          _searchController.clear();
                        });
                      },
                      accentColor: accentColor,
                    ),
                  ),

                // "About the album" editorial section
                if (_resolvedDescription != null && _resolvedDescription!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: AboutSection(
                      title: 'About the album',
                      text: _resolvedDescription!,
                      accentColor: accentColor,
                    ),
                  ),

                // Numbered Tracklist (1, 2, 3...)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = displayedTracks[index];
                        final originalTrackNumber = _tracks.indexOf(track) + 1;
                        final isPlayingThis = musicProvider.currentTrack?.id == track.id;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              final startIndex = _tracks.indexOf(track);
                              musicProvider.playTrackList(
                                _tracks,
                                initialIndex: startIndex >= 0 ? startIndex : 0,
                              );
                            },
                            splashColor: Colors.white.withValues(alpha: 0.08),
                            highlightColor: Colors.white.withValues(alpha: 0.04),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                              child: Row(
                                children: [
                                  // Track Number or Animated Equalizer
                                  SizedBox(
                                    width: 30,
                                    child: isPlayingThis && musicProvider.isPlaying
                                        ? AnimatedEqualizerIcon(
                                            isPlaying: true,
                                            color: accentColor,
                                            size: 18,
                                          )
                                        : Text(
                                            '$originalTrackNumber',
                                            style: GoogleFonts.plusJakartaSans(
                                              color: isPlayingThis
                                                  ? accentColor
                                                  : Colors.white.withValues(alpha: 0.45),
                                              fontSize: 16,
                                              fontWeight: isPlayingThis ? FontWeight.w700 : FontWeight.w500,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Track Title & Artist
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          track.trackName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            color: isPlayingThis ? accentColor : Colors.white,
                                            fontSize: 16,
                                            fontWeight: isPlayingThis ? FontWeight.w700 : FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          track.artistName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            color: Colors.white.withValues(alpha: 0.55),
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Duration ("2:17")
                                  if (track.durationText.isNotEmpty)
                                    Text(
                                      track.durationText,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),

                                  // More Vertical Dots ⋮
                                  IconButton(
                                    icon: Icon(
                                      Icons.more_vert_rounded,
                                      color: Colors.white.withValues(alpha: 0.5),
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      ThemedOptionsSheet.show(context, track: track);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: displayedTracks.length,
                    ),
                  ),
                ),

                // Runtime Summary & Editorial Footer
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatTotalDuration(),
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '℗ $yearText ${_resolvedArtist ?? widget.albumName}',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 100), // Bottom clearance for mini player
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
