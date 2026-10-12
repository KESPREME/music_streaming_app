// lib/services/lyrics/lrc_red_provider.dart
// lrc.red - Apple Music syllable timings, filed by recording (ISRC).
//
// Port of `LrcRed.kt`.
//
// Every document lives at `https://lrc.red/s/{ISRC}.ttml`, so a track whose
// recording is already known costs ONE request and cannot come back as the
// wrong edit. Without an ISRC, lrc.red's own free-text search is asked
// (`/search.json?q=title artist`) and its hits are MATCHED here rather than
// trusted in order: the search ranks "Bohemian Rhapsody (Operatic Section /
// 2011 A Cappella Mix)" above the song itself. See [LrcRedProvider.best].
//
// WHAT THIS REPLACES
//
// The previous version required the search answer to be a JSON array of
// `{id, trackName}` and fetched `/s/{id}.ttml`. The real answer is
// `{"hits":[{"isrc","title","artist","album","year","duration"}],"next":..}`
// and documents are keyed by ISRC, so it matched nothing and fetched nothing.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/lyrics_entry.dart';
import 'apple_lyrics_common.dart';
import 'lyrics_url.dart';

/// One row of lrc.red's search answer.
class LrcRedHit {
  const LrcRedHit({
    this.isrc,
    this.title,
    this.artist,
    this.album,
    this.year,
    this.duration,
  });

  /// Reads one `hits[]` element; tolerant of absent or oddly-typed fields.
  factory LrcRedHit.fromJson(Map<dynamic, dynamic> json) {
    String? text(Object? v) => v is String ? v : null;
    return LrcRedHit(
      isrc: text(json['isrc']),
      title: text(json['title']),
      artist: text(json['artist']),
      album: text(json['album']),
      year: json['year'] is num ? (json['year'] as num).toInt() : null,
      duration:
          json['duration'] is num ? (json['duration'] as num).toDouble() : null,
    );
  }

  final String? isrc;
  final String? title;
  final String? artist;
  final String? album;
  final int? year;

  /// Seconds, fractional (`237.8`).
  final double? duration;

  @override
  String toString() => 'LrcRedHit($isrc, "$title" - "$artist", ${duration}s)';
}

class LrcRedProvider extends AppleLyricsSource {
  LrcRedProvider({super.http});

  static const String _base = 'https://lrc.red/';

  /// How far a hit's length may be from the playing track's. YouTube reports
  /// whole seconds, and lrc.red lists the 2011 remaster of "Bohemian Rhapsody"
  /// at 356.5 s against 352.0 s for the live cut - close enough that the
  /// version words in [best] have to do most of the work, not this.
  static const double durationToleranceSeconds = 3.0;

  /// `CC-XXX-YY-NNNNN` without the dashes - and nothing else goes into a path.
  static final RegExp _isrc = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$');

  /// [isrc] trimmed and upper-cased, or null when it is not a well-formed ISRC.
  static String? normalizeIsrc(String? isrc) {
    final value = isrc?.trim().toUpperCase();
    return value != null && _isrc.hasMatch(value) ? value : null;
  }

  /// Where the document for [isrc] lives, or null for a malformed code.
  static String? documentUrl(String? isrc) {
    final value = normalizeIsrc(isrc);
    return value == null ? null : '${_base}s/$value.ttml';
  }

  /// Syllable-synced lyrics for [query], or null when this host has none.
  ///
  /// A known ISRC ([AppleLyricsQuery.isrc]) is tried first. A recording lrc.red
  /// does not have - a local file whose tag names a release it never indexed -
  /// still gets a search, because the same song is often catalogued under a
  /// sibling release's code.
  ///
  /// [get] replaces the document download (see [DocumentFetcher]). [onIsrc] is
  /// told the ISRC of the hit a SEARCH settled on, before its document is
  /// fetched, so a failed download still shares what was learned with the other
  /// sources.
  Future<List<LyricsEntry>?> getLyrics(
    AppleLyricsQuery query, {
    DocumentFetcher? get,
    void Function(String isrc)? onIsrc,
  }) async {
    final known = documentUrl(query.isrc);
    if (known != null) {
      final entries = await fetchTtml(known, get: get);
      if (entries != null) return entries;
    }

    final hits = await search(query.title, query.artist);
    final hit = best(hits, query.title, query.artist, query.durationMs);
    if (hit == null) return null;

    final isrc = normalizeIsrc(hit.isrc);
    if (isrc == null) return null; // best() guarantees one; belt and braces
    onIsrc?.call(isrc);

    final found = documentUrl(isrc);
    // Already tried: a second download of the same file is a second failure.
    if (found == null || found == known) return null;
    return fetchTtml(found, get: get);
  }

  /// lrc.red's search for `title artist`, in the order it ranked them.
  Future<List<LrcRedHit>> search(String title, String artist) async {
    final url = buildLyricsUrl(
      '${_base}search.json',
      {'q': '$title $artist'.trim()},
    );
    final body = await lyricsHttp.getText(url);
    if (body == null) return const <LrcRedHit>[];
    final hits = parseSearch(body);
    if (kDebugMode) {
      debugPrint('LrcRedProvider: search returned ${hits.length} hits');
    }
    return hits;
  }

  /// The hits in a search answer. Accepts the `{"hits":[...]}` envelope and,
  /// defensively, a bare array of the same rows.
  static List<LrcRedHit> parseSearch(String body) {
    try {
      final decoded = jsonDecode(body);
      final rows = decoded is Map ? decoded['hits'] : decoded;
      if (rows is! List) return const <LrcRedHit>[];
      return <LrcRedHit>[
        for (final row in rows)
          if (row is Map) LrcRedHit.fromJson(row),
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('LrcRedProvider: search unreadable: $e');
      return const <LrcRedHit>[];
    }
  }

  // ---------------------------------------------------------------- matching

  /// The hit that is this recording, or null if none of them is sure to be.
  ///
  /// A miss here is recoverable - the sources behind this one get their turn -
  /// and the wrong words scrolling in time with the right song is not, so every
  /// test is a requirement rather than a score:
  ///
  ///  * the hit has a well-formed ISRC (it is the key to its document);
  ///  * the title, outside its brackets and any " - " suffix, is the same;
  ///  * the words that name a different recording ([versionWords]: live,
  ///    remix, acoustic...) found in the brackets and suffix are the same on
  ///    both sides - "Remastered" and "From 'Aashiqui 2'" do not count;
  ///  * at least one credited artist is shared;
  ///  * the length is within [durationToleranceSeconds], when both are known.
  ///
  /// Of the hits that pass, the closest in length wins, and the search's own
  /// rank breaks a tie. [durationMs] null or <= 0 means unknown, which counts
  /// as distance 0 rather than as a veto.
  static LrcRedHit? best(
    List<LrcRedHit> hits,
    String title,
    String artist,
    int? durationMs,
  ) {
    final wantedTitle = coreOf(title);
    final wantedVersion = versionOf(title);
    final wantedArtists = artistsOf(artist);
    final wantedSeconds = (durationMs ?? 0) / 1000.0;

    double distance(LrcRedHit hit) {
      final duration = hit.duration;
      if (durationMs == null || durationMs <= 0 || duration == null) return 0.0;
      return (duration - wantedSeconds).abs();
    }

    LrcRedHit? winner;
    var winnerDistance = double.infinity;
    for (final hit in hits) {
      final name = hit.title;
      if (name == null) continue;
      if (documentUrl(hit.isrc) == null) continue;
      if (coreOf(name) != wantedTitle) continue;
      if (!setEquals(versionOf(name), wantedVersion)) continue;
      if (wantedArtists.isNotEmpty &&
          !artistsOf(hit.artist ?? '').any(wantedArtists.contains)) {
        continue;
      }
      final d = distance(hit);
      if (d > durationToleranceSeconds) continue;
      // Strictly closer, so a tie keeps the earlier (higher-ranked) hit.
      if (d < winnerDistance) {
        winner = hit;
        winnerDistance = d;
      }
    }
    return winner;
  }

  static final RegExp _bracketed = RegExp(r'[(\[][^)\]]*[)\]]');
  static final RegExp _combiningMarks = RegExp(r'\p{Mn}+', unicode: true);
  static final RegExp _notLetterOrDigit =
      RegExp(r'[^\p{L}\p{Nd}]', unicode: true);
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _artistSeparators = RegExp(
    r'\s*(?:,|&|;|/|\s+and\s+|\s+x\s+|\s+with\s+|\s+feat\.?\s+|\s+ft\.?\s+)\s*',
    caseSensitive: false,
  );

  /// Bracket words that make it a different recording, not a different label.
  static const Set<String> versionWords = <String>{
    'live', 'remix', 'remixed', 'mix', 'acoustic', 'unplugged', 'instrumental',
    'karaoke', 'cappella', 'acapella', 'demo', 'edit', 'version', 'cover',
    'sped', 'slowed', 'reverb', 'nightcore', 'lofi', 'orchestral', 'extended',
  };

  /// "Song (Live) - 2011 Remaster" -> "song".
  @visibleForTesting
  static String coreOf(String title) {
    final withoutBrackets = title.replaceAll(_bracketed, ' ');
    final dash = withoutBrackets.indexOf(' - ');
    final head =
        dash < 0 ? withoutBrackets : withoutBrackets.substring(0, dash);
    final core = normalized(head);
    return core.isEmpty ? normalized(title) : core;
  }

  /// The version words in the parts [coreOf] throws away.
  @visibleForTesting
  static Set<String> versionOf(String title) {
    final extras = StringBuffer(
      _bracketed.allMatches(title).map((m) => m.group(0)!).join(' '),
    )..write(' ');
    final dash = title.indexOf(' - ');
    if (dash >= 0) extras.write(title.substring(dash + 3));
    return normalized(extras.toString())
        .split(' ')
        .where(versionWords.contains)
        .toSet();
  }

  @visibleForTesting
  static Set<String> artistsOf(String artist) => artist
      .split(_artistSeparators)
      .map(normalized)
      .where((a) => a.isNotEmpty)
      .toSet();

  /// Lower case, accents off ("ROSE" is "rose"), and only letters and digits.
  ///
  /// The reference does this with NFD and a strip of combining marks. Dart has
  /// no Unicode normaliser and this app takes no dependency for one, so the
  /// precomposed Latin letters NFD would split are folded by table instead
  /// ([_foldTable]). Both sides of every comparison go through the same
  /// function, which is what matters: it only has to be consistent.
  @visibleForTesting
  static String normalized(String value) {
    final folded = StringBuffer();
    for (final rune in value.toLowerCase().runes) {
      folded.write(_fold[rune] ?? String.fromCharCode(rune));
    }
    return folded
        .toString()
        .replaceAll(_combiningMarks, '')
        .replaceAll(_notLetterOrDigit, ' ')
        .replaceAll(_whitespace, ' ')
        .trim();
  }

  /// Base letter -> the precomposed letters NFD decomposes into it. Letters NFD
  /// leaves whole (o-slash, l-stroke, d-stroke, sharp s, ae) are deliberately
  /// absent, as they are in the reference.
  static const Map<String, String> _foldTable = <String, String>{
    'a': 'àáâãäåāăąǎǟǡǻȁȃȧḁạảấầẩẫậắằẳẵặ',
    'c': 'çćĉċčḉ',
    'd': 'ďḋḍḏḑḓ',
    'e': 'èéêëēĕėęěȅȇȩḕḗḙḛḝẹẻẽếềểễệ',
    'g': 'ĝğġģǧǵḡ',
    'h': 'ĥȟḣḥḧḩḫẖ',
    'i': 'ìíîïĩīĭįǐȉȋḭḯỉị',
    'j': 'ĵǰ',
    'k': 'ķǩḱḳḵ',
    'l': 'ĺļľḷḹḻḽ',
    'm': 'ḿṁṃ',
    'n': 'ñńņňǹṅṇṉṋ',
    'o': 'òóôõöōŏőơǒǫǭȍȏȫȭȯȱṍṏṑṓọỏốồổỗộớờởỡợ',
    'p': 'ṕṗ',
    'r': 'ŕŗřȑȓṙṛṝṟ',
    's': 'śŝşšșṡṣṥṧṩ',
    't': 'ţťțṫṭṯṱẗ',
    'u': 'ùúûüũūŭůűųưǔǖǘǚǜȕȗṳṵṷṹṻụủứừửữự',
    'v': 'ṽṿ',
    'w': 'ŵẁẃẅẇẉẘ',
    'x': 'ẋẍ',
    'y': 'ýÿŷȳẏỳỵỷỹẙ',
    'z': 'źżžẑẓẕ',
  };

  static final Map<int, String> _fold = <int, String>{
    for (final entry in _foldTable.entries)
      for (final rune in entry.value.runes) rune: entry.key,
  };
}
