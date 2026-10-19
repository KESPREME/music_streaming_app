// lib/screens/local_music_screen.dart
//
// LOCAL FILES (glass). Plan: docs/PLAN-local-import-youtube.md §3.
//
// The music stored on this phone, in four views - Songs, Albums, Artists,
// Folders. A group (an album, an artist, a folder) opens in place; back closes
// it before it closes the screen. Built from the collection kit, so it plays
// and selects like the rest of the Library.
//
//   * Play / Shuffle play OFFLINE, in the order shown.
//   * Search covers title, artist, album and folder; sort uses every criterion
//     the scanner supports and is remembered (MusicProvider settings).
//   * Rows show the file's embedded cover.
//   * No swipe-to-remove: these are the listener's files, not a list we own.
//   * States: scanning, access refused (Allow / Open settings), nothing found
//     (Rescan / Add a folder); pull down to rescan.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../presentation/liked/liked_songs_query.dart' show formatCollectionDuration;
import '../presentation/local/local_library.dart';
import '../providers/music_provider.dart';
import '../services/local_music_service.dart' show SortCriteria;
import '../theme/amoled_theme.dart';
import '../widgets/collection/collection_kit.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/home_sections.dart' show PressableScale;
import '../widgets/local_artwork.dart';
import '../widgets/playlist/add_to_playlist_sheet.dart';
import '../widgets/themed_options_sheet.dart';

const String kLocalContextId = 'local_files';

class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({super.key});

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Set<String> _selected = {};

  LocalView _view = LocalView.songs;
  LocalGroup? _open;
  String _query = '';

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<MusicProvider>();
      if (p.localTracks.isEmpty && !p.isLoadingLocal) p.loadLocalMusicFiles();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _play(List<Track> list, {int index = 0}) {
    if (list.isEmpty) return;
    context.read<MusicProvider>().playOfflineTrack(list[index], contextList: List<Track>.of(list));
  }

  void _shuffle(List<Track> list) {
    if (list.isEmpty) return;
    HapticFeedback.lightImpact();
    final s = List<Track>.of(list)..shuffle();
    if (s.length > 1 && s.first.id == context.read<MusicProvider>().currentTrack?.id) s.add(s.removeAt(0));
    _play(s);
  }

  void _queue(List<Track> tracks) {
    if (tracks.isEmpty) return;
    final p = context.read<MusicProvider>();
    for (final t in tracks) {
      p.addToQueue(t);
    }
    HapticFeedback.lightImpact();
    showCollectionToast(
      context,
      tracks.length == 1 ? 'Added "${tracks.first.trackName}" to queue' : 'Added ${tracks.length} songs to queue',
      icon: Icons.queue_music_rounded,
    );
  }

  Future<void> _rescan() async {
    HapticFeedback.lightImpact();
    await context.read<MusicProvider>().loadLocalMusicFiles(forceRescan: true);
  }

  Future<void> _addFolder() async {
    await context.read<MusicProvider>().addLocalMusicFolder();
  }

  void _setView(LocalView v) {
    HapticFeedback.selectionClick();
    setState(() {
      _view = v;
      _open = null;
    });
  }

  void _openGroup(LocalGroup g) {
    HapticFeedback.lightImpact();
    setState(() => _open = g);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _openSort(SortCriteria current) {
    HapticFeedback.lightImpact();
    showCollectionSheet<void>(
      context,
      (sheet) => [
        Text('Sort songs by', style: CollectionStyle.title(18)),
        const SizedBox(height: 6),
        for (final c in SortCriteria.values)
          SheetRow(
            icon: switch (c) {
              SortCriteria.nameAsc || SortCriteria.nameDesc => Icons.sort_by_alpha_rounded,
              SortCriteria.artistAsc || SortCriteria.artistDesc => Icons.person_rounded,
              SortCriteria.albumAsc || SortCriteria.albumDesc => Icons.album_rounded,
              SortCriteria.durationAsc || SortCriteria.durationDesc => Icons.timer_outlined,
              SortCriteria.folderAsc || SortCriteria.folderDesc => Icons.folder_rounded,
              SortCriteria.dateAddedAsc || SortCriteria.dateAddedDesc => Icons.schedule_rounded,
            },
            label: sortLabel(c),
            checked: c == current,
            onTap: () => context.read<MusicProvider>().sortLocalTracks(c),
          ),
      ],
      scrollControlled: true,
    );
  }

  void _openMore(List<Track> visible) {
    HapticFeedback.lightImpact();
    showCollectionSheet<void>(
      context,
      (sheet) => [
        Text('Local Files', style: CollectionStyle.title(18)),
        const SizedBox(height: 6),
        SheetRow(icon: Icons.refresh_rounded, label: 'Rescan this device', onTap: _rescan),
        SheetRow(icon: Icons.create_new_folder_outlined, label: 'Add a folder', onTap: _addFolder),
        if (visible.isNotEmpty) ...[
          SheetRow(icon: Icons.queue_music_rounded, label: 'Add shown songs to queue', onTap: () => _queue(visible)),
          SheetRow(
            icon: Icons.checklist_rounded,
            label: 'Select songs',
            onTap: () => setState(() => _selected.add(visible.first.id)),
          ),
        ],
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final all = context.select<MusicProvider, List<Track>>((p) => p.localTracks);
    final loading = context.select<MusicProvider, bool>((p) => p.isLoadingLocal);
    final denied = context.select<MusicProvider, bool>((p) => p.localPermissionDenied);
    final loadedOnce = context.select<MusicProvider, bool>((p) => p.localLoadedOnce);
    final sort = context.select<MusicProvider, SortCriteria>((p) => p.localTracksSortCriteria);
    final currentId = context.select<MusicProvider, String?>((p) => p.currentTrack?.id);
    final playing = context.select<MusicProvider, bool>((p) => p.isPlaying);

    final ids = {for (final t in all) t.id};
    _selected.removeWhere((id) => !ids.contains(id));

    final matching = searchLocal(all, _query);
    final groups = _view == LocalView.songs ? const <LocalGroup>[] : groupLocal(matching, _view);
    // An open group is re-read from the current data, so a rescan updates it.
    final open = _open == null ? null : groups.where((g) => g.key == _open!.key).firstOrNull;
    final songs = _view == LocalView.songs ? matching : (open?.tracks ?? const <Track>[]);
    final showingSongs = _view == LocalView.songs || open != null;
    final top = MediaQuery.paddingOf(context).top;
    final amoled = AmoledTheme.isOn(context);
    final clearance = collectionBottomClearance(context);
    final duration = formatCollectionDuration(all);
    final hasMusic = all.isNotEmpty;
    final title = open?.label ?? 'Local Files';
    List<Track> picked() => songs.where((t) => _selected.contains(t.id)).toList();

    Widget body;
    if (loading && !hasMusic) {
      body = SliverList(
        delegate: SliverChildBuilderDelegate((_, __) => const _SkeletonRow(), childCount: 8),
      );
    } else if (denied && !hasMusic) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: CollectionEmptyState(
          title: 'Allow access to your music',
          message: 'Mine Music needs permission to read the songs stored on this phone. Nothing leaves the device.',
          actionLabel: 'Allow access',
          actionIcon: Icons.lock_open_rounded,
          onAction: _rescan,
          secondaryLabel: 'Open settings',
          onSecondary: () => openAppSettings(),
        ),
      );
    } else if (!hasMusic && loadedOnce) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: CollectionEmptyState(
          title: 'No music on this device',
          message: 'Songs you copy to this phone show up here. Add a folder if yours live somewhere else.',
          actionLabel: 'Rescan',
          actionIcon: Icons.refresh_rounded,
          onAction: _rescan,
          secondaryLabel: 'Add a folder',
          onSecondary: _addFolder,
        ),
      );
    } else if (!hasMusic) {
      body = const SliverToBoxAdapter(child: SizedBox.shrink());
    } else if (showingSongs && songs.isEmpty) {
      body = SliverToBoxAdapter(
        child: CollectionNoMatch(
          query: _query,
          onClear: () => setState(() {
            _search.clear();
            _query = '';
          }),
        ),
      );
    } else if (showingSongs) {
      body = SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final t = songs[i];
            return CollectionTrackRow(
              key: ValueKey('local_${t.id}'),
              track: t,
              current: t.id == currentId,
              playing: t.id == currentId && playing,
              downloaded: false,
              selecting: _selecting,
              selected: _selected.contains(t.id),
              last: i == songs.length - 1,
              swipeRemoveEnabled: false,
              artOverride: LocalArtwork(track: t, size: CollectionStyle.art),
              subtitleOverride: [
                t.artistName,
                if (_view == LocalView.songs) t.albumName,
                if (t.durationText.isNotEmpty) t.durationText,
              ].where((s) => !isUnknownTag(s)).join(' · '),
              onTap: () => _selecting
                  ? setState(() => _selected.contains(t.id) ? _selected.remove(t.id) : _selected.add(t.id))
                  : _play(songs, index: i),
              onLongPress: () {
                HapticFeedback.mediumImpact();
                setState(() => _selected.add(t.id));
              },
              onOptions: () => ThemedOptionsSheet.show(context, track: t),
              onQueue: () => _queue([t]),
              onRemove: () {},
            );
          },
          childCount: songs.length,
          findChildIndexCallback: (key) {
            if (key is! ValueKey<String>) return null;
            final i = songs.indexWhere((t) => 'local_${t.id}' == key.value);
            return i < 0 ? null : i;
          },
        ),
      );
    } else if (groups.isEmpty) {
      body = SliverToBoxAdapter(
        child: CollectionNoMatch(
          query: _query,
          onClear: () => setState(() {
            _search.clear();
            _query = '';
          }),
        ),
      );
    } else {
      body = SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => _GroupRow(
            group: groups[i],
            view: _view,
            last: i == groups.length - 1,
            onTap: () => _openGroup(groups[i]),
          ),
          childCount: groups.length,
        ),
      );
    }

    return PlayerAwarePopScope(
      child: PopScope(
        canPop: !_selecting && open == null,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_selecting) {
            setState(_selected.clear);
          } else if (open != null) {
            setState(() => _open = null);
          }
        },
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
                          colors: [Color(0x339B50DA), Color(0x00000000)],
                        ),
                      ),
                    ),
                  ),
                ),
              RefreshIndicator(
                onRefresh: _rescan,
                color: CollectionStyle.accent,
                backgroundColor: AmoledTheme.surfaceOf(context, const Color(0xFF141414)),
                edgeOffset: top + 64,
                child: CustomScrollView(
                  controller: _scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    SliverToBoxAdapter(child: SizedBox(height: top + 64)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 4, CollectionStyle.gutter, 16),
                        child: AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
                          child: Column(
                            key: ValueKey(title),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (open != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(_view.label.toUpperCase(),
                                      style: CollectionStyle.meta(size: 12, alpha: 0.5, w: FontWeight.w700).copyWith(letterSpacing: 1.4)),
                                ),
                              Semantics(
                                header: true,
                                child: Text(title,
                                    maxLines: 2, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(open == null ? 36 : 30)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                open != null
                                    ? [
                                        if (open.subtitle.isNotEmpty && _view == LocalView.albums) open.subtitle,
                                        open.tracks.length == 1 ? '1 song' : '${open.tracks.length} songs',
                                        if (formatCollectionDuration(open.tracks) != null) formatCollectionDuration(open.tracks)!,
                                      ].join(' · ')
                                    : loading && !hasMusic
                                        ? 'Looking for music on this device…'
                                        : [
                                            all.length == 1 ? '1 song' : '${all.length} songs',
                                            if (duration != null) duration,
                                            'on this device',
                                          ].join(' · '),
                                maxLines: 2,
                                style: CollectionStyle.meta(size: 15, alpha: 0.55),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (hasMusic) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 0, CollectionStyle.gutter, 14),
                          child: Opacity(
                            opacity: showingSongs && songs.isEmpty ? 0.4 : 1,
                            child: Row(
                              children: [
                                Expanded(
                                  child: CollectionPill(
                                    label: 'Play',
                                    icon: Icons.play_arrow_rounded,
                                    filled: true,
                                    onTap: () => _play(showingSongs ? songs : matching),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CollectionPill(
                                    label: 'Shuffle',
                                    icon: Icons.shuffle_rounded,
                                    filled: false,
                                    onTap: () => _shuffle(showingSongs ? songs : matching),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (open == null) ...[
                        SliverToBoxAdapter(
                          child: CollectionSearchField(
                            controller: _search,
                            focus: _searchFocus,
                            hint: 'Find on this device',
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: CollectionChips(
                            chips: [for (final v in LocalView.values) CollectionChipData(id: v.name, label: v.label)],
                            selectedId: _view.name,
                            onTap: (c) => _setView(LocalView.values.firstWhere((v) => v.name == c.id)),
                          ),
                        ),
                        if (_view == LocalView.songs)
                          SliverToBoxAdapter(child: CollectionSortRow(label: sortLabel(sort), onSort: () => _openSort(sort))),
                        if (_query.trim().isNotEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 2, CollectionStyle.gutter, 6),
                              child: Text('${matching.length} of ${all.length} songs',
                                  style: CollectionStyle.meta(size: 13, alpha: 0.5)),
                            ),
                          ),
                      ],
                    ],
                    FadeInSliver(
                      key: ValueKey('${_view.name}|${open?.key}|$_query|${sort.name}|${all.length}|$loading|$denied'),
                      sliver: body,
                    ),
                    SliverToBoxAdapter(child: SizedBox(height: clearance + (_selecting ? 76 : 0))),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: CollectionNavBar(
                  scroll: _scroll,
                  topInset: top,
                  title: title,
                  backLabel: open == null ? 'Library' : _view.label,
                  onBack: () => Navigator.maybePop(context),
                  onMore: () => _openMore(showingSongs ? songs : matching),
                  selecting: _selecting,
                  selectedCount: _selected.length,
                  allSelected: songs.isNotEmpty && songs.every((t) => _selected.contains(t.id)),
                  onEndSelection: () => setState(_selected.clear),
                  onSelectAll: () => setState(() {
                    if (songs.every((t) => _selected.contains(t.id))) {
                      _selected.clear();
                    } else {
                      _selected.addAll(songs.map((t) => t.id));
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
                      setState(_selected.clear);
                      _play(list);
                    }),
                    SelectionAction(Icons.queue_music_rounded, 'Queue', () {
                      final list = picked();
                      setState(_selected.clear);
                      _queue(list);
                    }),
                    SelectionAction(Icons.playlist_add_rounded, 'Playlist', () {
                      final list = picked();
                      setState(_selected.clear);
                      showAddToPlaylistSheet(context, list);
                    }),
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

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.view, required this.last, required this.onTap});

  final LocalGroup group;
  final LocalView view;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = group.tracks.length;
    final count = n == 1 ? '1 song' : '$n songs';
    final meta = switch (view) {
      LocalView.albums => '${group.subtitle} · $count',
      LocalView.folders => count,
      _ => count,
    };
    final circle = view == LocalView.artists;
    final art = view == LocalView.folders
        ? Container(
            color: const Color(0xFF231833),
            child: const Icon(Icons.folder_rounded, color: Color(0xFFB98AE6), size: 28),
          )
        : LocalArtwork(track: group.tracks.first, size: 56);
    return Semantics(
      button: true,
      label: '${group.label}, $meta',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 0.6)),
          ),
          padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 9, CollectionStyle.gutter - 6, 9),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: circle ? ClipOval(child: art) : ClipRRect(borderRadius: BorderRadius.circular(10), child: art),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(16, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.meta()),
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

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final c = Colors.white.withValues(alpha: 0.06);
    return Padding(
      padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 8, CollectionStyle.gutter, 8),
      child: Row(
        children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 13, width: 170, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                Container(height: 11, width: 110, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
