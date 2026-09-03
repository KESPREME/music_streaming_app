import '../../models/track.dart';

/// How much the pipeline trusts this candidate's provenance (spec #30).
/// Influences ranking — trusted sources can rank on their own metadata;
/// weak sources need personal relevance or popularity to surface.
enum SourceTrust { high, medium, low }

/// One candidate with the metadata the engine can legitimately use
/// (spec #4). Fields stay null when the source never provided them —
/// the engine NEVER fabricates genre/language/popularity/dates.
class RichCandidate {
  RichCandidate({
    required this.id,
    required this.title,
    required this.artists,
    required this.source,
    this.genres = const [],
    this.languages = const [],
    this.releaseYear,
    this.chartRank,
    this.chartSize,
    this.albumName,
    this.durationMs,
    this.sourceTrust = SourceTrust.medium,
    this.playlistId,
    this.artworkUrl,
    this.editorialRank,
  });
  final String id;
  final String title;

  /// Parsed artist list (spec #6) — never a joined collaboration blob.
  final List<String> artists;
  String get primaryArtist => artists.isNotEmpty ? artists.first : '';

  /// Normalized genre cluster tags (spec #52). Empty when unknown.
  final List<String> genres;

  /// ISO-ish language tags (spec #8). Empty today — YTM gives us none
  /// without login. Scaffolded so future metadata plugs in (spec #88/89).
  final List<String> languages;

  /// Release year when the source carried it (publishedText fragment).
  final int? releaseYear;

  /// Position in a trusted chart (0-based). The ONLY legitimate numeric
  /// popularity signal we receive — chart order. Normalized via
  /// [popularityFromChartRank].
  final int? chartRank;
  final int? chartSize;

  final String? albumName;
  final int? durationMs;

  /// Provenance tag ('local_history', 'local_favorites', 'chart',
  /// 'native_home', 'search_followup', 'new_release').
  final String source;
  final SourceTrust sourceTrust;
  final String? playlistId;

  /// Cover URL — carried through the pipeline so UI never gets blank art.
  final String? artworkUrl;

  /// Position within the source pool (shelf/chart order). Editorial
  /// order = trusted popularity proxy → deterministic tiebreak BEFORE
  /// alphabetical id (a shelf is curated, not a string sort).
  final int? editorialRank;

  /// Normalized popularity 0-1 from chart position; null when unranked.
  double? get popularity => popularityFromChartRank(chartRank, chartSize);

  /// An origin is not a recommendation (spec #31): native candidates
  /// carry medium trust until personal/popularity evidence exists.
  static SourceTrust trustFor(String source) {
    switch (source) {
      case 'chart':
      case 'local_history':
      case 'local_favorites':
      case 'search_followup':
        return SourceTrust.high;
      case 'native_home':
        return SourceTrust.medium;
      default:
        return SourceTrust.low;
    }
  }

  factory RichCandidate.fromTrack({
    required String trackId,
    required String title,
    required String artistName,
    required String source,
    String? genre,
    String? albumName,
    int? durationMs,
    int? chartRank,
    int? chartSize,
    int? releaseYear,
    String? playlistId,
    String? albumArt,
    int? editorialRank,
  }) {
    return RichCandidate(
      id: trackId,
      title: title,
      artists: parseArtists(artistName),
      genres: [if (normalizeGenre(genre) != null) normalizeGenre(genre)!],
      source: source,
      sourceTrust: trustFor(source),
      albumName: (albumName != null && albumName.isNotEmpty) ? albumName : null,
      durationMs: durationMs,
      chartRank: chartRank,
      chartSize: chartSize,
      releaseYear: releaseYear,
      playlistId: playlistId,
      artworkUrl: (albumArt != null && albumArt.isNotEmpty) ? albumArt : null,
      editorialRank: editorialRank,
    );
  }
}

/// One metadata-junk run (durations, view counts) that must never be an
/// artist. Shared by every intake path.
final RegExp _junkDuration = RegExp(r'^\d{1,3}(:\d{2}){1,2}$');
final RegExp _junkCount = RegExp(
    r'^[\d,.]+\s*[KMB]?\s*(plays?|views?|streams?|listeners?|monthly listeners?)$',
    caseSensitive: false);
bool _isJunkRun(String s) =>
    _junkDuration.hasMatch(s) || _junkCount.hasMatch(s);

/// Split a display artist string into distinct artists (spec #6).
/// Conservative: comma-only, trim, cap 4, keep "&"/"x" joined —
/// "Simon & Garfunkel" and "A x B" must not become fake solo acts.
/// Metadata junk ("3:44", "222M plays") is dropped — live log showed
/// "Lynyrd Skynyrd, 222M plays" surfacing as a display artist.
List<String> parseArtists(String artistName) {
  final raw = artistName.trim();
  if (raw.isEmpty) return const [];
  return raw
      .split(',')
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty && !_isJunkRun(a))
      .take(4)
      .toList(growable: false);
}

/// Normalize a genre/mood label into a cluster tag (spec #7/#52).
/// Small curated map over mood-title vocabulary YTM actually serves;
/// unknown labels pass through lowercased (never dropped, never invented).
/// Returns null only for empty input.
String? normalizeGenre(String? genre) {
  if (genre == null) return null;
  final g = genre.trim().toLowerCase();
  if (g.isEmpty) return null;
  const clusters = <String, String>{
    'bollywood': 'bollywood',
    'tollywood': 'film',
    'kollywood': 'film',
    'hip-hop': 'hip-hop',
    'hip hop': 'hip-hop',
    'rap': 'hip-hop',
    'r&b': 'r&b',
    'rnb': 'r&b',
    'indie pop': 'indie-pop',
    'indie': 'indie-pop',
    'devotional & spiritual': 'devotional',
    'devotional': 'devotional',
    'edm / electronic': 'electronic',
    'electronic': 'electronic',
    'lo-fi': 'lofi',
    'lofi': 'lofi',
    'romance': 'romance',
    'chill': 'chill',
    'focus': 'focus',
    'workout': 'workout',
    'sleep': 'sleep',
    'party': 'party',
    'pop': 'pop',
    'rock': 'rock',
  };
  return clusters[g] ?? g;
}

/// Chart position → normalized popularity (spec #19/#27). Rank 1 → 1.0,
/// linear to last rank. Unknown → null: absence of evidence is not a
/// middling score.
double? popularityFromChartRank(int? rank, int? size) {
  if (rank == null || size == null || size <= 0) return null;
  if (rank < 0 || rank >= size) return null;
  return 1.0 - (rank / size);
}
