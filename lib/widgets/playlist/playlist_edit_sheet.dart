// lib/widgets/playlist/playlist_edit_sheet.dart
//
// CREATE / EDIT A PLAYLIST - one sheet for both (the reference's "Add to
// playlist" editor): Cancel · title · Save, a large cover with "Change image",
// the name set big, a description.
//
// The cover can be a song's cover (from the songs the playlist has or starts
// with), a picture from the device, or none (then the playlist collages its
// songs). Save is disabled until there is a name.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../collection/collection_kit.dart';
import '../home_sections.dart' show PressableScale;
import 'playlist_cover.dart';
import 'playlist_cover_store.dart';

typedef CoverPicker = Future<String?> Function();

/// Shows the editor. Returns the created or updated playlist, or null if the
/// listener cancelled. [initialTracks] seed a NEW playlist ("Save as playlist",
/// "Add to playlist > New").
Future<Playlist?> showPlaylistEditSheet(
  BuildContext context, {
  Playlist? existing,
  List<Track> initialTracks = const [],
  CoverPicker? coverPicker,
}) {
  return showModalBottomSheet<Playlist>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => _EditBody(
      existing: existing,
      initialTracks: initialTracks,
      coverPicker: coverPicker ?? pickAndStorePlaylistCover,
    ),
  );
}

class _EditBody extends StatefulWidget {
  const _EditBody({required this.existing, required this.initialTracks, required this.coverPicker});

  final Playlist? existing;
  final List<Track> initialTracks;
  final CoverPicker coverPicker;

  @override
  State<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends State<_EditBody> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.existing?.description ?? '');
  late String _image = widget.existing?.imageUrl ?? '';
  final List<String> _pickedThisSession = [];
  bool _saving = false;

  bool get _editing => widget.existing != null;
  List<Track> get _songs => widget.existing?.tracks ?? widget.initialTracks;
  bool get _canSave => _name.text.trim().isNotEmpty && !_saving;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Playlist get _preview => Playlist(
        id: widget.existing?.id ?? 'preview',
        name: _name.text.trim().isEmpty ? 'Playlist' : _name.text,
        imageUrl: _image,
        tracks: _songs,
      );

  Future<void> _chooseCover() async {
    HapticFeedback.selectionClick();
    final covers = {
      for (final t in _songs)
        if (t.albumArtUrl.isNotEmpty) t.albumArtUrl,
    }.take(12).toList();
    await showCollectionSheet<void>(
      context,
      (sheet) => [
        Text('Cover', style: CollectionStyle.title(18)),
        const SizedBox(height: 6),
        SheetRow(
          icon: Icons.photo_library_rounded,
          label: 'Choose from device',
          onTap: () async {
            final path = await widget.coverPicker();
            if (path != null && mounted) {
              _pickedThisSession.add(path);
              setState(() => _image = path);
            }
          },
        ),
        if (covers.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Use a song\'s cover', style: CollectionStyle.meta(size: 13, alpha: 0.6, w: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: covers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => Semantics(
                button: true,
                label: 'Use cover ${i + 1}',
                child: PressableScale(
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _image = covers[i]);
                  },
                  child: PlaylistCover(
                    playlist: Playlist(id: 'c', name: 'c', imageUrl: covers[i], tracks: const []),
                    size: 76,
                    radius: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_image.isNotEmpty)
          SheetRow(
            icon: Icons.hide_image_rounded,
            label: 'Remove image',
            destructive: true,
            onTap: () => setState(() => _image = ''),
          ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final p = context.read<MusicProvider>();
    Playlist? result;
    if (_editing) {
      final old = widget.existing!.imageUrl;
      await p.updatePlaylist(widget.existing!.id,
          name: _name.text, description: _desc.text, imageUrl: _image);
      result = p.playlistById(widget.existing!.id);
      if (old.isNotEmpty && old != _image) await deleteStoredCover(old);
    } else {
      result = await p.createPlaylistWith(
        name: _name.text,
        tracks: widget.initialTracks,
        imageUrl: _image.isEmpty ? null : _image,
        description: _desc.text,
      );
    }
    // Pictures picked then replaced in this session are orphans.
    for (final path in _pickedThisSession) {
      if (path != _image) await deleteStoredCover(path);
    }
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E10),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetHandle(),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      child: Text('Cancel', style: CollectionStyle.meta(size: 16, alpha: 0.8, w: FontWeight.w600)),
                    ),
                    Expanded(
                      child: Text(_editing ? 'Edit playlist' : 'New playlist',
                          textAlign: TextAlign.center, style: CollectionStyle.title(17)),
                    ),
                    TextButton(
                      onPressed: _canSave ? _save : null,
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      child: Text('Save',
                          style: CollectionStyle.meta(size: 16, alpha: _canSave ? 1 : 0.3, w: FontWeight.w800)
                              .copyWith(color: _canSave ? CollectionStyle.accent : null)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Semantics(
                  button: true,
                  label: 'Change image',
                  excludeSemantics: true,
                  child: PressableScale(
                    onTap: _chooseCover,
                    child: Column(
                      children: [
                        PlaylistCover(playlist: _preview, size: 168, radius: 20, shadow: true),
                        const SizedBox(height: 12),
                        Text('Change image',
                            style: CollectionStyle.meta(size: 14.5, alpha: 0.85, w: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _name,
                  autofocus: !_editing,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor: CollectionStyle.accent,
                  maxLength: 60,
                  style: CollectionStyle.title(26),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Playlist name',
                    hintStyle: CollectionStyle.title(26).copyWith(color: Colors.white.withValues(alpha: 0.3)),
                    border: InputBorder.none,
                  ),
                ),
                Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
                TextField(
                  controller: _desc,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor: CollectionStyle.accent,
                  style: CollectionStyle.meta(size: 15.5, alpha: 0.9),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Description',
                    hintStyle: GoogleFonts.plusJakartaSans(color: Colors.white.withValues(alpha: 0.35), fontSize: 15.5),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (!_editing && widget.initialTracks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.initialTracks.length == 1
                          ? 'Starts with "${widget.initialTracks.first.trackName}"'
                          : 'Starts with ${widget.initialTracks.length} songs',
                      style: CollectionStyle.meta(size: 13.5, alpha: 0.55),
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
