// lib/screens/liked_songs_screen.dart
//
// LIKED SONGS (glass). Plan: docs/PLAN-liked-songs.md.
//
// One live list (no snapshot): a like or unlike anywhere in the app shows up
// here at once. Everything acts on the VISIBLE list - sorted, filtered and
// searched - so Play plays what you see. Built from the collection kit, the
// same pieces as Your Playlists and a playlist.
//
//   * Hero: glass heart tile, title, "N songs · 7 hr 12 min".
//   * Play / Shuffle pills. Play turns into Pause / Resume while this collection
//     is what is playing.
//   * "Find in Liked Songs" search, sort ("Recently added ⌄"), filter chips
//     (Downloaded, artists with 2+ songs, tagged genres).
//   * Rows: tap plays in context, ⋮ options, swipe right = add to queue, swipe
//     left = remove (with Undo), long-press = select several.
//   * Selection: Play, Queue, Download, Add to playlist, Remove (one Undo).
//   * ⋮: Download all, Add to queue, Save as playlist, Select songs, Sort.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../presentation/liked/liked_songs_query.dart';
import '../providers/music_provider.dart';
import '../theme/amoled_theme.dart';
import '../widgets/collection/collection_kit.dart';
import '../widgets/glass_circle_button.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/playlist/add_to_playlist_sheet.dart';
import '../widgets/playlist/playlist_edit_sheet.dart';
import '../widgets/themed_options_sheet.dart';
import '../widgets/song_sheet_plan.dart';

const String kLikedContextId = 'liked_songs';
const String kLikedSortPref = 'liked_sort_v1';

class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  LikedQuery _query = const LikedQuery();
  bool _showFilters = false;
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final sort = LikedSort.fromName(p.getString(kLikedSortPref));
      if (mounted && sort != _query.sort) {
        setState(() => _query = _query.copyWith(sort: sort));
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

  void _setSort(LikedSort sort) {
    HapticFeedback.selectionClick();
    setState(() => _query = _query.copyWith(sort: sort));
    SharedPreferences.getInstance()
        .then((p) => p.setString(kLikedSortPref, sort.name))
        .catchError((_) => false);
  }

  static String _chipId(LikedFilter f) => '${f.kind.name}:${normalizeForSearch(f.value)}';

  void _toggleFilter(LikedFilter f) {
    HapticFeedback.selectionClick();
    setState(() {
      _query = _query.filter == f ? _query.copyWith(clearFilter: true) : _query.copyWith(filter: f);
    });
  }

  void _clearNarrowing() {
    _search.clear();
    setState(() => _query = _query.copyWith(search: '', clearFilter: true));
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  void _playList(List<Track> list, {int index = 0}) {
    if (list.isEmpty) return;
    context.read<MusicProvider>().playTrack(
          list[index],
          playlistTracks: List<Track>.of(list),
          playlistId: kLikedContextId,
        );
  }

  void _shuffle(List<Track> list) {
    if (list.isEmpty) return;
    HapticFeedback.lightImpact();
    final shuffled = List<Track>.of(list)..shuffle();
    // Starting on the song already playing would toggle it to pause.
    final current = context.read<MusicProvider>().currentTrack?.id;
    if (shuffled.length > 1 && shuffled.first.id == current) {
      shuffled.add(shuffled.removeAt(0));
    }
    _playList(shuffled);
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _remove(Iterable<String> ids) {
    final removed = context.read<MusicProvider>().unlikeSongs(ids);
    if (removed.isEmpty) return;
    HapticFeedback.mediumImpact();
    showCollectionToast(
      context,
      removed.length == 1
          ? 'Removed "${removed.first.track.trackName}" from Liked Songs'
          : 'Removed ${removed.length} songs from Liked Songs',
      icon: Icons.heart_broken_rounded,
      action: SnackBarAction(
        label: 'Undo',
        textColor: CollectionStyle.accent,
        onPressed: () {
          if (mounted) context.read<MusicProvider>().restoreLikedSongs(removed);
        },
      ),
    );
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

  void _download(List<Track> tracks) {
    final p = context.read<MusicProvider>();
    final todo = tracks.where((t) => t.source != 'local' && !p.isTrackDownloadedSync(t.id)).toList();
    if (todo.isEmpty) {
      showCollectionToast(context, 'Already downloaded', icon: Icons.download_done_rounded);
      return;
    }
    p.downloadTracks(todo);
    showCollectionToast(
      context,
      todo.length == 1 ? 'Downloading "${todo.first.trackName}"' : 'Downloading ${todo.length} songs',
      icon: Icons.download_rounded,
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

  // ── Selection ────────────────────────────────────────────────────────────

  void _toggleSelected(String id) {
    HapticFeedback.selectionClick();
    setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
  }

  void _endSelection() => setState(_selected.clear);

  // ── Sheets ───────────────────────────────────────────────────────────────

  void _openSort() {
    HapticFeedback.lightImpact();
    showCollectionSheet<void>(
      context,
      (sheet) => [
        Text('Sort by', style: CollectionStyle.title(18)),
        const SizedBox(height: 6),
        for (final s in LikedSort.values)
          SheetRow(
            icon: switch (s) {
              LikedSort.recentlyAdded => Icons.schedule_rounded,
              LikedSort.title => Icons.sort_by_alpha_rounded,
              LikedSort.artist => Icons.person_rounded,
              LikedSort.album => Icons.album_rounded,
              LikedSort.mostPlayed => Icons.trending_up_rounded,
            },
            label: s.label,
            checked: s == _query.sort,
            onTap: () => _setSort(s),
          ),
      ],
    );
  }

  void _openMore(List<Track> all, List<Track> visible) {
    HapticFeedback.lightImpact();
    showCollectionSheet<void>(
      context,
      (sheet) => [
        Text('Liked Songs', style: CollectionStyle.title(18)),
        const SizedBox(height: 6),
        SheetRow(icon: Icons.download_rounded, label: 'Download all', onTap: () => _download(all)),
        SheetRow(
          icon: Icons.queue_music_rounded,
          label: _query.isNarrowed ? 'Add shown songs to queue' : 'Add all to queue',
          onTap: () => _queue(visible),
        ),
        SheetRow(
          icon: Icons.playlist_add_rounded,
          label: _query.isNarrowed ? 'Save shown songs as playlist' : 'Save as playlist',
          onTap: () => _saveAsPlaylist(visible),
        ),
        SheetRow(
          icon: Icons.checklist_rounded,
          label: 'Select songs',
          onTap: () {
            if (visible.isNotEmpty) setState(() => _selected.add(visible.first.id));
          },
        ),
        SheetRow(icon: Icons.swap_vert_rounded, label: 'Sort by…', onTap: _openSort),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final liked = context.select<MusicProvider, List<Track>>((p) => p.likedSongs);
    final currentId = context.select<MusicProvider, String?>((p) => p.currentTrack?.id);
    final playing = context.select<MusicProvider, bool>((p) => p.isPlaying);
    final ourContext = context.select<MusicProvider, bool>((p) => p.currentPlaylistId == kLikedContextId);
    final provider = context.read<MusicProvider>();
    bool downloaded(String id) => provider.isTrackDownloadedSync(id);

    // Drop selections that are no longer liked (removed elsewhere).
    final likedIds = {for (final t in liked) t.id};
    _selected.removeWhere((id) => !likedIds.contains(id));

    final visible = applyLikedQuery(
      liked,
      _query,
      playCounts: _query.sort == LikedSort.mostPlayed ? provider.listeningStats.playCounts() : const {},
      isDownloaded: downloaded,
    );
    final chips = likedFilterChips(liked, isDownloaded: downloaded);
    final collectionActive = ourContext && currentId != null && likedIds.contains(currentId);
    final top = MediaQuery.paddingOf(context).top;
    final amoled = AmoledTheme.isOn(context);
    final clearance = collectionBottomClearance(context);
    final filtersShown = (_showFilters || _query.filter != null) && chips.isNotEmpty;

    List<Track> picked() => visible.where((t) => _selected.contains(t.id)).toList();

    return PlayerAwarePopScope(
      child: PopScope(
        canPop: !_selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _selecting) _endSelection();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // A faint crimson light behind the hero; none in pure-black mode.
              if (!amoled)
                const Positioned(
                  top: -120,
                  left: -80,
                  right: -80,
                  height: 420,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(-0.5, -0.2),
                          radius: 0.9,
                          colors: [Color(0x40B0193D), Color(0x00000000)],
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
                  SliverToBoxAdapter(child: _Hero(tracks: liked)),
                  if (liked.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: CollectionEmptyState(
                        title: 'Songs you like live here',
                        message: 'Tap the heart on any song to save it.',
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
                      child: _Actions(
                        active: collectionActive,
                        playing: collectionActive && playing,
                        onPlay: () {
                          HapticFeedback.lightImpact();
                          final p = context.read<MusicProvider>();
                          if (collectionActive) {
                            playing ? p.pauseTrack() : p.resumeTrack();
                          } else {
                            _playList(visible);
                          }
                        },
                        onShuffle: () => _shuffle(visible),
                        enabled: visible.isNotEmpty,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: CollectionSearchField(
                        controller: _search,
                        focus: _searchFocus,
                        hint: 'Find in Liked Songs',
                        onChanged: (v) => setState(() => _query = _query.copyWith(search: v)),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: CollectionSortRow(
                        label: _query.sort.label,
                        onSort: _openSort,
                        trailing: chips.isEmpty
                            ? null
                            : GlassCircleButton(
                                icon: _query.filter != null ? Icons.filter_alt_off_rounded : Icons.tune_rounded,
                                size: 44,
                                iconSize: 20,
                                isActive: filtersShown,
                                semanticLabel: _query.filter != null
                                    ? 'Clear filter'
                                    : (filtersShown ? 'Hide filters' : 'Show filters'),
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    if (_query.filter != null) {
                                      _query = _query.copyWith(clearFilter: true);
                                      _showFilters = false;
                                    } else {
                                      _showFilters = !_showFilters;
                                    }
                                  });
                                },
                              ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: AnimatedSize(
                        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: filtersShown
                            ? CollectionChips(
                                chips: [
                                  for (final c in chips)
                                    CollectionChipData(
                                      id: _chipId(c),
                                      label: c.label,
                                      icon: c.kind == LikedFilterKind.downloaded ? Icons.download_done_rounded : null,
                                    ),
                                ],
                                selectedId: _query.filter == null ? null : _chipId(_query.filter!),
                                onTap: (d) => _toggleFilter(chips.firstWhere((c) => _chipId(c) == d.id)),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ),
                    if (_query.isNarrowed)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 2, CollectionStyle.gutter, 6),
                          child: Text('${visible.length} of ${liked.length} songs',
                              style: CollectionStyle.meta(size: 13, alpha: 0.5)),
                        ),
                      ),
                    FadeInSliver(
                      key: ValueKey(_query.signature),
                      sliver: visible.isEmpty
                          ? SliverToBoxAdapter(
                              child: CollectionNoMatch(query: _query.search, onClear: _clearNarrowing),
                            )
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  final t = visible[i];
                                  return CollectionTrackRow(
                                    key: ValueKey('liked_${t.id}'),
                                    track: t,
                                    current: t.id == currentId,
                                    playing: t.id == currentId && playing,
                                    downloaded: t.source != 'local' && downloaded(t.id),
                                    selecting: _selecting,
                                    selected: _selected.contains(t.id),
                                    last: i == visible.length - 1,
                                    onTap: () => _selecting ? _toggleSelected(t.id) : _playList(visible, index: i),
                                    onLongPress: () {
                                      HapticFeedback.mediumImpact();
                                      setState(() => _selected.add(t.id));
                                    },
                                    onOptions: () => ThemedOptionsSheet.show(context, origin: SongSheetOrigin.liked, track: t),
                                    onQueue: () => _queue([t]),
                                    onRemove: () => _remove([t.id]),
                                  );
                                },
                                childCount: visible.length,
                                findChildIndexCallback: (key) {
                                  if (key is! ValueKey<String>) return null;
                                  final i = visible.indexWhere((t) => 'liked_${t.id}' == key.value);
                                  return i < 0 ? null : i;
                                },
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
                  title: 'Liked Songs',
                  selecting: _selecting,
                  selectedCount: _selected.length,
                  allSelected: visible.isNotEmpty && visible.every((t) => _selected.contains(t.id)),
                  onBack: () => Navigator.maybePop(context),
                  onMore: liked.isEmpty ? null : () => _openMore(liked, visible),
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
                      _playList(list);
                    }),
                    SelectionAction(Icons.queue_music_rounded, 'Queue', () {
                      final list = picked();
                      _endSelection();
                      _queue(list);
                    }),
                    SelectionAction(Icons.download_rounded, 'Download', () {
                      final list = liked.where((t) => _selected.contains(t.id)).toList();
                      _endSelection();
                      _download(list);
                    }),
                    SelectionAction(Icons.playlist_add_rounded, 'Playlist', () {
                      final list = picked();
                      _endSelection();
                      showAddToPlaylistSheet(context, list);
                    }),
                    SelectionAction(Icons.heart_broken_rounded, 'Remove', () {
                      final ids = Set<String>.of(_selected);
                      _endSelection();
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

// ── Pieces specific to Liked Songs ─────────────────────────────────────────

class _HeartArt extends StatelessWidget {
  const _HeartArt({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.2),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6A1530), Color(0xFF3A0B1A), Color(0xFF1A050C)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: CollectionStyle.accentDeep.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      // Glass catches light along its top edge.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.2),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0)],
        ),
      ),
      child: Center(
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8FA6), Color(0xFFFF3B5C), Color(0xFFC81E45)],
          ).createShader(r),
          child: Icon(
            Icons.favorite_rounded,
            size: size * 0.46,
            color: Colors.white,
            shadows: [
              Shadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 6)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final n = tracks.length;
    final duration = formatCollectionDuration(tracks);
    final count = n == 1 ? '1 song' : '$n songs';
    return Padding(
      padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 4, CollectionStyle.gutter, 20),
      child: Row(
        children: [
          const _HeartArt(size: CollectionStyle.heroArt),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Liked Songs', maxLines: 2, style: CollectionStyle.title(28)),
                ),
                const SizedBox(height: 4),
                Text('Your saved tracks', maxLines: 1, style: CollectionStyle.meta(size: 15, alpha: 0.6)),
                const SizedBox(height: 4),
                Text(duration == null ? count : '$count · $duration',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CollectionStyle.meta(size: 13.5, alpha: 0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.active,
    required this.playing,
    required this.onPlay,
    required this.onShuffle,
    required this.enabled,
  });

  final bool active;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final label = !active ? 'Play' : (playing ? 'Pause' : 'Resume');
    final icon = playing ? Icons.pause_rounded : Icons.play_arrow_rounded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 0, CollectionStyle.gutter, 14),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Row(
            children: [
              Expanded(child: CollectionPill(label: label, icon: icon, filled: true, onTap: onPlay)),
              const SizedBox(width: 12),
              Expanded(
                child: CollectionPill(label: 'Shuffle', icon: Icons.shuffle_rounded, filled: false, onTap: onShuffle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
