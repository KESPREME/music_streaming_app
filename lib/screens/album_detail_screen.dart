import 'dart:io';
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
import '../widgets/covered_gate.dart';
import '../widgets/animated_equalizer_icon.dart';
import '../widgets/bitchord_detail/bitchord_detail.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/themed_artist_detail_screen.dart';
import '../widgets/artist_picker_sheet.dart';
import '../core/navigation/root_navigator.dart';
import '../services/innertube/track_artist_credit.dart';

/// Sleeve aspect ratio matching BitChord's SLEEVE_RATIO in DetailScreen.kt

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

  /// The page's own title and release kind ("Album", "EP", "Single"): the
  /// name a search result passed can be shortened or decorated.
  String? _resolvedTitle;
  String? _resolvedKind;

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

  /// The open player is covering this page. The looping canvas keeps no decoder
  /// running for a header nobody can see.
  bool _playerCovers = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final covered = CoveredScope.of(context);
    if (covered == _playerCovers) return;
    _playerCovers = covered;
    final c = _albumVideoController;
    if (c == null || !c.value.isInitialized) return;
    (covered ? c.pause() : c.play()).ignore();
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
      if (!_playerCovers) await c.play();

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
      // A page whose header names no artist must not be shown as though it did.
      // "Unknown Artist" is what a row falls back to when it says nothing, not a
      // name - adopting it here would print that literal in the header and offer
      // it as a tap target. The constructor argument is the last honest source:
      // it came from a search result that knew the artist.
      final fromTrack = _tracks.first.artistName;
      final passed = (widget.artistName ?? '').trim();
      if (isUsableArtistName(fromTrack)) {
        _resolvedArtist = fromTrack;
      } else if (isUsableArtistName(passed)) {
        _resolvedArtist = passed;
      }
    }
    if (_resolvedImageUrl == null || _resolvedImageUrl!.isEmpty) {
      _resolvedImageUrl = _tracks.first.albumArtUrl;
    }
    final artUrl = _resolvedImageUrl ?? (_tracks.isNotEmpty ? _tracks.first.albumArtUrl : null);
    if (artUrl != null && artUrl.isNotEmpty) {
      if (_artworkPalette == null || _artworkPalette == ArtworkPalette.defaultDark) {
        _resolvePalette(artUrl);
      }
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
        // The header's own metadata is kept even when the page came back with no
        // tracks. It used to be applied only inside the `tracks.isNotEmpty`
        // branch below, so falling through to fetchAlbumTracks threw away an
        // artist name we already had and then re-derived it from the first
        // track - which, on an album page, reads "Unknown Artist".
        final pageArtist = pageData.artistName.trim();
        final headerArtist =
            pageArtist.isEmpty ? null : pageArtist;
        if (pageData.tracks.isNotEmpty && mounted) {
          setState(() {
            _tracks = pageData.tracks;
            if (pageData.artistName.isNotEmpty) _resolvedArtist = pageData.artistName;
            if (pageData.artistBrowseId != null) _resolvedArtistId = pageData.artistBrowseId;
            if (pageData.year != null) _resolvedYear = pageData.year;
            if (pageData.coverUrl.isNotEmpty) {
              _resolvedImageUrl = pageData.coverUrl;
              _resolvePalette(pageData.coverUrl);
            }
            if (pageData.description != null && pageData.description!.isNotEmpty) {
              _resolvedDescription = pageData.description;
            }
            if (pageData.title.trim().isNotEmpty) _resolvedTitle = pageData.title.trim();
            _resolvedKind = pageData.kind;
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
            // Survives _extractMetadata's own fallback below, which would
            // otherwise reach for the first track's artist - and that reads
            // "Unknown Artist" on exactly the pages that land here.
            if (_resolvedArtist == null || _resolvedArtist!.isEmpty) {
              _resolvedArtist = headerArtist;
            }
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

  int _totalSeconds() {
    var total = 0;
    for (final t in _tracks) {
      final ms = t.durationMs;
      if (ms != null && ms > 0) total += (ms / 1000).round();
    }
    return total;
  }

  ReleaseDownloadState _downloadState(MusicProvider mp) {
    final ids = [for (final t in _tracks) if (t.source != 'local') t.id];
    if (ids.isEmpty) return ReleaseDownloadState.none;
    final active = {
      for (final t in mp.currentlyDownloadingTracks) t.id,
      for (final t in mp.downloadQueue) t.id,
    };
    if (ids.any(active.contains)) return ReleaseDownloadState.downloading;
    final done = ids.where(mp.isTrackDownloadedSync).length;
    if (done == ids.length) return ReleaseDownloadState.done;
    return done > 0 ? ReleaseDownloadState.partial : ReleaseDownloadState.none;
  }

  void _onDownloadTap(ReleaseDownloadState state) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    switch (state) {
      case ReleaseDownloadState.downloading:
        messenger?.showSnackBar(const SnackBar(content: Text('Downloading this album…')));
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

  void _openArtist(MusicProvider musicProvider) {
    final artist = _resolvedArtist;
    if (artist == null || artist.isEmpty) return;
    if (ArtistPickerSheet.hasMultipleArtists(artist)) {
      ArtistPickerSheet.showIfNeeded(context, musicProvider, artist);
      return;
    }
    final nav = mainNavigatorKey.currentState ?? Navigator.of(context);
    nav.push(
      MaterialPageRoute(
        builder: (_) => ThemedArtistDetailScreen(
          artistId: _resolvedArtistId ?? 'artist_${widget.albumName}',
          artistName: artist,
          artistImage: _resolvedImageUrl,
        ),
      ),
    );
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
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final artPalette = _artworkPalette ?? ArtworkPalette.defaultDark;
    final darkBg = artPalette.background;
    final washColor = artPalette.wash;
    final accentColor = artPalette.accent;
    final elevatedColor = artPalette.elevated;

    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    final sleeveSize = releaseSleeveSize(media.size);
    // Where the album title sits: the bar's own title fades in once it has
    // scrolled under the bar.
    final headerHeight = topInset + kToolbarHeight + 8 + sleeveSize + 60;
    final displayedTracks = _getFilteredTracks();
    final title = _resolvedTitle ?? widget.albumName;

    // Track numbers once per build, by identity: indexOf per row was O(n^2)
    // and numbered a repeated track by its first appearance.
    final numberOf = Map<Track, int>.identity();
    for (var i = 0; i < _tracks.length; i++) {
      numberOf[_tracks[i]] = i + 1;
    }

    final metadataLine = releaseMetaLine(
      kind: _resolvedKind ?? 'Album',
      year: _resolvedYear,
      trackCount: _tracks.length,
      totalSeconds: _totalSeconds(),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Flat palette colour, washed down from the sleeve (no full-bleed
          // photo behind the page: the framed cover is the picture).
          Positioned.fill(
            child: RepaintBoundary(
              child: ArtworkWash(
                backgroundColor: darkBg,
                washColor: washColor,
                accentColor: accentColor,
                elevatedColor: elevatedColor,
                washFraction: (headerHeight / media.size.height).clamp(0.40, 0.75),
                imageUrl: _resolvedImageUrl ?? widget.albumImage,
              ),
            ),
          ),

          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            cacheExtent: 600.0,
            slivers: [
              BitchordSliverAppBar(
                title: title,
                scrollController: _scrollController,
                artHeight: headerHeight,
                backgroundColor: darkBg,
                actions: [
                  IconButton(
                    tooltip: _isSearching ? 'Close search' : 'Search in album',
                    icon: Icon(
                      _isSearching ? Icons.search_off_rounded : Icons.search_rounded,
                      color: Colors.white,
                      size: 24,
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
                  IconButton(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 24),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      GlassPlaylistOptionsSheet.show(
                        context,
                        playlistName: title,
                        playlistImage: _resolvedImageUrl,
                        tracks: _tracks,
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ),

              // The release header: framed sleeve, title, artist, one meta
              // line, actions. Shown while loading too, from what the caller
              // passed, so the page does not jump when the tracks land.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 18),
                  child: Column(
                    children: [
                      AnimatedBuilder(
                        animation: _scrollController,
                        builder: (context, child) {
                          final offset =
                              _scrollController.hasClients ? _scrollController.offset : 0.0;
                          // Recedes as it scrolls under the bar instead of
                          // being cut by it.
                          final p = (offset / (sleeveSize * 0.9)).clamp(0.0, 1.0);
                          return Opacity(
                            opacity: 1 - 0.85 * p,
                            child: Transform.scale(scale: 1 - 0.12 * p, child: child),
                          );
                        },
                        child: RepaintBoundary(
                          child: FramedSleeve(
                            key: const ValueKey('album_sleeve'),
                            imageUrl: _resolvedImageUrl ?? widget.albumImage,
                            size: sleeveSize,
                            overlay: (_albumVideoController != null &&
                                    _albumVideoController!.value.isInitialized)
                                ? FittedBox(
                                    fit: BoxFit.cover,
                                    clipBehavior: Clip.hardEdge,
                                    child: SizedBox(
                                      width: _albumVideoController!.value.size.width,
                                      height: _albumVideoController!.value.size.height,
                                      child: VideoPlayer(_albumVideoController!),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28.0),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_resolvedArtist != null && _resolvedArtist!.isNotEmpty)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _openArtist(musicProvider),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 2),
                            child: Text(
                              _resolvedArtist!,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                color: Color.lerp(accentColor, Colors.white, 0.35),
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ),
                      if (metadataLine.isNotEmpty && !_isLoading) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28.0),
                          child: Text(
                            metadataLine,
                            key: const ValueKey('album_meta'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      ReleaseActionRow(
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
                        trailing: Selector<MusicProvider, ReleaseDownloadState>(
                          selector: (_, mp) => _downloadState(mp),
                          builder: (context, state, _) => ReleaseDownloadButton(
                            state: state,
                            accent: accentColor,
                            onTap: () => _onDownloadTap(state),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Text(_error!, style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 12),
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
                        final originalTrackNumber = numberOf[track] ?? (index + 1);

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
                                palette: artPalette,
                                child: Material(
                                  color: isPlayingThis
                                      ? accentColor.withValues(alpha: 0.12)
                                      : Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      final startIndex = (numberOf[track] ?? 1) - 1;
                                      context.read<MusicProvider>().playTrackList(
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
                                            child: isPlayingThis && isPlaying
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
                              );
                            },
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
                          // The year only when the page said it.
                          _resolvedYear != null
                              ? '℗ $_resolvedYear ${_resolvedArtist ?? title}'
                              : '℗ ${_resolvedArtist ?? title}',
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
