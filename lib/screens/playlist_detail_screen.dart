import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_font.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../utils/app_image_cache.dart';
import '../utils/artwork_palette_resolver.dart';
import '../widgets/jelly_icon_button.dart';
import '../widgets/animated_equalizer_icon.dart';
import '../widgets/bitchord_detail/bitchord_detail.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/song_sheet_plan.dart';
import '../widgets/glass_options_sheet.dart';
import 'album_detail_screen.dart';

const double _kPlaylistArtRatio = 0.92;

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

    final initialImg = widget.playlistImage ??
        (widget.cachedTracks != null && widget.cachedTracks!.isNotEmpty
            ? widget.cachedTracks!.first.albumArtUrl
            : null);
    _artworkPalette = ArtworkPaletteResolver.getCached(initialImg);
    if (_artworkPalette == null && initialImg != null && initialImg.isNotEmpty) {
      _resolvePalette(initialImg);
    }

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

  void _resolvePalette(String imageUrl) {
    ArtworkPaletteResolver.resolve(imageUrl).then((p) {
      if (mounted) {
        setState(() {
          _artworkPalette = p;
        });
      }
    });
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
    final artUrl = _resolvedImageUrl ??
        (_collageThumbnails?.firstOrNull) ??
        (_tracks.isNotEmpty ? _tracks.first.albumArtUrl : null);
    if (artUrl != null && artUrl.isNotEmpty) {
      if (_artworkPalette == null || _artworkPalette == ArtworkPalette.defaultDark) {
        _resolvePalette(artUrl);
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
            if (pageData.coverUrl.isNotEmpty) {
              _resolvedImageUrl = pageData.coverUrl;
              _resolvePalette(pageData.coverUrl);
            }
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

  int _totalSeconds() {
    var total = 0;
    for (final t in _tracks) {
      final ms = t.durationMs;
      if (ms != null && ms > 0) total += (ms / 1000).round();
    }
    return total;
  }

  void _onDownloadTap(ReleaseDownloadState state) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    switch (state) {
      case ReleaseDownloadState.downloading:
        messenger?.showSnackBar(const SnackBar(content: Text('Downloading this playlist.')));
        return;
      case ReleaseDownloadState.done:
        messenger?.showSnackBar(const SnackBar(content: Text('Every song is downloaded')));
        return;
      case ReleaseDownloadState.none:
      case ReleaseDownloadState.partial:
        final mp = context.read<MusicProvider>();
        final missing = _tracks
            .where((t) => t.source != 'local' && !mp.isTrackDownloadedSync(t.id))
            .toList();
        if (missing.isEmpty) return;
        mp.downloadTracks(missing);
        messenger?.showSnackBar(SnackBar(
          content: Text('Downloading ${missing.length} ${missing.length == 1 ? 'song' : 'songs'}'),
        ));
    }
  }

  void _openOptions() {
    GlassPlaylistOptionsSheet.show(
      context,
      playlistName: widget.playlistName,
      playlistImage: _resolvedImageUrl,
      tracks: _tracks,
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  void _playFrom(List<Track> order, int index) {
    if (order.isEmpty) return;
    context.read<MusicProvider>().playTrackList(order, initialIndex: index.clamp(0, order.length - 1));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  /// The playlist's picture: the 2x2 collage when the page gave four covers,
  /// else its single cover. Full bleed, like the album page.
  Widget _cover(Color wash) {
    final url = _resolvedImageUrl ?? widget.playlistImage ?? '';
    if (url.isEmpty && (_collageThumbnails == null || _collageThumbnails!.length < 4)) {
      return ColoredBox(color: wash);
    }
    return CollageArtwork(
      collageUrls: _collageThumbnails,
      fallbackUrl: url,
      fit: BoxFit.cover,
    );
  }

  /// Title, curator, one meta line and the action row, over the fade.
  Widget _titleBlock({
    required String subtitleLine,
    required String metaLine,
    required ArtworkPalette pal,
  }) {
    final accent = pal.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              widget.playlistName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppFont.style(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
                height: 1.1,
                shadows: const [Shadow(color: Color(0x66000000), blurRadius: 14)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 6, 28, 2),
            child: Text(
              subtitleLine,
              key: const ValueKey('playlist_curator'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFont.style(
                color: Color.lerp(accent, Colors.white, 0.35),
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (metaLine.isNotEmpty && !_isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 28, 0),
              child: Text(
                metaLine,
                key: const ValueKey('playlist_meta'),
                textAlign: TextAlign.center,
                style: AppFont.style(
                  color: Colors.white.withValues(alpha: 0.66),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: 14),
          DetailActionRow(
            accent: accent,
            onPlay: () => _playFrom(_tracks, 0),
            leading: DetailGlassCircle(
              icon: Icons.shuffle_rounded,
              label: 'Shuffle',
              size: DetailGlass.actionSize,
              accent: accent,
              onTap: () {
                if (_tracks.isEmpty) return;
                _playFrom(List<Track>.from(_tracks)..shuffle(), 0);
              },
            ),
            trailing: Selector<MusicProvider, ReleaseDownloadState>(
              selector: (_, mp) => releaseDownloadStateFor(mp, _tracks),
              builder: (context, state, _) {
                final busy = state == ReleaseDownloadState.downloading;
                final done = state == ReleaseDownloadState.done;
                return DetailGlassCircle(
                  label: busy ? 'Downloading' : (done ? 'Downloaded' : 'Download'),
                  size: DetailGlass.actionSize,
                  accent: accent,
                  icon: done ? Icons.download_done_rounded : Icons.download_rounded,
                  iconColor: done ? accent : Colors.white,
                  onTap: () => _onDownloadTap(state),
                  child: busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: accent),
                        )
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackRow(Track track, ArtworkPalette pal) {
    final accentColor = pal.accent;
    return RepaintBoundary(
      child: Selector<MusicProvider, ({bool isCurrent, bool isPlaying})>(
        selector: (_, mp) => (
          isCurrent: track.isSameTrackAs(mp.currentTrack),
          isPlaying: mp.isPlaying,
        ),
        builder: (context, playbackState, _) {
          final isPlayingThis = playbackState.isCurrent;
          final isPlaying = playbackState.isPlaying;

          return BitchordSwipeableTrackRow(
            track: track,
            palette: pal,
            child: Material(
              color: isPlayingThis ? accentColor.withValues(alpha: 0.12) : Colors.transparent,
              child: InkWell(
                onTap: () {
                  final startIndex = _tracks.indexOf(track);
                  _playFrom(_tracks, startIndex >= 0 ? startIndex : 0);
                },
                splashColor: Colors.white.withValues(alpha: 0.08),
                highlightColor: Colors.white.withValues(alpha: 0.04),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                  child: Row(
                    children: [
                      // 48x48 squircle artwork thumbnail
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
                                memCacheWidth: AppImageCache.thumbnailMemCache,
                                memCacheHeight: AppImageCache.thumbnailMemCache,
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
                                    child: isPlaying
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

                      // Track title & artist
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
                                    style: AppFont.style(
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
                              style: AppFont.style(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (track.durationText.isNotEmpty)
                        Text(
                          track.durationText,
                          style: AppFont.style(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),

                      JellyIconButton(
                        tooltip: 'More options for ${track.trackName}',
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 20,
                        ),
                        onPressed: () => ThemedOptionsSheet.show(context, origin: SongSheetOrigin.remotePlaylist, track: track),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _suggestedRow(Track song, ArtworkPalette pal, MusicProvider musicProvider) {
    return BitchordSwipeableTrackRow(
      track: song,
      palette: pal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 6.0),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: song.albumArtUrl,
                memCacheWidth: AppImageCache.thumbnailMemCache,
                memCacheHeight: AppImageCache.thumbnailMemCache,
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
                    style: AppFont.style(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    song.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.style(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            JellyIconButton(
              tooltip: 'Add ${song.trackName} to this playlist',
              icon: Icon(
                Icons.add_rounded,
                color: pal.accent,
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

    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final pal = _artworkPalette ?? ArtworkPalette.defaultDark;
    final media = MediaQuery.of(context);
    // FULL BLEED, like the album page: the cover is the page's header, edge to
    // edge, and dissolves into the page colour (see ImmersiveHeader).
    final heroH = (media.size.width / _kPlaylistArtRatio).clamp(media.padding.top + 56 + 262, 560.0);
    final displayedTracks = _getFilteredTracks();

    // Curator & views subtitle (e.g. "Tems, 78K views" or "YouTube Music")
    final curatorText = _resolvedCurator ?? 'YouTube Music';
    final subtitleLine = _resolvedViews != null && _resolvedViews!.isNotEmpty
        ? '$curatorText, $_resolvedViews'
        : curatorText;
    final metaLine = releaseMetaLine(
      kind: 'Playlist',
      trackCount: _tracks.length,
      totalSeconds: _totalSeconds(),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: ArtworkWash(
                backgroundColor: pal.background,
                washColor: pal.wash,
                accentColor: pal.accent,
                elevatedColor: pal.elevated,
                washFraction: (heroH / media.size.height).clamp(0.30, 0.80),
                seamOverhang: 160,
                meshInset: 120,
                imageUrl: _resolvedImageUrl ?? widget.playlistImage,
              ),
            ),
          ),

          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: ImmersiveHeader(
                  height: heroH,
                  washColor: pal.wash,
                  scrollController: _scrollController,
                  photo: _cover(pal.wash),
                  child: _titleBlock(
                    subtitleLine: subtitleLine,
                    metaLine: metaLine,
                    pal: pal,
                  ),
                ),
              ),

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
                    accentColor: pal.accent,
                  ),
                ),

              if (_isLoading)
                SliverToBoxAdapter(
                  child: BitchordTracklistSkeleton(
                    baseColor: pal.accent,
                    itemCount: 8,
                    hasLeadingThumb: true,
                  ),
                )
              else if (_error != null && _tracks.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Icon(Icons.queue_music_rounded, size: 48, color: Colors.white.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(_error!, style: AppFont.style(color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 12),
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
                if (_resolvedDescription != null && _resolvedDescription!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: AboutSection(
                      title: 'About',
                      text: _resolvedDescription!,
                      accentColor: pal.accent,
                    ),
                  ),

                if (_isSearching && displayedTracks.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          'No songs match "$_searchQuery"',
                          style: AppFont.style(color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                        ),
                      ),
                    ),
                  ),

                SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _trackRow(displayedTracks[index], pal),
                      childCount: displayedTracks.length,
                      addRepaintBoundaries: true,
                      addAutomaticKeepAlives: false,
                    ),
                  ),
                ),

                // Suggested songs (if returned by YouTube)
                if (_suggestedTracks.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                      child: Text(
                        'Suggested',
                        style: AppFont.style(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _suggestedRow(_suggestedTracks[index], pal, musicProvider),
                      childCount: _suggestedTracks.length,
                    ),
                  ),
                ],

                // Runtime summary footer
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatTotalDuration(),
                          style: AppFont.style(
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

          // The glass chrome floats ABOVE the scroll view.
          DetailTopBar(
            controller: _scrollController,
            title: widget.playlistName,
            background: pal.background,
            accent: pal.accent,
            titleAppearsAt: heroH - media.padding.top - 120,
            slots: [
              DetailGlassSlot(
                icon: _isSearching ? Icons.search_off_rounded : Icons.search_rounded,
                label: _isSearching ? 'Close search' : 'Search in playlist',
                onTap: _toggleSearch,
              ),
              DetailGlassSlot(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                onTap: _openOptions,
              ),
            ],
          ),
        ],
      ),
    );
  }
}