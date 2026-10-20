import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../../services/home/home_models.dart';

/// Albums and playlists on Home: what they are, and how to get their songs.
///
/// A card is "a collection" when the feed typed it as an album or a playlist. It
/// has no videoId of its own, so the song pipeline cannot play it directly: its
/// songs have to be fetched first. That is what these helpers are for, and why
/// the card needs a play affordance and an options sheet of its own rather than
/// the song ones.

/// True for album and playlist cards.
bool homeItemIsCollection(HomeItem item) =>
    item.contentType == HomeContentType.album || item.contentType == HomeContentType.playlist;

/// The id the collection's page and song fetch use.
String homeCollectionId(HomeItem item) {
  final browse = item.browseId;
  return (browse != null && browse.isNotEmpty) ? browse : item.id;
}

/// Album ids live under the album endpoints; everything else is a playlist.
bool homeCollectionIdIsAlbum(String id) => id.startsWith('MPREb_') || id.startsWith('OLAK');

/// Ids a playlist page can load. A mood or genre tile is typed as a playlist by
/// the feed but its id (`FEmusic_moods...`) opens a category, not a list of songs,
/// so it must not get a play button or a song-level menu.
bool homeCollectionIdHasSongs(String id) =>
    homeCollectionIdIsAlbum(id) ||
    id.startsWith('VL') ||
    id.startsWith('PL') ||
    id.startsWith('RD') ||
    id.startsWith('LM');

/// Whether [item] is a collection whose songs we can actually fetch.
bool homeItemHasSongs(HomeItem item) =>
    homeItemIsCollection(item) && homeCollectionIdHasSongs(homeCollectionId(item));

/// The artist to show / navigate to for a collection card, if the feed named one.
String? homeItemArtist(HomeItem item) {
  for (final a in item.artists) {
    final name = a.trim();
    if (name.isNotEmpty) return name;
  }
  return null;
}

/// The songs of a collection card. Empty (never throws) when they cannot be loaded,
/// so every caller has one failure path: say so, do not crash, do not go quiet.
Future<List<Track>> loadHomeCollectionTracks(MusicProvider provider, HomeItem item) =>
    loadCollectionTracks(provider, homeCollectionId(item));

/// The songs of the album or playlist [id] (Search results and the Library's account
/// playlists use this too). Empty - never an exception - when they cannot be loaded.
Future<List<Track>> loadCollectionTracks(MusicProvider provider, String id) async {
  if (id.isEmpty) return const [];
  try {
    if (homeCollectionIdIsAlbum(id)) {
      final page = await provider.fetchAlbumPageData(id);
      if (page.tracks.isNotEmpty) return page.tracks;
      return await provider.fetchAlbumTracks(id);
    }
    final page = await provider.fetchPlaylistPageData(id);
    if (page.tracks.isNotEmpty) return page.tracks;
    return await provider.fetchPlaylistDetails(id);
  } catch (_) {
    return const [];
  }
}
