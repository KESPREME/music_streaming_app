// lib/services/lyrics/lyrics_query.dart
// A track name, as a lyrics database would have indexed it.
//
// Port of `LyricsQuery.kt:26-59`.
//
// Every source but SimpMusic is asked for a NAME, and the name this app has is
// YouTube's, which is not the name anyone catalogued. "Dracula (feat. JENNIE)"
// is filed by Apple, LRCLIB and everyone else as "Dracula", and asked for
// verbatim it misses all of them - which is how a track ends up answered by
// whichever source happened to clean the title on its own, regardless of the
// order the listener put their sources in.
//
// WHAT IS TAKEN OFF, AND WHAT IS DELIBERATELY LEFT ON
//
// Only credits and packaging: who else is on the record, and how the upload was
// labelled. Those are not part of the recording's name anywhere.
//
// Anything that names a DIFFERENT recording stays - "(Remix)", "(Acoustic)",
// "(Live)", "(Remastered 2011)", "(Sped Up)". They look like the same kind of
// bracket and are the opposite: stripping them turns a search for one recording
// into a search for another, and the lyrics that come back are confidently
// wrong rather than merely missing. A miss is recoverable; the wrong words
// scrolling in time with the right song is not.

final RegExp _whitespace = RegExp(r'\s+');

final List<RegExp> _credits = <RegExp>[
  // Bracketed credits: (feat. X), [ft. X], (with X).
  RegExp(r'\s*[(\[]\s*(feat|ft|featuring|with)\b[^)\]]*[)\]]',
      caseSensitive: false),
  // The same, unbracketed and running to the end of the title.
  RegExp(r'\s+(feat|ft|featuring)\.?\s+.*$', caseSensitive: false),
  // How the upload was labelled, not what was recorded.
  RegExp(
    r'\s*[(\[]\s*(official\s*)?(music\s*)?'
    r'(video|audio|visuali[sz]er|lyrics?\s*video|lyrics?|m/?v|hd|hq|4k|full\s*song)'
    r'\s*[)\]]',
    caseSensitive: false,
  ),
  RegExp(r'\s*[(\[]\s*official\s*[)\]]', caseSensitive: false),
];

/// [raw] with credits and upload packaging removed.
String forLyricsSearch(String raw) {
  var name = raw;
  for (final pattern in _credits) {
    name = name.replaceAll(pattern, ' ');
  }
  name = name.replaceAll(_whitespace, ' ').trim();
  // Trailing separators left behind by a removed credit.
  name = name.replaceAll(RegExp(r'[,\-\u2013\u2014\s]+$'), '').trim();
  // A title that was ONLY packaging is no title at all; better to ask with what
  // we were given than with nothing.
  return name.isEmpty ? raw.trim() : name;
}

/// Trims " - Topic" off an auto-generated channel name.
///
/// YouTube's own artist channels for licensed music are named this way, and it
/// reaches the player as the artist on anything played from one.
String artistForLyricsSearch(String raw) {
  var artist = raw;
  const suffix = ' - Topic';
  if (artist.endsWith(suffix)) {
    artist = artist.substring(0, artist.length - suffix.length);
  }
  artist = artist.trim();
  return artist.isEmpty ? raw.trim() : artist;
}
