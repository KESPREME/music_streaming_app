// lib/services/lyrics/provider_lyrics.dart
// Turns the wire formats of the smaller lyric providers into [LyricsEntry]s.
//
// Port of `ProviderLyrics.kt` (and its `KaraokeLrc`).
//
// WHY A SEPARATE LAYER
//
// BetterLyrics, its Portato endpoint and a few others wrap the SAME lyric string
// in one or two JSON envelopes whose key differs from host to host
// (`ttml`, `lyrics`, `data.lyrics`, ...). Reading one literal key is how
// Portato came to return nothing at all: its body is `{"lyrics":"<?xml ...
// <QrcInfos>..."}`, not `{"ttml":...}`. This finds the string wherever it is,
// then decides what format it is by LOOKING at it rather than trusting the
// host's name for it.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';
import 'better_lyrics_provider.dart';
import 'lyric_words.dart';

class ProviderLyrics {
  ProviderLyrics._();

  /// Envelope keys that may hold the lyric string, in the order they are tried.
  static const List<String> contentKeys = <String>[
    'ttml', 'ttmlContent', 'lyrics', 'lrc', 'content', 'text',
    'plainLyrics', 'syncedLyrics', 'line', 'lines', 'lyric',
    'data', 'result', 'response',
  ];

  static final RegExp _ttmlRoot = RegExp(r'<tt(?:\s|>)', caseSensitive: false);
  static final RegExp _notLyrics = RegExp(
    r'\b(?:lyrics? (?:not found|unavailable)|error)\b',
    caseSensitive: false,
  );
  static final RegExp _metadataLine = RegExp(r'^\[[A-Za-z]+:.*\]$');

  /// Lyrics in whatever form [raw] holds them, or null when nothing in it is
  /// usable.
  ///
  /// Never throws: a provider's body is untrusted input and a malformed one is
  /// a miss, not an error.
  static List<LyricsEntry>? parse(String raw) {
    try {
      final unwrapped = unwrap(raw);
      if (unwrapped == null) return null;
      final content = _unescapeTtml(unwrapped);

      final List<LyricsEntry> lines;
      if (_ttmlRoot.hasMatch(content) ||
          content.toLowerCase().contains('http://www.w3.org/ns/ttml')) {
        lines = BetterLyricsProvider.parseTtml(content);
      } else if (KaraokeLrc.looksLike(content)) {
        lines = KaraokeLrc.parse(content);
      } else if (content.trimLeft().startsWith('<')) {
        // Markup that is not lyrics: an HTML error page, an unknown XML. Handing
        // it to the plain-text path would show the page as a song.
        lines = const <LyricsEntry>[];
      } else {
        lines = _lrcOrPlain(content);
      }
      return lines.any((l) => l.text.trim().isNotEmpty) ? lines : null;
    } catch (e) {
      if (kDebugMode) debugPrint('ProviderLyrics: parse failed: $e');
      return null;
    }
  }

  /// Enhanced LRC (`<mm:ss.xx>` word stamps) and ordinary LRC both go through
  /// [LyricsUtils.parseLrc], which owns every LRC rule this app follows. It
  /// always returns a leading empty head entry, so "found something" has to be
  /// asked of the text rather than of the list's length.
  static List<LyricsEntry> _lrcOrPlain(String content) {
    final lrc = LyricsUtils.parseLrc(content);
    if (lrc.any((e) => e.text.trim().isNotEmpty)) return lrc;
    return _plain(content);
  }

  /// Unsynced text: one line each, all stamped 0, which is how every unsynced
  /// source here says "no timing" - the panel reads it as words to scroll by
  /// hand rather than to follow. No timings are invented.
  static List<LyricsEntry> _plain(String content) {
    if (_notLyrics.hasMatch(content)) return const <LyricsEntry>[];
    return <LyricsEntry>[
      for (final raw in const LineSplitter().convert(content))
        if (raw.trim().isNotEmpty && !_metadataLine.hasMatch(raw.trim()))
          LyricsEntry(timeMs: 0, text: raw.trim()),
    ];
  }

  /// The lyric string inside [raw], peeling BOMs, a code fence and up to any
  /// number of JSON envelopes. Null when the envelope says it is an error.
  static String? unwrap(String raw) {
    var value = raw.replaceAll('\uFEFF', '').trim();
    if (value.startsWith('```')) {
      final lines = const LineSplitter().convert(value).skip(1).toList();
      if (lines.isNotEmpty && lines.last.trim() == '```') lines.removeLast();
      value = lines.join('\n').trim();
    }
    if (value.isEmpty) return null;

    final Object? json;
    try {
      json = jsonDecode(value);
    } catch (_) {
      return value; // Not JSON: it is the lyric itself.
    }
    final text = _extract(json)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _extract(Object? element) {
    if (element == null) return null;
    if (element is String) {
      final text = element.trim();
      if (text.isEmpty) return null;
      // A string that is itself JSON is another envelope.
      Object? nested;
      try {
        nested = jsonDecode(text);
      } catch (_) {
        return text;
      }
      return nested is Map || nested is List ? _extract(nested) : text;
    }
    if (element is List) {
      final parts = <String>[
        for (final item in element)
          if (_extract(item) case final String s) s,
      ];
      final joined = parts.join('\n');
      return joined.trim().isEmpty ? null : joined;
    }
    if (element is Map) {
      if (element['isError'] == true || element['ok'] == false) return null;
      final error = element['error'];
      if (error != null && error != false && error != '') return null;

      for (final key in contentKeys) {
        final value = element[key];
        if (value == null) continue;
        final found = _extract(value);
        if (found != null) return found;
      }
      final metadata = element['metadata'];
      if (metadata is Map) {
        final found = _extract(metadata);
        if (found != null) return found;
      }
      final words = element['words'];
      return words == null ? null : _extract(words);
    }
    return null; // numbers and booleans carry no lyric
  }

  /// A TTML document served HTML-escaped inside another document.
  static String _unescapeTtml(String value) {
    if (!value.toLowerCase().contains('&lt;tt')) return value;
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }
}

/// QQ/QRC and NetEase YRC: millisecond line and word ranges.
///
/// ```
/// [7805,7284]Gone (7805,224)a (8029,177)little (8206,479)far (8685,1057)    QRC
/// [7805,7284](7805,224,0)Gone (8029,177,0)a (8206,479,0)little               YRC
/// ```
///
/// QRC puts a syllable's stamp AFTER its text and YRC puts it BEFORE, and
/// nothing in the line says which, so both readings are taken and the one that
/// recovers more of the text is believed.
class KaraokeLrc {
  KaraokeLrc._();

  static final RegExp _line = RegExp(r'^\[(\d{1,8}),(\d{1,8})\](.*)$');
  static final RegExp _prefixWord =
      RegExp(r'\((\d{1,8}),(\d{1,8})(?:,\d{1,8})?\)([^()]*)');
  static final RegExp _suffixWord =
      RegExp(r'([^()]*)\((\d{1,8}),(\d{1,8})(?:,\d{1,8})?\)');
  static final RegExp _wordTime = RegExp(r'\(\d{1,8},\d{1,8}(?:,\d{1,8})?\)');
  static final RegExp _content =
      RegExp(r'LyricContent\s*=\s*"([^"]*)"', caseSensitive: false);

  /// Whether [raw] carries at least one `[start,dur]` line with stamped words.
  static bool looksLike(String raw) =>
      const LineSplitter().convert(_lyricContent(raw)).any((source) {
        final match = _line.firstMatch(source.trim());
        if (match == null) return false;
        final body = match.group(3)!;
        return _prefixWord.hasMatch(body) || _suffixWord.hasMatch(body);
      });

  static List<LyricsEntry> parse(String raw) {
    final rows = <({int index, LyricsEntry entry})>[];
    var index = 0;
    for (final source in const LineSplitter().convert(_lyricContent(raw))) {
      final match = _line.firstMatch(source.trim());
      if (match == null) continue;
      final lineStart = int.parse(match.group(1)!);
      final lineDuration = int.parse(match.group(2)!);
      final body = match.group(3)!;

      // QRC and YRC stamp each syllable, and say which ones make a word by
      // leaving the space out between them - see [wordsFromRuns].
      final prefixed = wordsFromRuns([
        for (final m in _prefixWord.allMatches(body))
          _run(m.group(3)!, m.group(1)!, m.group(2)!),
      ]);
      final suffixed = wordsFromRuns([
        for (final m in _suffixWord.allMatches(body))
          _run(m.group(1)!, m.group(2)!, m.group(3)!),
      ]);
      final words = _textLength(prefixed) >= _textLength(suffixed)
          ? prefixed
          : suffixed;
      if (words.isEmpty) continue;

      final text = decodeLyricEntities(body.replaceAll(_wordTime, ''))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isEmpty) continue;

      rows.add((
        index: index++,
        entry: LyricsEntry(
          timeMs: math.min(lineStart, words.first.startMs),
          // How long the line is sung for, from its own header.
          endMs: lineDuration > 0 ? lineStart + lineDuration : null,
          text: text,
          // Both fields, as the TTML parser does: `lyricWords` is what the
          // renderer reads and `words` keeps flat-list consumers working.
          words: [
            for (final w in words)
              WordTiming(
                timeMs: w.startMs,
                durationMs: w.endMs > w.startMs ? w.endMs - w.startMs : 400,
                text: w.text,
              ),
          ],
          lyricWords: words,
        ),
      ));
    }
    // List.sort is not stable; the original index breaks ties so two lines
    // stamped alike keep the order they were written in.
    rows.sort((a, b) {
      final byTime = a.entry.timeMs.compareTo(b.entry.timeMs);
      return byTime != 0 ? byTime : a.index.compareTo(b.index);
    });
    return [for (final r in rows) r.entry];
  }

  static int _textLength(List<LyricWord> words) =>
      words.fold(0, (sum, w) => sum + w.text.length);

  static TimedRun _run(String text, String start, String duration) {
    final startMs = int.parse(start);
    return TimedRun(
      startMs: startMs,
      endMs: startMs + int.parse(duration),
      raw: decodeLyricEntities(text),
    );
  }

  /// The lyric body: the `LyricContent="..."` attribute of QQ's XML wrapper
  /// when there is one, otherwise [raw] itself.
  static String _lyricContent(String raw) {
    final match = _content.firstMatch(raw);
    if (match == null) return raw;
    return match
        .group(1)!
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }
}

/// Decodes the HTML entities lyric hosts leave in their text.
///
/// SimpMusic and QQ serve rich sync HTML-escaped, so an apostrophe arrives as
/// `&#x27;` and would otherwise be sung literally. `&amp;` goes last so
/// `&amp;#x27;` does not decode twice.
String decodeLyricEntities(String text) {
  if (!text.contains('&')) return text;
  return text
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => _codePoint(int.tryParse(m.group(1)!, radix: 16)) ?? m.group(0)!,
      )
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) => _codePoint(int.tryParse(m.group(1)!)) ?? m.group(0)!,
      )
      .replaceAll('&apos;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

String? _codePoint(int? code) {
  if (code == null || code < 0 || code > 0x10FFFF) return null;
  if (code >= 0xD800 && code <= 0xDFFF) return null; // lone surrogate
  return String.fromCharCode(code);
}
