// lib/screens/downloaded_songs_screen.dart
//
// DOWNLOADED (glass): what is on this device, playable with no connection.
//
//   * In-progress downloads sit above the list with their own progress bar and a
//     cancel; when one finishes it joins the list.
//   * Play / Shuffle play OFFLINE (playOfflineTrack), search and sort find a song.
//   * Removing a download deletes a file, which cannot be undone - so it is never
//     one swipe: it goes through selection (or "Remove all") and a confirmation
//     that says what happens and that it can be downloaded again.
//
// Built from the collection kit.

import 'package:flutter/material.dart';
import '../widgets/jelly_icon_button.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../presentation/liked/liked_songs_query.dart' show normalizeForSearch;
import '../providers/music_provider.dart';
import '../theme/amoled_theme.dart';
import '../widgets/collection/collection_kit.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/playlist/add_to_playlist_sheet.dart';
import '../widgets/themed_options_sheet.dart';

enum DownloadSort {
  recent('Recently downloaded'),
  title('Title'),
  artist('Artist');

  const DownloadSort(this.label);
  final String label;
}

/// [tracks] (newest download first, as stored) ordered by [sort].
List<Track> sortDownloads(List<Track> tracks, DownloadSort sort) {
  final rows = [for (var i = 0; i < tracks.length; i++) (i, tracks[i])];
  int cmp(String a, String b) => normalizeForSearch(a).compareTo(normalizeForSearch(b));
  switch (sort) {
    case DownloadSort.recent:
      break;
    case DownloadSort.title:
      rows.sort((a, b) {
        final c = cmp(a.$2.trackName, b.$2.trackName);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    case DownloadSort.artist:
      rows.sort((a, b) {
        final c = cmp(a.$2.artistName, b.$2.artistName);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
  }
  return [for (final r in rows) r.$2];
}

class DownloadedSongsScreen extends StatefulWidget {
  const DownloadedSongsScreen({super.key});

  @override
  State<DownloadedSongsScreen> createState() => _DownloadedSongsScreenState();
}

class _DownloadedSongsScreenState extends State<DownloadedSongsScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Set<String> _selected = {};

  List<Track> _tracks = const [];
  bool _loaded = false;
  String? _loadError;
  String _query = '';
  DownloadSort _sort = DownloadSort.recent;
  int _lastActiveCount = -1;

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final list = await context.read<MusicProvider>().getDownloadedTracks();
      if (!mounted) return;
      setState(() {
        _tracks = list;
        _loaded = true;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadError = 'Could not read your downloads.';
      });
    }
  }

  void _play(List<Track> list, {int index = 0}) {
    if (list.isEmpty) return;
    context.read<MusicProvider>().playOfflineTrack(list[index], contextList: List<Track>.of(list));
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

  Future<void> _confirmRemove(List<Track> tracks, {bool all = false}) async {
    if (tracks.isEmpty) return;
    final n = tracks.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(all ? 'Remove all downloads?' : (n == 1 ? 'Remove this download?' : 'Remove $n downloads?')),
        content: Text(n == 1
            ? '"${tracks.first.trackName}" will no longer play offline. You can download it again any time.'
            : 'These $n songs will no longer play offline. You can download them again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove', style: TextStyle(color: CollectionStyle.accent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final p = context.read<MusicProvider>();
    for (final t in tracks) {
      await p.deleteDownloadedTrack(t.id);
    }
    HapticFeedback.mediumImpact();
    await _reload();
    if (mounted) {
      setState(_selected.clear);
      showCollectionToast(context, n == 1 ? 'Download removed' : '$n downloads removed', icon: Icons.delete_outline_rounded);
    }
  }

  void _openSort() {
    HapticFeedback.lightImpact();
    showCollectionSheet<void>(
      context,
      (sheet) => [
        Text('Sort by', style: CollectionStyle.title(18)),
        const SizedBox(height: 6),
        for (final s in DownloadSort.values)
          SheetRow(
            icon: switch (s) {
              DownloadSort.recent => Icons.schedule_rounded,
              DownloadSort.title => Icons.sort_by_alpha_rounded,
              DownloadSort.artist => Icons.person_rounded,
            },
            label: s.label,
            checked: s == _sort,
            onTap: () => setState(() => _sort = s),
          ),
      ],
    );
  }

  void _openMore(List<Track> visible) {
    HapticFeedback.lightImpact();
    showCollectionSheet<void>(
      context,
      (sheet) => [
        Text('Downloaded', style: CollectionStyle.title(18)),
        const SizedBox(height: 6),
        SheetRow(icon: Icons.queue_music_rounded, label: 'Add shown songs to queue', onTap: () => _queue(visible)),
        SheetRow(
          icon: Icons.checklist_rounded,
          label: 'Select songs',
          onTap: () {
            if (visible.isNotEmpty) setState(() => _selected.add(visible.first.id));
          },
        ),
        SheetRow(icon: Icons.swap_vert_rounded, label: 'Sort by…', onTap: _openSort),
        SheetRow(
          icon: Icons.delete_sweep_rounded,
          label: 'Remove all downloads',
          destructive: true,
          onTap: () => _confirmRemove(_tracks, all: true),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = context.select<MusicProvider, List<Track>>((p) => p.currentlyDownloadingTracks);
    final progress = context.select<MusicProvider, Map<String, double>>((p) => p.downloadProgress);
    final currentId = context.select<MusicProvider, String?>((p) => p.currentTrack?.id);
    final playing = context.select<MusicProvider, bool>((p) => p.isPlaying);
    final provider = context.read<MusicProvider>();

    // A download finishing (or starting) changes what is on disk.
    if (_lastActiveCount != active.length) {
      final changed = _lastActiveCount != -1;
      _lastActiveCount = active.length;
      if (changed) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _reload() : null);
    }

    final ids = {for (final t in _tracks) t.id};
    _selected.removeWhere((id) => !ids.contains(id));

    final words = normalizeForSearch(_query).split(' ').where((w) => w.isNotEmpty).toList();
    final matching = words.isEmpty
        ? _tracks
        : _tracks.where((t) {
            final hay = normalizeForSearch('${t.trackName} ${t.artistName} ${t.albumName}');
            return words.every(hay.contains);
          }).toList();
    final visible = sortDownloads(matching, _sort);
    final top = MediaQuery.paddingOf(context).top;
    final amoled = AmoledTheme.isOn(context);
    final clearance = collectionBottomClearance(context);
    final n = _tracks.length;
    List<Track> picked() => _tracks.where((t) => _selected.contains(t.id)).toList();

    return PlayerAwarePopScope(
      child: PopScope(
        canPop: !_selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _selecting) setState(_selected.clear);
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
                          colors: [Color(0x332EB15E), Color(0x00000000)],
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
                          Semantics(header: true, child: Text('Downloaded', style: CollectionStyle.title(36))),
                          const SizedBox(height: 4),
                          Text(
                            !_loaded
                                ? 'Reading your downloads…'
                                : '${n == 1 ? '1 song' : '$n songs'} · available offline',
                            style: CollectionStyle.meta(size: 16, alpha: 0.55),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (active.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 0, CollectionStyle.gutter, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Downloading', style: CollectionStyle.title(18)),
                            const SizedBox(height: 8),
                            for (final t in active)
                              _DownloadingRow(
                                track: t,
                                value: progress[t.id],
                                onCancel: () => provider.cancelDownload(t.id),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_loadError != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(CollectionStyle.gutter),
                        child: Text(_loadError!, style: CollectionStyle.meta(size: 15, alpha: 0.7)),
                      ),
                    ),
                  if (_loaded && _tracks.isEmpty && active.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: CollectionEmptyState(
                        title: 'Nothing downloaded yet',
                        message: 'Download songs to listen without a connection.',
                        actionLabel: 'Find music',
                        actionIcon: Icons.explore_rounded,
                        onAction: () {
                          context.read<MusicProvider>().requestTab(1);
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        },
                      ),
                    )
                  else if (_tracks.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 0, CollectionStyle.gutter, 14),
                        child: Opacity(
                          opacity: visible.isEmpty ? 0.4 : 1,
                          child: IgnorePointer(
                            ignoring: visible.isEmpty,
                            child: Row(
                              children: [
                                Expanded(
                                  child: CollectionPill(
                                      label: 'Play', icon: Icons.play_arrow_rounded, filled: true, onTap: () => _play(visible)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CollectionPill(
                                    label: 'Shuffle',
                                    icon: Icons.shuffle_rounded,
                                    filled: false,
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      _play(List<Track>.of(visible)..shuffle());
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: CollectionSearchField(
                        controller: _search,
                        focus: _searchFocus,
                        hint: 'Find in Downloaded',
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    SliverToBoxAdapter(child: CollectionSortRow(label: _sort.label, onSort: _openSort)),
                    FadeInSliver(
                      key: ValueKey('${_sort.name}|${normalizeForSearch(_query)}'),
                      sliver: visible.isEmpty
                          ? SliverToBoxAdapter(
                              child: CollectionNoMatch(
                                query: _query,
                                onClear: () => setState(() {
                                  _search.clear();
                                  _query = '';
                                }),
                              ),
                            )
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  final t = visible[i];
                                  return CollectionTrackRow(
                                    key: ValueKey('dl_${t.id}'),
                                    track: t,
                                    current: t.id == currentId,
                                    playing: t.id == currentId && playing,
                                    downloaded: false,
                                    selecting: _selecting,
                                    selected: _selected.contains(t.id),
                                    last: i == visible.length - 1,
                                    swipeRemoveEnabled: false,
                                    onTap: () => _selecting
                                        ? setState(() => _selected.contains(t.id) ? _selected.remove(t.id) : _selected.add(t.id))
                                        : _play(visible, index: i),
                                    onLongPress: () {
                                      HapticFeedback.mediumImpact();
                                      setState(() => _selected.add(t.id));
                                    },
                                    onOptions: () => ThemedOptionsSheet.show(context, track: t),
                                    onQueue: () => _queue([t]),
                                    onRemove: () {},
                                  );
                                },
                                childCount: visible.length,
                              ),
                            ),
                    ),
                  ],
                  SliverToBoxAdapter(child: SizedBox(height: clearance + (_selecting ? 76 : 0))),
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: CollectionNavBar(
                  scroll: _scroll,
                  topInset: top,
                  title: 'Downloaded',
                  selecting: _selecting,
                  selectedCount: _selected.length,
                  allSelected: visible.isNotEmpty && visible.every((t) => _selected.contains(t.id)),
                  onBack: () => Navigator.maybePop(context),
                  onMore: _tracks.isEmpty ? null : () => _openMore(visible),
                  onEndSelection: () => setState(_selected.clear),
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
                    SelectionAction(Icons.delete_outline_rounded, 'Remove', () => _confirmRemove(picked()), destructive: true),
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

class _DownloadingRow extends StatelessWidget {
  const _DownloadingRow({required this.track, required this.value, required this.onCancel});

  final Track track;
  final double? value;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final pct = value == null ? null : (value!.clamp(0.0, 1.0) * 100).round();
    return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.trackName,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(15, w: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(pct == null ? 'Starting…' : '$pct% · ${track.artistName}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.meta(size: 12.5)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: value?.clamp(0.0, 1.0),
                      semanticsLabel: 'Downloading ${track.trackName}',
                      color: const Color(0xFF2EB15E),
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
            JellyIconButton(
              tooltip: 'Cancel download of ${track.trackName}',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.7)),
              onPressed: onCancel,
            ),
          ],
        ),
    );
  }
}
