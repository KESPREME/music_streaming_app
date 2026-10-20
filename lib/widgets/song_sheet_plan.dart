// lib/widgets/song_sheet_plan.dart
//
// WHAT A SONG'S OPTIONS SHEET OFFERS, DEPENDING ON WHERE IT WAS OPENED.
//
// The sheet used to be one flat list of up to thirteen rows for every origin, and
// most of them did nothing useful at most places: "Sleep Timer" on a Home card,
// "Song Info" on a search result, "Download" for a file already on the phone,
// "Go to album" on the album you are looking at. The rule the reference apps
// follow is that a row appears only if it can do something useful HERE.
//
// This file is the rule, as pure data: no widgets, so the whole matrix is a table
// test (test/song_sheet_plan_test.dart). The sheet draws whatever the plan says.

import '../models/track.dart';

/// Where the sheet was opened from.
enum SongSheetOrigin {
  /// Resolve from the other arguments (a playlist id, the queue flag, a local file).
  auto,

  /// An unknown caller: everything that could apply, as before. The old tests and
  /// any caller nobody has classified yet land here, so nothing regresses.
  generic,

  // Discovery: the listener has not decided to keep this song yet.
  home,
  search,
  explore,

  // The listener's own music.
  liked,
  downloads,
  device,
  history,
  playlist,
  remotePlaylist,

  // Pages about the thing the song belongs to.
  album,
  artist,

  // The player.
  nowPlaying,
  lyrics,
  queue,
}

/// One thing the sheet can do.
enum SongAction {
  playNext,
  addToQueue,
  download,
  removeDownload,
  share,
  addToPlaylist,
  goToAlbum,
  goToArtist,
  code,
  songInfo,
  sleepTimer,
  notInterested,
  removeFromQueue,
  removeFromPlaylist,
  removeFromHistory,
}

/// The sheet's layout: four quick tiles, then groups of rows.
class SongSheetPlan {
  const SongSheetPlan({
    required this.tiles,
    required this.library,
    required this.navigate,
    required this.more,
    required this.danger,
  });

  /// Up to four glass tiles across the top.
  final List<SongAction> tiles;

  /// Keeping the song: Add to a playlist.
  final List<SongAction> library;

  /// Going somewhere: Go to album / artist.
  final List<SongAction> navigate;

  /// Everything else.
  final List<SongAction> more;

  /// Destructive, last, in their own red group.
  final List<SongAction> danger;

  Iterable<SongAction> get all => [...tiles, ...library, ...navigate, ...more, ...danger];

  bool has(SongAction a) => all.contains(a);
}

/// A tag the source did not fill in.
bool songTagIsUnknown(String value) {
  final v = value.trim().toLowerCase();
  return v.isEmpty || v == 'unknown album' || v == 'unknown artist' || v == '<unknown>' || v == 'unknown';
}

/// The plan for [track] opened from [origin] (never [SongSheetOrigin.auto]: resolve it first).
///
/// [isCurrent] - this is the song that is playing. [inUpNext] - it is actually in the
/// queue (the queue header opens the sheet for the PLAYING song, whose "remove from
/// queue" would be a no-op). [hasDislike] - the origin supplied a "not interested"
/// callback (Explore). [hasPlaylistId] - it is inside one of the listener's playlists.
/// [isHistory] - it is in a history list.
SongSheetPlan planSongSheet({
  required SongSheetOrigin origin,
  required Track track,
  bool isCurrent = false,
  bool inUpNext = false,
  bool hasDislike = false,
  bool hasPlaylistId = false,
  bool isHistory = false,
}) {
  assert(origin != SongSheetOrigin.auto, 'resolve auto before planning');
  final local = track.source == 'local';
  final isPlayer = origin == SongSheetOrigin.nowPlaying || origin == SongSheetOrigin.lyrics;
  final discovery = origin == SongSheetOrigin.home ||
      origin == SongSheetOrigin.search ||
      origin == SongSheetOrigin.explore;

  final tiles = <SongAction>[
    // Playing already, or being looked at in the player: "next" and "queue" are
    // about OTHER songs' order.
    if (!isCurrent && !isPlayer) SongAction.playNext,
    if (!isPlayer) SongAction.addToQueue,
    if (!local) origin == SongSheetOrigin.downloads ? SongAction.removeDownload : SongAction.download,
    // A file on this phone has no link anyone else can open.
    if (!local) SongAction.share,
  ];

  final hasAlbum = !songTagIsUnknown(track.albumName);
  final hasArtist = !songTagIsUnknown(track.artistName);

  return SongSheetPlan(
    tiles: tiles,
    library: const [SongAction.addToPlaylist],
    navigate: [
      // A local file's tags would be searched on YouTube Music: wrong page, or none.
      if (hasAlbum && !local && origin != SongSheetOrigin.album) SongAction.goToAlbum,
      if (hasArtist && !local && origin != SongSheetOrigin.artist) SongAction.goToArtist,
    ],
    more: [
      if (!local &&
          origin != SongSheetOrigin.downloads &&
          origin != SongSheetOrigin.history &&
          origin != SongSheetOrigin.device)
        SongAction.code,
      // Inspecting a song is a library / player thing, not a "what is this" on Home.
      if (!discovery) SongAction.songInfo,
      if (isPlayer || origin == SongSheetOrigin.queue || origin == SongSheetOrigin.generic)
        SongAction.sleepTimer,
      if (hasDislike) SongAction.notInterested,
    ],
    danger: [
      if (origin == SongSheetOrigin.queue && inUpNext) SongAction.removeFromQueue,
      if (hasPlaylistId) SongAction.removeFromPlaylist,
      if (isHistory) SongAction.removeFromHistory,
    ],
  );
}
