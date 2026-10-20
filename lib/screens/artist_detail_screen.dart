import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import '../utils/app_image_cache.dart';
import '../theme/app_font.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/bitchord_page_models.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../core/navigation/root_navigator.dart';
import '../services/auth_service.dart';
import '../widgets/account_button.dart';
import '../widgets/themed_settings_screen.dart';
import 'account_switcher_sheet.dart';
import '../services/innertube/innertube_service.dart';
import '../utils/artwork_palette_resolver.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/bitchord_detail/bitchord_detail.dart';

/// Aspect ratio for artist hero photography matching BitChord ARTIST_PHOTO_RATIO in DetailScreen.kt
const double _kArtistPhotoRatio = 0.95;

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

  // ── Actions ────────────────────────────────────────────────────────────────

  void _toast(String message) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));

  List<Track> get _shownSongs =>
      _topSongs.length > _topSongsCap ? _topSongs.sublist(0, _topSongsCap) : _topSongs;

  void _playNextAll() {
    final songs = _shownSongs;
    if (songs.isEmpty) return;
    final mp = context.read<MusicProvider>();
    // playNext inserts at the front, so go backwards to keep the order.
    for (final t in songs.reversed) {
      mp.playNext(t);
    }
    _toast('Playing next: ${songs.length} songs');
  }

  void _queueAll() {
    final songs = _shownSongs;
    if (songs.isEmpty) return;
    context.read<MusicProvider>().addListToQueue(songs);
    _toast('Added ${songs.length} songs to the queue');
  }

  Future<void> _saveAsPlaylist() async {
    final songs = _shownSongs;
    if (songs.isEmpty) return;
    final name = '$_resolvedArtistName: top songs';
    final pl = await context.read<MusicProvider>().createPlaylistWith(
          name: name,
          tracks: songs,
          imageUrl: _resolvedArtistImage,
        );
    if (!mounted) return;
    _toast(pl == null ? "Couldn't save the playlist" : 'Saved "$name" to your playlists');
  }

  void _onDownloadTap(ReleaseDownloadState state) {
    switch (state) {
      case ReleaseDownloadState.downloading:
        _toast('Downloading their top songs…');
        return;
      case ReleaseDownloadState.done:
        _toast('Every top song is downloaded');
        return;
      case ReleaseDownloadState.none:
      case ReleaseDownloadState.partial:
        final mp = context.read<MusicProvider>();
        final missing = _shownSongs
            .where((t) => t.source != 'local' && !mp.isTrackDownloadedSync(t.id))
            .toList();
        if (missing.isEmpty) return;
        mp.downloadTracks(missing);
        _toast('Downloading ${missing.length} ${missing.length == 1 ? 'song' : 'songs'}');
    }
  }

  /// Signed in: the account switcher. Signed out: Settings, which is where
  /// sign-in lives (the same two destinations as the avatar on Home).
  void _openAccount(AuthService? auth) {
    if (auth != null && auth.isLoggedIn) {
      AccountSwitcherSheet.show(context);
    } else {
      pushAboveShell<void>(context, const ThemedSettingsScreen());
    }
  }

  List<Widget> _moreItems(ReleaseDownloadState dl) => [
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
          title: 'Save top songs as playlist',
          icon: const Icon(Icons.library_add_rounded),
          onTap: _saveAsPlaylist,
        ),
        lgw.GlassMenuItem(
          title: dl == ReleaseDownloadState.done ? 'Top songs downloaded' : 'Download top songs',
          icon: Icon(dl == ReleaseDownloadState.done ? Icons.download_done_rounded : Icons.download_rounded),
          onTap: () => _onDownloadTap(dl),
        ),
        const lgw.GlassMenuDivider(),
        lgw.GlassMenuItem(
          title: 'Share',
          icon: const Icon(Icons.ios_share_rounded),
          onTap: _share,
        ),
      ];

  // ── Build ──────────────────────────────────────────────────────────────────

  Widget _photo(Color wash) {
    final url = _resolvedArtistImage ?? '';
    if (url.isEmpty) return ColoredBox(color: wash);
    return CachedNetworkImage(
      imageUrl: ImageQualityUtils.getHighQualityUrl(url),
      fit: BoxFit.cover,
      // Faces sit in the upper third of a portrait: crop the foot, not the head.
      alignment: const Alignment(0, -0.6),
      memCacheWidth: AppImageCache.heroMemCache,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => ColoredBox(color: wash),
      errorWidget: (_, __, ___) => ColoredBox(color: wash),
    );
  }

  /// "239M monthly listeners" from YouTube's "239M monthly audience".
  String? get _listenersCaption {
    final raw = _monthlyListenerCount?.trim();
    if (raw == null || raw.isEmpty) return null;
    return '${raw.split(' ').first} monthly listeners';
  }

  Widget _titleBlock({
    required ArtworkPalette pal,
    required MusicProvider musicProvider,
  }) {
    final accent = pal.accent;
    final caption = _listenersCaption;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _resolvedArtistName,
              key: const ValueKey('artist_name'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppFont.style(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.0,
                height: 1.05,
                shadows: const [Shadow(color: Color(0x66000000), blurRadius: 16)],
              ),
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                caption,
                key: const ValueKey('artist_listeners'),
                textAlign: TextAlign.center,
                style: AppFont.style(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          if (_topSongs.isNotEmpty) ...[
            const SizedBox(height: 14),
            DetailGlassScope(
              accent: accent,
              child: Padding(
                // Room for the press to inflate without being clipped.
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DetailGlassCircle(
                      icon: Icons.shuffle_rounded,
                      label: 'Shuffle',
                      size: DetailGlass.actionSize,
                      accent: accent,
                      onTap: () {
                        final shuffled = List<Track>.from(_topSongs)..shuffle();
                        musicProvider.playTrackList(shuffled, initialIndex: 0);
                      },
                    ),
                    const SizedBox(width: 26),
                    DetailGlassPill.disc(
                      onTap: () => musicProvider.playTrackList(_topSongs, initialIndex: 0),
                    ),
                    const SizedBox(width: 26),
                    Selector<MusicProvider, ReleaseDownloadState>(
                      selector: (_, mp) => releaseDownloadStateFor(mp, _shownSongs),
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
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final artPalette = _artworkPalette ?? ArtworkPalette.defaultDark;
    final accentColor = artPalette.accent;

    // The signed-in picture for the capsule. Absent in isolated tests.
    AuthService? auth;
    try {
      auth = context.watch<AuthService>();
    } catch (_) {
      auth = null;
    }

    final media = MediaQuery.of(context);
    // FULL BLEED, ONE SURFACE: the portrait is the page's header and dissolves
    // into the page colour (ImmersiveHeader). Tall enough that name, caption
    // and the action row always sit over the fade.
    final heroH = (media.size.width / _kArtistPhotoRatio).clamp(media.padding.top + 56 + 290, 620.0);
    final dl = releaseDownloadStateFor(musicProvider, _shownSongs);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: ArtworkWash(
                backgroundColor: artPalette.background,
                washColor: artPalette.wash,
                accentColor: accentColor,
                elevatedColor: artPalette.elevated,
                washFraction: (heroH / media.size.height).clamp(0.30, 0.80),
                seamOverhang: 160,
                meshInset: 120,
                imageUrl: _resolvedArtistImage ?? widget.artistImage,
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
                  washColor: artPalette.wash,
                  scrollController: _scrollController,
                  photo: _photo(artPalette.wash),
                  child: _titleBlock(pal: artPalette, musicProvider: musicProvider),
                ),
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Icon(Icons.person_off_rounded, size: 48, color: Colors.white.withValues(alpha: 0.4)),
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
                        songs: _shownSongs,
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

                // About, then the listener stats, at the end (BitChord order).
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
                const SliverToBoxAdapter(child: SizedBox(height: 120)), // mini player + nav bar
              ],
            ],
          ),

          // The glass chrome floats ABOVE the scroll view.
          DetailTopBar(
            controller: _scrollController,
            title: _resolvedArtistName,
            background: artPalette.background,
            accent: accentColor,
            titleAppearsAt: heroH - media.padding.top - 120,
            slots: [
              DetailGlassSlot(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                onTap: _share,
              ),
              DetailGlassSlot(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                menuItems: _moreItems(dl),
                menuWidth: 244,
              ),
              DetailGlassSlot(
                label: auth != null && auth.isLoggedIn ? 'Account' : 'Sign in',
                child: auth == null
                    ? const Icon(Icons.person_rounded, color: Colors.white, size: 22)
                    : IconTheme(
                        data: const IconThemeData(color: Colors.white),
                        child: AccountAvatar(auth: auth),
                      ),
                onTap: () => _openAccount(auth),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
