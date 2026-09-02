import '../../models/track.dart';
import '../../services/home/home_models.dart';

/// Presentation layer for the composed HomeFeed (spec #3/#4): content
/// semantics → presentation semantics → geometry. The data model stays
/// content/source-oriented; this classifier+planner is a separate concern
/// so HomeScreen renders instead of deciding.

/// Semantic type derived deterministically from section title, item
/// content types, and provenance (spec #5). UNKNOWN is safe — it still
/// gets a presentation.
enum HomeSemanticType {
  topPicks,
  recentlyPlayed,
  newReleases,
  musicVideos,
  episodes,
  trending,
  playlists,
  moods,
  chart,
  artists,
  albums,
  unknown,
}

/// Layout families with their geometry contracts (spec #17 matrix).
enum HomeLayoutKind {
  heroCarousel, // ~4:5 portrait, 86-92% width, peeking
  squareRail, // 1:1 rail with peek
  squareGrid, // 1:1 2-col grid
  portraitRail, // 4:5 rail with peek
  landscapeRail16x9, // video/episode cards
  compactList, // vertical rows, thumbnail ~16:9 small
  artistRail, // 1:1 circles
  playlistRail, // landscape covers
}

/// One resolved presentation for a section — the only thing the UI consumes.
class HomePresentationModel {
  const HomePresentationModel({
    required this.semanticType,
    required this.layoutKind,
    required this.aspectRatio,
    this.cardWidthFactor = 0.42,
    this.maxLines = 1,
    this.showOverlay = false,
  });

  final HomeSemanticType semanticType;
  final HomeLayoutKind layoutKind;

  /// Target artwork aspect ratio (w/h) per spec #17 matrix.
  final double aspectRatio;

  /// Fraction of available content width for rail cards.
  final double cardWidthFactor;

  /// Title line budget: 1 default, 2 for hero (spec #25).
  final int maxLines;

  /// Hero/editorial overlay vs text-below-artwork (spec #27).
  final bool showOverlay;

  /// Zero-invisible-space (spec #31): does this layout adapt when the
  /// section has fewer items than a full row?
  bool get adaptsToItemCount =>
      layoutKind == HomeLayoutKind.squareGrid ||
      layoutKind == HomeLayoutKind.compactList;
}

/// Deterministic classifier (spec #5): native title → semantic type.
/// Never fabricates: 'Picked for you' only when the source title actually
/// says so; 'Rain Therapy' stays a mood, never re-titled.
HomeSemanticType classifySection(HomeSection section) {
  final title = section.title.toLowerCase().trim();
  final types = section.items.map((i) => i.contentType).toSet();

  // Title-driven semantics (native titles are authoritative) — checked
  // BEFORE the video-dominant branch so 'Popular episodes' (whose items
  // are video-typed) classifies as episodes, not music videos.
  if (title.contains('top pick') ||
      title.contains('picked for you') ||
      title.contains('recommended')) {
    return HomeSemanticType.topPicks;
  }
  if (title.contains('recent') ||
      title.contains('jump back') ||
      title.contains('listen again') ||
      title.contains('history')) {
    return HomeSemanticType.recentlyPlayed;
  }
  if (title.contains('new release') || title.contains('new release')) {
    return HomeSemanticType.newReleases;
  }
  if (title.contains('episode') || title.contains('podcast')) {
    return HomeSemanticType.episodes;
  }
  if (title.contains('trending') ||
      title.contains('chart') ||
      title.contains('hit')) {
    return HomeSemanticType.trending;
  }
  if (title.contains('mood') ||
      title.contains('vibe') ||
      title.contains('therapy') ||
      title.contains('morning') ||
      title.contains('focus') ||
      title.contains('workout') ||
      title.contains('romantic') ||
      title.contains('chill')) {
    return HomeSemanticType.moods;
  }
  if (title.contains('playlist')) {
    return HomeSemanticType.playlists;
  }
  if (title.contains('album') || title.contains('release')) {
    return HomeSemanticType.albums;
  }
  if (title.contains('artist')) {
    return HomeSemanticType.artists;
  }

  // Video-dominant shelves (after explicit episode/podcast titles).
  if (types.contains(HomeContentType.video) ||
      title.contains('video') ||
      title.contains('visualizer')) {
    return HomeSemanticType.musicVideos;
  }

  // Item-type-driven fallback when the title is generic.
  if (types.length == 1) {
    switch (types.first) {
      case HomeContentType.artist:
        return HomeSemanticType.artists;
      case HomeContentType.album:
        return HomeSemanticType.albums;
      case HomeContentType.playlist:
        return HomeSemanticType.playlists;
      case HomeContentType.video:
        return HomeSemanticType.musicVideos;
      default:
        break;
    }
  }

  // Provenance fallback.
  if (section.provenance == 'chart') return HomeSemanticType.trending;
  if (section.provenance == 'new_release') {
    return HomeSemanticType.newReleases;
  }

  return HomeSemanticType.unknown;
}

/// Presentation planner (spec #4/#15): semantic type + item count →
/// geometry. Deterministic; adapts to actual item count (spec #31).
HomePresentationModel planPresentation(HomeSection section) {
  final semantic = classifySection(section);
  final count = section.items.length;

  switch (semantic) {
    case HomeSemanticType.topPicks:
      return const HomePresentationModel(
        semanticType: HomeSemanticType.topPicks,
        layoutKind: HomeLayoutKind.heroCarousel,
        aspectRatio: 4 / 5,
        cardWidthFactor: 0.88,
        maxLines: 2,
        showOverlay: true,
      );

    case HomeSemanticType.recentlyPlayed:
      // Dense square grid for 2+; single item → compact square (spec #8:
      // 1 item must not reserve an empty second column).
      return HomePresentationModel(
        semanticType: HomeSemanticType.recentlyPlayed,
        layoutKind:
            count == 1 ? HomeLayoutKind.squareRail : HomeLayoutKind.squareGrid,
        aspectRatio: 1.0,
        cardWidthFactor: 0.42,
      );

    case HomeSemanticType.newReleases:
    case HomeSemanticType.albums:
      return const HomePresentationModel(
        semanticType: HomeSemanticType.newReleases,
        layoutKind: HomeLayoutKind.squareGrid,
        aspectRatio: 1.0,
        cardWidthFactor: 0.42,
      );

    case HomeSemanticType.musicVideos:
    case HomeSemanticType.episodes:
      return HomePresentationModel(
        semanticType: semantic,
        layoutKind: HomeLayoutKind.landscapeRail16x9,
        aspectRatio: 16 / 9,
        cardWidthFactor: 0.62,
      );

    case HomeSemanticType.trending:
    case HomeSemanticType.chart:
      // Dense compact rows (spec #12) — much closer to Muzo's editorial
      // rhythm than another giant card rail.
      return const HomePresentationModel(
        semanticType: HomeSemanticType.trending,
        layoutKind: HomeLayoutKind.compactList,
        aspectRatio: 16 / 9,
        cardWidthFactor: 0.16,
      );

    case HomeSemanticType.moods:
    case HomeSemanticType.playlists:
      // Curated editorial: portrait-ish cards (spec #14), never destructively
      // cropped 16:9.
      return const HomePresentationModel(
        semanticType: HomeSemanticType.moods,
        layoutKind: HomeLayoutKind.playlistRail,
        aspectRatio: 1.0,
        cardWidthFactor: 0.38,
      );

    case HomeSemanticType.artists:
      return const HomePresentationModel(
        semanticType: HomeSemanticType.artists,
        layoutKind: HomeLayoutKind.artistRail,
        aspectRatio: 1.0,
        cardWidthFactor: 0.28,
      );

    case HomeSemanticType.unknown:
      // Safe generic (spec #5): square rail with peek.
      return const HomePresentationModel(
        semanticType: HomeSemanticType.unknown,
        layoutKind: HomeLayoutKind.squareRail,
        aspectRatio: 1.0,
        cardWidthFactor: 0.42,
      );
  }
}

/// Converts a HomeItem to a display Track when it has playback identity.
Track? homeItemToTrack(HomeItem item) {
  final videoId = item.videoId;
  if (videoId == null) return null;
  return Track(
    id: videoId,
    trackName: item.title,
    artistName:
        item.artists.isNotEmpty ? item.artists.join(', ') : item.subtitle,
    albumName: '',
    previewUrl: '',
    albumArt: item.artworkUrl,
    source: 'youtube',
  );
}

// touch
