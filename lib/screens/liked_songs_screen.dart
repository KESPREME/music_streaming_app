// lib/screens/liked_songs_screen.dart
//
// LIKED SONGS (glass). Plan: docs/PLAN-liked-songs.md.
//
// One live list (no snapshot): a like or unlike anywhere in the app shows up
// here at once. Everything acts on the VISIBLE list - sorted, filtered and
// searched - so Play plays what you see.
//
//   * Hero: glass heart tile, title, "N songs · 7 hr 12 min".
//   * Play / Shuffle pills. Play turns into Pause / Resume while this collection
//     is what is playing.
//   * "Find in Liked Songs" search, sort ("Recently added ⌄"), filter chips
//     (Downloaded, artists with 2+ songs, tagged genres).
//   * Rows: tap plays in context, ⋮ options, swipe right = add to queue, swipe
//     left = remove (with Undo), long-press = select several.
//   * Selection: Play, Add to queue, Download, Remove (one Undo for the batch).
//
// Motion: the collapsed title in the nav row is driven by scroll offset (no
// ticker); the list fades in on arrival and on every sort/filter/search change;
// a removed row collapses (Dismissible); the playing row's equalizer animates
// only while audio plays. All of it is instant under reduce motion.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../presentation/liked/liked_songs_query.dart';
import '../providers/music_provider.dart';
import '../theme/amoled_theme.dart';
import '../theme/glass_tokens.dart';
import '../utils/app_image_cache.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/glass_circle_button.dart';
import '../widgets/glass_surface.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/home_sections.dart' show PressableScale;
import '../widgets/themed_options_sheet.dart';

/// Tokens for this screen (plan section 4).
abstract final class LikedStyle {
  static const Color accent = Color(0xFFFF3B5C);
  static const Color accentDeep = Color(0xFFB0193D);
  static const double gutter = 20;
  static const double art = 56;
  static const double heroArt = 124;
  static const double pill = 52;

  static TextStyle title(double size, {FontWeight w = FontWeight.w800}) =>
      GoogleFonts.plusJakartaSans(
        color: Colors.white,
        fontSize: size,
        fontWeight: w,
        letterSpacing: -size * 0.02,
      );

  static TextStyle meta({double size = 13.5, double alpha = 0.55, FontWeight w = FontWeight.w500}) =>
      GoogleFonts.plusJakartaSans(
        color: Colors.white.withValues(alpha: alpha),
        fontSize: size,
        fontWeight: w,
      );
}

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

  void _toggleFilter(LikedFilter f) {
    HapticFeedback.selectionClick();
    setState(() {
      _query = _query.filter == f
          ? _query.copyWith(clearFilter: true)
          : _query.copyWith(filter: f);
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
      final t = shuffled.removeAt(0);
      shuffled.add(t);
    }
    _playList(shuffled);
  }

  // ── Feedback ─────────────────────────────────────────────────────────────

  double get _bottomClearance =>
      GlassTokens.playerBottomInset +
      GlassTokens.playerPillHeight +
      20 +
      MediaQuery.paddingOf(context).bottom;

  void _toast(String message, {IconData icon = Icons.check_rounded, SnackBarAction? action}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, _bottomClearance - 8),
      duration: Duration(milliseconds: action == null ? 1600 : 5000),
      content: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LikedStyle.meta(size: 14, alpha: 0.95, w: FontWeight.w600)),
          ),
        ],
      ),
      action: action,
    ));
  }

  void _remove(Iterable<String> ids) {
    final removed = context.read<MusicProvider>().unlikeSongs(ids);
    if (removed.isEmpty) return;
    HapticFeedback.mediumImpact();
    final label = removed.length == 1
        ? 'Removed "${removed.first.track.trackName}" from Liked Songs'
        : 'Removed ${removed.length} songs from Liked Songs';
    _toast(
      label,
      icon: Icons.heart_broken_rounded,
      action: SnackBarAction(
        label: 'Undo',
        textColor: LikedStyle.accent,
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
    _toast(
      tracks.length == 1 ? 'Added "${tracks.first.trackName}" to queue' : 'Added ${tracks.length} songs to queue',
      icon: Icons.queue_music_rounded,
    );
  }

  void _download(List<Track> tracks) {
    final p = context.read<MusicProvider>();
    final todo = tracks
        .where((t) => t.source != 'local' && !p.isTrackDownloadedSync(t.id))
        .toList();
    if (todo.isEmpty) {
      _toast('Already downloaded', icon: Icons.download_done_rounded);
      return;
    }
    p.downloadTracks(todo);
    _toast(
      todo.length == 1 ? 'Downloading "${todo.first.trackName}"' : 'Downloading ${todo.length} songs',
      icon: Icons.download_rounded,
    );
  }

  // ── Selection ────────────────────────────────────────────────────────────

  void _toggleSelected(String id) {
    HapticFeedback.selectionClick();
    setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
  }

  void _endSelection() => setState(_selected.clear);

  // ── Sheets ───────────────────────────────────────────────────────────────

  Future<void> _sheet(List<Widget> Function(BuildContext) children) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => GlassSurface(
        tier: GlassTier.chrome,
        borderRadius: 24,
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...children(sheet),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetRow(BuildContext sheet, IconData icon, String label, VoidCallback onTap,
      {bool checked = false}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 52,
      leading: Icon(icon, color: Colors.white.withValues(alpha: checked ? 1 : 0.7)),
      title: Text(label,
          style: LikedStyle.meta(size: 15, alpha: checked ? 1 : 0.85, w: checked ? FontWeight.w700 : FontWeight.w500)),
      trailing: checked ? const Icon(Icons.check_rounded, color: Colors.white) : null,
      onTap: () {
        Navigator.pop(sheet);
        onTap();
      },
    );
  }

  void _openSort() {
    HapticFeedback.lightImpact();
    _sheet((sheet) => [
          Text('Sort by', style: LikedStyle.title(18)),
          const SizedBox(height: 6),
          for (final s in LikedSort.values)
            _sheetRow(
              sheet,
              switch (s) {
                LikedSort.recentlyAdded => Icons.schedule_rounded,
                LikedSort.title => Icons.sort_by_alpha_rounded,
                LikedSort.artist => Icons.person_rounded,
                LikedSort.album => Icons.album_rounded,
                LikedSort.mostPlayed => Icons.trending_up_rounded,
              },
              s.label,
              () => _setSort(s),
              checked: s == _query.sort,
            ),
        ]);
  }

  void _openMore(List<Track> all, List<Track> visible) {
    HapticFeedback.lightImpact();
    _sheet((sheet) => [
          Text('Liked Songs', style: LikedStyle.title(18)),
          const SizedBox(height: 6),
          _sheetRow(sheet, Icons.download_rounded, 'Download all', () => _download(all)),
          _sheetRow(sheet, Icons.queue_music_rounded,
              _query.isNarrowed ? 'Add shown songs to queue' : 'Add all to queue', () => _queue(visible)),
          _sheetRow(sheet, Icons.checklist_rounded, 'Select songs', () {
            if (visible.isNotEmpty) setState(() => _selected.add(visible.first.id));
          }),
          _sheetRow(sheet, Icons.swap_vert_rounded, 'Sort by…', _openSort),
        ]);
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
                      child: _EmptyState(onFindMusic: () {
                        context.read<MusicProvider>().requestTab(1);
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      }),
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
                      child: _SearchField(
                        controller: _search,
                        focus: _searchFocus,
                        onChanged: (v) => setState(() => _query = _query.copyWith(search: v)),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SortRow(
                        sort: _query.sort,
                        onSort: _openSort,
                        hasChips: chips.isNotEmpty,
                        filtersShown: _showFilters || _query.filter != null,
                        filterActive: _query.filter != null,
                        onToggleFilters: () {
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
                    SliverToBoxAdapter(
                      child: AnimatedSize(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: (_showFilters || _query.filter != null) && chips.isNotEmpty
                            ? _Chips(chips: chips, selected: _query.filter, onTap: _toggleFilter)
                            : const SizedBox(width: double.infinity),
                      ),
                    ),
                    if (_query.isNarrowed)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(LikedStyle.gutter, 2, LikedStyle.gutter, 6),
                          child: Text(
                            '${visible.length} of ${liked.length} songs',
                            style: LikedStyle.meta(size: 13, alpha: 0.5),
                          ),
                        ),
                      ),
                    _FadeInSliver(
                      key: ValueKey(_query.signature),
                      sliver: visible.isEmpty
                          ? SliverToBoxAdapter(
                              child: _NoMatch(query: _query.search, onClear: _clearNarrowing),
                            )
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  final t = visible[i];
                                  return _LikedRow(
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
                                    onOptions: () => ThemedOptionsSheet.show(context, track: t),
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
                  SliverToBoxAdapter(
                    child: SizedBox(height: _bottomClearance + (_selecting ? 76 : 0)),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _NavBar(
                  scroll: _scroll,
                  topInset: top,
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
                bottom: _bottomClearance - 6,
                child: _SelectionBar(
                  visible: _selecting,
                  onPlay: () {
                    final picked = visible.where((t) => _selected.contains(t.id)).toList();
                    _endSelection();
                    _playList(picked);
                  },
                  onQueue: () {
                    final picked = visible.where((t) => _selected.contains(t.id)).toList();
                    _endSelection();
                    _queue(picked);
                  },
                  onDownload: () {
                    final picked = liked.where((t) => _selected.contains(t.id)).toList();
                    _endSelection();
                    _download(picked);
                  },
                  onRemove: () {
                    final ids = Set<String>.of(_selected);
                    _endSelection();
                    _remove(ids);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pieces ─────────────────────────────────────────────────────────────────

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.scroll,
    required this.topInset,
    required this.selecting,
    required this.selectedCount,
    required this.allSelected,
    required this.onBack,
    required this.onMore,
    required this.onEndSelection,
    required this.onSelectAll,
  });

  final ScrollController scroll;
  final double topInset;
  final bool selecting;
  final int selectedCount;
  final bool allSelected;
  final VoidCallback onBack;
  final VoidCallback? onMore;
  final VoidCallback onEndSelection;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, _) {
        final offset = scroll.hasClients ? scroll.offset : 0.0;
        // The scrim fills in over the first 60 dp; the small title arrives once
        // the hero title has scrolled under the bar.
        final scrim = (offset / 60).clamp(0.0, 1.0);
        final titleIn = ((offset - 70) / 50).clamp(0.0, 1.0);
        return Container(
          padding: EdgeInsets.fromLTRB(12, topInset + 8, 12, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.92 * scrim),
                Colors.black.withValues(alpha: 0.75 * scrim),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06 * scrim), width: 0.6),
            ),
          ),
          child: SizedBox(
            height: 48,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
              child: selecting
                  ? Row(
                      key: const ValueKey('select'),
                      children: [
                        GlassCircleButton(
                          icon: Icons.close_rounded,
                          size: 44,
                          iconSize: 22,
                          semanticLabel: 'Done selecting',
                          onTap: onEndSelection,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text('$selectedCount selected',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: LikedStyle.title(18)),
                          ),
                        ),
                        TextButton(
                          onPressed: onSelectAll,
                          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                          child: Text(allSelected ? 'Deselect all' : 'Select all',
                              style: LikedStyle.meta(size: 14.5, alpha: 0.9, w: FontWeight.w700)),
                        ),
                      ],
                    )
                  : Row(
                      key: const ValueKey('nav'),
                      children: [
                        GlassCircleButton(
                          icon: Icons.arrow_back_rounded,
                          size: 44,
                          iconSize: 22,
                          semanticLabel: 'Back to Library',
                          onTap: onBack,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              Opacity(
                                opacity: 1 - titleIn,
                                child: ExcludeSemantics(
                                  child: Text('Library',
                                      maxLines: 1, style: LikedStyle.meta(size: 16, alpha: 0.6, w: FontWeight.w600)),
                                ),
                              ),
                              Opacity(
                                opacity: titleIn,
                                child: Transform.translate(
                                  offset: Offset(0, 6 * (1 - titleIn)),
                                  child: Text('Liked Songs',
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: LikedStyle.title(18)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onMore != null)
                          GlassCircleButton(
                            icon: Icons.more_vert_rounded,
                            size: 44,
                            iconSize: 22,
                            semanticLabel: 'More options',
                            onTap: onMore!,
                          ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

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
            color: LikedStyle.accentDeep.withValues(alpha: 0.35),
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
      padding: const EdgeInsets.fromLTRB(LikedStyle.gutter, 4, LikedStyle.gutter, 20),
      child: Row(
        children: [
          const _HeartArt(size: LikedStyle.heroArt),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Liked Songs', maxLines: 2, style: LikedStyle.title(28)),
                ),
                const SizedBox(height: 4),
                Text('Your saved tracks', maxLines: 1, style: LikedStyle.meta(size: 15, alpha: 0.6)),
                const SizedBox(height: 4),
                Text(duration == null ? count : '$count · $duration',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LikedStyle.meta(size: 13.5, alpha: 0.5)),
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
      padding: const EdgeInsets.fromLTRB(LikedStyle.gutter, 0, LikedStyle.gutter, 14),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Row(
            children: [
              Expanded(
                child: _Pill(
                  label: label,
                  icon: icon,
                  filled: true,
                  onTap: onPlay,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Pill(label: 'Shuffle', icon: Icons.shuffle_rounded, filled: false, onTap: onShuffle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.filled, required this.onTap});

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.black : Colors.white;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          height: LikedStyle.pill,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: filled
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFFFFF), Color(0xFFE6E6EA)],
                  )
                : null,
            color: filled ? null : Colors.white.withValues(alpha: 0.07),
            border: Border.all(color: Colors.white.withValues(alpha: filled ? 0 : 0.14), width: 0.8),
            boxShadow: filled
                ? [BoxShadow(color: Colors.white.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(icon, key: ValueKey(icon), color: fg, size: 24),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(color: fg, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focus, required this.onChanged});

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(LikedStyle.gutter, 0, LikedStyle.gutter, 6),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.8),
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.6), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  cursorColor: LikedStyle.accent,
                  style: LikedStyle.meta(size: 15.5, alpha: 0.95),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Find in Liked Songs',
                    hintStyle: LikedStyle.meta(size: 15.5, alpha: 0.45),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.cancel_rounded, color: Colors.white.withValues(alpha: 0.55), size: 20),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              else
                const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.sort,
    required this.onSort,
    required this.hasChips,
    required this.filtersShown,
    required this.filterActive,
    required this.onToggleFilters,
  });

  final LikedSort sort;
  final VoidCallback onSort;
  final bool hasChips;
  final bool filtersShown;
  final bool filterActive;
  final VoidCallback onToggleFilters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(LikedStyle.gutter - 8, 2, LikedStyle.gutter - 4, 2),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Sort: ${sort.label}',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onSort,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(sort.label, style: LikedStyle.meta(size: 15.5, alpha: 0.8, w: FontWeight.w600)),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withValues(alpha: 0.7)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (hasChips)
            GlassCircleButton(
              icon: filterActive ? Icons.filter_alt_off_rounded : Icons.tune_rounded,
              size: 44,
              iconSize: 20,
              isActive: filtersShown,
              semanticLabel: filterActive ? 'Clear filter' : (filtersShown ? 'Hide filters' : 'Show filters'),
              onTap: onToggleFilters,
            ),
        ],
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.chips, required this.selected, required this.onTap});

  final List<LikedFilter> chips;
  final LikedFilter? selected;
  final ValueChanged<LikedFilter> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(LikedStyle.gutter, 6, LikedStyle.gutter, 6),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = chips[i];
          final on = c == selected;
          return Semantics(
            button: true,
            selected: on,
            label: 'Filter: ${c.label}',
            excludeSemantics: true,
            child: PressableScale(
              onTap: () => onTap(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? Colors.white : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: on ? 0 : 0.10), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.kind == LikedFilterKind.downloaded) ...[
                      Icon(Icons.download_done_rounded, size: 16, color: on ? Colors.black : Colors.white70),
                      const SizedBox(width: 6),
                    ],
                    Text(c.label,
                        style: GoogleFonts.plusJakartaSans(
                          color: on ? Colors.black : Colors.white.withValues(alpha: 0.85),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LikedRow extends StatelessWidget {
  const _LikedRow({
    super.key,
    required this.track,
    required this.current,
    required this.playing,
    required this.downloaded,
    required this.selecting,
    required this.selected,
    required this.last,
    required this.onTap,
    required this.onLongPress,
    required this.onOptions,
    required this.onQueue,
    required this.onRemove,
  });

  final Track track;
  final bool current;
  final bool playing;
  final bool downloaded;
  final bool selecting;
  final bool selected;
  final bool last;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onOptions;
  final VoidCallback onQueue;
  final VoidCallback onRemove;

  Widget _swipeBg({required bool left, required Color color, required IconData icon, required String label}) {
    return Container(
      color: color,
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!left) Text(label, style: LikedStyle.meta(size: 15, alpha: 1, w: FontWeight.w700)),
          if (!left) const SizedBox(width: 8),
          Icon(icon, color: Colors.white),
          if (left) const SizedBox(width: 8),
          if (left) Text(label, style: LikedStyle.meta(size: 15, alpha: 1, w: FontWeight.w700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final art = track.albumArtUrl;
    final placeholder = Container(
      color: Colors.white.withValues(alpha: 0.06),
      child: const Icon(Icons.music_note_rounded, color: Colors.white24),
    );

    final songArea = Semantics(
      button: true,
      selected: selecting ? selected : current,
      label: '${track.trackName}, ${track.artistName}'
          '${current ? (playing ? ', now playing' : ', paused') : ''}',
      hint: selecting ? (selected ? 'Selected' : 'Not selected') : null,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        onLongPress: selecting ? null : onLongPress,
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.fromLTRB(LikedStyle.gutter, 8, 0, 8),
          child: Row(
            children: [
              AnimatedContainer(
                duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: selecting ? 36 : 0,
                height: 24,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: 36,
                    child: AnimatedSwitcher(
                      duration: reduce ? Duration.zero : const Duration(milliseconds: 140),
                      child: Icon(
                        selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        key: ValueKey(selected),
                        color: selected ? LikedStyle.accent : Colors.white38,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: LikedStyle.art,
                height: LikedStyle.art,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: art.isEmpty
                      ? placeholder
                      : CachedNetworkImage(
                          imageUrl: ImageQualityUtils.getHighResArtwork(art),
                          fit: BoxFit.cover,
                          memCacheWidth: AppImageCache.thumbnailMemCache,
                          fadeInDuration: const Duration(milliseconds: 160),
                          placeholder: (_, __) => placeholder,
                          errorWidget: (_, __, ___) => placeholder,
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.trackName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LikedStyle.title(16, w: FontWeight.w700)
                            .copyWith(color: current ? LikedStyle.accent : Colors.white)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (track.isExplicit) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('E',
                                style: GoogleFonts.plusJakartaSans(
                                    color: Colors.black, fontSize: 9.5, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (downloaded) ...[
                          const Icon(Icons.download_done_rounded, size: 15, color: Color(0xFF2EB15E)),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(track.artistName,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: LikedStyle.meta()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (current) ...[
                const SizedBox(width: 8),
                _Equalizer(playing: playing),
              ],
            ],
          ),
        ),
      ),
    );

    final row = DecoratedBox(
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 0.6)),
      ),
      position: DecorationPosition.foreground,
      child: Row(
        children: [
          Expanded(child: songArea),
          if (!selecting)
            IconButton(
              tooltip: 'More options for ${track.trackName}',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(Icons.more_vert_rounded, color: Colors.white.withValues(alpha: 0.7)),
              onPressed: onOptions,
            )
          else
            const SizedBox(width: 12),
          const SizedBox(width: 4),
        ],
      ),
    );

    if (selecting) return row;
    return Dismissible(
      key: ValueKey('dismiss_${track.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.4,
      },
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onQueue();
          return false; // springs back
        }
        return true;
      },
      onDismissed: (_) => onRemove(),
      background: _swipeBg(
          left: true, color: const Color(0xFF1F3B63), icon: Icons.queue_music_rounded, label: 'Queue'),
      secondaryBackground: _swipeBg(
          left: false, color: LikedStyle.accentDeep, icon: Icons.heart_broken_rounded, label: 'Remove'),
      child: row,
    );
  }
}

/// Three bars that dance while [playing] and rest (static) otherwise.
class _Equalizer extends StatefulWidget {
  const _Equalizer({required this.playing});

  final bool playing;

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.playing && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Equalizer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.playing ? 'Now playing' : 'Paused',
      child: SizedBox(
        width: 20,
        height: 18,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            const phases = [0.0, 0.33, 0.66];
            const rest = [0.45, 0.8, 0.6];
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 4,
                    height: 18 *
                        (_c.isAnimating
                            ? 0.3 + 0.7 * (0.5 + 0.5 * _wave((_c.value + phases[i]) % 1))
                            : rest[i]),
                    decoration: BoxDecoration(
                      color: LikedStyle.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static double _wave(double t) {
    // A cheap smooth periodic curve in [-1, 1].
    final x = t * 2 - 1;
    return 1 - 2 * x * x;
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.visible,
    required this.onPlay,
    required this.onQueue,
    required this.onDownload,
    required this.onRemove,
  });

  final bool visible;
  final VoidCallback onPlay;
  final VoidCallback onQueue;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    Widget action(IconData icon, String label, VoidCallback onTap, {Color? color}) => Expanded(
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                HapticFeedback.lightImpact();
                onTap();
              },
              child: SizedBox(
                height: 60,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: color ?? Colors.white, size: 22),
                    const SizedBox(height: 3),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LikedStyle.meta(size: 11.5, alpha: 0.9, w: FontWeight.w600)
                            .copyWith(color: color)),
                  ],
                ),
              ),
            ),
          ),
        );

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.4),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
          child: GlassSurface(
            tier: GlassTier.floating,
            borderRadius: 22,
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  action(Icons.play_arrow_rounded, 'Play', onPlay),
                  action(Icons.queue_music_rounded, 'Queue', onQueue),
                  action(Icons.download_rounded, 'Download', onDownload),
                  action(Icons.heart_broken_rounded, 'Remove', onRemove, color: LikedStyle.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onFindMusic});

  final VoidCallback onFindMusic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Songs you like live here',
              textAlign: TextAlign.center, style: LikedStyle.title(22)),
          const SizedBox(height: 8),
          Text('Tap the heart on any song to save it.',
              textAlign: TextAlign.center, style: LikedStyle.meta(size: 15, alpha: 0.6)),
          const SizedBox(height: 22),
          SizedBox(
            width: 200,
            child: _Pill(label: 'Find music', icon: Icons.explore_rounded, filled: true, onTap: onFindMusic),
          ),
        ],
      ),
    );
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 20),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(q.isEmpty ? 'No songs match this filter' : 'No songs match "$q"',
              textAlign: TextAlign.center, style: LikedStyle.title(18)),
          const SizedBox(height: 6),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text('Clear search and filters',
                style: LikedStyle.meta(size: 14.5, alpha: 0.9, w: FontWeight.w700).copyWith(color: LikedStyle.accent)),
          ),
        ],
      ),
    );
  }
}

/// Fades its sliver in on arrival. Keyed by the query, so a new sort, filter or
/// search reads as the list settling rather than a cut.
class _FadeInSliver extends StatefulWidget {
  const _FadeInSliver({super.key, required this.sliver});

  final Widget sliver;

  @override
  State<_FadeInSliver> createState() => _FadeInSliverState();
}

class _FadeInSliverState extends State<_FadeInSliver> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SliverFadeTransition(opacity: _a, sliver: widget.sliver);
}
