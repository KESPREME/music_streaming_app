// lib/screens/user_playlist_detail_screen.dart
//
// YOUR PLAYLIST, LIVE. (Plan: docs/PLAN-your-playlists.md, section 3.9-12.)
//
// The screen reads the playlist from the provider on every change, so an edit
// made anywhere - here, the Add to playlist sheet, Now Playing - shows at once.
// It replaces the old frozen copy, which could not remove a song and did not
// know an empty playlist from a missing one.
//
//   * Header after the reference: centred cover, name, description, "Made by
//     you · 30 songs · 4 hr 31 min"; Download · Shuffle · a large Play (Pause
//     while this playlist is what is playing).
//   * "Add songs": search, your likes, suggestions - one tall sheet.
//   * Songs: the shared row (tap plays in order, swipe right queues, swipe left
//     removes with Undo, long-press selects).
//   * Reorder mode (menu > Reorder songs): drag handles replace the menus.
//   * Menu: Edit details, Add songs, Reorder, Select, Add to queue, Download,
//     Pin, Delete (with Undo).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../theme/amoled_theme.dart';
import '../utils/artwork_palette_resolver.dart';
import '../widgets/collection/collection_kit.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/home_sections.dart' show PressableScale;
import '../widgets/playlist/add_songs_sheet.dart';
import '../widgets/playlist/add_to_playlist_sheet.dart';
import '../widgets/playlist/playlist_cover.dart';
import '../widgets/playlist/playlist_edit_sheet.dart';
import '../widgets/themed_options_sheet.dart';
import '../presentation/liked/liked_songs_query.dart' show normalizeForSearch, formatCollectionDuration;

class UserPlaylistDetailScreen extends StatefulWidget {
  const UserPlaylistDetailScreen({super.key, required this.playlistId, this.usePalette});

  final String playlistId;

  /// Tint the screen from the cover (needs the image). Null = [defaultUsePalette].
  final bool? usePalette;

  /// Tests turn this off: decoding a network cover starts timers the test
  /// harness would (rightly) flag.
  @visibleForTesting
  static bool defaultUsePalette = true;

  @override
  State<UserPlaylistDetailScreen> createState() => _UserPlaylistDetailScreenState();
}

class _UserPlaylistDetailScreenState extends State<UserPlaylistDetailScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Set<String> _selected = {};
  bool _reordering = false;
  String _filter = '';
  ArtworkPalette? _palette;
  String? _paletteFor;
  bool _popping = false;

  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _resolvePalette(Playlist p) {
    if (!(widget.usePalette ?? UserPlaylistDetailScreen.defaultUsePalette)) return;
    final url = p.imageUrl.isNotEmpty && !isLocalImagePath(p.imageUrl)
        ? p.imageUrl
        : (playlistCollageCovers(p).firstOrNull ?? '');
    if (url == _paletteFor) return;
    _paletteFor = url;
    if (url.isEmpty) {
      _palette = null;
      return;
    }
    final cached = ArtworkPaletteResolver.getCached(url);
    if (cached != null) {
      _palette = cached;
      return;
    }
    ArtworkPaletteResolver.resolve(url).then((pal) {
      if (mounted && _paletteFor == url) setState(() => _palette = pal);
    }).catchError((_) {});
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _play(Playlist p, List<Track> list, {int index = 0}) {
    if (list.isEmpty) return;
    final provider = context.read<MusicProvider>();
    provider.markPlaylistPlayed(p.id);
    provider.playTrack(list[index], playlistTracks: List<Track>.of(list), playlistId: p.id);
  }

  void _shuffle(Playlist p) {
    if (p.tracks.isEmpty) return;
    HapticFeedback.lightImpact();
    final list = List<Track>.of(p.tracks)..shuffle();
    if (list.length > 1 && list.first.id == context.read<MusicProvider>().currentTrack?.id) {
      list.add(list.removeAt(0));
    }
    _play(p, list);
  }

  void _download(List<Track> tracks) {
    final provider = context.read<MusicProvider>();
    final todo = tracks.where((t) => t.source != 'local' && !provider.isTrackDownloadedSync(t.id)).toList();
    if (tracks.isEmpty) return;
    if (todo.isEmpty) {
      showCollectionToast(context, 'Already downloaded', icon: Icons.download_done_rounded);
      return;
    }
    provider.downloadTracks(todo);
    showCollectionToast(context, 'Downloading ${todo.length} ${todo.length == 1 ? 'song' : 'songs'}',
        icon: Icons.download_rounded);
  }

  void _queue(List<Track> tracks) {
    if (tracks.isEmpty) return;
    final provider = context.read<MusicProvider>();
    for (final t in tracks) {
      provider.addToQueue(t);
    }
    HapticFeedback.lightImpact();
    showCollectionToast(
      context,
      tracks.length == 1 ? 'Added "${tracks.first.trackName}" to queue' : 'Added ${tracks.length} songs to queue',
      icon: Icons.queue_music_rounded,
    );
  }

  void _removeSongs(Playlist p, Iterable<String> ids) {
    final removed = context.read<MusicProvider>().removeTracksFromPlaylist(p.id, ids);
    if (removed.isEmpty) return;
    HapticFeedback.mediumImpact();
    showCollectionToast(
      context,
      removed.length == 1
          ? 'Removed "${removed.first.track.trackName}"'
          : 'Removed ${removed.length} songs',
      icon: Icons.remove_circle_outline_rounded,
      action: SnackBarAction(
        label: 'Undo',
        textColor: CollectionStyle.accent,
        onPressed: () {
          if (mounted) context.read<MusicProvider>().restorePlaylistTracks(p.id, removed);
        },
      ),
    );
  }

  void _deletePlaylist(Playlist p) {
    final provider = context.read<MusicProvider>();
    // Leaving on purpose: the "deleted elsewhere" path must not pop again.
    _popping = true;
    final removed = provider.deletePlaylistWithUndo(p.id);
    if (removed == null) return;
    HapticFeedback.mediumImpact();
    // The undo lives on the screen we return to.
    final messenger = ScaffoldMessenger.of(context);
    final inset = collectionBottomClearance(context);
    Navigator.of(context).maybePop();
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, inset - 8),
      duration: const Duration(seconds: 5),
      content: Text('Deleted "${p.name}"', maxLines: 1, overflow: TextOverflow.ellipsis),
      action: SnackBarAction(
        label: 'Undo',
        textColor: CollectionStyle.accent,
        onPressed: () => provider.restorePlaylist(removed),
      ),
    ));
  }

  void _edit(Playlist p) => showPlaylistEditSheet(context, existing: p);

  void _endSelection() => setState(_selected.clear);

  void _toggleSelected(String id) {
    HapticFeedback.selectionClick();
    setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
  }

  void _openMenu(Playlist p) {
    HapticFeedback.lightImpact();
    showCollectionSheet<void>(
      context,
      (sheet) => [
        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(18)),
        const SizedBox(height: 6),
        SheetRow(icon: Icons.edit_rounded, label: 'Edit details', onTap: () => _edit(p)),
        SheetRow(icon: Icons.playlist_add_rounded, label: 'Add songs', onTap: () => showAddSongsSheet(context, p.id)),
        if (p.tracks.length > 1)
          SheetRow(
            icon: Icons.drag_indicator_rounded,
            label: 'Reorder songs',
            onTap: () => setState(() {
              _reordering = true;
              _search.clear();
              _filter = '';
            }),
          ),
        if (p.tracks.isNotEmpty) ...[
          SheetRow(
            icon: Icons.checklist_rounded,
            label: 'Select songs',
            onTap: () => setState(() => _selected.add(p.tracks.first.id)),
          ),
          SheetRow(icon: Icons.queue_music_rounded, label: 'Add all to queue', onTap: () => _queue(p.tracks)),
          SheetRow(icon: Icons.download_rounded, label: 'Download all', onTap: () => _download(p.tracks)),
        ],
        SheetRow(
          icon: p.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          label: p.pinned ? 'Unpin' : 'Pin to top',
          onTap: () => context.read<MusicProvider>().setPlaylistPinned(p.id, !p.pinned),
        ),
        SheetRow(icon: Icons.delete_outline_rounded, label: 'Delete playlist', destructive: true, onTap: () => _deletePlaylist(p)),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.select<MusicProvider, Playlist?>((m) => m.playlistById(widget.playlistId));
    final currentId = context.select<MusicProvider, String?>((m) => m.currentTrack?.id);
    final playing = context.select<MusicProvider, bool>((m) => m.isPlaying);
    final ourContext = context.select<MusicProvider, bool>((m) => m.currentPlaylistId == widget.playlistId);
    final provider = context.read<MusicProvider>();

    if (p == null) {
      // Deleted elsewhere while open. Only close THIS page, and only while it is
      // on top: when it was deleted from its own menu it is already leaving, and
      // a second pop would close the screen under it.
      if (!_popping) {
        _popping = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final route = ModalRoute.of(context);
          if (route != null && route.isCurrent) Navigator.of(context).maybePop();
        });
      }
      return const Scaffold(backgroundColor: Colors.black);
    }
    _resolvePalette(p);

    final ids = {for (final t in p.tracks) t.id};
    _selected.removeWhere((id) => !ids.contains(id));
    bool downloaded(String id) => provider.isTrackDownloadedSync(id);

    final q = normalizeForSearch(_filter);
    final visible = q.isEmpty
        ? p.tracks
        : p.tracks
            .where((t) => normalizeForSearch('${t.trackName} ${t.artistName} ${t.albumName}').contains(q))
            .toList();
    final narrowed = q.isNotEmpty;
    final showSearch = p.tracks.length >= 8;
    final active = ourContext && currentId != null && ids.contains(currentId);
    final allDownloaded = p.tracks.isNotEmpty && p.tracks.every((t) => t.source == 'local' || downloaded(t.id));
    final top = MediaQuery.paddingOf(context).top;
    final amoled = AmoledTheme.isOn(context);
    final clearance = collectionBottomClearance(context);
    final tint = _palette?.accent ?? playlistHue(p.name);
    final duration = formatCollectionDuration(p.tracks);
    final n = p.tracks.length;
    final meta = [
      p.isUserCreated ? 'Made by you' : 'Imported playlist',
      n == 0 ? 'No songs' : (n == 1 ? '1 song' : '$n songs'),
      if (duration != null) duration,
    ].join(' · ');
    List<Track> picked() => p.tracks.where((t) => _selected.contains(t.id)).toList();

    Widget rowFor(Track t, int i, {Widget? handle}) => CollectionTrackRow(
          key: ValueKey('plt_${t.id}'),
          track: t,
          current: t.id == currentId,
          playing: t.id == currentId && playing,
          downloaded: t.source != 'local' && downloaded(t.id),
          selecting: _selecting,
          selected: _selected.contains(t.id),
          last: i == visible.length - 1,
          removeLabel: 'Remove',
          subtitleOverride: t.durationText.isEmpty ? null : '${t.artistName} · ${t.durationText}',
          reorderHandle: handle,
          onTap: () => _selecting ? _toggleSelected(t.id) : _play(p, visible, index: i),
          onLongPress: () {
            HapticFeedback.mediumImpact();
            setState(() => _selected.add(t.id));
          },
          onOptions: () => ThemedOptionsSheet.show(context, track: t, playlistId: p.id),
          onQueue: () => _queue([t]),
          onRemove: () => _removeSongs(p, [t.id]),
        );

    return PlayerAwarePopScope(
      child: PopScope(
        canPop: !_selecting && !_reordering,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_selecting) _endSelection();
          if (_reordering) setState(() => _reordering = false);
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              if (!amoled)
                Positioned(
                  top: -60,
                  left: -120,
                  right: -120,
                  height: 560,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.5),
                          radius: 0.85,
                          colors: [tint.withValues(alpha: 0.42), tint.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                ),
              CustomScrollView(
                controller: _scroll,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: top + 64)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 8, CollectionStyle.gutter, 4),
                      child: Column(
                        children: [
                          PlaylistCover(playlist: p, size: 210, radius: 22, shadow: true),
                          const SizedBox(height: 20),
                          Semantics(
                            header: true,
                            child: Text(p.name,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: CollectionStyle.title(28)),
                          ),
                          if (p.description.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(p.description,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: CollectionStyle.meta(size: 14.5, alpha: 0.65).copyWith(height: 1.35)),
                          ],
                          const SizedBox(height: 8),
                          Text(meta,
                              textAlign: TextAlign.center,
                              style: CollectionStyle.meta(size: 13.5, alpha: 0.5)),
                          const SizedBox(height: 18),
                          _ActionRow(
                            allDownloaded: allDownloaded,
                            empty: p.tracks.isEmpty,
                            active: active,
                            playing: active && playing,
                            tint: tint,
                            onDownload: () => _download(p.tracks),
                            onShuffle: () => _shuffle(p),
                            onPlay: () {
                              HapticFeedback.lightImpact();
                              final m = context.read<MusicProvider>();
                              if (active) {
                                playing ? m.pauseTrack() : m.resumeTrack();
                              } else {
                                _play(p, p.tracks);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          _AddSongsCard(tint: tint, onTap: () => showAddSongsSheet(context, p.id)),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  if (showSearch && !_reordering)
                    SliverToBoxAdapter(
                      child: CollectionSearchField(
                        controller: _search,
                        focus: _searchFocus,
                        hint: 'Find in this playlist',
                        onChanged: (v) => setState(() => _filter = v),
                      ),
                    ),
                  if (p.tracks.isEmpty)
                    SliverToBoxAdapter(
                      child: CollectionEmptyState(
                        title: 'This playlist is empty',
                        message: 'Add songs to start listening.',
                        actionLabel: 'Add songs',
                        actionIcon: Icons.add_rounded,
                        onAction: () => showAddSongsSheet(context, p.id),
                      ),
                    )
                  else if (visible.isEmpty)
                    SliverToBoxAdapter(
                      child: CollectionNoMatch(
                        query: _filter,
                        onClear: () => setState(() {
                          _search.clear();
                          _filter = '';
                        }),
                      ),
                    )
                  else if (_reordering && !narrowed)
                    SliverReorderableList(
                      itemCount: visible.length,
                      onReorderStart: (_) => HapticFeedback.mediumImpact(),
                      // onReorderItem hands over the index AFTER the removal; the
                      // provider takes the slot before it (ReorderableListView's).
                      onReorderItem: (from, to) => context
                          .read<MusicProvider>()
                          .reorderPlaylistTrack(p.id, from, to > from ? to + 1 : to),
                      itemBuilder: (context, i) => rowFor(
                        visible[i],
                        i,
                        handle: ReorderableDragStartListener(
                          index: i,
                          child: Semantics(
                            label: 'Drag to reorder ${visible[i].trackName}',
                            child: const SizedBox(
                              width: 48,
                              height: 48,
                              child: Icon(Icons.drag_handle_rounded, color: Colors.white54),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    FadeInSliver(
                      key: ValueKey('${p.id}|$q'),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => rowFor(visible[i], i),
                          childCount: visible.length,
                          findChildIndexCallback: (key) {
                            if (key is! ValueKey<String>) return null;
                            final i = visible.indexWhere((t) => 'plt_${t.id}' == key.value);
                            return i < 0 ? null : i;
                          },
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(child: SizedBox(height: clearance + (_selecting ? 76 : 0))),
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _reordering
                    ? _ReorderBar(topInset: top, onDone: () => setState(() => _reordering = false))
                    : CollectionNavBar(
                        scroll: _scroll,
                        topInset: top,
                        title: p.name,
                        titleAppearsAt: 230,
                        onBack: () => Navigator.maybePop(context),
                        onMore: () => _openMenu(p),
                        selecting: _selecting,
                        selectedCount: _selected.length,
                        allSelected: visible.isNotEmpty && visible.every((t) => _selected.contains(t.id)),
                        onEndSelection: _endSelection,
                        onSelectAll: () => setState(() {
                          if (visible.every((t) => _selected.contains(t.id))) {
                            _selected.clear();
                          } else {
                            _selected.addAll(visible.map((t) => t.id));
                          }
                        }),
                      ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: clearance - 6,
                child: CollectionSelectionBar(
                  visible: _selecting,
                  actions: [
                    SelectionAction(Icons.play_arrow_rounded, 'Play', () {
                      final list = picked();
                      _endSelection();
                      _play(p, list);
                    }),
                    SelectionAction(Icons.queue_music_rounded, 'Queue', () {
                      final list = picked();
                      _endSelection();
                      _queue(list);
                    }),
                    SelectionAction(Icons.download_rounded, 'Download', () {
                      final list = picked();
                      _endSelection();
                      _download(list);
                    }),
                    SelectionAction(Icons.playlist_add_rounded, 'Playlist', () {
                      final list = picked();
                      _endSelection();
                      showAddToPlaylistSheet(context, list);
                    }),
                    SelectionAction(Icons.remove_circle_outline_rounded, 'Remove', () {
                      final ids = Set<String>.of(_selected);
                      _endSelection();
                      _removeSongs(p, ids);
                    }, destructive: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReorderBar extends StatelessWidget {
  const _ReorderBar({required this.topInset, required this.onDone});

  final double topInset;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, topInset + 8, 12, 10),
      color: Colors.black.withValues(alpha: 0.9),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(child: Text('Drag to reorder', style: CollectionStyle.title(18))),
            TextButton(
              onPressed: onDone,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text('Done',
                  style: CollectionStyle.meta(size: 16, alpha: 1, w: FontWeight.w800).copyWith(color: CollectionStyle.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.allDownloaded,
    required this.empty,
    required this.active,
    required this.playing,
    required this.tint,
    required this.onDownload,
    required this.onShuffle,
    required this.onPlay,
  });

  final bool allDownloaded;
  final bool empty;
  final bool active;
  final bool playing;
  final Color tint;
  final VoidCallback onDownload;
  final VoidCallback onShuffle;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    Widget icon(IconData i, String label, VoidCallback onTap, {Color? color}) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: PressableScale(
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(i, size: 26, color: color ?? Colors.white.withValues(alpha: empty ? 0.3 : 0.85)),
            ),
          ),
        );

    final label = !active ? 'Play' : (playing ? 'Pause' : 'Resume');
    return Row(
      children: [
        icon(allDownloaded ? Icons.download_done_rounded : Icons.download_rounded,
            allDownloaded ? 'Downloaded' : 'Download', onDownload,
            color: allDownloaded ? const Color(0xFF2EB15E) : null),
        const Spacer(),
        icon(Icons.shuffle_rounded, 'Shuffle', onShuffle),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: PressableScale(
            onTap: empty ? null : onPlay,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: empty ? Colors.white.withValues(alpha: 0.12) : Colors.white,
                boxShadow: empty
                    ? null
                    : [BoxShadow(color: tint.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    key: ValueKey(playing), size: 36, color: empty ? Colors.white30 : Colors.black),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddSongsCard extends StatelessWidget {
  const _AddSongsCard({required this.tint, required this.onTap});

  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add songs',
      excludeSemantics: true,
      child: PressableScale(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(colors: [
              Color.lerp(tint, Colors.white, 0.1)!.withValues(alpha: 0.55),
              tint.withValues(alpha: 0.3),
            ]),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 0.8),
          ),
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(child: Text('Add songs', style: CollectionStyle.title(16, w: FontWeight.w700))),
              Text('Search · Liked · Suggested', style: CollectionStyle.meta(size: 12.5, alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
