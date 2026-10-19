// lib/widgets/playlist/add_songs_sheet.dart
//
// ADD SONGS to a playlist you are looking at - the reference's "Explore this
// playlist", made useful. Three sources in one tall sheet:
//
//   Suggested - songs the app already ranked for you (For you, Quick picks, the
//               chart), not just recommendations "based on this playlist": the
//               label says what it is.
//   Liked     - your Liked Songs.
//   Search    - the same song search as the rest of the app.
//
// Tapping a row's + adds it at once and turns into a check (the playlist behind
// the sheet updates live). A song the playlist has is shown as added and cannot
// be added twice.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../../utils/app_image_cache.dart';
import '../../utils/image_quality_utils.dart';
import '../collection/collection_kit.dart';
import '../glass_surface.dart';
import '../home_sections.dart' show PressableScale;

/// What the Suggested tab offers: ranked sources merged, de-duplicated, first
/// [limit]. Pure so it can be tested.
List<Track> suggestedSongs(
  Iterable<Iterable<Track>> sources, {
  Set<String> exclude = const {},
  int limit = 30,
}) {
  final seen = <String>{...exclude};
  final out = <Track>[];
  for (final src in sources) {
    for (final t in src) {
      if (out.length >= limit) return out;
      if (seen.add(t.id)) out.add(t);
    }
  }
  return out;
}

Future<void> showAddSongsSheet(
  BuildContext context,
  String playlistId, {
  Future<List<Track>> Function(String query)? searchOverride,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddSongsBody(playlistId: playlistId, search: searchOverride),
  );
}

enum _Tab { suggested, liked, search }

class _AddSongsBody extends StatefulWidget {
  const _AddSongsBody({required this.playlistId, this.search});

  final String playlistId;
  final Future<List<Track>> Function(String query)? search;

  @override
  State<_AddSongsBody> createState() => _AddSongsBodyState();
}

class _AddSongsBodyState extends State<_AddSongsBody> {
  _Tab _tab = _Tab.suggested;
  final TextEditingController _q = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<Track> _results = const [];
  bool _searching = false;
  bool _searched = false;
  String? _error;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
        _searching = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () => _run(v.trim()));
  }

  Future<void> _run(String query) async {
    final gen = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final list = await (widget.search ?? context.read<MusicProvider>().searchTracks)(query);
      if (!mounted || gen != _generation) return;
      setState(() {
        _results = list;
        _searching = false;
        _searched = true;
      });
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _searching = false;
        _searched = true;
        // Stale results under an error message would read as the answer.
        _results = const [];
        _error = 'Search failed. Check your connection and try again.';
      });
    }
  }

  Future<void> _add(Track t) async {
    HapticFeedback.selectionClick();
    await context.read<MusicProvider>().addTracksToPlaylist(widget.playlistId, [t]);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final playlist = provider.playlistById(widget.playlistId);
    final have = {for (final t in playlist?.tracks ?? const <Track>[]) t.id};
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    final List<Track> shown;
    String? empty;
    switch (_tab) {
      case _Tab.suggested:
        shown = suggestedSongs(
          [provider.recommendedTracks, provider.quickPicks, provider.trendingTracks],
          exclude: const {},
        );
        empty = 'Nothing to suggest yet. Play a few songs and check back.';
      case _Tab.liked:
        shown = provider.likedSongs;
        empty = 'You have not liked any songs yet.';
      case _Tab.search:
        shown = _results;
        empty = _searching
            ? null
            : _error ??
                (_searched
                    ? 'No songs found for "${_q.text.trim()}"'
                    : 'Search for a song, artist or album.');
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: GlassSurface(
        tier: GlassTier.chrome,
        borderRadius: 24,
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const SheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text('Add songs', style: CollectionStyle.title(20)),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                        child: Text('Done', style: CollectionStyle.meta(size: 16, alpha: 1, w: FontWeight.w800)
                            .copyWith(color: CollectionStyle.accent)),
                      ),
                    ],
                  ),
                ),
                CollectionChips(
                  chips: const [
                    CollectionChipData(id: 'suggested', label: 'Suggested'),
                    CollectionChipData(id: 'liked', label: 'Liked'),
                    CollectionChipData(id: 'search', label: 'Search'),
                  ],
                  selectedId: _tab.name,
                  onTap: (c) {
                    HapticFeedback.selectionClick();
                    setState(() => _tab = _Tab.values.firstWhere((t) => t.name == c.id));
                    if (_tab == _Tab.search) _focus.requestFocus();
                  },
                ),
                if (_tab == _Tab.search)
                  CollectionSearchField(
                    controller: _q,
                    focus: _focus,
                    hint: 'Songs, artists, albums',
                    onChanged: _onQuery,
                  ),
                if (_searching && _tab == _Tab.search)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: LinearProgressIndicator(minHeight: 2, color: CollectionStyle.accent, backgroundColor: Colors.transparent),
                  ),
                Expanded(
                  child: shown.isEmpty
                      ? (empty == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
                              child: Text(empty,
                                  textAlign: TextAlign.center,
                                  style: CollectionStyle.meta(size: 15, alpha: 0.6)),
                            ))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 12, 24),
                          itemCount: shown.length,
                          itemBuilder: (context, i) {
                            final t = shown[i];
                            return _SongAddRow(track: t, added: have.contains(t.id), onAdd: () => _add(t));
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SongAddRow extends StatelessWidget {
  const _SongAddRow({required this.track, required this.added, required this.onAdd});

  final Track track;
  final bool added;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final art = track.albumArtUrl;
    final placeholder = Container(color: Colors.white.withValues(alpha: 0.06), child: const Icon(Icons.music_note_rounded, color: Colors.white24));
    return Semantics(
      button: !added,
      enabled: !added,
      label: '${added ? 'Added: ' : 'Add '}${track.trackName}, ${track.artistName}',
      excludeSemantics: true,
      child: PressableScale(
        onTap: added ? null : onAdd,
        child: Container(
          height: 64,
          color: Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: art.isEmpty
                      ? placeholder
                      : CachedNetworkImage(
                          imageUrl: ImageQualityUtils.getHighResArtwork(art),
                          fit: BoxFit.cover,
                          memCacheWidth: AppImageCache.thumbnailMemCache,
                          placeholder: (_, __) => placeholder,
                          errorWidget: (_, __, ___) => placeholder,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.trackName,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(15.5, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(track.artistName, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.meta(size: 13)),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Container(
                  key: ValueKey(added),
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: added ? CollectionStyle.accent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.08),
                    border: Border.all(color: added ? CollectionStyle.accent : Colors.white24, width: 0.9),
                  ),
                  child: Icon(added ? Icons.check_rounded : Icons.add_rounded,
                      size: 20, color: added ? CollectionStyle.accent : Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
