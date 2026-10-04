/// What a track shows when nothing named its artist.
///
/// This is a display placeholder, not a name: it exists so a row has something
/// to render. It must never be mistaken for a real artist - not by a track
/// parser resolving a credit, and not by a screen deriving a header from the
/// first row it has.
const String kUnknownArtist = 'Unknown Artist';

/// Resolves the artist name a track should carry.
///
/// Order matters, and mirrors the reference implementation:
///
/// 1. The row's own credit, when it names one. A compilation, a remix, or a
///    featuring credit knows its own artist and keeps it.
/// 2. The page-level credit, when the row named nothing. A release's rows do not
///    name the artist individually - only its header does - so without this
///    every track on an album reads [kUnknownArtist] while the header above them
///    reads correctly.
/// 3. [kUnknownArtist], only when neither exists. There is genuinely nothing to
///    show, and saying so beats showing a blank.
///
/// Only album pages have a page-level credit to offer, so [pageCredit] is left
/// null everywhere else. That is what keeps a playlist's curator, or an
/// artist's channel name, from being stamped onto a track list.
String resolveTrackArtistCredit({
  required String rowArtist,
  String? pageCredit,
}) {
  final row = rowArtist.trim();
  if (row.isNotEmpty && row != kUnknownArtist) return row;

  final page = (pageCredit ?? '').trim();
  if (page.isNotEmpty && page != kUnknownArtist) return page;

  return kUnknownArtist;
}

/// Whether a name is a real artist rather than [kUnknownArtist] or blank.
///
/// Screens use this to decide if a name is worth displaying or offering as a
/// tap target.
bool isUsableArtistName(String? name) {
  final trimmed = (name ?? '').trim();
  return trimmed.isNotEmpty && trimmed != kUnknownArtist;
}
