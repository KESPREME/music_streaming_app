// lib/screens/recently_played_screen.dart
//
// HISTORY (glass). What you played, newest first, grouped Today / Yesterday /
// This week / Earlier from the play log. Built from the collection kit, so it
// behaves like Liked Songs and a playlist: tap plays in order, swipe right
// queues, swipe left removes (with Undo), long-press selects, search finds.
//
// ⋮: Add to queue, Save as playlist, Select, Clear history (with Undo).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../presentation/history/history_groups.dart';
import '../presentation/liked/liked_songs_query.dart' show normalizeForSearch;
import '../providers/music_provider.dart';
import '../theme/amoled_theme.dart';
import '../widgets/collection/collection_kit.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/playlist/add_to_playlist_sheet.dart';
import '../widgets/playlist/playlist_edit_sheet.dart';
import '../widgets/themed_options_sheet.dart';

const String kHistoryContextId = 'recently_played';

class RecentlyPlayedScreen extends StatefulWidget {
  const RecentlyPlayedScreen({super.key, this.now});

  /// Fixed clock for tests.
  final DateTime? now;

  @override
  State<RecentlyPlayedScreen> createState() => _RecentlyPlayedScreenState();
}

class _RecentlyPlayedScreenState extends State<RecentlyPlayedScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Set<String> _selected = {};
  String _query = '';

  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _play(List<Track> list, {int index = 0}) {
    if (list.isEmpty) return;
    context.read<MusicProvider>().playTrack(list[index],
        playlistTracks: List<Track>.of(list), playlistId: kHistoryContextId);
  }

  void _shuffle(List<Track> list) {
    if (list.isEmpty) return;
    HapticFeedback.lightImpact();
    final s = List<Track>.of(list)..shuffle();
    if (s.length > 1 && s.first.id == context.read<MusicProvider>().currentTrack?.id) {
      s.add(s.removeAt(0));
    }
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

  void _remove(Iterable<String> ids, {bool clearing = false}) {
    final removed = context.read<MusicProvider>().removeRecentlyPlayed(ids);
    if (removed.isEmpty) return;
    HapticFeedback.mediumImpact();
    showCollectionToast(
      context,
      clearing
          ? 'History cleared'
          : (removed.length == 1
              ? 'Removed "${removed.first.track.trackName}" from History'
              : 'Removed ${removed.length} songs from History'),
      icon: Icons.history_toggle_off_rounded,
      action: SnackBarAction(
        label: 'Undo',
        textColor: CollectionStyle.accent,
        onPressed: () {
          if (mounted) context.read<MusicProvider>().restoreRecentlyPlayed(removed);
        },
      ),
    );
  }

  Future<void> _saveAsPlaylist(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final made = await showPlaylistEditSheet(context, initialTracks: tracks);
    if (made != null && mounted) {
      showCollectionToast(context, 'Saved "${made.name}" with ${tracks.length} songs',
          icon: Icons.playlist_add_check_rounded);
    }
  }

  void _openMore(List<Track> all, List<Track> visible) {
    HapticFeedback.lightImpact();
    showCollectionSheet<void>(
      context,
      (sheet) => [
        Text('History', style: CollectionStyle.title(18)),
        const SizedBox(height: 6),
        SheetRow(icon: Icons.queue_music_rounded, label: 'Add shown songs to queue', onTap: () => _queue(visible)),
        SheetRow(icon: Icons.playlist_add_rounded, label: 'Save as playlist', onTap: () => _saveAsPlaylist(visible)),
        SheetRow(
          icon: Icons.checklist_rounded,
          label: 'Select songs',
          onTap: () {
            if (visible.isNotEmpty) setState(() => _selected.add(visible.first.id));
          },
        ),
        SheetRow(
          icon: Icons.delete_sweep_rounded,
          label: 'Clear history',
          destructive: true,
          onTap: () => _remove(all.map((t) => t.id), clearing: true),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = context.select<MusicProvider, List<Track>>((p) => p.recentlyPlayed);
    final currentId = context.select<MusicProvider, String?>((p) => p.currentTrack?.id);
    final playing = context.select<MusicProvider, bool>((p) => p.isPlaying);
    final ourContext = context.select<MusicProvider, bool>((p) => p.currentPlaylistId == kHistoryContextId);
    final provider = context.read<MusicProvider>();
    bool downloaded(String id) => provider.isTrackDownloadedSync(id);

    final ids = {for (final t in all) t.id};
    _selected.removeWhere((id) => !ids.contains(id));

    final q = normalizeForSearch(_query);
    final words = q.split(' ').where((w) => w.isNotEmpty).toList();
    final visible = words.isEmpty
        ? all
        : all.where((t) {
            final hay = normalizeForSearch('${t.trackName} ${t.artistName} ${t.albumName}');
            return words.every(hay.contains);
          }).toList();
    final groups = groupHistory(visible, provider.listeningStats.lastPlayedAt(), widget.now ?? DateTime.now());
    final active = ourContext && currentId != null && ids.contains(currentId);
    final top = MediaQuery.paddingOf(context).top;
    final amoled = AmoledTheme.isOn(context);
    final clearance = collectionBottomClearance(context);

    // Flatten groups into header + row entries.
    final entries = <Object>[];
    for (final g in groups) {
      entries.add(g.label);
      for (var i = 0; i < g.tracks.length; i++) {
        entries.add((g.tracks[i], i == g.tracks.length - 1));
      }
    }
    List<Track> picked() => all.where((t) => _selected.contains(t.id)).toList();

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
                          colors: [Color(0x33A8662A), Color(0x00000000)],
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
                          Semantics(header: true, child: Text('History', style: CollectionStyle.title(36))),
                          const SizedBox(height: 4),
                          Text(all.length == 1 ? '1 song' : '${all.length} songs',
                              style: CollectionStyle.meta(size: 16, alpha: 0.55)),
                        ],
                      ),
                    ),
                  ),
                  if (all.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: CollectionEmptyState(
                        title: 'Nothing played yet',
                        message: 'Songs you listen to show up here, newest first.',
                        actionLabel: 'Find music',
                        actionIcon: Icons.explore_rounded,
                        onAction: () {
                          context.read<MusicProvider>().requestTab(1);
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        },
                      ),
                    )
                  else ...[
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
                                    label: active ? (playing ? 'Pause' : 'Resume') : 'Play',
                                    icon: playing && active ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    filled: true,
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      final p = context.read<MusicProvider>();
                                      if (active) {
                                        playing ? p.pauseTrack() : p.resumeTrack();
                                      } else {
                                        _play(visible);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CollectionPill(
                                      label: 'Shuffle', icon: Icons.shuffle_rounded, filled: false, onTap: () => _shuffle(visible)),
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
                        hint: 'Find in History',
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    if (words.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 6, CollectionStyle.gutter, 6),
                          child: Text('${visible.length} of ${all.length} songs',
                              style: CollectionStyle.meta(size: 13, alpha: 0.5)),
                        ),
                      ),
                    FadeInSliver(
                      key: ValueKey(q),
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
                                  final e = entries[i];
                                  if (e is String) {
                                    return Padding(
                                      padding: EdgeInsets.fromLTRB(CollectionStyle.gutter, i == 0 ? 8 : 22, CollectionStyle.gutter, 4),
                                      child: Semantics(
                                          header: true, child: Text(e, style: CollectionStyle.title(20))),
                                    );
                                  }
                                  final (t, last) = e as (Track, bool);
                                  return CollectionTrackRow(
                                    key: ValueKey('hist_${t.id}'),
                                    track: t,
                                    current: t.id == currentId,
                                    playing: t.id == currentId && playing,
                                    downloaded: t.source != 'local' && downloaded(t.id),
                                    selecting: _selecting,
                                    selected: _selected.contains(t.id),
                                    last: last,
                                    removeLabel: 'Remove',
                                    onTap: () => _selecting
                                        ? setState(() => _selected.contains(t.id) ? _selected.remove(t.id) : _selected.add(t.id))
                                        : _play(visible, index: visible.indexWhere((v) => v.id == t.id)),
                                    onLongPress: () {
                                      HapticFeedback.mediumImpact();
                                      setState(() => _selected.add(t.id));
                                    },
                                    onOptions: () => ThemedOptionsSheet.show(context, track: t, isRecentlyPlayedContext: true),
                                    onQueue: () => _queue([t]),
                                    onRemove: () => _remove([t.id]),
                                  );
                                },
                                childCount: entries.length,
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
                  title: 'History',
                  selecting: _selecting,
                  selectedCount: _selected.length,
                  allSelected: visible.isNotEmpty && visible.every((t) => _selected.contains(t.id)),
                  onBack: () => Navigator.maybePop(context),
                  onMore: all.isEmpty ? null : () => _openMore(all, visible),
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
                    SelectionAction(Icons.history_toggle_off_rounded, 'Remove', () {
                      final ids = Set<String>.of(_selected);
                      setState(_selected.clear);
                      _remove(ids);
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
