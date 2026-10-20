import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_font.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../services/canvas_resolution_service.dart';
import '../services/innertube/innertube_service.dart';
import '../models/bitchord_page_models.dart';
import '../utils/app_image_cache.dart';
import '../utils/artwork_palette_resolver.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/covered_gate.dart';
import '../widgets/animated_equalizer_icon.dart';
import '../widgets/bitchord_detail/bitchord_detail.dart';
import '../widgets/themed_options_sheet.dart';
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

  /// More by the artist / You might also like / Other versions.
  List<DetailShelf> _shelves = const [];

  /// How the list is ordered. Playing, the queue and Play all follow it.
  AlbumSort _sort = AlbumSort.albumOrder;

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
            _shelves = pageData.shelves;
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

  /// The album in the chosen order. Identity-stable (the same Track objects),
  /// so row numbers keyed by identity survive a sort.
  List<Track> _sortedTracks() => sortAlbumTracks(_tracks, _sort);

  List<Track> _getFilteredTracks() {
    final sorted = _sortedTracks();
    final query = _searchQuery.trim();
    if (query.isEmpty) return sorted;
    final q = _normalize(query);
    return sorted.where((t) =>
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

  // ── Actions ────────────────────────────────────────────────────────────────

  void _toast(String message) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));

  void _playNextAll() {
    if (_tracks.isEmpty) return;
    final mp = context.read<MusicProvider>();
    // playNext inserts at the front, so go backwards to keep album order.
    for (final t in _sortedTracks().reversed) {
      mp.playNext(t);
    }
    _toast('Playing next: ${_tracks.length} ${_tracks.length == 1 ? 'song' : 'songs'}');
  }

  void _queueAll() {
    if (_tracks.isEmpty) return;
    context.read<MusicProvider>().addListToQueue(_sortedTracks());
    _toast('Added ${_tracks.length} ${_tracks.length == 1 ? 'song' : 'songs'} to the queue');
  }

  Future<void> _saveAsPlaylist(String title) async {
    if (_tracks.isEmpty) return;
    final mp = context.read<MusicProvider>();
    final pl = await mp.createPlaylistWith(
      name: title,
      tracks: _tracks,
      imageUrl: _resolvedImageUrl,
    );
    if (!mounted) return;
    _toast(pl == null ? "Couldn't save the playlist" : 'Saved "$title" to your playlists');
  }

  void _shareAlbum(String title) {
    final artist = _resolvedArtist;
    final id = widget.albumId;
    final link = (id.startsWith('MPREb_') || id.startsWith('OLAK'))
        ? '\nhttps://music.youtube.com/browse/$id'
        : '';
    final who = (artist == null || artist.isEmpty) ? '' : ' by $artist';
    SharePlus.instance.share(ShareParams(text: '$title$who$link'));
  }

  void _playFrom(List<Track> order, int index) {
    if (order.isEmpty) return;
    context.read<MusicProvider>().playTrackList(order, initialIndex: index.clamp(0, order.length - 1));
  }

  List<Widget> _moreItems(String title, ReleaseDownloadState dl) => [
        lgw.GlassMenuItem(
          title: 'Play next',
          icon: const Icon(Icons.queue_play_next_rounded),
          onTap: _playNextAll,
        ),
        lgw.GlassMenuItem(
          title: 'Add to queue',
          icon: const Icon(Icons.playlist_add_rounded),
          onTap: _queueAll,
        ),
        lgw.GlassMenuItem(
          title: 'Save as playlist',
          icon: const Icon(Icons.library_add_rounded),
          onTap: () => _saveAsPlaylist(title),
        ),
        lgw.GlassMenuItem(
          title: dl == ReleaseDownloadState.done ? 'Downloaded' : 'Download album',
          icon: Icon(dl == ReleaseDownloadState.done ? Icons.download_done_rounded : Icons.download_rounded),
          onTap: () => _onDownloadTap(dl),
        ),
        const lgw.GlassMenuDivider(),
        lgw.GlassMenuItem(
          title: 'Share',
          icon: const Icon(Icons.ios_share_rounded),
          onTap: () => _shareAlbum(title),
        ),
        if (_resolvedArtist != null && _resolvedArtist!.isNotEmpty)
          lgw.GlassMenuItem(
            title: 'Go to artist',
            icon: const Icon(Icons.person_rounded),
            onTap: () => _openArtist(context.read<MusicProvider>()),
          ),
      ];

  List<Widget> _sortItems() => [
        for (final s in AlbumSort.values)
          lgw.GlassMenuItem(
            title: s.label,
            icon: Icon(s.icon),
            isSelected: s == _sort,
            trailing: s == _sort ? const Icon(Icons.check_rounded, size: 18) : null,
            onTap: () => setState(() => _sort = s),
          ),
      ];

  // ── Build ──────────────────────────────────────────────────────────────────

  Widget _cover(Color wash) {
    final url = _resolvedImageUrl ?? widget.albumImage ?? '';
    if (url.isEmpty) return ColoredBox(color: wash);
    return CachedNetworkImage(
      imageUrl: ImageQualityUtils.getHighQualityUrl(url),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      memCacheWidth: AppImageCache.heroMemCache,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => ColoredBox(color: wash),
      errorWidget: (_, __, ___) => ColoredBox(color: wash),
    );
  }

  Widget? _motionCover() {
    final c = _albumVideoController;
    if (c == null || !c.value.isInitialized) return null;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }

  /// Title, artist, one meta line and the action row, over the fade.
  Widget _titleBlock({
    required String title,
    required String metadataLine,
    required ArtworkPalette pal,
    required MusicProvider musicProvider,
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
              title,
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
          if (_resolvedArtist != null && _resolvedArtist!.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openArtist(musicProvider),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 6, 28, 2),
                child: Text(
                  _resolvedArtist!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.style(
                    color: Color.lerp(accent, Colors.white, 0.35),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          if (metadataLine.isNotEmpty && !_isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 28, 0),
              child: Text(
                metadataLine,
                key: const ValueKey('album_meta'),
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
            onPlay: () => _playFrom(_sortedTracks(), 0),
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
              selector: (_, mp) => _downloadState(mp),
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

  Widget _trackRow({
    required Track track,
    required List<Track> order,
    required Map<Track, int> numberOf,
    required ArtworkPalette pal,
  }) {
    final accent = pal.accent;
    final number = numberOf[track] ?? 0;
    return RepaintBoundary(
      child: Selector<MusicProvider, ({bool isCurrent, bool isPlaying})>(
        selector: (_, mp) => (
          isCurrent: track.isSameTrackAs(mp.currentTrack),
          isPlaying: mp.isPlaying,
        ),
        builder: (context, st, _) {
          final current = st.isCurrent;
          final duration = track.durationText;
          return BitchordSwipeableTrackRow(
            track: track,
            palette: pal,
            child: Material(
              color: current ? accent.withValues(alpha: 0.12) : Colors.transparent,
              child: InkWell(
                // The queue is the album in the order SHOWN, from this row.
                onTap: () => _playFrom(order, order.indexWhere((t) => identical(t, track))),
                splashColor: Colors.white.withValues(alpha: 0.08),
                highlightColor: Colors.white.withValues(alpha: 0.04),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 11, 8, 11),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: current && st.isPlaying
                            ? AnimatedEqualizerIcon(isPlaying: true, color: accent, size: 18)
                            : current
                                ? Icon(Icons.play_arrow_rounded, color: accent, size: 20)
                                : Text(
                                    '$number',
                                    style: AppFont.style(
                                      color: Colors.white.withValues(alpha: 0.45),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                      ),
                      const SizedBox(width: 8),
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
                                      color: current ? accent : Colors.white,
                                      fontSize: 16,
                                      fontWeight: current ? FontWeight.w700 : FontWeight.w600,
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
                      if (duration.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          duration,
                          key: ValueKey('duration_${track.id}'),
                          style: AppFont.style(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                      IconButton(
                        tooltip: 'More',
                        icon: Icon(Icons.more_vert_rounded, color: Colors.white.withValues(alpha: 0.5), size: 20),
                        onPressed: () => ThemedOptionsSheet.show(context, track: track),
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

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final pal = _artworkPalette ?? ArtworkPalette.defaultDark;

    final media = MediaQuery.of(context);
    // FULL BLEED: the cover is the page's header, edge to edge, and dissolves
    // into the page colour (see ImmersiveHeader). Tall enough that the title
    // block always sits over the fade and never over the picture's subject.
    final heroH = (media.size.width / 0.92).clamp(media.padding.top + 56 + 262, 560.0);
    final displayedTracks = _getFilteredTracks();
    final order = _sortedTracks();
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

    final dl = _downloadState(musicProvider);

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
                imageUrl: _resolvedImageUrl ?? widget.albumImage,
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
                  overlay: _motionCover(),
                  child: _titleBlock(
                    title: title,
                    metadataLine: metadataLine,
                    pal: pal,
                    musicProvider: musicProvider,
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
                    hasLeadingThumb: false,
                  ),
                )
              else if (_error != null && _tracks.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Text(_error!, style: AppFont.style(color: Colors.white70, fontSize: 16)),
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
                if (_resolvedDescription != null && _resolvedDescription!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: AboutSection(
                      title: 'About the album',
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
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _trackRow(
                        track: displayedTracks[index],
                        order: order,
                        numberOf: numberOf,
                        pal: pal,
                      ),
                      childCount: displayedTracks.length,
                      addRepaintBoundaries: true,
                      addAutomaticKeepAlives: false,
                    ),
                  ),
                ),

                // Runtime summary and the (p) line
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
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
                        const SizedBox(height: 4),
                        Text(
                          // The year only when the page said it.
                          _resolvedYear != null
                              ? '℗ $_resolvedYear ${_resolvedArtist ?? title}'
                              : '℗ ${_resolvedArtist ?? title}',
                          style: AppFont.style(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // More by the artist / You might also like / Other versions
                for (final shelf in _shelves)
                  SliverToBoxAdapter(
                    child: ShelfCarousel(shelf: shelf, artistNameHint: _resolvedArtist),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 120)), // mini player + nav bar
              ],
            ],
          ),

          // The glass chrome floats ABOVE the scroll view.
          DetailTopBar(
            controller: _scrollController,
            title: title,
            background: pal.background,
            accent: pal.accent,
            titleAppearsAt: heroH - media.padding.top - 120,
            slots: [
              DetailGlassSlot(
                icon: _isSearching ? Icons.search_off_rounded : Icons.search_rounded,
                label: _isSearching ? 'Close search' : 'Search in album',
                onTap: () => setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchQuery = '';
                    _searchController.clear();
                  }
                }),
              ),
              DetailGlassSlot(
                icon: Icons.sort_rounded,
                label: 'Sort',
                menuItems: _sortItems(),
                menuWidth: 220,
              ),
              DetailGlassSlot(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                menuItems: _moreItems(title, dl),
                menuWidth: 232,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How an album's songs are ordered.
enum AlbumSort {
  albumOrder('Album order', Icons.format_list_numbered_rounded),
  title('Title', Icons.sort_by_alpha_rounded),
  duration('Longest first', Icons.timer_outlined);

  const AlbumSort(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// [tracks] in [sort] order. Stable (ties keep album order) and never mutates
/// its input.
List<Track> sortAlbumTracks(List<Track> tracks, AlbumSort sort) {
  switch (sort) {
    case AlbumSort.albumOrder:
      return tracks;
    case AlbumSort.title:
      final indexed = [for (var i = 0; i < tracks.length; i++) (i, tracks[i])];
      indexed.sort((a, b) {
        final c = a.$2.trackName.toLowerCase().compareTo(b.$2.trackName.toLowerCase());
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
      return [for (final e in indexed) e.$2];
    case AlbumSort.duration:
      final indexed = [for (var i = 0; i < tracks.length; i++) (i, tracks[i])];
      indexed.sort((a, b) {
        final c = (b.$2.durationMs ?? 0).compareTo(a.$2.durationMs ?? 0);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
      return [for (final e in indexed) e.$2];
  }
}
