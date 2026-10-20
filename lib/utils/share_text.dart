import '../models/track.dart';

final RegExp _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// A link a friend can open for [track], or null when there is none worth sending.
///
/// The song sheet used to share `previewUrl`, which is empty for every YouTube
/// track: the message ended in a blank line. A YouTube id is enough to build the
/// watch link; a local file's "link" is a path on this phone and means nothing to
/// anyone else.
String? songShareLink(Track track) {
  if (track.source == 'local') return null;
  if (_videoId.hasMatch(track.id)) return 'https://music.youtube.com/watch?v=${track.id}';
  final preview = track.previewUrl.trim();
  if (preview.startsWith('http://') || preview.startsWith('https://')) return preview;
  return null;
}

/// "Title by Artist" and, when there is one, a link on the next line.
String songShareText(Track track) {
  final link = songShareLink(track);
  final head = 'Check out this track: ${track.trackName} by ${track.artistName}';
  return link == null ? head : '$head\n$link';
}

/// Link for a YouTube Music collection id, or null when the id is not one.
///
/// Albums (`MPREb_...`, `OLAK...`) live under /browse; playlists under
/// /playlist?list= without the browse-only `VL` prefix.
String? collectionShareLink(String id) {
  final clean = id.trim();
  if (clean.isEmpty) return null;
  if (clean.startsWith('MPREb_') || clean.startsWith('OLAK')) {
    return 'https://music.youtube.com/browse/$clean';
  }
  if (clean.startsWith('VL')) return 'https://music.youtube.com/playlist?list=${clean.substring(2)}';
  if (clean.startsWith('PL') || clean.startsWith('RDCLAK') || clean.startsWith('RD') || clean.startsWith('LM')) {
    return 'https://music.youtube.com/playlist?list=$clean';
  }
  return null;
}

/// "Title by Artist" plus the collection link when the id gives one.
String collectionShareText({required String title, String? artist, required String id}) {
  final who = (artist == null || artist.trim().isEmpty) ? '' : ' by ${artist.trim()}';
  final link = collectionShareLink(id);
  return link == null ? '$title$who' : '$title$who\n$link';
}
