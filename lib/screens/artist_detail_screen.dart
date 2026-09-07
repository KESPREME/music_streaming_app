import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/bitchord_page_models.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../utils/color_utils.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/bitchord_detail/bitchord_detail.dart';
import '../widgets/themed_options_sheet.dart';

/// Aspect ratio for artist hero photography matching BitChord ARTIST_PHOTO_RATIO in DetailScreen.kt
const double _kArtistPhotoRatio = 0.95;
const double _kHeaderDrop = 44.0;

/// BitChord 1:1 Parity Artist Detail Screen (Screenshots 4, 5, 6, 7, 8)
class ArtistDetailScreen extends StatefulWidget {
  final String artistId;
  final String artistName;
  final String? artistImage;
  final bool searchByName;

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
  String? _error;

  String _resolvedArtistName = '';
  String? _resolvedArtistImage;
  String? _subscriberCountText;
  String? _monthlyListenerCount;
  String? _description;

  List<Track> _topSongs = [];
  List<DetailShelf> _shelves = [];

  // Scroll tracking for MergeBand
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _resolvedArtistName = widget.artistName;
    _resolvedArtistImage = widget.artistImage;

    _scrollController.addListener(() {
      if (mounted) {
        setState(() {
          _scrollOffset = _scrollController.offset;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchDetails();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    if (!mounted) return;
    try {
      final provider = Provider.of<MusicProvider>(context, listen: false);
      String artistIdToFetch = widget.artistId;

      if (widget.searchByName ||
          widget.artistId.isEmpty ||
          widget.artistId.startsWith('artist_') ||
          !widget.artistId.contains('UC')) {
        await provider
            .fetchArtistTracks(widget.artistName)
            .timeout(const Duration(seconds: 10));

        final results = provider.artistTracks;
        if (results.isNotEmpty) {
          final exactMatch = results.firstWhere(
            (track) => track.artistName.toLowerCase() == widget.artistName.toLowerCase(),
            orElse: () => results.first,
          );
          artistIdToFetch = exactMatch.id;
          if (_resolvedArtistImage == null || _resolvedArtistImage!.isEmpty) {
            _resolvedArtistImage = exactMatch.albumArtUrl;
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

      // 1. Fetch rich BitChord ArtistPageData (hero image, subscribers, monthly listeners, bio, shelves)
      final pageData = await provider
          .fetchArtistPageData(artistIdToFetch)
          .timeout(const Duration(seconds: 12));

      if (pageData.topSongs.isNotEmpty || pageData.shelves.isNotEmpty) {
        if (mounted) {
          setState(() {
            if (pageData.name.isNotEmpty && pageData.name != 'Artist') {
              _resolvedArtistName = pageData.name;
            }
            if (pageData.heroImageUrl.isNotEmpty) {
              _resolvedArtistImage = pageData.heroImageUrl;
            }
            _subscriberCountText = pageData.subscriberCountText;
            _monthlyListenerCount = pageData.monthlyListenerCount;
            _description = pageData.description;
            _topSongs = pageData.topSongs;
            _shelves = pageData.shelves;
            _isLoading = false;
          });
          return;
        }
      }

      // 2. Fallback to fetchArtistDetails if needed
      final details = await provider
          .fetchArtistDetails(artistIdToFetch)
          .timeout(const Duration(seconds: 10));

      final tracks = details['tracks'] as List<Track>? ?? [];
      final albums = details['albums'] as List? ?? [];
      final singles = details['singles'] as List? ?? [];

      final fallbackShelves = <DetailShelf>[];
      if (albums.isNotEmpty) {
        fallbackShelves.add(DetailShelf(
          title: 'Albums',
          items: albums.map((a) => DetailShelfItem(
            title: a.name,
            subtitle: a.artistName,
            browseId: a.id,
            imageUrl: a.imageUrl,
            type: 'album',
          )).toList(),
        ));
      }
      if (singles.isNotEmpty) {
        fallbackShelves.add(DetailShelf(
          title: 'Singles & EPs',
          items: singles.map((s) => DetailShelfItem(
            title: s.name,
            subtitle: s.artistName,
            browseId: s.id,
            imageUrl: s.imageUrl,
            type: 'single',
          )).toList(),
        ));
      }

      if (mounted) {
        setState(() {
          _topSongs = tracks;
          _shelves = fallbackShelves;
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
    final musicProvider = Provider.of<MusicProvider>(context);
    final palette = musicProvider.paletteGenerator;
    final accentColor = ColorUtils.getVibrantAccent(
      palette,
      const Color(0xFFFF7043), // Warm coral/orange fallback matching Tems
    );
    final darkBg = ColorUtils.getBackgroundWash(palette);
    final washColor = ColorUtils.getDominantWash(palette);

    final screenWidth = MediaQuery.of(context).size.width;
    final artHeight = screenWidth / _kArtistPhotoRatio;

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

          // 2. Layer 2: Full-bleed Hero Photography at top with scroll offset (Screenshot 8)
          Positioned(
            top: -_scrollOffset.clamp(0.0, artHeight * 1.5),
            left: 0,
            right: 0,
            height: artHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Cinematic Artist Portrait
                if (_resolvedArtistImage != null && _resolvedArtistImage!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: ImageQualityUtils.getHighQualityUrl(_resolvedArtistImage!),
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black38),
                  ),

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

          // 4. Layer 4: Scrollable content
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Clear SliverAppBar with circular back and account/more buttons
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
                      icon: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
                      onPressed: () {
                        HapticFeedback.lightImpact();
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
              else if (_error != null && _topSongs.isEmpty && _shelves.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off_rounded, size: 56, color: Colors.white.withValues(alpha: 0.4)),
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

                // Artist Name (Screenshot 8: Large centered bold text)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      _resolvedArtistName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // Subscriber & Monthly Listener Stat Chips (Screenshot 8)
                SliverToBoxAdapter(
                  child: ArtistStatsRow(
                    subscriberCountText: _subscriberCountText,
                    monthlyListenerCount: _monthlyListenerCount,
                  ),
                ),

                // Action Row: [ 🔀 ]  [ ▶ Play ]
                if (_topSongs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleIconButton(
                            icon: Icons.shuffle_rounded,
                            onTap: () {
                              final shuffled = List<Track>.from(_topSongs)..shuffle();
                              musicProvider.playTrackList(shuffled, initialIndex: 0);
                            },
                          ),
                          const SizedBox(width: 10),
                          PlayPill(
                            onPlay: () {
                              musicProvider.playTrackList(_topSongs, initialIndex: 0);
                            },
                            accentColor: accentColor,
                          ),
                        ],
                      ),
                    ),
                  ),

                // "About the artist" editorial section (Screenshot 7 & 8)
                if (_description != null && _description!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: AboutSection(
                      title: 'About the artist',
                      text: _description!,
                      accentColor: accentColor,
                    ),
                  ),

                // "Top songs" horizontal 4-row pager grid (Screenshot 7)
                if (_topSongs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: TopSongsPagerGrid(
                      songs: _topSongs,
                      onSongTap: (queue, index) {
                        musicProvider.playTrackList(queue, initialIndex: index);
                      },
                      currentTrack: musicProvider.currentTrack,
                      isPlaying: musicProvider.isPlaying,
                      accentColor: accentColor,
                    ),
                  ),

                // Carousels: "Albums", "Singles & EPs", "Featured on", "Playlists by [Artist]", "Fans might also like"
                // (Screenshots 4, 5, 6)
                for (final shelf in _shelves)
                  SliverToBoxAdapter(
                    child: ShelfCarousel(
                      shelf: shelf,
                      artistNameHint: _resolvedArtistName,
                    ),
                  ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 120), // Bottom clearance for mini player
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
