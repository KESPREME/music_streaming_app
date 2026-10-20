import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'jelly_press.dart';
import 'song_sheet_plan.dart';
import '../theme/app_font.dart';
import '../utils/app_image_cache.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import 'themed_album_detail_screen.dart';
import 'themed_artist_detail_screen.dart';
import '../theme/glass_tokens.dart';
import 'glass_surface.dart';
import 'playlist_selection_dialog.dart';
import 'glass_snackbar.dart';
import '../core/navigation/root_navigator.dart';
import 'artist_picker_sheet.dart'; // Multi-artist selection
import 'glass_download_selection_sheet.dart';
import '../presentation/explore/explore_top_pill.dart';
import '../utils/color_utils.dart';
import '../utils/image_quality_utils.dart';
import '../utils/share_text.dart';
import 'package:cached_network_image/cached_network_image.dart';

class GlassOptionsSheet extends StatelessWidget {
  final BuildContext? parentContext;
  final Track track;
  final String? playlistId;
  final bool isInQueueContext;
  final bool isRecentlyPlayedContext; // New context
  final VoidCallback? onDislike; // Explore-only: null hides the row
  final Color? accentColor;
  final Color? dominantColor;

  /// Where the sheet was opened from, which decides which rows it offers (see
  /// song_sheet_plan.dart). [SongSheetOrigin.auto] works it out from the other
  /// arguments; an unclassified caller gets everything that could apply.
  final SongSheetOrigin origin;

  const GlassOptionsSheet({
    super.key,
    this.parentContext,
    required this.track,
    this.playlistId,
    this.isInQueueContext = false,
    this.isRecentlyPlayedContext = false,
    this.onDislike,
    this.accentColor,
    this.dominantColor,
    this.origin = SongSheetOrigin.auto,
  });

  /// [origin] with `auto` resolved from the rest of the arguments.
  SongSheetOrigin get resolvedOrigin {
    if (origin != SongSheetOrigin.auto) return origin;
    if (playlistId != null) return SongSheetOrigin.playlist;
    if (isInQueueContext) return SongSheetOrigin.queue;
    if (isRecentlyPlayedContext) return SongSheetOrigin.history;
    if (track.source == 'local') return SongSheetOrigin.device;
    return SongSheetOrigin.generic;
  }

  /// Helper to show the options sheet while hiding the mini player
  static Future<void> show(
    BuildContext context, {
    required Track track,
    String? playlistId,
    bool isInQueueContext = false,
    bool isRecentlyPlayedContext = false,
    VoidCallback? onDislike,
    Color? accentColor,
    Color? dominantColor,
    SongSheetOrigin origin = SongSheetOrigin.auto,
  }) async {
    final provider = Provider.of<MusicProvider>(context, listen: false);

    final wasPlayerExpanded = provider.isPlayerExpanded;
    final wasHidden = provider.hideMiniPlayer;
    // Hide Mini Player only if not already in full player mode
    if (!wasPlayerExpanded) {
      provider.setHideMiniPlayer(true);
    }

    final effectiveAccent = accentColor ??
        ColorUtils.getVibrantAccent(
          provider.paletteGenerator,
          const Color(0xFFE89838),
        );
    final effectiveDominant = dominantColor ??
        provider.paletteGenerator?.dominantColor?.color ??
        effectiveAccent;

    try {
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.28),
        isScrollControlled: true,
        sheetAnimationStyle: const AnimationStyle(
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
          duration: Duration(milliseconds: 320),
        ),
        builder: (_) => GlassOptionsSheet(
          parentContext: context,
          track: track,
          playlistId: playlistId,
          isInQueueContext: isInQueueContext,
          isRecentlyPlayedContext: isRecentlyPlayedContext,
          onDislike: onDislike,
          accentColor: effectiveAccent,
          dominantColor: effectiveDominant,
          origin: origin,
        ),
      );
    } finally {
      // Restore Mini Player
      if (!wasHidden && !wasPlayerExpanded) {
        provider.setHideMiniPlayer(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if liked (requires listening to provider or passing in state,
    // but Consumer is safer for up-to-date state in a sheet)

    return Consumer<MusicProvider>(
      builder: (context, provider, child) {
        final dynAccent = accentColor ??
            ColorUtils.getVibrantAccent(
              provider.paletteGenerator,
              const Color(0xFFE89838),
            );

        final rawDominant = dominantColor ??
            provider.paletteGenerator?.dominantColor?.color ??
            dynAccent;

        final hslDominant = HSLColor.fromColor(rawDominant);
        // Deep chromatic background matching BitChord's dominant.withHsl(saturation.coerceIn(0.20, 0.62), lightness = 0.13)
        final sheetBgColor = hslDominant
            .withSaturation(hslDominant.saturation.clamp(0.20, 0.58))
            .withLightness(0.12)
            .toColor();

        final borderTint = dynAccent.withValues(alpha: 0.28);

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: Container(
            decoration: BoxDecoration(
              color: sheetBgColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(
                color: Color.alphaBlend(
                  borderTint,
                  Colors.white.withValues(alpha: 0.16),
                ),
                width: 1.0,
              ),
            ),
            child: Stack(
              children: [
                // BitChord ArtworkBackdrop: Blurred artwork wash across top 70%
                if (track.albumArtUrl.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 260,
                    child: ClipRect(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Transform.scale(
                            scale: 1.4,
                            alignment: Alignment.topCenter,
                            child: ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: 45,
                                sigmaY: 45,
                              ),
                              child: CachedNetworkImage(
                                imageUrl: ImageQualityUtils.getHighResArtwork(
                                  track.albumArtUrl,
                                ),
                                fit: BoxFit.cover,
                                memCacheWidth: AppImageCache.heroMemCache,
                                errorWidget: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  sheetBgColor.withValues(alpha: 0.35),
                                  sheetBgColor.withValues(alpha: 0.55),
                                  sheetBgColor.withValues(alpha: 0.85),
                                  sheetBgColor,
                                ],
                                stops: const [0.0, 0.22, 0.60, 0.95],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // GlassSurface overlay & content
                GlassSurface(
                  tier: GlassTier.sheet,
                  borderRadius: 32,
                  child: SafeArea(
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Handle Bar
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            width: 36,
                            height: 4.5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(2.25),
                            ),
                          ),
                          Flexible(
                            child: SongOptionsContent(
                              track: track,
                              provider: provider,
                              accent: dynAccent,
                              origin: resolvedOrigin,
                              parentContext: parentContext,
                              playlistId: playlistId,
                              isHistory: isRecentlyPlayedContext ||
                                  resolvedOrigin == SongSheetOrigin.history,
                              onDislike: onDislike,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Add to a playlist..." - with how many of your playlists already have it.
String _addToPlaylistLabel(int inCount) => inCount == 0
    ? 'Add to a playlist...'
    : 'Add to a playlist... (in $inCount)';

enum _Dl { idle, queued, running, done }

/// The sheet's header, quick tiles and grouped rows.
///
/// Stateful for two reasons only: the entrance (tiles pop in, groups fade up) and
/// the beat a finished instant action stays on screen as a check before the sheet
/// closes. Everything it shows comes from [planSongSheet].
class SongOptionsContent extends StatefulWidget {
  const SongOptionsContent({
    super.key,
    required this.track,
    required this.provider,
    required this.accent,
    required this.origin,
    this.parentContext,
    this.playlistId,
    this.isHistory = false,
    this.onDislike,
  });

  final Track track;
  final MusicProvider provider;
  final Color accent;
  final SongSheetOrigin origin;
  final BuildContext? parentContext;
  final String? playlistId;
  final bool isHistory;
  final VoidCallback? onDislike;

  @override
  State<SongOptionsContent> createState() => _SongOptionsContentState();
}

class _SongOptionsContentState extends State<SongOptionsContent> with SingleTickerProviderStateMixin {
  /// How long a finished instant action shows its check before the sheet closes.
  /// Short on purpose: long enough to be seen, short enough that nothing waits.
  static const Duration _checkBeat = Duration(milliseconds: 340);

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  /// One staggered slot per block: four tiles, then four groups.
  late final List<Animation<double>> _slots = [
    for (var i = 0; i < 8; i++)
      CurvedAnimation(
        parent: _enter,
        curve: Interval(0.06 * i, (0.06 * i + 0.5).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
      ),
  ];

  /// Instant actions that have happened: shown as "Added" / "Playing next" with a check.
  final Map<SongAction, String> _done = {};
  Timer? _closeTimer;
  bool _started = false;

  Track get track => widget.track;
  MusicProvider get provider => widget.provider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _enter.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// The navigator's context: it outlives this sheet, which is gone ~300 ms after
  /// it pops (see showAddToPlaylistSheet for what that cost once).
  BuildContext get _host => Navigator.of(context).context;

  void _toast(String message) {
    final host = _host;
    if (host.mounted) showGlassSnackBar(host, message);
  }

  /// Does [run] now, shows [doneLabel] with a check on the tile, then closes.
  void _instant(SongAction action, String doneLabel, VoidCallback run) {
    if (_done.containsKey(action)) return;
    HapticFeedback.lightImpact();
    run();
    setState(() => _done[action] = doneLabel);
    _closeTimer?.cancel();
    _closeTimer = Timer(_checkBeat, () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _playNext() => _instant(SongAction.playNext, 'Playing next', () {
        provider.playNext(track);
        _toast('Playing "${track.trackName}" next');
      });

  void _addToQueue() => _instant(SongAction.addToQueue, 'Added', () {
        provider.addToQueue(track);
        _toast('Added "${track.trackName}" to queue');
      });

  void _share() {
    Navigator.pop(context);
    SharePlus.instance.share(ShareParams(text: songShareText(track)));
  }

  Future<void> _addToPlaylist() async {
    final host = _host;
    Navigator.pop(context);
    await Future.delayed(const Duration(milliseconds: 100));
    if (host.mounted) await showPlaylistSelectionDialog(host, track);
  }

  void _code() {
    Navigator.pop(context);
    final accent = ColorUtils.getVibrantAccent(provider.paletteGenerator, const Color(0xFFE89838));
    showDialog(
      context: context,
      builder: (_) => SongCodeDialog(track: track, accent: accent),
    );
  }

  void _info() {
    Navigator.pop(context);
    showDialog(context: context, builder: (_) => SongInfoDialog(track: track));
  }

  void _sleep() {
    Navigator.pop(context);
    _showSleepTimerSheet(context, provider);
  }

  void _notInterested() {
    Navigator.pop(context);
    widget.onDislike?.call();
  }

  void _goToAlbum() {
    final target = widget.parentContext ?? context;
    Navigator.pop(context);
    _navigateToAlbum(target, provider, track);
  }

  void _goToArtist() {
    final target = widget.parentContext ?? context;
    Navigator.pop(context);
    if (ArtistPickerSheet.hasMultipleArtists(track.artistName)) {
      ArtistPickerSheet.showIfNeeded(target, provider, track.artistName, fallbackImage: track.albumArtUrl);
    } else {
      _navigateToArtist(target, provider, track.artistName, fallbackImage: track.albumArtUrl);
    }
  }

  void _removeFromQueue() => _instant(SongAction.removeFromQueue, 'Removed', () {
        provider.removeFromQueue(track);
        _toast('Removed from the queue');
      });

  void _removeFromPlaylist() => _instant(SongAction.removeFromPlaylist, 'Removed', () {
        provider.removeTrackFromPlaylist(widget.playlistId!, track.id);
        _toast('Removed from the playlist');
      });

  void _removeFromHistory() => _instant(SongAction.removeFromHistory, 'Removed', () {
        provider.removeFromRecentlyPlayed(track.id);
        _toast('Removed from Recently Played');
      });

  // ── Downloads: one tile that morphs through its states ────────────────────

  _Dl get _dlState {
    if (provider.isTrackDownloadedSync(track.id)) return _Dl.done;
    if (provider.isDownloading[track.id] == true) return _Dl.running;
    if (provider.downloadQueue.any((t) => t.id == track.id)) return _Dl.queued;
    return _Dl.idle;
  }

  Future<void> _downloadTap(_Dl state) async {
    switch (state) {
      case _Dl.idle:
        _instant(SongAction.download, 'Queued', () {
          _toast('Starting download: ${track.trackName}');
          provider.downloadTrack(track);
        });
      case _Dl.queued:
      case _Dl.running:
        HapticFeedback.lightImpact();
        provider.cancelDownload(track.id);
        _toast('Download cancelled');
      case _Dl.done:
        await _confirmAndRemoveDownload();
    }
  }

  /// A downloaded song asks before it is deleted (the old row only said "already
  /// downloaded", with no way to act on it). Deleting keeps the sheet open, so the
  /// tile visibly turns back into "Download".
  Future<void> _confirmAndRemoveDownload({bool closeAfter = false}) async {
    HapticFeedback.lightImpact();
    final host = _host;
    final ok = await confirmRemoveDownload(context, track);
    if (!ok) return;
    await provider.deleteDownloadedTrack(track.id);
    HapticFeedback.mediumImpact();
    if (host.mounted) showGlassSnackBar(host, 'Download removed');
    if (closeAfter && mounted) Navigator.pop(context);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLiked = provider.isSongLiked(track.id);
    final plan = planSongSheet(
      origin: widget.origin,
      track: track,
      isCurrent: provider.currentTrack?.id == track.id,
      inUpNext: provider.upNext.any((t) => t.id == track.id),
      hasDislike: widget.onDislike != null,
      hasPlaylistId: widget.playlistId != null,
      isHistory: widget.isHistory,
    );

    final tiles = plan.tiles.map(_tile).toList();
    final groups = <Widget>[
      if (plan.library.isNotEmpty) _group(plan.library, 4),
      if (plan.navigate.isNotEmpty) _group(plan.navigate, 5),
      if (plan.more.isNotEmpty) _group(plan.more, 6),
      if (plan.danger.isNotEmpty) _group(plan.danger, 7),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header (track info)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 14, 14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: ImageQualityUtils.getHighResArtwork(track.albumArtUrl),
                  width: 52,
                  memCacheWidth: AppImageCache.thumbnailMemCache,
                  height: 52,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 52,
                    height: 52,
                    color: Colors.grey[900],
                    child: const Icon(Icons.music_note, color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.trackName,
                      style: AppFont.style(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.artistName,
                      style: AppFont.style(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _LikeButton(
                liked: isLiked,
                accent: widget.accent,
                onTap: () => provider.toggleLike(track),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 0.5, color: Colors.white.withValues(alpha: 0.10)),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              children: [
                if (tiles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      children: [
                        for (var i = 0; i < tiles.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(child: _Reveal(animation: _slots[i], scale: true, child: tiles[i])),
                        ],
                      ],
                    ),
                  ),
                ...groups,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _group(List<SongAction> actions, int slot) {
    final rows = [for (final a in actions) _row(a)];
    final danger = actions.every((a) =>
        a == SongAction.removeFromQueue ||
        a == SongAction.removeFromPlaylist ||
        a == SongAction.removeFromHistory);
    return _Reveal(
      animation: _slots[slot],
      child: _GroupCard(danger: danger, children: rows),
    );
  }

  // ── Tiles ──────────────────────────────────────────────────────────────────

  Widget _tile(SongAction a) {
    switch (a) {
      case SongAction.playNext:
        return _QuickTile(
          icon: Icons.playlist_play_rounded,
          label: 'Play next',
          doneLabel: _done[a],
          accent: widget.accent,
          onTap: _playNext,
        );
      case SongAction.addToQueue:
        return _QuickTile(
          icon: Icons.queue_music_rounded,
          label: 'Add to queue',
          doneLabel: _done[a],
          accent: widget.accent,
          onTap: _addToQueue,
        );
      case SongAction.share:
        return _QuickTile(
          icon: Icons.ios_share_rounded,
          label: 'Share',
          accent: widget.accent,
          onTap: _share,
        );
      case SongAction.removeDownload:
        return _QuickTile(
          icon: Icons.delete_outline_rounded,
          label: 'Remove',
          destructive: true,
          accent: widget.accent,
          onTap: () => _confirmAndRemoveDownload(closeAfter: true),
        );
      case SongAction.download:
        return _downloadTile();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _downloadTile() {
    final state = _dlState;
    final progress = (provider.downloadProgress[track.id] ?? 0.0).clamp(0.0, 1.0);
    final done = _done[SongAction.download];
    final String label;
    final Widget glyph;
    switch (state) {
      case _Dl.idle:
        label = 'Download';
        glyph = const Icon(Icons.file_download_outlined, key: ValueKey('dl_idle'), size: 24);
      case _Dl.queued:
        label = 'Queued';
        glyph = Icon(Icons.hourglass_top_rounded, key: const ValueKey('dl_queued'), size: 24, color: widget.accent);
      case _Dl.running:
        label = '${(progress * 100).round()}%';
        glyph = SizedBox(
          key: const ValueKey('dl_running'),
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: progress <= 0 ? null : progress,
            strokeWidth: 2.6,
            color: widget.accent,
            backgroundColor: Colors.white.withValues(alpha: 0.14),
          ),
        );
      case _Dl.done:
        label = 'Downloaded';
        glyph = const Icon(Icons.download_done_rounded, key: ValueKey('dl_done'), size: 24, color: Color(0xFF4ADE80));
    }
    return _QuickTile(
      glyph: glyph,
      label: label,
      doneLabel: done,
      accent: widget.accent,
      onTap: () => _downloadTap(state),
    );
  }

  // ── Rows ───────────────────────────────────────────────────────────────────

  Widget _row(SongAction a) {
    final scheme = Theme.of(context).colorScheme;
    switch (a) {
      case SongAction.addToPlaylist:
        return _SheetRow(
          icon: Icons.playlist_add_rounded,
          label: _addToPlaylistLabel(provider.playlistsContaining(track.id).length),
          onTap: _addToPlaylist,
        );
      case SongAction.goToAlbum:
        return _SheetRow(
          icon: Icons.album_outlined,
          label: 'Go to album',
          fallbackLabel: 'Go to Album',
          // Which album, not which artist: the artist is already the header's line.
          subtitle: track.albumName,
          onTap: _goToAlbum,
        );
      case SongAction.goToArtist:
        return _SheetRow(
          icon: Icons.person_outline_rounded,
          label: 'Go to artist',
          fallbackLabel: 'Go to Artist',
          onTap: _goToArtist,
        );
      case SongAction.code:
        return _SheetRow(
          icon: Icons.qr_code_2_rounded,
          label: 'Mine Music Code',
          fallbackLabel: 'Muzo Code',
          onTap: _code,
        );
      case SongAction.songInfo:
        return _SheetRow(icon: Icons.info_outline_rounded, label: 'Song Info', onTap: _info);
      case SongAction.sleepTimer:
        return _SheetRow(icon: Icons.timer_outlined, label: 'Sleep Timer', onTap: _sleep);
      case SongAction.notInterested:
        return _SheetRow(icon: Icons.heart_broken_rounded, label: 'Not interested', onTap: _notInterested);
      case SongAction.removeFromQueue:
        return _SheetRow(
          icon: Icons.delete_sweep_rounded,
          label: _done.containsKey(a) ? 'Removed' : 'Remove from Queue',
          color: scheme.error,
          onTap: _removeFromQueue,
        );
      case SongAction.removeFromPlaylist:
        return _SheetRow(
          icon: Icons.remove_circle_outline_rounded,
          label: _done.containsKey(a) ? 'Removed' : 'Remove from Playlist',
          color: scheme.error,
          onTap: _removeFromPlaylist,
        );
      case SongAction.removeFromHistory:
        return _SheetRow(
          icon: Icons.history_toggle_off_rounded,
          label: _done.containsKey(a) ? 'Removed' : 'Remove from History',
          color: scheme.error,
          onTap: _removeFromHistory,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Navigation helpers (the sheet is already closed when these run) ───────

  void _navigateToAlbum(BuildContext context, MusicProvider provider, Track track) {
    provider.setHideMiniPlayer(false);
    provider.setPlayerExpanded(false);
    provider.playerNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    final primaryArtist = ArtistPickerSheet.getPrimaryArtist(track.artistName);
    final nav = mainNavigatorKey.currentState ?? rootNavigatorKey.currentState ?? Navigator.of(context);
    nav.push(
      MaterialPageRoute(
        builder: (_) => ThemedAlbumDetailScreen(
          albumId: track.albumId?.isNotEmpty == true ? track.albumId! : 'album_${track.albumName}',
          albumName: track.albumName,
          artistName: primaryArtist,
          albumImage: track.albumArtUrl,
          searchByName: true,
        ),
      ),
    );
  }

  void _navigateToArtist(
    BuildContext context,
    MusicProvider provider,
    String artistName, {
    String? fallbackImage,
  }) {
    provider.setHideMiniPlayer(false);
    provider.setPlayerExpanded(false);
    provider.playerNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    final nav = mainNavigatorKey.currentState ?? rootNavigatorKey.currentState ?? Navigator.of(context);
    nav.push(
      MaterialPageRoute(
        builder: (_) => ThemedArtistDetailScreen(
          artistId: 'artist_$artistName',
          artistName: artistName,
          searchByName: true,
          fallbackImage: fallbackImage,
        ),
      ),
    );
  }

  void _showSleepTimerSheet(BuildContext context, MusicProvider provider) {
    // The choices stay up for as long as a person takes to pick one - long after the
    // options sheet that opened them has closed - so the confirmation must go
    // through the navigator's context, not this sheet's (which is gone by then).
    final host = Navigator.of(context).context;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassSurface(
        tier: GlassTier.sheet,
        borderRadius: GlassTokens.radiusSheet,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Sleep Timer',
                  style: AppFont.style(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...[15, 30, 45, 60].map(
                (mins) => ListTile(
                  title: Text(
                    '$mins Minutes',
                    style: AppFont.style(color: Colors.white),
                  ),
                  onTap: () {
                    provider.setSleepTimer(mins);
                    Navigator.pop(ctx);
                    showGlassSnackBar(host, 'Sleep timer set for $mins minutes');
                  },
                ),
              ),
              ListTile(
                title: Text(
                  'End of Track',
                  style: AppFont.style(color: Colors.white),
                ),
                onTap: () {
                  provider.setSleepTimer(0);
                  Navigator.pop(ctx);
                  showGlassSnackBar(host, 'Playback will stop after this track');
                },
              ),
              ListTile(
                title: Text(
                  'Turn Off',
                  style: AppFont.style(color: Colors.white54),
                ),
                onTap: () {
                  provider.setSleepTimer(-1);
                  Navigator.pop(ctx);
                  showGlassSnackBar(host, 'Sleep timer turned off');
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks before a downloaded song is deleted. Same words as the Downloads screen.
Future<bool> confirmRemoveDownload(BuildContext context, Track track) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Remove this download?'),
      content: Text('"${track.trackName}" will no longer play offline. You can download it again any time.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Remove', style: TextStyle(color: Color(0xFFFF3B5C))),
        ),
      ],
    ),
  );
  return ok == true;
}

/// One block's entrance: fades up (and, for tiles, pops in) on its slot of the stagger.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.animation, required this.child, this.scale = false});

  final Animation<double> animation;
  final Widget child;
  final bool scale;

  @override
  Widget build(BuildContext context) {
    Widget out = SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.10), end: Offset.zero).animate(animation),
      child: child,
    );
    if (scale) {
      out = ScaleTransition(scale: Tween<double>(begin: 0.9, end: 1).animate(animation), child: out);
    }
    return FadeTransition(opacity: animation, child: out);
  }
}

/// The like star: a jelly circle whose glyph morphs (a bounce into colour) when toggled.
class _LikeButton extends StatelessWidget {
  const _LikeButton({required this.liked, required this.accent, required this.onTap});

  final bool liked;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: liked,
      label: liked ? 'Unlike' : 'Like',
      excludeSemantics: true,
      child: JellyPress(
        profile: JellyProfile.circle,
        haptic: JellyHaptic.light,
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.elasticOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: RotationTransition(turns: Tween<double>(begin: -0.08, end: 0).animate(anim), child: child),
              ),
              child: Icon(
                liked ? Icons.star_rounded : Icons.star_outline_rounded,
                key: ValueKey(liked),
                color: liked ? accent : Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A glass tile: a glyph over a label. Morphs to a check and a past-tense label for
/// a beat when its action has happened ([doneLabel]).
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    this.icon,
    this.glyph,
    required this.label,
    required this.onTap,
    required this.accent,
    this.doneLabel,
    this.destructive = false,
  }) : assert(icon != null || glyph != null);

  final IconData? icon;

  /// Replaces [icon] (the download tile's ring). Give it a key: the glyph morphs
  /// between states with a scale-and-fade, and the key is what tells it they differ.
  final Widget? glyph;
  final String label;
  final String? doneLabel;
  final Color accent;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = doneLabel != null;
    final fg = destructive ? scheme.error : scheme.onSurface;
    final shownLabel = doneLabel ?? label;
    return Semantics(
      button: true,
      label: shownLabel,
      excludeSemantics: true,
      child: JellyPress(
        profile: JellyProfile.pill,
        haptic: JellyHaptic.none,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 78,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: confirmed ? accent.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.07),
            border: Border.all(
              color: confirmed ? accent.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.10),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                child: confirmed
                    ? Icon(Icons.check_rounded, key: const ValueKey('done'), size: 26, color: accent)
                    : IconTheme(
                        key: ValueKey(glyph?.key ?? icon),
                        data: IconThemeData(color: fg, size: 24),
                        child: glyph ?? Icon(icon, size: 24),
                      ),
              ),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    shownLabel,
                    maxLines: 1,
                    style: AppFont.style(
                      color: confirmed ? accent : fg,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An inset rounded group of rows (iOS settings style), hairlines between.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children, this.danger = false});

  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: danger ? scheme.error.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: danger ? scheme.error.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 56, color: Colors.white.withValues(alpha: 0.08)),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A row inside a [_GroupCard]. Rows keep Material ink (they are rows, not controls
/// floating on glass).
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.fallbackLabel,
    this.color,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? fallbackLabel;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurface;
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: color ?? fg, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Text(
                          label,
                          style: AppFont.style(color: fg, fontWeight: FontWeight.w500, fontSize: 15.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // The pre-redesign casing, kept so anything that looks a row up by
                        // either spelling still finds it. Invisible and never hit.
                        if (fallbackLabel != null)
                          Opacity(
                            opacity: 0.0,
                            child: Text(fallbackLabel!, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.style(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (color == null) Icon(Icons.chevron_right_rounded, size: 20, color: Colors.white.withValues(alpha: 0.28)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Song Information Dialog with detailed metadata
class SongInfoDialog extends StatelessWidget {
  final Track track;

  const SongInfoDialog({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: GlassSurface(
        tier: GlassTier.sheet,
        borderRadius: 24,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: track.albumArtUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: track.albumArtUrl,
                              width: 52,
                              height: 52,
                              memCacheWidth: AppImageCache.thumbnailMemCache,
                              memCacheHeight: AppImageCache.thumbnailMemCache,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 52,
                              height: 52,
                              color: Colors.grey[900],
                              child: const Icon(Icons.music_note,
                                  color: Colors.white30),
                            ),
                          )
                        : Container(
                            width: 52,
                            height: 52,
                            color: Colors.grey[900],
                            child: const Icon(Icons.music_note,
                                color: Colors.white30),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.trackName,
                          style: AppFont.style(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artistName,
                          style: AppFont.style(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, thickness: 0.5, color: Colors.white12),
              const SizedBox(height: 14),
              _buildInfoRow(
                'Album',
                track.albumName.isNotEmpty ? track.albumName : 'Single',
              ),
              _buildInfoRow('Duration', _formatDuration(track.duration ?? (track.durationMs != null ? Duration(milliseconds: track.durationMs!) : null))),
              _buildInfoRow('Quality', 'Lossless • High Fidelity (320kbps AAC)'),
              _buildInfoRow(
                'Source',
                track.source.isNotEmpty
                    ? track.source.toUpperCase()
                    : 'MINE MUSIC STREAM',
              ),
              _buildInfoRow('Track ID', track.id),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    'Close',
                    style: AppFont.style(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: AppFont.style(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppFont.style(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration? d) {
    if (d == null || d == Duration.zero) return '--:--';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class GlassPlaylistOptionsSheet extends StatelessWidget {
  final String playlistName;
  final String? playlistImage;
  final List<Track> tracks;

  const GlassPlaylistOptionsSheet({
    super.key,
    required this.playlistName,
    this.playlistImage,
    required this.tracks,
  });

  static Future<void> show(
    BuildContext context, {
    required String playlistName,
    String? playlistImage,
    required List<Track> tracks,
  }) async {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    provider.setHideMiniPlayer(true);
    try {
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => GlassPlaylistOptionsSheet(
          playlistName: playlistName,
          playlistImage: playlistImage,
          tracks: tracks,
        ),
      );
    } finally {
      provider.setHideMiniPlayer(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final provider = Provider.of<MusicProvider>(context, listen: false);

    return GlassSurface(
      tier: GlassTier.sheet,
      borderRadius: GlassTokens.radiusSheet,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: playlistImage != null
                        ? Image.network(
                            playlistImage!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey[900],
                              width: 56,
                              height: 56,
                            ),
                          )
                        : Container(
                            color: Colors.grey[900],
                            width: 56,
                            height: 56,
                            child: const Icon(
                              Icons.music_note,
                              color: Colors.white24,
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      playlistName,
                      style: AppFont.style(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 0.5),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildOption(
                      context,
                      icon: Icons.download_rounded,
                      label: 'Download Playlist',
                      onTap: () {
                        Navigator.pop(context);
                        provider.downloadTracks(tracks);
                        showGlassSnackBar(
                          context,
                          'Downloading ${tracks.length} tracks',
                        );
                      },
                    ),
                    _buildOption(
                      context,
                      icon: Icons.checklist_rounded,
                      label: 'Select to Download',
                      onTap: () async {
                        final host = Navigator.of(context).context;
                        Navigator.pop(context);
                        await Future.delayed(const Duration(milliseconds: 100));
                        if (host.mounted) {
                          await showModalBottomSheet(
                            context: host,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (c) => GlassDownloadSelectionSheet(
                              tracks: tracks,
                              playlistName: playlistName,
                            ),
                          );
                        }
                      },
                    ),
                    _buildOption(
                      context,
                      icon: Icons.queue_music_rounded,
                      label: 'Add All to Queue',
                      onTap: () {
                        Navigator.pop(context);
                        for (var t in tracks) {
                          provider.addToQueue(t);
                        }
                        showGlassSnackBar(
                          context,
                          'Added ${tracks.length} to queue',
                        );
                      },
                    ),
                    _buildOption(
                      context,
                      icon: Icons.shuffle_rounded,
                      label: 'Shuffle Play',
                      onTap: () {
                        Navigator.pop(context);
                        provider.shuffleAndPlay(tracks);
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: effectiveColor),
      title: Text(
        label,
        style: AppFont.style(
          color: effectiveColor,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
    );
  }
}
