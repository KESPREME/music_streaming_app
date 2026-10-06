import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import 'lyric_words.dart';

/// Provider for BetterLyrics — Apple Music TTML word and syllable-timed lyrics.
///
/// Two endpoints behind one parser, because they answer with the same shape:
/// the Apple catalogue, and QQ Music's karaoke timings reached through the same
/// gateway. Portato is worth offering separately rather than as a fallback
/// inside this one — it is a different catalogue, so a track can be in one and
/// not the other, and a fallback would hide which one actually answered.
class BetterLyricsProvider {
  static const String _baseUrl = 'https://lyrics-api.boidu.dev/getLyrics';

  /// QQ Music karaoke timings through the same gateway.
  static const String portatoUrl = 'https://lyrics-api.boidu.dev/getLyricsPortato';

  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) =>
      _fetch(_baseUrl, title, artist, durationMs, album);

  /// QQ Music karaoke timings, per syllable.
  ///
  /// Sings the notes rather than the lyrics, so its spans are tighter and more
  /// numerous than Apple's — which is the whole reason to ask for it.
  Future<List<LyricsEntry>?> getPortato({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) =>
      _fetch(portatoUrl, title, artist, durationMs, album);

  Future<List<LyricsEntry>?> _fetch(
    String endpoint,
    String title,
    String artist,
    int? durationMs,
    String? album,
  ) async {
    try {
      final cleanTitle = _cleanQuery(title);
      final cleanArtist = _cleanQuery(artist);
      if (cleanTitle.isEmpty || cleanArtist.isEmpty) return null;

      final queryParams = <String, String>{
        's': cleanTitle,
        'a': cleanArtist,
      };
      if (durationMs != null && durationMs > 0) {
        queryParams['d'] = (durationMs ~/ 1000).toString();
      }
      if (album != null && album.isNotEmpty) {
        queryParams['al'] = album;
      }

      final uri = Uri.parse(endpoint).replace(queryParameters: queryParams);
      final response = await http
          .get(uri, headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          })
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;

      final ttml = json['ttml'] as String?;
      if (ttml == null || ttml.isEmpty) return null;

      return parseTtml(ttml);
    } catch (e) {
      if (kDebugMode) debugPrint('BetterLyricsProvider: lookup failed: $e');
      return null;
    }
  }

  /// Parses Apple Music TTML with per-syllable / per-word timings into [LyricsEntry]
  static List<LyricsEntry> parseTtml(String ttml) {
    final entries = <LyricsEntry>[];
    // Find all <p begin="..." end="..."> ... </p> elements
    final pRegex = RegExp(
      r'<p\b[^>]*\bbegin="([^"]+)"(?:\s+[^>]*\bend="([^"]+)")?[^>]*>(.*?)<\/p>',
      dotAll: true,
      caseSensitive: false,
    );

    final spanRegex = RegExp(
      r'<span\b[^>]*\bbegin="([^"]+)"(?:\s+[^>]*\bend="([^"]+)")?[^>]*>(.*?)<\/span>',
      dotAll: true,
      caseSensitive: false,
    );

    for (final pMatch in pRegex.allMatches(ttml)) {
      final lineBeginStr = pMatch.group(1);
      final lineEndStr = pMatch.group(2);
      final lineContent = pMatch.group(3) ?? '';

      final lineTimeMs = _parseTimestampMs(lineBeginStr);
      if (lineTimeMs == null) continue;
      final lineEndMs = _parseTimestampMs(lineEndStr);

      var lyricWords = <LyricWord>[];
      final rawTextBuffer = StringBuffer();

      // Check if line contains per-syllable / word spans
      final spanMatches = spanRegex.allMatches(lineContent).toList();
      if (spanMatches.isNotEmpty) {
        // Collect the spans as timed runs, spacing intact, and let
        // wordsFromRuns decide what glues into a word.
        //
        // Treating every span as its own word is what this used to do, and it
        // splits every word in an Apple TTML line: `<span>e</span><span>nough
        // </span>` is one word "enough" sung over two syllables, and reading it
        // as the words "e" then "nough" lights up at the wrong times and
        // cannot interpolate inside either.
        //
        // The whitespace BETWEEN spans is carried on the preceding run's raw
        // text, because that gap is the only thing saying where one word stops.
        final runs = <TimedRun>[];
        var lastIndex = 0;

        for (int i = 0; i < spanMatches.length; i++) {
          final sMatch = spanMatches[i];

          // Preserve any inter-span characters (spaces or punctuation between
          // tags) - they are word boundaries.
          //
          // Spacing between span i and span i+1 belongs to the END of run i,
          // because that space is what closes the word run i is part of. Putting
          // it on the following run instead glues the two words together:
          // "One</span> <span>tear" became the single word "Onetear".
          //
          // Spacing before the FIRST span is the line's own indentation and is
          // not a boundary at all. Apple serves compact TTML, but a mirror that
          // indents its markup should not cost the wipe its words.
          String inter = '';
          if (sMatch.start > lastIndex) {
            inter = _unescapeXml(_stripXmlTags(
              lineContent.substring(lastIndex, sMatch.start),
            ));
            if (i > 0 && runs.isNotEmpty && inter.isNotEmpty) {
              final prev = runs.removeLast();
              runs.add(TimedRun(
                startMs: prev.startMs,
                endMs: prev.endMs,
                raw: prev.raw + inter,
              ));
            }
            rawTextBuffer.write(i == 0 ? inter.trimLeft() : inter);
          }

          final sBeginStr = sMatch.group(1);
          final sEndStr = sMatch.group(2);
          final sText = _unescapeXml(_stripXmlTags(sMatch.group(3) ?? ''));

          rawTextBuffer.write(sText);

          final sTimeMs = _parseTimestampMs(sBeginStr) ?? lineTimeMs;
          final sEnd = _parseTimestampMs(sEndStr) ?? (sTimeMs + 400);

          runs.add(TimedRun(
            startMs: sTimeMs,
            endMs: sEnd,
            raw: sText,
          ));

          lastIndex = sMatch.end;
        }

        var tail = '';
        if (lastIndex < lineContent.length) {
          tail = _unescapeXml(_stripXmlTags(
            lineContent.substring(lastIndex),
          ));
          rawTextBuffer.write(tail);
        }
        // Trailing spacing after the last span belongs to that span, for the
        // same reason inter-span spacing does.
        if (tail.isNotEmpty && runs.isNotEmpty) {
          final last = runs.removeLast();
          runs.add(TimedRun(
            startMs: last.startMs,
            endMs: last.endMs,
            raw: last.raw + tail,
          ));
        }

        lyricWords = wordsFromRuns(runs);
      } else {
        // Plain text inside <p>
        rawTextBuffer.write(_unescapeXml(_stripXmlTags(lineContent)));
      }

      var fullLineText = rawTextBuffer.toString();
      // Normalize any multi-whitespace or newlines into single spaces
      fullLineText = fullLineText.replaceAll(RegExp(r'[ \t\r\n]+'), ' ').trim();

      if (fullLineText.isNotEmpty) {
        // Both fields are populated. `lyricWords` is the glued two-level model
        // the renderer reads, and `words` stays filled so anything still
        // consuming the flat word list keeps working - the renderer prefers
        // lyricWords and falls back to this.
        final legacyWords = <WordTiming>[
          for (final w in lyricWords)
            WordTiming(
              timeMs: w.startMs,
              durationMs: w.endMs > w.startMs ? w.endMs - w.startMs : 400,
              text: w.text,
            ),
        ];
        entries.add(LyricsEntry(
          timeMs: lineTimeMs,
          endMs: lineEndMs,
          text: fullLineText,
          words: legacyWords.isEmpty ? null : legacyWords,
          lyricWords: lyricWords.isEmpty ? null : lyricWords,
        ));
      }
    }

    entries.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return entries;
  }

  static String _stripXmlTags(String raw) {
    return raw
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), '');
  }

  static String _unescapeXml(String text) {
    return text
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  static int? _parseTimestampMs(String? raw) {
    if (raw == null) return null;
    raw = raw.trim();
    if (raw.isEmpty) return null;

    if (raw.contains(':')) {
      final parts = raw.split(':');
      if (parts.length == 2) {
        final m = int.tryParse(parts[0]) ?? 0;
        final s = double.tryParse(parts[1]) ?? 0.0;
        return (m * 60 * 1000 + s * 1000).round();
      } else if (parts.length == 3) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final s = double.tryParse(parts[2]) ?? 0.0;
        return (h * 3600 * 1000 + m * 60 * 1000 + s * 1000).round();
      }
    }
    final sec = double.tryParse(raw);
    if (sec != null) return (sec * 1000).round();
    return null;
  }

  static String _cleanQuery(String raw) {
    return raw
        .replaceAll(
            RegExp(
              r'(\s*[\(\[](?:feat\.?|ft\.?|official|video|remastered|bonus track|audio|lyrics)[^\)\]]*[\)\]])',
              caseSensitive: false,
            ),
            '')
        .trim();
  }
}
