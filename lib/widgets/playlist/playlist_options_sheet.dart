// lib/widgets/playlist/playlist_options_sheet.dart
//
// Touch-and-hold on one of the listener's OWN playlists (Home, the Library). The same
// sheet as an album's - cover, Play, Shuffle, Play next, Add to queue, Add to a
// playlist..., Download - with the things only a playlist of yours has: Pin to top,
// Edit details, and Delete (with Undo). The old Library menu offered Rename and
// Delete and nothing else, not even Play.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../collection/collection_kit.dart';
import '../collection_options_sheet.dart';
import 'playlist_cover.dart';
import 'playlist_edit_sheet.dart';

/// "3 songs" / "1 song" / "Empty".
String playlistSongsText(Playlist p) {
  final n = p.tracks.length;
  return n == 0 ? 'Empty' : (n == 1 ? '1 song' : '$n songs');
}

/// The first artwork of [p] that is a web link (the sheet's backdrop wash).
String _washFor(Playlist p) {
  if (p.imageUrl.startsWith('http')) return p.imageUrl;
  for (final t in p.tracks) {
    if (t.albumArtUrl.startsWith('http')) return t.albumArtUrl;
  }
  return '';
}

/// Plays [p] from the first (or a shuffled) song and records that it was played, the
/// way the Playlists screen does.
Future<void> playUserPlaylist(MusicProvider provider, Playlist p, List<Track> tracks, {bool shuffle = false}) async {
  if (tracks.isEmpty) return;
  final list = List<Track>.of(tracks);
  if (shuffle) {
    list.shuffle();
    // Never open a shuffle on the song that is already playing.
    if (list.length > 1 && list.first.id == provider.currentTrack?.id) {
      list.add(list.removeAt(0));
    }
  }
  provider.markPlaylistPlayed(p.id);
  await provider.playTrack(list.first, playlistTracks: list, playlistId: p.id);
}

Future<void> showUserPlaylistSheet(BuildContext context, Playlist playlist) {
  final provider = Provider.of<MusicProvider>(context, listen: false);
  List<Track> current() => List<Track>.of(provider.playlistById(playlist.id)?.tracks ?? playlist.tracks);

  return showCollectionOptionsSheet(
    context,
    title: playlist.name,
    subtitle: 'Playlist \u00b7 ${playlistSongsText(playlist)}',
    artworkUrl: _washFor(playlist),
    // A playlist of yours has no public link to share.
    collectionId: '',
    cover: PlaylistCover(playlist: playlist, size: 64, radius: 12),
    emptyMessage: 'This playlist is empty. Add songs to it first.',
    loadTracks: () async => current(),
    // Shuffle arrives already shuffled from the sheet; Play arrives in the playlist's order.
    play: (mp, tracks) => playUserPlaylist(mp, playlist, tracks),
    extraRows: [
      CollectionSheetRow(
        icon: playlist.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
        label: playlist.pinned ? 'Unpin' : 'Pin to top',
        onTap: (c) async => c.provider.setPlaylistPinned(playlist.id, !playlist.pinned),
      ),
      CollectionSheetRow(
        icon: Icons.edit_rounded,
        label: 'Edit details',
        onTap: (c) async {
          // After the sheet's own exit, like every chained sheet.
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (!c.host.mounted) return;
          await showPlaylistEditSheet(c.host, existing: c.provider.playlistById(playlist.id) ?? playlist);
        },
      ),
    ],
    dangerRows: [
      CollectionSheetRow(
        icon: Icons.delete_outline_rounded,
        label: 'Delete playlist',
        destructive: true,
        onTap: (c) async {
          final removed = c.provider.deletePlaylistWithUndo(playlist.id);
          if (removed == null || !c.host.mounted) return;
          HapticFeedback.mediumImpact();
          showCollectionToast(
            c.host,
            'Deleted "${playlist.name}"',
            icon: Icons.delete_outline_rounded,
            action: SnackBarAction(
              label: 'Undo',
              textColor: CollectionStyle.accent,
              onPressed: () => c.provider.restorePlaylist(removed),
            ),
          );
        },
      ),
    ],
  );
}
