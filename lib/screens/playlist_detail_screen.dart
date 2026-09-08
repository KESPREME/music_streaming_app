import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../utils/artwork_palette_resolver.dart';
import '../widgets/animated_equalizer_icon.dart';
import '../widgets/bitchord_detail/bitchord_detail.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/glass_options_sheet.dart';
import 'album_detail_screen.dart';

const double _kPlaylistArtRatio = 0.92;
const double _kHeaderDrop = 44.0;

/// BitChord 1:1 Parity Playlist Detail Screen (Screenshot 3)
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
  List<Track> _suggestedTracks = [];
  List<String>? _collageThumbnails;
  String? _resolvedCurator;
  String? _resolvedViews;
  String? _resolvedImageUrl;
  String? _resolvedDescription;
  String? _error;

  // In-playlist search
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Isolated scroll controller for 120 FPS sliver interpolation
  final ScrollController _scrollController = ScrollController();
  ArtworkPalette? _artworkPalette;

  @override
  void initState() {
    super.initState();
    _resolvedCurator = widget.artistNameHint ?? 'YouTube Music';
    _resolvedImageUrl = widget.playlistImage;

    if (widget.cachedTracks != null && widget.cachedTracks!.isNotEmpty) {
      _tracks = widget.cachedTracks!;
      _isLoading = false;
      _extractCollage();
    } else {
      _fetchDetails();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _extractCollage() {
    if (_tracks.length >= 4 && _collageThumbnails == null) {
      final thumbs = _tracks
          .map((t) => t.albumArtUrl)
          .where((url) => url.isNotEmpty)
          .toSet()
          .take(4)
          .toList();
      if (thumbs.length >= 4) {
        _collageThumbnails = thumbs;
      }
    }
  }

  Future<void> _fetchDetails() async {
    try {
      final provider = Provider.of<MusicProvider>(context, listen: false);

      if (widget.playlistId.isNotEmpty) {
        final pageData = await provider.fetchPlaylistPageData(widget.playlistId);
        if (pageData.tracks.isNotEmpty && mounted) {
          setState(() {
            _tracks = pageData.tracks;
            _suggestedTracks = pageData.suggestedTracks;
            _resolvedCurator = pageData.curatorName.isNotEmpty
                ? pageData.curatorName
                : widget.artistNameHint ?? 'YouTube Music';
            _resolvedViews = pageData.viewsText;
            if (pageData.coverUrl.isNotEmpty) _resolvedImageUrl = pageData.coverUrl;
            _collageThumbnails = pageData.collageThumbnails;
            _resolvedDescription = pageData.description;
            _isLoading = false;
            _extractCollage();
          });
          return;
        }

        // Fallback to fetchPlaylistDetails
        final loaded = await provider.fetchPlaylistDetails(widget.playlistId);
        if (mounted) {
          setState(() {
            _tracks = loaded;
            _isLoading = false;
            _extractCollage();
            if (loaded.isEmpty) _error = 'No songs found in this playlist';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Playlist not found';
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

  static String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r"['’]"), '')
        .replaceAll('ã', 'a')
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
  }

  List<Track> _getFilteredTracks() {
    final query = _searchQuery.trim();
    if (query.isEmpty) return _tracks;
    final q = _normalize(query);
    return _tracks.where((t) =>
        _normalize(t.trackName).contains(q) ||
        _normalize(t.artistName).contains(q)).toList();
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
    if (mins < 60) return '${_tracks.length} songs, $mins min';
    final hrs = mins ~/ 60;
    final remMins = mins % 60;
    return '${_tracks.length} songs, $hrs hr $remMins min';
  }

  @override
  Widget build(BuildContext context) {
    // If album, delegate cleanly to AlbumDetailScreen
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
      );
    }

    final musicProvider = Provider.of<MusicProvider>(context);
    final artPalette = _artworkPalette ?? ArtworkPalette.defaultDark;
    final darkBg = artPalette.background;
    final washColor = artPalette.wash;
    final accentColor = artPalette.accent;
    final elevatedColor = artPalette.elevated;

    final screenWidth = MediaQuery.of(context).size.width;
    final artHeight = screenWidth / _kPlaylistArtRatio;
    final displayedTracks = _getFilteredTracks();

    // Curator & views subtitle (e.g. "Tems, 78K views" or "YouTube Music")
    final curatorText = _resolvedCurator ?? 'YouTube Music';
    final subtitleLine = _resolvedViews != null && _resolvedViews!.isNotEmpty
        ? '$curatorText, $_resolvedViews'
        : curatorText;
    final metadataLine = 'PLAYLIST • ${_tracks.length} TRACKS';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1. Layer 1: PageBackground with ArtworkWash
          ArtworkWash(
            backgroundColor: darkBg,
            washColor: washColor,
            accentColor: accentColor,
            elevatedColor: elevatedColor,
            washFraction: (artHeight / MediaQuery.of(context).size.height).clamp(0.40, 0.70),
            imageUrl: _resolvedImageUrl ?? widget.playlistImage,
          ),

          // 2. Layer 2: Full-bleed Top Cover / 2x2 Collage Artwork with isolated parallax render offset (BitChord 120 FPS parity)
          AnimatedBuilder(
            animation: _scrollController,
            builder: (context, child) {
              final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
              return Positioned(
                top: -offset.clamp(0.0, artHeight * 1.5),
                left: 0,
                right: 0,
                height: artHeight,
                child: child!,
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 2x2 Collage or Single Image
                CollageArtwork(
                  collageUrls: _collageThumbnails,
                  fallbackUrl: _resolvedImageUrl ?? (widget.playlistImage ?? ''),
                  fit: BoxFit.cover,
                ),

                // Top shade under the glass bar (BitChord DetailScreen.kt parity)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: artHeight * 0.28,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          darkBg.withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom fade settling onto the wash (BitChord DetailScreen.kt parity)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: artHeight * 0.48,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.55, 1.0],
                        colors: [
                          Colors.transparent,
                          washColor.withValues(alpha: 0.35),
                          washColor.withValues(alpha: 0.88),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2.5 Layer 2.5: MergeBand across the artwork join (BitChord parity)
          MergeBand(
            scrollController: _scrollController,
            artHeight: artHeight,
            washColor: washColor,
          ),

          // 3. Layer 3: Scrollable content
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Scroll-linked Frosted SliverAppBar (BitChord parity)
              BitchordSliverAppBar(
                title: widget.playlistName,
                scrollController: _scrollController,
                artHeight: artHeight,
                backgroundColor: darkBg,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      GlassPlaylistOptionsSheet.show(
                        context,
                        playlistName: widget.playlistName,
                        playlistImage: _resolvedImageUrl,
                        tracks: _tracks,
                      );
                    },
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 14),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF23201E),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.person_rounded, color: Colors.white70, size: 20),
                    ),
                  ),
                ],
              ),

              if (_isLoading)
                SliverToBoxAdapter(
                  child: BitchordTracklistSkeleton(
                    baseColor: accentColor,
                    itemCount: 8,
                    hasLeadingThumb: true,
                  ),
                )
              else if (_error != null && _tracks.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.queue_music_rounded, size: 56, color: Colors.white.withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text(_error!, style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 16)),
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
                )
              else ...[
                // Spacer matching artHeight + HEADER_DROP
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: (artHeight - kToolbarHeight - MediaQuery.of(context).padding.top) + _kHeaderDrop,
                  ),
                ),

                // Playlist Header (Title, Subtitle in accent color, Uppercase Metadata, Action Bar)
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // Playlist Title
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          widget.playlistName,
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

                      // Curator & Views in Accent Color (Screenshot 3: "Tems, 78K views")
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          subtitleLine,
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
                      const SizedBox(height: 8),

                      // Metadata (PLAYLIST • 5 TRACKS)
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
                        palette: artPalette,
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
                            playlistName: widget.playlistName,
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

                // In-playlist Search Field
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

                // Description (if any)
                if (_resolvedDescription != null && _resolvedDescription!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: AboutSection(
                      title: 'About',
                      text: _resolvedDescription!,
                      accentColor: accentColor,
                    ),
                  ),

                // Playlist Tracklist (Squircle Thumbnails + Title + Artist + Duration + More)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = displayedTracks[index];
                        final isPlayingThis = track.isSameTrackAs(musicProvider.currentTrack);

                        return BitchordSwipeableTrackRow(
                          track: track,
                          palette: artPalette,
                          child: Material(
                            color: isPlayingThis
                                ? accentColor.withValues(alpha: 0.12)
                                : Colors.transparent,
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
                                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                                child: Row(
                                  children: [
                                    // 48x48 Squircle Artwork Thumbnail (Screenshot 3)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        color: Colors.white.withValues(alpha: 0.08),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            CachedNetworkImage(
                                              imageUrl: track.albumArtUrl,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) => const Icon(
                                                Icons.music_note_rounded,
                                                color: Colors.white38,
                                              ),
                                            ),
                                            if (isPlayingThis)
                                              Container(
                                                color: Colors.black.withValues(alpha: 0.55),
                                                child: Center(
                                                  child: musicProvider.isPlaying
                                                      ? AnimatedEqualizerIcon(
                                                          isPlaying: true,
                                                          color: accentColor,
                                                          size: 20,
                                                        )
                                                      : Icon(
                                                          Icons.play_arrow_rounded,
                                                          color: accentColor,
                                                          size: 22,
                                                        ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // Track Title & Artist
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              if (track.isExplicit) ...[
                                                const BitchordExplicitBadge(),
                                                const SizedBox(width: 6),
                                              ],
                                              Expanded(
                                                child: Text(
                                                  track.trackName,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    color: isPlayingThis ? accentColor : Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: isPlayingThis ? FontWeight.w700 : FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
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

                                    // Duration ("3:28")
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
                          ),
                        );
                      },
                      childCount: displayedTracks.length,
                    ),
                  ),
                ),

                // Suggested Songs section (if returned by YouTube)
                if (_suggestedTracks.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                      child: Text(
                        'Suggested',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = _suggestedTracks[index];
                        return BitchordSwipeableTrackRow(
                          track: song,
                          palette: artPalette,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 6.0),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: song.albumArtUrl,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Icon(Icons.music_note_rounded),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.trackName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        song.artistName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white54,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.add_rounded,
                                    color: accentColor,
                                    size: 24,
                                  ),
                                  onPressed: () {
                                    musicProvider.addTrackToPlaylist(
                                      widget.playlistName,
                                      song,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: _suggestedTracks.length,
                    ),
                  ),
                ],

                // Runtime Summary Footer
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
                        const SizedBox(height: 100), // Bottom clearance for mini player & nav bar
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
