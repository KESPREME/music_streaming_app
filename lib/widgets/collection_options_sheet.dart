// lib/widgets/collection_options_sheet.dart
//
// TOUCH-AND-HOLD ON AN ALBUM OR PLAYLIST CARD.
//
// A song has a sheet (Play next, Add to queue, ...). An album or playlist did not:
// on Home the card was inert. This is that sheet, in the same glass as the song
// one. Order follows Apple Music's context menu and the reference apps: the two
// things people do most (Play, Shuffle) as large pills, then the list in the order
// they are used, and nothing destructive.
//
// The songs are fetched ONCE, when the sheet opens, so by the time a row is tapped
// they are usually there. A row tapped early waits for them (a spinner on that
// row); if they cannot be loaded the sheet says so and the next tap tries again.
// A control never goes silent.

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/navigation/root_navigator.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../theme/app_font.dart';
import '../utils/app_image_cache.dart';
import '../utils/image_quality_utils.dart';
import '../utils/share_text.dart';
import 'artist_picker_sheet.dart';
import 'glass_snackbar.dart';
import 'glass_surface.dart';
import 'jelly_press.dart';
import 'playlist/add_to_playlist_sheet.dart';
import 'themed_artist_detail_screen.dart';

/// Opens the sheet for one album or playlist.
///
/// [loadTracks] is called once, when the sheet opens. [collectionId] only builds the
/// share link. [artistName] enables "Go to artist".
Future<void> showCollectionOptionsSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String artworkUrl,
  required String collectionId,
  required Future<List<Track>> Function() loadTracks,
  String? artistName,
}) async {
  final provider = Provider.of<MusicProvider>(context, listen: false);
  // The navigator outlives this sheet; the sheet's own context does not. Every
  // follow-up (toasts, the add-to-playlist sheet) goes through it.
  final host = Navigator.of(context).context;

  final wasHidden = provider.hideMiniPlayer;
  final wasExpanded = provider.isPlayerExpanded;
  if (!wasExpanded) provider.setHideMiniPlayer(true);
  try {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CollectionSheet(
        host: host,
        provider: provider,
        title: title,
        subtitle: subtitle,
        artworkUrl: artworkUrl,
        collectionId: collectionId,
        artistName: artistName,
        loadTracks: loadTracks,
      ),
    );
  } finally {
    if (!wasHidden && !wasExpanded) provider.setHideMiniPlayer(false);
  }
}

class _CollectionSheet extends StatefulWidget {
  const _CollectionSheet({
    required this.host,
    required this.provider,
    required this.title,
    required this.subtitle,
    required this.artworkUrl,
    required this.collectionId,
    required this.loadTracks,
    this.artistName,
  });

  final BuildContext host;
  final MusicProvider provider;
  final String title;
  final String subtitle;
  final String artworkUrl;
  final String collectionId;
  final String? artistName;
  final Future<List<Track>> Function() loadTracks;

  @override
  State<_CollectionSheet> createState() => _CollectionSheetState();
}

class _CollectionSheetState extends State<_CollectionSheet> {
  late Future<List<Track>> _tracks = widget.loadTracks();
  bool _loaded = false;
  bool _failed = false;

  /// The row that is waiting on the songs (a spinner replaces its icon).
  String? _waiting;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  void _watch() {
    _tracks.then((t) {
      if (!mounted) return;
      setState(() {
        _loaded = t.isNotEmpty;
        _failed = t.isEmpty;
      });
    }, onError: (_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  /// Runs [action] with the songs once they are in. Closes the sheet first so the
  /// answer (playback, a toast, the next sheet) is what the listener sees.
  Future<void> _withTracks(String key, Future<void> Function(List<Track> tracks) action) async {
    if (_waiting != null) return;
    HapticFeedback.lightImpact();
    if (_failed) {
      // Try again: the failure may have been a dropped connection.
      setState(() {
        _failed = false;
        _tracks = widget.loadTracks();
      });
      _watch();
    }
    if (!_loaded) setState(() => _waiting = key);
    List<Track> tracks;
    try {
      tracks = await _tracks;
    } catch (_) {
      tracks = const [];
    }
    if (!mounted) return;
    if (tracks.isEmpty) {
      setState(() {
        _waiting = null;
        _failed = true;
      });
      return;
    }
    Navigator.pop(context);
    await action(tracks);
  }

  void _toast(String message) {
    if (widget.host.mounted) showGlassSnackBar(widget.host, message);
  }

  String _songs(int n) => '$n ${n == 1 ? 'song' : 'songs'}';

  Future<void> _play(List<Track> tracks, {bool shuffle = false}) async {
    final list = shuffle ? (List<Track>.of(tracks)..shuffle()) : tracks;
    await widget.provider.playTrackList(list, initialIndex: 0);
  }

  Future<void> _playNext(List<Track> tracks) async {
    // playNext inserts at the front, so go backwards to keep the order.
    for (final t in tracks.reversed) {
      widget.provider.playNext(t);
    }
    _toast('Playing next: ${_songs(tracks.length)}');
  }

  Future<void> _queue(List<Track> tracks) async {
    widget.provider.addListToQueue(tracks);
    _toast('Added ${_songs(tracks.length)} to the queue');
  }

  Future<void> _download(List<Track> tracks) async {
    _toast('Downloading ${_songs(tracks.length)}');
    await widget.provider.downloadTracks(tracks);
  }

  Future<void> _addToPlaylist(List<Track> tracks) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (widget.host.mounted) await showAddToPlaylistSheet(widget.host, tracks);
  }

  void _share() {
    Navigator.pop(context);
    SharePlus.instance.share(ShareParams(
      text: collectionShareText(title: widget.title, artist: widget.artistName, id: widget.collectionId),
    ));
  }

  void _goToArtist() {
    final name = widget.artistName;
    if (name == null || name.isEmpty) return;
    Navigator.pop(context);
    // "A & B" credits ask which artist first, like the song sheet does.
    if (ArtistPickerSheet.hasMultipleArtists(name)) {
      ArtistPickerSheet.showIfNeeded(widget.host, widget.provider, name);
      return;
    }
    widget.provider.setHideMiniPlayer(false);
    final nav = mainNavigatorKey.currentState ?? rootNavigatorKey.currentState ?? Navigator.of(widget.host);
    nav.push(MaterialPageRoute<void>(
      builder: (_) => ThemedArtistDetailScreen(
        artistId: 'artist_$name',
        artistName: name,
        searchByName: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const base = Color(0xFF121214);
    final hasArt = widget.artworkUrl.isNotEmpty;
    final hasArtist = (widget.artistName ?? '').isNotEmpty;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: Container(
        decoration: BoxDecoration(
          color: base,
          border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Stack(
          children: [
            // The cover, blurred, as the sheet's wash (same idea as the song sheet).
            if (hasArt)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 240,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Transform.scale(
                        scale: 1.4,
                        alignment: Alignment.topCenter,
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
                          child: CachedNetworkImage(
                            imageUrl: ImageQualityUtils.getHighResArtwork(widget.artworkUrl),
                            fit: BoxFit.cover,
                            memCacheWidth: AppImageCache.thumbnailMemCache,
                            memCacheHeight: AppImageCache.thumbnailMemCache,
                            errorWidget: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              base.withValues(alpha: 0.35),
                              base.withValues(alpha: 0.6),
                              base.withValues(alpha: 0.9),
                              base,
                            ],
                            stops: const [0.0, 0.25, 0.65, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            GlassSurface(
              tier: GlassTier.sheet,
              borderRadius: 32,
              child: SafeArea(
                top: false,
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        width: 36,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2.25),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 6, 22, 16),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 64,
                                height: 64,
                                child: hasArt
                                    ? CachedNetworkImage(
                                        imageUrl: ImageQualityUtils.getHighResArtwork(widget.artworkUrl),
                                        fit: BoxFit.cover,
                                        memCacheWidth: AppImageCache.thumbnailMemCache,
                                        memCacheHeight: AppImageCache.thumbnailMemCache,
                                        errorWidget: (_, __, ___) => const _CoverFallback(),
                                      )
                                    : const _CoverFallback(),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: Text(
                                      widget.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFont.style(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                        height: 1.15,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  if (widget.subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      widget.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFont.style(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // The two things people do most, as pills.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: _ActionPill(
                                label: 'Play',
                                icon: Icons.play_arrow_rounded,
                                filled: true,
                                busy: _waiting == 'play',
                                onTap: () => _withTracks('play', _play),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ActionPill(
                                label: 'Shuffle',
                                icon: Icons.shuffle_rounded,
                                filled: false,
                                busy: _waiting == 'shuffle',
                                onTap: () => _withTracks('shuffle', (t) => _play(t, shuffle: true)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_failed)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 4, 22, 6),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Couldn't load the songs. Tap an option to try again.",
                                  style: AppFont.style(fontSize: 13, color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Divider(height: 1, thickness: 0.5, color: Colors.white.withValues(alpha: 0.10)),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              _Row(
                                icon: Icons.playlist_play_rounded,
                                label: 'Play next',
                                busy: _waiting == 'next',
                                onTap: () => _withTracks('next', _playNext),
                              ),
                              _Row(
                                icon: Icons.queue_music_rounded,
                                label: 'Add to queue',
                                busy: _waiting == 'queue',
                                onTap: () => _withTracks('queue', _queue),
                              ),
                              _Row(
                                icon: Icons.playlist_add_rounded,
                                label: 'Add to a playlist...',
                                busy: _waiting == 'playlist',
                                onTap: () => _withTracks('playlist', _addToPlaylist),
                              ),
                              _Row(
                                icon: Icons.file_download_outlined,
                                label: 'Download',
                                busy: _waiting == 'download',
                                onTap: () => _withTracks('download', _download),
                              ),
                              _Row(
                                icon: Icons.ios_share_rounded,
                                label: 'Share',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  _share();
                                },
                              ),
                              if (hasArtist)
                                _Row(
                                  icon: Icons.person_outline_rounded,
                                  label: 'Go to artist',
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _goToArtist();
                                  },
                                ),
                              const SizedBox(height: 16),
                            ],
                          ),
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
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.grey[900],
        child: const Icon(Icons.album_rounded, color: Colors.white24, size: 30),
      );
}

/// A sheet row: icon, label; a spinner in place of the icon while it waits on the
/// songs. Rows keep Material ink (they are rows, not controls floating on glass).
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap, this.busy = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 22),
        visualDensity: const VisualDensity(vertical: -1.5),
        minLeadingWidth: 28,
        horizontalTitleGap: 14,
        leading: busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: color.withValues(alpha: 0.8)),
              )
            : Icon(icon, color: color, size: 22),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppFont.style(color: color, fontWeight: FontWeight.w500, fontSize: 15.5),
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Play / Shuffle: a large pill with the house jelly.
class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.black : Colors.white;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: JellyPress(
        profile: JellyProfile.pill,
        haptic: JellyHaptic.none,
        onTap: onTap,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: filled ? Colors.white : Colors.white.withValues(alpha: 0.10),
            border: Border.all(color: Colors.white.withValues(alpha: filled ? 0 : 0.18), width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                )
              else
                Icon(icon, color: fg, size: 24),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppFont.style(color: fg, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
