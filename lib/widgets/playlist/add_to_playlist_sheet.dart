// lib/widgets/playlist/add_to_playlist_sheet.dart
//
// ADD TO PLAYLIST - one sheet for every place a song (or many) can be saved.
//
// "New playlist" is always the first row; your playlists follow, most recently
// updated first. Tick any number of them and press one button. A playlist that
// already has the song says so and cannot be ticked, so nothing is added twice
// and nothing silently does nothing. Search appears once there are enough
// playlists to need it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../presentation/playlists/playlist_query.dart';
import '../../providers/music_provider.dart';
import '../collection/collection_kit.dart';
import '../glass_surface.dart';
import '../home_sections.dart' show PressableScale;
import 'playlist_cover.dart';
import 'playlist_edit_sheet.dart';

/// Opens the sheet for [tracks]. Resolves when it closes.
Future<void> showAddToPlaylistSheet(BuildContext context, List<Track> tracks) async {
  if (tracks.isEmpty) return;
  // Hold the NAVIGATOR's context, not the caller's. The caller is usually the song
  // options sheet, which closes itself before opening this one and is gone about
  // 300 ms later - long before the listener has chosen. A check like
  // caller.mounted afterwards could only ever be false, so "New playlist" and the
  // "Added to ..." confirmation were silently dropped. The navigator outlives every
  // sheet it shows, and Navigator.of(...) accepts the navigator's own context.
  final outer = Navigator.of(context).context;
  final createdOrAdded = await showModalBottomSheet<_Outcome>(
    context: outer,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => _AddBody(tracks: tracks),
  );
  if (createdOrAdded == null || !outer.mounted) return;
  if (createdOrAdded.wantsNew) {
    final made = await showPlaylistEditSheet(outer, initialTracks: tracks);
    if (made != null && outer.mounted) {
      showCollectionToast(
        outer,
        'Created "${made.name}"${tracks.length == 1 ? '' : ' with ${tracks.length} songs'}',
        icon: Icons.playlist_add_check_rounded,
      );
    }
    return;
  }
  showCollectionToast(outer, createdOrAdded.message, icon: Icons.playlist_add_check_rounded);
}

class _Outcome {
  const _Outcome.add(this.message) : wantsNew = false;
  const _Outcome.create()
      : wantsNew = true,
        message = '';

  final bool wantsNew;
  final String message;
}

class _AddBody extends StatefulWidget {
  const _AddBody({required this.tracks});

  final List<Track> tracks;

  @override
  State<_AddBody> createState() => _AddBodyState();
}

class _AddBodyState extends State<_AddBody> {
  final Set<String> _picked = {};
  final TextEditingController _search = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// How many of the songs [p] already has.
  int _have(Playlist p) {
    final ids = p.tracks.map((t) => t.id).toSet();
    return widget.tracks.where((t) => ids.contains(t.id)).length;
  }

  Future<void> _confirm(List<Playlist> all) async {
    if (_picked.isEmpty || _busy) return;
    setState(() => _busy = true);
    final provider = context.read<MusicProvider>();
    final names = <String>[];
    var added = 0;
    for (final id in _picked) {
      final pl = all.where((p) => p.id == id).firstOrNull;
      if (pl == null) continue;
      final n = await provider.addTracksToPlaylist(id, widget.tracks);
      if (n > 0) {
        added += n;
        names.add(pl.name);
      }
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    final message = added == 0
        ? 'Already in ${_picked.length == 1 ? 'that playlist' : 'those playlists'}'
        : names.length == 1
            ? 'Added to ${names.first}'
            : 'Added to ${names.length} playlists';
    Navigator.pop(context, _Outcome.add(message));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicProvider>();
    final all = sortPlaylists(provider.userPlaylists, PlaylistSort.recentlyUpdated);
    final needSearch = all.length >= 6;
    final q = normalizeName(_search.text);
    final shown = q.isEmpty ? all : all.where((p) => normalizeName(p.name).contains(q)).toList();
    final single = widget.tracks.length == 1;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final label = _picked.isEmpty
        ? 'Choose playlists'
        : _picked.length == 1
            ? 'Add to ${all.where((p) => p.id == _picked.first).firstOrNull?.name ?? 'playlist'}'
            : 'Add to ${_picked.length} playlists';

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: GlassSurface(
        tier: GlassTier.chrome,
        borderRadius: 24,
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  const SheetHandle(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(header: true, child: Text('Add to playlist', style: CollectionStyle.title(20))),
                        const SizedBox(height: 2),
                        Text(
                          single ? widget.tracks.first.trackName : '${widget.tracks.length} songs',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CollectionStyle.meta(size: 14, alpha: 0.55),
                        ),
                      ],
                    ),
                  ),
                  if (needSearch)
                    CollectionSearchField(
                      controller: _search,
                      focus: FocusNode(),
                      hint: 'Find a playlist',
                      onChanged: (_) => setState(() {}),
                    ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      children: [
                        _NewRow(onTap: () => Navigator.pop(context, const _Outcome.create())),
                        if (all.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text('You have no playlists yet. Make the first one.',
                                style: CollectionStyle.meta(size: 14.5, alpha: 0.55)),
                          ),
                        if (all.isNotEmpty && shown.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text('No playlists match "${_search.text.trim()}"',
                                style: CollectionStyle.meta(size: 14.5, alpha: 0.55)),
                          ),
                        for (final p in shown)
                          _PlaylistRow(
                            playlist: p,
                            have: _have(p),
                            total: widget.tracks.length,
                            picked: _picked.contains(p.id),
                            onTap: () {
                              if (_have(p) == widget.tracks.length) return;
                              HapticFeedback.selectionClick();
                              setState(() => _picked.contains(p.id) ? _picked.remove(p.id) : _picked.add(p.id));
                            },
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    child: Opacity(
                      opacity: _picked.isEmpty ? 0.4 : 1,
                      child: CollectionPill(
                        label: label,
                        icon: Icons.playlist_add_check_rounded,
                        filled: true,
                        onTap: () => _confirm(all),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewRow extends StatelessWidget {
  const _NewRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'New playlist',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          height: 68,
          color: Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.8),
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Text('New playlist',
                  style: CollectionStyle.title(16, w: FontWeight.w700).copyWith(color: CollectionStyle.accent)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.have,
    required this.total,
    required this.picked,
    required this.onTap,
  });

  final Playlist playlist;
  final int have;
  final int total;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final complete = have == total;
    final n = playlist.tracks.length;
    final meta = complete
        ? (total == 1 ? 'Already in this playlist' : 'All already in this playlist')
        : have > 0
            ? '$have already in · ${n == 1 ? '1 song' : '$n songs'}'
            : (n == 1 ? '1 song' : '$n songs');
    return Semantics(
      button: !complete,
      enabled: !complete,
      selected: picked || complete,
      label: '${playlist.name}, $meta',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Opacity(
          opacity: complete ? 0.55 : 1,
          child: Container(
            height: 68,
            color: Colors.transparent,
            child: Row(
              children: [
                PlaylistCover(playlist: playlist, size: 52, radius: 12),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(playlist.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(16, w: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.meta(size: 13)),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  child: Icon(
                    complete
                        ? Icons.check_circle_rounded
                        : (picked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded),
                    key: ValueKey('$complete$picked'),
                    color: complete ? Colors.white38 : (picked ? CollectionStyle.accent : Colors.white38),
                    size: 26,
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
