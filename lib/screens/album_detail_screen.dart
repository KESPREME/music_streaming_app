import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../services/canvas_resolution_service.dart';
import '../services/innertube/innertube_service.dart';
import '../utils/artwork_palette_resolver.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/animated_equalizer_icon.dart';
import '../widgets/bitchord_detail/bitchord_detail.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/artist_picker_sheet.dart';

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

  // Video canvas controller (BitChord album canvas parity)
  VideoPlayerController? _albumVideoController;

  // In-album search
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Scroll tracking for MergeBand & Canvas
  final ScrollController _scrollController = ScrollController();
  ArtworkPalette? _artworkPalette;

  @override
  void initState() {
    super.initState();
    _resolvedArtist = widget.artistName;
    _resolvedImageUrl = widget.albumImage;

    final initialImg = widget.albumImage ?? (widget.cachedTracks != null && widget.cachedTracks!.isNotEmpty ? widget.cachedTracks!.first.albumArtUrl : null);
    _artworkPalette = ArtworkPaletteResolver.getCached(initialImg);
    if (_artworkPalette == null && initialImg != null && initialImg.isNotEmpty) {
      _resolvePalette(initialImg);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.cachedTracks != null && widget.cachedTracks!.isNotEmpty) {
        setState(() {
          _tracks = widget.cachedTracks!;
          _isLoading = false;
        });
        _extractMetadata();
        _loadAlbumCanvas();
      } else {
        _loadAlbumDetails();
      }
    });
  }

  @override
  void dispose() {
    _albumVideoController?.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _resolvePalette(String imageUrl) {
    ArtworkPaletteResolver.resolve(imageUrl).then((p) {
      if (mounted) {
        setState(() {
          _artworkPalette = p;
        });
      }
    });
  }

  Future<void> _loadAlbumCanvas() async {
    if (widget.albumName.isEmpty) return;
    final album = widget.albumName;
    final artist = _resolvedArtist ?? widget.artistName ?? '';
    try {
      final videoUrl = await CanvasResolutionService.instance.resolveAlbumCanvas(
        album,
        artist,
      );
      if (!mounted || videoUrl == null || videoUrl.isEmpty) return;

      final isLocal = videoUrl.startsWith('/') ||
          videoUrl.startsWith('file://') ||
          (videoUrl.length > 2 && videoUrl[1] == ':');
      final VideoPlayerController c;
      if (isLocal) {
        final filePath = videoUrl.replaceFirst('file://', '');
        c = VideoPlayerController.file(
          File(filePath),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } else {
        final uri = Uri.tryParse(videoUrl);
        if (uri == null) return;
        final ua = InnerTubeService.userAgentForStreamUrl(videoUrl);
        c = VideoPlayerController.networkUrl(
          uri,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          httpHeaders: ua != null ? {'User-Agent': ua} : const {},
        );
      }

      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setVolume(0.0);
      await c.setLooping(true);
      await c.play();

      final old = _albumVideoController;
      if (mounted) {
        setState(() {
          _albumVideoController = c;
        });
      } else {
        await c.dispose();
      }
      if (old != null) {
        await old.dispose();
      }
    } catch (e) {
      debugPrint('AlbumDetailScreen: album canvas initialization failed: $e');
    }
  }

  void _extractMetadata() {
    if (_tracks.isEmpty) return;
    if (_resolvedArtist == null || _resolvedArtist!.isEmpty) {
      _resolvedArtist = _tracks.first.artistName;
    }
    if (_resolvedImageUrl == null || _resolvedImageUrl!.isEmpty) {
      _resolvedImageUrl = _tracks.first.albumArtUrl;
    }
    if (_artworkPalette == null && _resolvedImageUrl != null && _resolvedImageUrl!.isNotEmpty) {
      _resolvePalette(_resolvedImageUrl!);
    }
    final firstTrack = _tracks.first;
    if (firstTrack.albumName.isNotEmpty && _resolvedYear == null) {
      final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(firstTrack.albumName);
      if (match != null) _resolvedYear = match.group(0);
    }
    _loadAlbumCanvas();
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
    final artPalette = _artworkPalette ?? ArtworkPalette.defaultDark;
    final darkBg = artPalette.background;
    final washColor = artPalette.wash;
    final accentColor = artPalette.accent;
    final elevatedColor = artPalette.elevated;

    final screenWidth = MediaQuery.of(context).size.width;
    final artHeight = screenWidth / _kSleeveRatio;
    final displayedTracks = _getFilteredTracks();

    // Year display
    final yearText = _resolvedYear ?? '2024';
    final metadataLine = 'ALBUM • $yearText • ${_tracks.length} TRACKS';

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
            imageUrl: _resolvedImageUrl ?? widget.albumImage,
          ),

          // 2. Layer 2: Full-bleed Immersive Artwork with isolated parallax render offset
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
                // Still Image
                if (_resolvedImageUrl != null && _resolvedImageUrl!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: ImageQualityUtils.getHighQualityUrl(_resolvedImageUrl!),
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black38),
                  ),

                // Looping Video Canvas (Only for authentic album motion covers)
                if (_albumVideoController != null && _albumVideoController!.value.isInitialized)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: _albumVideoController!.value.size.width,
                      height: _albumVideoController!.value.size.height,
                      child: VideoPlayer(_albumVideoController!),
                    ),
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

                // Bottom fade settling seamlessly onto the wash (BitChord DetailScreen.kt parity)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.40, 0.65, 0.85, 0.96, 1.0],
                          colors: [
                            Colors.transparent,
                            washColor.withValues(alpha: 0.30),
                            washColor.withValues(alpha: 0.75),
                            washColor,
                            washColor,
                          ],
                        ),
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

          // 3. Layer 3: Scrollable content (Titles, Pills, Bio, Tracklist)
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            cacheExtent: 600.0,
            slivers: [
              // Scroll-linked Frosted SliverAppBar (BitChord parity)
              BitchordSliverAppBar(
                title: widget.albumName,
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
                        playlistName: widget.albumName,
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
                    hasLeadingThumb: false,
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
                            if (ArtistPickerSheet.hasMultipleArtists(_resolvedArtist!)) {
                              ArtistPickerSheet.showIfNeeded(
                                context,
                                musicProvider,
                                _resolvedArtist!,
                              );
                            } else {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ThemedArtistDetailScreen(
                                    artistId: _resolvedArtistId ?? 'artist_${widget.albumName}',
                                    artistName: _resolvedArtist!,
                                    artistImage: _resolvedImageUrl,
                                  ),
                                ),
                              );
                            }
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
                        final isPlayingThis = track.isSameTrackAs(musicProvider.currentTrack);

                        return RepaintBoundary(
                          child: BitchordSwipeableTrackRow(
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
                                          : isPlayingThis
                                              ? Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: accentColor,
                                                  size: 20,
                                                )
                                              : Text(
                                                  '$originalTrackNumber',
                                                  style: GoogleFonts.plusJakartaSans(
                                                    color: Colors.white.withValues(alpha: 0.45),
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                    ),
                                    const SizedBox(width: 8),

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
                        ),
                      );
                    },
                    childCount: displayedTracks.length,
                      addRepaintBoundaries: true,
                      addAutomaticKeepAlives: false,
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
