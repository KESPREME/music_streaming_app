import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../../services/home/home_models.dart';

/// Playability contract (spec #19): identity ≠ playability. Each level
/// names the exact downstream action — no "videoId = always playable"
/// shortcut.
enum HomePlayAction {
  /// Direct song playback through the proven playTrack path.
  playSong,

  /// Video content: resolve via canonical videoId through the same song
  /// pipeline (audio stream).
  playVideo,

  /// Navigate to playlist/album detail (the app's established model for
  /// collection entities — same as Library/Moods elsewhere).
  navigateCollection,

  /// Artist → artist page.
  navigateArtist,

  /// No safe action exists.
  none,
}

/// Unified Home playback dispatcher (spec #29): every Home widget calls
/// this; no widget owns resolver/queue logic. JumpBackIn's proven path
/// (MusicProvider.playTrack with a context playlist) is THE song path —
/// all song/video shelves route through it identically.
class HomePlaybackController {
  HomePlaybackController._();

  /// Route one HomeItem. [contextPlaylist] is the shelf's track list for
  /// queue continuity. Returns the action taken (for tests/diagnostics).
  static HomePlayAction activate(
    BuildContext context,
    HomeItem item, {
    required String sectionTitle,
    List<Track>? contextPlaylist,
  }) {
    final action = actionFor(item);
    switch (action) {
      case HomePlayAction.playSong:
      case HomePlayAction.playVideo:
        final track = _toTrack(item);
        if (track == null) {
          _fail(context, item, sectionTitle, action, 'identity→Track failed');
          return HomePlayAction.none;
        }
        try {
          HapticFeedback.lightImpact();
          // ignore: use_build_context_synchronously
          context
              .read<MusicProvider>()
              .playTrack(track, playlistTracks: contextPlaylist ?? [track]);
          _success(item, sectionTitle, action, track.id);
          return action;
        } catch (e) {
          _fail(context, item, sectionTitle, action, e.toString());
          return HomePlayAction.none;
        }

      case HomePlayAction.navigateCollection:
      case HomePlayAction.navigateArtist:
      case HomePlayAction.none:
        // Navigation is performed by the widget (needs Navigator); the
        // dispatcher only classifies. Logged for the play matrix.
        if (kDebugMode) {
          debugPrint('HOME_PLAY section="$sectionTitle" item="${item.title}" '
              'type=${item.contentType.name} id=${item.id} '
              'action=${action.name} result=NAVIGATE');
        }
        return action;
    }
  }

  /// Strict playability predicate for hero/promoted surfaces (live-run
  /// fix): only true 11-char videoIds with song semantics qualify. Album
  /// (MPREb/OLAK) or playlist (VL/PL) ids must never reach playTrack —
  /// the runtime log showed exactly that failure ("Skipping non-playable
  /// track: Good Times (ID: MPREb_…)") after the fallback source
  /// mislabeled album items as songs.
  static bool isPlayableSongItem(HomeItem item) =>
      item.contentType == HomeContentType.song &&
      item.videoId != null &&
      item.videoId!.length == 11 &&
      !item.videoId!.startsWith(RegExp(r'(MPREb|OLAK|VL|PL|UC)'));

  /// Explicit routing table (spec #19/#20/#21/#22/#23/#24): content type →
  /// action. A song WITHOUT videoId is not playable (never guessed).
  static HomePlayAction actionFor(HomeItem item) {
    switch (item.contentType) {
      case HomeContentType.song:
        return isPlayableSongItem(item)
            ? HomePlayAction.playSong
            : HomePlayAction.none;
      case HomeContentType.video:
        return item.videoId != null
            ? HomePlayAction.playVideo
            : HomePlayAction.none;
      case HomeContentType.album:
      case HomeContentType.playlist:
        return item.browseId != null || item.id.isNotEmpty
            ? HomePlayAction.navigateCollection
            : HomePlayAction.none;
      case HomeContentType.artist:
        return HomePlayAction.navigateArtist;
      case HomeContentType.unknown:
        // Unknown-but-identified: if it carries a videoId it is at worst a
        // video; without one, navigation-only.
        return item.videoId != null
            ? HomePlayAction.playVideo
            : HomePlayAction.none;
    }
  }

  static Track? _toTrack(HomeItem item) {
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

  static void _success(
      HomeItem item, String section, HomePlayAction action, String id) {
    if (kDebugMode) {
      debugPrint('HOME_PLAY section="$section" item="${item.title}" '
          'type=${item.contentType.name} id=$id action=${action.name} '
          'result=SUCCESS');
    }
  }

  static void _fail(BuildContext context, HomeItem item, String section,
      HomePlayAction action, String reason) {
    if (kDebugMode) {
      debugPrint('HOME_PLAY_FAIL section="$section" item="${item.title}" '
          'type=${item.contentType.name} videoId=${item.videoId} '
          'browseId=${item.browseId} playability=${item.playability.name} '
          'action=${action.name} reason=$reason');
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not play "${item.title}"'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
