// lib/screens/user_playlist_screen.dart
//
// YOUR PLAYLISTS (glass). Plan: docs/PLAN-your-playlists.md.
//
//   * Large title + count that collapses into the nav row; "+" makes a
//     playlist, the search circle jumps to the search field.
//   * Search finds a playlist by name or by a song inside it ("Contains
//     'Borderline'").
//   * Chips: All · Downloaded · Created by you · Imported (only when you have
//     imported any). Liked Songs is the first row of "All".
//   * Sort (recently updated, recently played, name, most songs, custom order
//     you drag into place) and a list / grid toggle - both remembered.
//   * Rows: cover, name, pin, "32 songs · Updated yesterday", a Downloaded
//     line, an equalizer when it is the playlist playing, ⋮ for the menu.
//     Swipe left deletes with Undo; long-press opens the menu.
//
// Built from the collection kit. Material You has its own screen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../presentation/playlists/playlist_query.dart';
import '../providers/music_provider.dart';
import '../services/innertube/library_playlists_parser.dart';
import '../theme/amoled_theme.dart';
import '../widgets/collection/collection_kit.dart';
import '../widgets/glass_circle_button.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/home_sections.dart' show PressableScale;
import '../widgets/playlist/open_playlist.dart';
import '../widgets/playlist/playlist_cover.dart';
import '../widgets/playlist/playlist_edit_sheet.dart';
import '../widgets/themed_liked_songs_screen.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import '../widgets/themed_playlist_import_screen.dart';

const String kPlaylistSortPref = 'playlists_sort_v1';
const String kPlaylistViewPref = 'playlists_view_v1';

class UserPlaylistScreen extends StatefulWidget {
  const UserPlaylistScreen({super.key, this.now});

  /// Fixed clock for tests.
  final DateTime? now;

  @override
  State<UserPlaylistScreen> createState() => _UserPlaylistScreenState();
}

class _UserPlaylistScreenState extends State<UserPlaylistScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  PlaylistQuery _query = const PlaylistQuery();
  bool _grid = false;

  /// The "YouTube Music" chip: show only the playlists from the signed-in
  /// YouTube account.
  bool _youtubeOnly = false;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MusicProvider>().loadYouTubeLibraryPlaylists();
    });
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      final sort = PlaylistSort.fromName(p.getString(kPlaylistSortPref));
      final grid = p.getString(kPlaylistViewPref) == 'grid';
      if (sort != _query.sort || grid != _grid) {
        setState(() {
          _query = _query.copyWith(sort: sort);
          _grid = grid;
        });
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Query ────────────────────────────────────────────────────────────────

  void _setSort(PlaylistSort sort) {
    HapticFeedback.selectionClick();
    setState(() => _query = _query.copyWith(sort: sort));
    SharedPreferences.getInstance()
        .then((p) => p.setString(kPlaylistSortPref, sort.name))
        .catchError((_) => false);
  }

  void _setGrid(bool grid) {
    if (grid == _grid) return;
    HapticFeedback.selectionClick();
    setState(() => _grid = grid);
    SharedPreferences.getInstance()
        .then((p) => p.setString(kPlaylistViewPref, grid ? 'grid' : 'list'))
        .catchError((_) => false);
  }

  void _clearNarrowing() {
    _search.clear();
    setState(() => _query = _query.copyWith(search: '', filter: PlaylistFilter.all));
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _create() async {
    HapticFeedback.lightImpact();
    final made = await showPlaylistEditSheet(context);
    if (made != null && mounted) {
      showCollectionToast(context, 'Created "${made.name}"', icon: Icons.playlist_add_check_rounded);
    }
  }

  void _play(Playlist p, {bool shuffle = false}) {
    if (p.tracks.isEmpty) {
      showCollectionToast(context, '"${p.name}" is empty', icon: Icons.queue_music_rounded);
      return;
    }
    final provider = context.read<MusicProvider>();
    final list = List<Track>.of(p.tracks);
    if (shuffle) {
      list.shuffle();
      if (list.length > 1 && list.first.id == provider.currentTrack?.id) {
        list.add(list.removeAt(0));
      }
    }
    provider.markPlaylistPlayed(p.id);
    provider.playTrack(list.first, playlistTracks: list, playlistId: p.id);
  }

  void _download(Playlist p) {
    final provider = context.read<MusicProvider>();
    final todo = p.tracks.where((t) => t.source != 'local' && !provider.isTrackDownloadedSync(t.id)).toList();
    if (p.tracks.isEmpty) {
      showCollectionToast(context, '"${p.name}" is empty', icon: Icons.queue_music_rounded);
    } else if (todo.isEmpty) {
      showCollectionToast(context, 'Already downloaded', icon: Icons.download_done_rounded);
    } else {
      provider.downloadTracks(todo);
      showCollectionToast(context, 'Downloading ${todo.length} ${todo.length == 1 ? 'song' : 'songs'}',
          icon: Icons.download_rounded);
    }
  }

  void _delete(Playlist p) {
    final provider = context.read<MusicProvider>();
    final removed = provider.deletePlaylistWithUndo(p.id);
    if (removed == null) return;
    HapticFeedback.mediumImpact();
    showCollectionToast(
      context,
      'Deleted "${p.name}"',
      icon: Icons.delete_outline_rounded,
      action: SnackBarAction(
        label: 'Undo',
        textColor: CollectionStyle.accent,
        onPressed: () {
          if (mounted) context.read<MusicProvider>().restorePlaylist(removed);
        },
      ),
    );
  }

  void _openMenu(Playlist p) {
    HapticFeedback.mediumImpact();
    showCollectionSheet<void>(
      context,
      (sheet) => [
        Row(
          children: [
            PlaylistCover(playlist: p, size: 56, radius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(18)),
                  Text(playlistMetaLine(p, _now),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.meta(size: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SheetRow(icon: Icons.play_arrow_rounded, label: 'Play', onTap: () => _play(p)),
        SheetRow(icon: Icons.shuffle_rounded, label: 'Shuffle', onTap: () => _play(p, shuffle: true)),
        SheetRow(
          icon: p.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          label: p.pinned ? 'Unpin' : 'Pin to top',
          onTap: () => context.read<MusicProvider>().setPlaylistPinned(p.id, !p.pinned),
        ),
        SheetRow(icon: Icons.download_rounded, label: 'Download', onTap: () => _download(p)),
        SheetRow(
          icon: Icons.edit_rounded,
          label: 'Edit details',
          onTap: () => showPlaylistEditSheet(context, existing: context.read<MusicProvider>().playlistById(p.id) ?? p),
        ),
        SheetRow(icon: Icons.delete_outline_rounded, label: 'Delete playlist', destructive: true, onTap: () => _delete(p)),
      ],
    );
  }

  void _openSort() {
    HapticFeedback.lightImpact();
    showCollectionSheet<void>(
      context,
      (sheet) => [
        Text('Sort by', style: CollectionStyle.title(18)),
        const SizedBox(height: 6),
        for (final s in PlaylistSort.values)
          SheetRow(
            icon: switch (s) {
              PlaylistSort.recentlyUpdated => Icons.update_rounded,
              PlaylistSort.recentlyPlayed => Icons.history_rounded,
              PlaylistSort.name => Icons.sort_by_alpha_rounded,
              PlaylistSort.mostSongs => Icons.format_list_numbered_rounded,
              PlaylistSort.custom => Icons.drag_indicator_rounded,
            },
            label: s.label,
            checked: s == _query.sort,
            onTap: () => _setSort(s),
          ),
      ],
    );
  }

  void _openYouTube(YouTubeLibraryPlaylist y) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ThemedPlaylistDetailScreen(
        playlistId: y.browseId,
        playlistName: y.title,
        playlistImage: y.thumbnailUrl.isEmpty ? null : y.thumbnailUrl,
      ),
    ));
  }

  Future<void> _playYouTube(YouTubeLibraryPlaylist y, {bool shuffle = false}) async {
    final provider = context.read<MusicProvider>();
    try {
      final page = await provider.fetchPlaylistPageData(y.browseId);
      final list = List<Track>.of(page.tracks);
      if (list.isEmpty) throw StateError('empty');
      if (shuffle) list.shuffle();
      await provider.playTrack(list.first, playlistTracks: list, playlistId: y.browseId);
    } catch (_) {
      if (mounted) showCollectionToast(context, 'Couldn\'t load "${y.title}"', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _copyYouTube(YouTubeLibraryPlaylist y) async {
    showCollectionToast(context, 'Copying "${y.title}"…', icon: Icons.downloading_rounded);
    final made = await context.read<MusicProvider>().saveYouTubePlaylistCopy(y);
    if (!mounted) return;
    if (made == null) {
      showCollectionToast(context, 'Couldn\'t copy "${y.title}"', icon: Icons.error_outline_rounded);
    } else {
      showCollectionToast(
        context,
        'Saved a copy · ${made.tracks.length} songs',
        icon: Icons.playlist_add_check_rounded,
        action: SnackBarAction(
          label: 'Open',
          textColor: CollectionStyle.accent,
          onPressed: () => openUserPlaylist(context, made),
        ),
      );
    }
  }

  void _openYouTubeMenu(YouTubeLibraryPlaylist y) {
    HapticFeedback.mediumImpact();
    showCollectionSheet<void>(
      context,
      (sheet) => [
        Row(
          children: [
            _YouTubeCover(playlist: y, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(y.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(18)),
                  Text('From YouTube Music', style: CollectionStyle.meta(size: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SheetRow(icon: Icons.play_arrow_rounded, label: 'Play', onTap: () => _playYouTube(y)),
        SheetRow(icon: Icons.shuffle_rounded, label: 'Shuffle', onTap: () => _playYouTube(y, shuffle: true)),
        SheetRow(icon: Icons.library_add_rounded, label: 'Save a copy to your playlists', onTap: () => _copyYouTube(y)),
      ],
    );
  }

  void _openLiked() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ThemedLikedSongsScreen()));

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final all = context.select<MusicProvider, List<Playlist>>((p) => p.userPlaylists);
    final currentPlaylist = context.select<MusicProvider, String?>((p) => p.currentPlaylistId);
    final playing = context.select<MusicProvider, bool>((p) => p.isPlaying);
    final likedCount = context.select<MusicProvider, int>((p) => p.likedSongs.length);
    final provider = context.read<MusicProvider>();
    bool downloaded(String id) => provider.isTrackDownloadedSync(id);
    final playedAt = <String, int>{
      for (final p in all)
        if (provider.playlistLastPlayedMs(p.id) != null) p.id: provider.playlistLastPlayedMs(p.id)!,
    };

    final matches = applyPlaylistQuery(all, _query, playedAt: playedAt, isDownloaded: downloaded);
    final hasImported = all.any((p) => !p.isUserCreated);
    final top = MediaQuery.paddingOf(context).top;
    final amoled = AmoledTheme.isOn(context);
    final clearance = collectionBottomClearance(context);
    final showLiked = !_youtubeOnly && _query.filter == PlaylistFilter.all &&
        (_query.search.trim().isEmpty || normalizeName('Liked Songs').contains(normalizeName(_query.search)));
    final reorderable = _query.sort == PlaylistSort.custom && !_query.isNarrowed && !_grid && matches.length > 1;
    final count = all.length;
    final ytStatus = context.select<MusicProvider, YouTubeLibraryStatus>((p) => p.youtubeLibraryStatus);
    final ytAll = context.select<MusicProvider, List<YouTubeLibraryPlaylist>>((p) => p.youtubeLibraryPlaylists);
    final ytWords = normalizeName(_query.search).split(' ').where((w) => w.isNotEmpty).toList();
    final ytShown = ytWords.isEmpty
        ? ytAll
        : ytAll.where((y) => ytWords.every(normalizeName(y.title).contains)).toList();
    final hasYouTube = ytStatus != YouTubeLibraryStatus.signedOut && ytStatus != YouTubeLibraryStatus.idle;
    // The section belongs to "All" and to its own chip; the other chips are
    // about your playlists.
    final showYouTube = hasYouTube && (_youtubeOnly || _query.filter == PlaylistFilter.all);
    // Nothing of yours and nothing from YouTube (or it is still arriving): the
    // invitation, not an empty list.
    final emptyLibrary = count == 0 && ytAll.isEmpty && ytStatus != YouTubeLibraryStatus.loading;

    final chips = <CollectionChipData>[
      for (final f in PlaylistFilter.values)
        if (f != PlaylistFilter.imported || hasImported) CollectionChipData(id: f.name, label: f.label),
      if (hasYouTube) const CollectionChipData(id: 'youtube', label: 'YouTube Music', icon: Icons.smart_display_rounded),
    ];

    Widget rowFor(PlaylistMatch m, int i, {Widget? handle}) => _PlaylistRow(
          key: ValueKey('pl_${m.playlist.id}'),
          match: m,
          now: _now,
          last: i == matches.length - 1 && !showLiked,
          current: currentPlaylist == m.playlist.id,
          playing: playing,
          allDownloaded: m.playlist.tracks.isNotEmpty && m.playlist.tracks.every((t) => downloaded(t.id)),
          swipe: handle == null,
          onTap: () => openUserPlaylist(context, m.playlist),
          onMenu: () => _openMenu(m.playlist),
          onDelete: () => _delete(m.playlist),
          handle: handle,
        );

    return PlayerAwarePopScope(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (!amoled)
              const Positioned(
                top: -140,
                left: -100,
                right: -100,
                height: 420,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(-0.4, -0.3),
                        radius: 0.9,
                        colors: [Color(0x332B3F7A), Color(0x00000000)],
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
                    padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 4, CollectionStyle.gutter, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(header: true, child: Text('Your Playlists', style: CollectionStyle.title(36))),
                        const SizedBox(height: 4),
                        Text(
                          [
                            count == 1 ? '1 playlist' : '$count playlists',
                            if (ytAll.isNotEmpty) '${ytAll.length} from YouTube Music',
                          ].join(' · '),
                          style: CollectionStyle.meta(size: 16, alpha: 0.55),
                        ),
                      ],
                    ),
                  ),
                ),
                if (emptyLibrary)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: CollectionEmptyState(
                      title: 'Make your first playlist',
                      message: 'Playlists you create or import live here.',
                      actionLabel: 'New playlist',
                      actionIcon: Icons.add_rounded,
                      onAction: _create,
                      secondaryLabel: 'Import from Spotify',
                      onSecondary: () => Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const ThemedPlaylistImportScreen())),
                    ),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: CollectionSearchField(
                      controller: _search,
                      focus: _searchFocus,
                      hint: 'Search your playlists',
                      onChanged: (v) => setState(() => _query = _query.copyWith(search: v)),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: CollectionChips(
                      chips: chips,
                      selectedId: _youtubeOnly ? 'youtube' : _query.filter.name,
                      onTap: (c) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (c.id == 'youtube') {
                            _youtubeOnly = !_youtubeOnly;
                            _query = _query.copyWith(filter: PlaylistFilter.all);
                          } else {
                            _youtubeOnly = false;
                            _query = _query.copyWith(
                                filter: PlaylistFilter.values.firstWhere((f) => f.name == c.id));
                          }
                        });
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: CollectionSortRow(
                      label: _query.sort.label,
                      onSort: _openSort,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ViewToggle(icon: Icons.view_list_rounded, label: 'List view', on: !_grid, onTap: () => _setGrid(false)),
                          _ViewToggle(icon: Icons.grid_view_rounded, label: 'Grid view', on: _grid, onTap: () => _setGrid(true)),
                        ],
                      ),
                    ),
                  ),
                  FadeInSliver(
                    key: ValueKey('${_query.signature}|$_grid|$_youtubeOnly'),
                    sliver: _grid && !_youtubeOnly
                        ? SliverPadding(
                            padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 8, CollectionStyle.gutter, 0),
                            sliver: SliverGrid(
                              // A fixed cell height built from the real cover width and
                              // the listener's text size, so large text grows the cell
                              // instead of overflowing it.
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 18,
                                mainAxisExtent: (MediaQuery.sizeOf(context).width - 2 * CollectionStyle.gutter - 14) / 2 +
                                    9 +
                                    MediaQuery.textScalerOf(context).scale(14.5) * 1.45 +
                                    MediaQuery.textScalerOf(context).scale(12.5) * 1.45 +
                                    4,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  if (showLiked && i == 0) {
                                    return _LikedTile(count: likedCount, onTap: _openLiked);
                                  }
                                  final m = matches[i - (showLiked ? 1 : 0)];
                                  return _PlaylistTile(
                                    match: m,
                                    current: currentPlaylist == m.playlist.id,
                                    playing: playing,
                                    onTap: () => openUserPlaylist(context, m.playlist),
                                    onMenu: () => _openMenu(m.playlist),
                                  );
                                },
                                childCount: matches.length + (showLiked ? 1 : 0),
                              ),
                            ),
                          )
                        : _youtubeOnly
                            ? const SliverToBoxAdapter(child: SizedBox.shrink())
                            : (matches.isEmpty && !showLiked)
                            ? SliverToBoxAdapter(
                                child: CollectionNoMatch(
                                    query: _query.search, onClear: _clearNarrowing, noun: 'playlists'))
                            : reorderable
                                ? SliverMainAxisGroup(slivers: [
                                    if (showLiked) SliverToBoxAdapter(child: _LikedRow(count: likedCount, onTap: _openLiked)),
                                    SliverReorderableList(
                                      itemCount: matches.length,
                                      onReorderStart: (_) => HapticFeedback.mediumImpact(),
                                      onReorderItem: (from, to) {
                                        final ids = [for (final m in matches) m.playlist.id];
                                        ids.insert(to, ids.removeAt(from));
                                        context.read<MusicProvider>().setPlaylistOrder(ids);
                                      },
                                      itemBuilder: (context, i) => rowFor(
                                        matches[i],
                                        i,
                                        handle: ReorderableDragStartListener(
                                          index: i,
                                          child: Semantics(
                                            label: 'Drag to reorder ${matches[i].playlist.name}',
                                            child: const SizedBox(
                                              width: 48,
                                              height: 48,
                                              child: Icon(Icons.drag_handle_rounded, color: Colors.white54),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ])
                                : SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, i) {
                                        if (showLiked && i == 0) return _LikedRow(count: likedCount, onTap: _openLiked);
                                        final k = i - (showLiked ? 1 : 0);
                                        return rowFor(matches[k], k);
                                      },
                                      childCount: matches.length + (showLiked ? 1 : 0),
                                    ),
                                  ),
                  ),
                ],
                if (!emptyLibrary && showYouTube)
                  SliverToBoxAdapter(
                    child: _YouTubeSection(
                      status: ytStatus,
                      playlists: ytShown,
                      searching: ytWords.isNotEmpty,
                      onRetry: () => context.read<MusicProvider>().loadYouTubeLibraryPlaylists(force: true),
                      onOpen: _openYouTube,
                      onMenu: _openYouTubeMenu,
                    ),
                  ),
                SliverToBoxAdapter(child: SizedBox(height: clearance)),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: CollectionNavBar(
                scroll: _scroll,
                topInset: top,
                title: 'Your Playlists',
                onBack: () => Navigator.maybePop(context),
                actions: [
                  GlassCircleButton(
                    icon: Icons.add_rounded,
                    size: 44,
                    iconSize: 24,
                    semanticLabel: 'New playlist',
                    onTap: _create,
                  ),
                  if (count > 0)
                    GlassCircleButton(
                      icon: Icons.search_rounded,
                      size: 44,
                      iconSize: 22,
                      semanticLabel: 'Search playlists',
                      onTap: () {
                        _scroll.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
                        _searchFocus.requestFocus();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.icon, required this.label, required this.on, required this.onTap});

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 48,
          height: 44,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: on ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? Colors.white.withValues(alpha: 0.18) : Colors.transparent, width: 0.8),
          ),
          child: Icon(icon, color: Colors.white.withValues(alpha: on ? 1 : 0.55), size: 22),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    super.key,
    required this.match,
    required this.now,
    required this.last,
    required this.current,
    required this.playing,
    required this.allDownloaded,
    required this.swipe,
    required this.onTap,
    required this.onMenu,
    required this.onDelete,
    this.handle,
  });

  final PlaylistMatch match;
  final DateTime now;
  final bool last;
  final bool current;
  final bool playing;
  final bool allDownloaded;
  final bool swipe;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback onDelete;
  final Widget? handle;

  @override
  Widget build(BuildContext context) {
    final p = match.playlist;
    final meta = playlistMetaLine(p, now);
    final hit = match.containsSong;
    final body = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              selected: current,
              label: '${p.name}, $meta${hit == null ? '' : ', contains $hit'}'
                  '${current ? (playing ? ', now playing' : ', paused') : ''}',
              excludeSemantics: true,
              child: PressableScale(
                onTap: onTap,
                onLongPress: onMenu,
                child: Container(
                  color: Colors.transparent,
                  padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 10, 0, 10),
                  child: Row(
                    children: [
                      PlaylistCover(playlist: p, size: 72, radius: 12),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: CollectionStyle.title(17, w: FontWeight.w700)
                                          .copyWith(color: current ? CollectionStyle.accent : Colors.white)),
                                ),
                                if (p.pinned) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.push_pin_rounded, size: 15, color: CollectionStyle.accent),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.meta()),
                            if (hit != null) ...[
                              const SizedBox(height: 3),
                              Text('Contains "$hit"',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: CollectionStyle.meta(size: 12.5, alpha: 0.75, w: FontWeight.w600)
                                      .copyWith(color: CollectionStyle.accent)),
                            ] else if (allDownloaded) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.download_done_rounded, size: 16, color: Color(0xFF2EB15E)),
                                  const SizedBox(width: 6),
                                  Text('Downloaded',
                                      style: CollectionStyle.meta(size: 13, alpha: 0.75)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (current) ...[
                        const SizedBox(width: 8),
                        CollectionEqualizer(playing: playing),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          handle ??
              IconButton(
                tooltip: 'More options for ${p.name}',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: Icon(Icons.more_vert_rounded, color: Colors.white.withValues(alpha: 0.7)),
                onPressed: onMenu,
              ),
          const SizedBox(width: 4),
        ],
      ),
    );

    if (!swipe) return body;
    return Dismissible(
      key: ValueKey('dismiss_${p.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(color: CollectionStyle.accentDeep),
      secondaryBackground: Container(
        color: CollectionStyle.accentDeep,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Delete', style: CollectionStyle.meta(size: 15, alpha: 1, w: FontWeight.w700)),
            const SizedBox(width: 8),
            const Icon(Icons.delete_outline_rounded, color: Colors.white),
          ],
        ),
      ),
      child: body,
    );
  }
}

/// Liked Songs as the first row: it is a playlist to the listener.
class _LikedRow extends StatelessWidget {
  const _LikedRow({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = count == 1 ? '1 song' : '$count songs';
    return Semantics(
      button: true,
      label: 'Liked Songs, $meta',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 0.6)),
          ),
          padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 10, CollectionStyle.gutter, 10),
          child: Row(
            children: [
              const _HeartTile(size: 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Liked Songs', style: CollectionStyle.title(17, w: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text('$meta · Your saved tracks', maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.meta()),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeartTile extends StatelessWidget {
  const _HeartTile({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.17),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6A1530), Color(0xFF1A050C)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.8),
        ),
        child: Icon(Icons.favorite_rounded, color: CollectionStyle.accent, size: size * 0.42),
      );
}

class _LikedTile extends StatelessWidget {
  const _LikedTile({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Liked Songs, ${count == 1 ? '1 song' : '$count songs'}',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeartTile(size: c.maxWidth),
              const SizedBox(height: 9),
              Text('Liked Songs', maxLines: 1, style: CollectionStyle.title(14.5, w: FontWeight.w700)),
              Text(count == 1 ? '1 song' : '$count songs', maxLines: 1, style: CollectionStyle.meta(size: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.match,
    required this.current,
    required this.playing,
    required this.onTap,
    required this.onMenu,
  });

  final PlaylistMatch match;
  final bool current;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final p = match.playlist;
    final n = p.tracks.length;
    final meta = n == 0 ? 'Empty' : (n == 1 ? '1 song' : '$n songs');
    return Semantics(
      button: true,
      selected: current,
      label: '${p.name}, $meta${current ? (playing ? ', now playing' : ', paused') : ''}',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        onLongPress: onMenu,
        child: LayoutBuilder(
          builder: (context, c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  PlaylistCover(playlist: p, size: c.maxWidth, radius: 16, shadow: true),
                  if (p.pinned)
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: Icon(Icons.push_pin_rounded, size: 18, color: Colors.white, shadows: [Shadow(blurRadius: 6)]),
                    ),
                  if (current)
                    Positioned(right: 10, bottom: 10, child: CollectionEqualizer(playing: playing)),
                ],
              ),
              const SizedBox(height: 9),
              Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CollectionStyle.title(14.5, w: FontWeight.w700)
                      .copyWith(color: current ? CollectionStyle.accent : Colors.white)),
              Text(match.containsSong == null ? meta : 'Contains "${match.containsSong}"',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.meta(size: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── From YouTube Music ─────────────────────────────────────────────────────

class _YouTubeCover extends StatelessWidget {
  const _YouTubeCover({required this.playlist, required this.size});

  final YouTubeLibraryPlaylist playlist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ph = Container(
      color: const Color(0xFF2A1416),
      alignment: Alignment.center,
      child: Icon(playlist.isLikedMusic ? Icons.thumb_up_rounded : Icons.queue_music_rounded,
          color: Colors.white38, size: size * 0.36),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: playlist.thumbnailUrl.isEmpty
                ? SizedBox(width: size, height: size, child: ph)
                : CachedNetworkImage(
                    imageUrl: playlist.thumbnailUrl,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => ph,
                    errorWidget: (_, __, ___) => ph,
                  ),
          ),
          // Where it lives: a small YouTube mark on the corner.
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF0033),
                borderRadius: BorderRadius.circular(5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4)],
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _YouTubeSection extends StatelessWidget {
  const _YouTubeSection({
    required this.status,
    required this.playlists,
    required this.searching,
    required this.onRetry,
    required this.onOpen,
    required this.onMenu,
  });

  final YouTubeLibraryStatus status;
  final List<YouTubeLibraryPlaylist> playlists;
  final bool searching;
  final VoidCallback onRetry;
  final ValueChanged<YouTubeLibraryPlaylist> onOpen;
  final ValueChanged<YouTubeLibraryPlaylist> onMenu;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    switch (status) {
      case YouTubeLibraryStatus.loading:
        if (playlists.isEmpty) {
          for (var i = 0; i < 3; i++) {
            children.add(const _SkeletonRow());
          }
        }
      case YouTubeLibraryStatus.error:
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: CollectionStyle.gutter, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Couldn\'t load your YouTube Music playlists.',
                    style: CollectionStyle.meta(size: 14.5, alpha: 0.65)),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text('Retry',
                    style: CollectionStyle.meta(size: 14.5, alpha: 1, w: FontWeight.w700)
                        .copyWith(color: CollectionStyle.accent)),
              ),
            ],
          ),
        ));
      case YouTubeLibraryStatus.ready:
        if (playlists.isEmpty) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: CollectionStyle.gutter, vertical: 8),
            child: Text(searching ? 'No YouTube Music playlists match.' : 'No playlists in your YouTube Music library.',
                style: CollectionStyle.meta(size: 14.5, alpha: 0.55)),
          ));
        }
      case YouTubeLibraryStatus.idle:
      case YouTubeLibraryStatus.signedOut:
        break;
    }
    for (var i = 0; i < playlists.length; i++) {
      final y = playlists[i];
      final meta = y.subtitle.isEmpty ? 'YouTube Music' : y.subtitle;
      children.add(Semantics(
        button: true,
        label: '${y.title}, $meta, from YouTube Music',
        excludeSemantics: true,
        child: PressableScale(
          onTap: () => onOpen(y),
          onLongPress: () => onMenu(y),
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 10, 4, 10),
            child: Row(
              children: [
                _YouTubeCover(playlist: y, size: 72),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(y.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(17, w: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.meta()),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'More options for ${y.title}',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: Icon(Icons.more_vert_rounded, color: Colors.white.withValues(alpha: 0.7)),
                  onPressed: () => onMenu(y),
                ),
              ],
            ),
          ),
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 28, CollectionStyle.gutter, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFFF0033), borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(header: true, child: Text('From YouTube Music', style: CollectionStyle.title(20))),
              ),
              if (status == YouTubeLibraryStatus.loading && playlists.isNotEmpty)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 0, CollectionStyle.gutter, 4),
          child: Text('Your YouTube account\'s playlists. Open one, or save a copy to edit it here.',
              style: CollectionStyle.meta(size: 13, alpha: 0.5)),
        ),
        ...children,
      ],
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final c = Colors.white.withValues(alpha: 0.06);
    return Padding(
      padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 10, CollectionStyle.gutter, 10),
      child: Row(
        children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 14, width: 160, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                Container(height: 11, width: 100, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}