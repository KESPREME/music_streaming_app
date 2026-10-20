import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../utils/app_image_cache.dart';
import '../theme/app_font.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/bitchord_page_models.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../services/innertube/innertube_service.dart';
import '../utils/artwork_palette_resolver.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/bitchord_detail/bitchord_detail.dart';

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

  /// The YouTube channel behind the page, for Share.
  String? _channelId;

  /// Top songs shown: BitChord's page lists 20 at most.
  static const int _topSongsCap = 20;

  /// The first item of the first Albums / Singles shelf: YouTube Music orders
  /// those newest first.
  ({DetailShelfItem item, String kind})? get _latestRelease {
    for (final shelf in _shelves) {
      final t = shelf.title.toLowerCase();
      final isReleases = t.contains('album') || t.contains('single') || t.contains(' ep');
      if (!isReleases || shelf.items.isEmpty) continue;
      final item = shelf.items.first;
      if (item.type == 'artist' || item.type == 'playlist') continue;
      final kind = item.type == 'single' || t.startsWith('single') ? 'Single' : 'Album';
      return (item: item, kind: kind);
    }
    return null;
  }

  /// "Single · 2023": the kind, and the year when the card's subtitle has one.
  static String _releaseEyebrow(String kind, String subtitle) {
    final year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(subtitle)?.group(0);
    return year == null ? kind : '$kind · $year';
  }

  void _share() {
    final id = _channelId;
    final text = id != null
        ? '$_resolvedArtistName on YouTube Music\nhttps://music.youtube.com/channel/$id'
        : '$_resolvedArtistName on YouTube Music';
    SharePlus.instance.share(ShareParams(text: text));
  }

  // Isolated scroll controller for 120 FPS sliver interpolation
  final ScrollController _scrollController = ScrollController();
  ArtworkPalette? _artworkPalette;

  @override
  void initState() {
    super.initState();
    _resolvedArtistName = widget.artistName;
    _resolvedArtistImage = widget.artistImage;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final initialImg = widget.artistImage;
        _artworkPalette = ArtworkPaletteResolver.getCached(initialImg);
        if (_artworkPalette == null && initialImg != null && initialImg.isNotEmpty) {
          _resolvePalette(initialImg);
        }
        _fetchDetails();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
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

  Future<void> _fetchDetails() async {
    if (!mounted) return;
    try {
      final provider = Provider.of<MusicProvider>(context, listen: false);
      String artistIdToFetch = widget.artistId;

      if (widget.searchByName ||
          widget.artistId.isEmpty ||
          widget.artistId.startsWith('artist_') ||
          !widget.artistId.contains('UC')) {
        final results = await InnerTubeService()
            .searchArtists(widget.artistName, limit: 5)
            .timeout(const Duration(seconds: 10));

        if (results.isNotEmpty) {
          final exactMatch = results.firstWhere(
            (track) => track.artistName.toLowerCase() == widget.artistName.toLowerCase() ||
                track.trackName.toLowerCase() == widget.artistName.toLowerCase(),
            orElse: () => results.first,
          );
          artistIdToFetch = exactMatch.id;
          if (_resolvedArtistImage == null || _resolvedArtistImage!.isEmpty) {
            _resolvedArtistImage = exactMatch.albumArtUrl;
            if (_resolvedArtistImage != null && _resolvedArtistImage!.isNotEmpty) {
              _resolvePalette(_resolvedArtistImage!);
            }
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
      _channelId = artistIdToFetch.startsWith('UC') ? artistIdToFetch : null;
      final pageData = await provider
          .fetchArtistPageData(artistIdToFetch)
          .timeout(const Duration(seconds: 12));

      if (pageData.topSongs.isNotEmpty || pageData.shelves.isNotEmpty) {
        if (mounted) {
          String? newHero = pageData.heroImageUrl.isNotEmpty
              ? pageData.heroImageUrl
              : (_resolvedArtistImage ?? pageData.topSongs.firstOrNull?.albumArtUrl ?? widget.artistImage);
          if (newHero != null && newHero.isNotEmpty) {
            if (_artworkPalette == null || _artworkPalette == ArtworkPalette.defaultDark || newHero != widget.artistImage) {
              _resolvePalette(newHero);
            }
          }
          setState(() {
            if (pageData.name.isNotEmpty && pageData.name != 'Artist') {
              _resolvedArtistName = pageData.name;
            }
            if (newHero != null && newHero.isNotEmpty) {
              _resolvedArtistImage = newHero;
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
        String? fallbackImg = _resolvedArtistImage ?? tracks.firstOrNull?.albumArtUrl ?? fallbackShelves.firstOrNull?.items.firstOrNull?.imageUrl;
        if (fallbackImg != null && fallbackImg.isNotEmpty) {
          _resolvePalette(fallbackImg);
        }
        setState(() {
          if (fallbackImg != null && fallbackImg.isNotEmpty) {
            _resolvedArtistImage = fallbackImg;
          }
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
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final artPalette = _artworkPalette ?? ArtworkPalette.defaultDark;
    final darkBg = artPalette.background;
    final washColor = artPalette.wash;
    final accentColor = artPalette.accent;

    final screenWidth = MediaQuery.of(context).size.width;
    final artHeight = screenWidth / _kArtistPhotoRatio;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1. Layer 1: PageBackground with ArtworkWash
          Positioned.fill(
            child: RepaintBoundary(
              child: ArtworkWash(
                backgroundColor: darkBg,
                washColor: washColor,
                accentColor: accentColor,
                elevatedColor: artPalette.elevated,
                washFraction: (artHeight / MediaQuery.of(context).size.height).clamp(0.40, 0.70),
                imageUrl: _resolvedArtistImage ?? widget.artistImage,
              ),
            ),
          ),

          // 2. Layer 2: Full-bleed Hero Photography with isolated parallax render offset (BitChord 120 FPS parity)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: artHeight,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _scrollController,
                builder: (context, child) {
                  final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                  final clamped = offset.clamp(0.0, artHeight * 1.5);
                  return Transform.translate(
                    offset: Offset(0, -clamped),
                    child: child,
                  );
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Cinematic Artist Portrait
                    if (_resolvedArtistImage != null && _resolvedArtistImage!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: ImageQualityUtils.getHighQualityUrl(_resolvedArtistImage!),
                          fit: BoxFit.cover,
                          memCacheWidth: AppImageCache.heroMemCache,
                          memCacheHeight: AppImageCache.heroMemCache,
                        errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black38),
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

                    // Eased foot fade settling onto the wash (BitChord PageBackground
                    // parity); the MergeBand veil covers the seam the rest of the way.
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: ArtworkFootFade(washColor: washColor),
                      ),
                    ),
                  ],
                ),
              ),
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
            cacheExtent: 600.0,
            slivers: [
              // Scroll-linked Frosted SliverAppBar (BitChord parity)
              BitchordSliverAppBar(
                title: _resolvedArtistName,
                scrollController: _scrollController,
                artHeight: artHeight,
                backgroundColor: darkBg,
                actions: [
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
              else if (_error != null && _topSongs.isEmpty && _shelves.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off_rounded, size: 56, color: Colors.white.withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text(_error!, style: AppFont.style(color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                              _error = null;
                            });
                            final initialImg = widget.artistImage;
    _artworkPalette = ArtworkPaletteResolver.getCached(initialImg);
    if (_artworkPalette == null && initialImg != null && initialImg.isNotEmpty) {
      _resolvePalette(initialImg);
    }
    _fetchDetails();
                          },
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                // ArtistHeader: matches artHeight + HEADER_DROP and pins artist name to bottomCenter
                // (BitChord DetailScreen.kt lines 870-887 parity)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: (artHeight + _kHeaderDrop - kToolbarHeight - MediaQuery.of(context).padding.top)
                        .clamp(180.0, double.infinity),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 14.0, bottom: 7.0),
                        child: Text(
                          _resolvedArtistName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.style(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),

                // [ shuffle ]  ( ▶ )  [ share ] (BitChord's artist row; its
                // star is a subscribe, which needs a signed-in write path this
                // app does not have, so it is not faked.)
                if (_topSongs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 22.0),
                      child: ArtistActionRow(
                        onShuffle: () {
                          final shuffled = List<Track>.from(_topSongs)..shuffle();
                          musicProvider.playTrackList(shuffled, initialIndex: 0);
                        },
                        onPlay: () => musicProvider.playTrackList(_topSongs, initialIndex: 0),
                        trailing: GhostCircleButton(
                          icon: Icons.ios_share_rounded,
                          semanticLabel: 'Share',
                          onTap: _share,
                        ),
                      ),
                    ),
                  ),

                // Latest release
                if (_latestRelease case final latest?)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: LatestReleaseCard(
                        key: const ValueKey('artist_latest_release'),
                        title: latest.item.title,
                        imageUrl: latest.item.imageUrl,
                        eyebrow: _releaseEyebrow(latest.kind, latest.item.subtitle),
                        caption: 'Latest release',
                        palette: artPalette,
                        onTap: () => openDetailShelfItem(
                          context,
                          latest.item,
                          artistNameHint: _resolvedArtistName,
                        ),
                      ),
                    ),
                  ),

                // "Top songs" horizontal 4-row pager grid, 20 at most
                if (_topSongs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Selector<MusicProvider, ({Track? currentTrack, bool isPlaying})>(
                      selector: (_, mp) => (
                        currentTrack: mp.currentTrack,
                        isPlaying: mp.isPlaying,
                      ),
                      builder: (context, playbackState, _) => TopSongsPagerGrid(
                        songs: _topSongs.length > _topSongsCap
                            ? _topSongs.sublist(0, _topSongsCap)
                            : _topSongs,
                        onSongTap: (queue, index) {
                          context.read<MusicProvider>().playTrackList(queue, initialIndex: index);
                        },
                        currentTrack: playbackState.currentTrack,
                        isPlaying: playbackState.isPlaying,
                        accentColor: accentColor,
                        palette: artPalette,
                      ),
                    ),
                  ),

                // Albums, Singles & EPs, Featured on, Playlists, Fans might
                // also like - each with Show all past five items.
                for (final shelf in _shelves)
                  SliverToBoxAdapter(
                    child: ShelfCarousel(
                      shelf: shelf,
                      artistNameHint: _resolvedArtistName,
                    ),
                  ),

                // About, then the listener stats, at the end (BitChord order):
                // the page leads with music, not a biography.
                if (_description != null && _description!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: AboutSection(
                        title: 'About the artist',
                        text: _description!,
                        accentColor: accentColor,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ArtistStatsRow(
                      subscriberCountText: _subscriberCountText,
                      monthlyListenerCount: _monthlyListenerCount,
                      palette: artPalette,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 100), // Bottom clearance for mini player & nav bar
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
