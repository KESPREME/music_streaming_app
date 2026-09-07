import 'track.dart';

/// Item in a horizontal carousel shelf on an artist or browse page (BitChord parity).
class DetailShelfItem {
  final String title;
  final String subtitle;
  final String browseId;
  final String imageUrl;
  final String type; // 'album', 'single', 'playlist', 'artist'
  final List<String>? collageThumbnails;

  const DetailShelfItem({
    required this.title,
    required this.subtitle,
    required this.browseId,
    required this.imageUrl,
    this.type = 'album',
    this.collageThumbnails,
  });
}

/// A horizontal section/shelf on an artist page (Albums, Singles & EPs, Featured on, Playlists, Fans might also like).
class DetailShelf {
  final String title;
  final List<DetailShelfItem> items;

  const DetailShelf({
    required this.title,
    required this.items,
  });
}

/// Rich Artist Page Data matching BitChord ArtistPage and InnertubeParser.
class ArtistDetailData {
  final String name;
  final String heroImageUrl;
  final String? subscriberCountText;
  final String? monthlyListenerCount;
  final String? description;
  final List<Track> topSongs;
  final List<DetailShelf> shelves;

  const ArtistDetailData({
    required this.name,
    required this.heroImageUrl,
    this.subscriberCountText,
    this.monthlyListenerCount,
    this.description,
    this.topSongs = const [],
    this.shelves = const [],
  });
}

/// Rich Album Page Data matching BitChord DetailPage and InnertubeParser.
class AlbumDetailData {
  final String title;
  final String artistName;
  final String? artistBrowseId;
  final String? year;
  final int? trackCount;
  final String coverUrl;
  final String? description;
  final List<Track> tracks;

  const AlbumDetailData({
    required this.title,
    required this.artistName,
    this.artistBrowseId,
    this.year,
    this.trackCount,
    required this.coverUrl,
    this.description,
    this.tracks = const [],
  });
}

/// Rich Playlist Page Data matching BitChord DetailPage and InnertubeParser.
class PlaylistDetailData {
  final String title;
  final String curatorName;
  final String? viewsText;
  final int? trackCount;
  final String coverUrl;
  final List<String>? collageThumbnails;
  final String? description;
  final List<Track> tracks;
  final List<Track> suggestedTracks;

  const PlaylistDetailData({
    required this.title,
    required this.curatorName,
    this.viewsText,
    this.trackCount,
    required this.coverUrl,
    this.collageThumbnails,
    this.description,
    this.tracks = const [],
    this.suggestedTracks = const [],
  });
}
