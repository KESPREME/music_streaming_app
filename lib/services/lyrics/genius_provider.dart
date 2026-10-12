// lib/services/lyrics/genius_provider.dart
// Genius - plain-text lyrics scraped, and only as a last resort.
//
// Port of `Genius.kt`. No timings at all: every provider above this one can
// sing along; this one only prints the words. It exists so a song with no
// synced coverage anywhere is not simply blank, and it is deliberately the
// final entry in the default order.
//
// WHAT WAS WRONG BEFORE
//
//   * A Chrome User-Agent was answered 403 with a Cloudflare challenge page.
//     Genius objects to a *browser-shaped* agent that cannot pass a JavaScript
//     challenge, not to an honest one: measured from this machine in 2026-10,
//     the app's own agent is answered 200 for both the search and the page,
//     and a Chrome one is answered 403 for both. So this sends the app's own
//     name (`LyricsHttp.agent`) and does not pretend to be anything else.
//   * The container regex ended at the first `</div>`. The first lyrics
//     container opens with a header made of nested divs, so it stopped inside
//     the header and every verse after it was lost.
//   * It searched the title alone and took the first URL, which on a common
//     title is some other song - or a translation of it.
//   * It invented a 4-second step per line. Plain lyrics have no time, and a
//     made-up one scrolls the words past at a pace the song never had.
//
// Lines are returned at `timeMs: 0`. Section headers such as `[Chorus]` are
// kept as lines of their own, because translation needs them to know where a
// stanza starts (see [isGeniusSectionHeader]).

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/lyrics_entry.dart';
import 'lyrics_http.dart';

/// Whether [text] is a Genius section marker such as `[Verse 1]` or `[Chorus]`.
bool isGeniusSectionHeader(String text) {
  final trimmed = text.trim();
  return trimmed.startsWith('[') &&
      trimmed.endsWith(']') &&
      trimmed.length >= 3 &&
      trimmed.length <= 60;
}

class GeniusProvider {
  GeniusProvider({LyricsHttp? http}) : _http = http ?? LyricsHttp.shared;

  final LyricsHttp _http;

  static const String _searchUrl = 'https://genius.com/api/search/multi';

  /// A song page is a few hundred KB. This is the last provider asked, so it is
  /// given a little longer than the 6s the racing ones get rather than being
  /// cut off after the work of finding the page has already been done.
  static const Duration _timeout = Duration(seconds: 8);

  static const Map<String, String> _headers = {
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,'
        'application/json,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Plain lyrics, or null when nothing matched.
  ///
  /// Returned without any timings (every line at `timeMs: 0`), so the caller
  /// renders it as unsynced text rather than as a wipe.
  Future<List<LyricsEntry>?> getLyrics({
    required String title,
    required String artist,
  }) async {
    try {
      for (final attempt in searchAttempts(title, artist)) {
        final url = await _searchSongUrl(attempt);
        if (url == null) continue;

        final html =
            await _http.getText(url, headers: _headers, timeout: _timeout);
        if (html == null || html.trim().isEmpty) return null;
        return parseHtml(html);
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('GeniusProvider: failed: $e');
      return null;
    }
  }

  Future<String?> _searchSongUrl(GeniusSearchAttempt attempt) async {
    final body = await _http.getText(
      '$_searchUrl?q=${Uri.encodeQueryComponent(attempt.query)}',
      headers: _headers,
      timeout: _timeout,
    );
    if (body == null) return null;
    return bestMatchUrl(body, attempt.title, attempt.artist);
  }

  // ---------------------------------------------------------------------------
  // Query building
  // ---------------------------------------------------------------------------

  static final RegExp _titleSeparator = RegExp(r'\s*[-–—:]\s*');
  static final RegExp _decorativeChars = RegExp(r'[♪♫★☆【】《》「」~_]');
  static final RegExp _producerTags = RegExp(
    r'\b(?:prod(?:uced)?\.?(?:\s+by)?)\s+.*$',
    caseSensitive: false,
  );
  static final RegExp _noise = RegExp(
    r'\s*[(\[]\s*(?:from|feat\.?|ft\.?|featuring|with|prod\.?|produced by|'
    r'official|lyrical|video|audio|remix|music video|visualizer|mv|hd|4k|hq|'
    r'full song)[^)\]]*[)\]]|'
    r'\s*\b(?:official\s+(?:music\s+)?(?:video|audio)|lyrical(?:\s+video)?|'
    r'full\s+song|4k\s+video|hd\s+video|music\s+video)\b',
    caseSensitive: false,
  );
  static final RegExp _bracketedContent = RegExp(r'\s*[\(\[].*?[\)\]]');
  static final RegExp _nonAlphanumeric =
      RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
  static final RegExp _whitespace = RegExp(r'\s+');

  /// The searches to try, most specific first, without repeats.
  ///
  /// The first is `"{artist} {title}"`, which is the one that nearly always
  /// finds the song. The rest only run when it finds nothing.
  @visibleForTesting
  static List<GeniusSearchAttempt> searchAttempts(String title, String artist) {
    final cleanTitle = _cleanQuery(title);
    final cleanArtist = _cleanQuery(artist);

    // "Artist - Title" uploads put both in the title.
    List<String>? titleParts;
    final separator = _titleSeparator.firstMatch(cleanTitle);
    if (separator != null) {
      titleParts = [
        cleanTitle.substring(0, separator.start),
        cleanTitle.substring(separator.end),
      ];
    }

    bool same(String a, String b) =>
        a.trim().toLowerCase() == b.trim().toLowerCase();

    final String extractedTitle;
    if (titleParts != null && same(titleParts[0], cleanArtist)) {
      extractedTitle = titleParts[1].trim();
    } else if (titleParts != null && same(titleParts[1], cleanArtist)) {
      extractedTitle = titleParts[0].trim();
    } else if (titleParts != null &&
        titleParts[0].trim().isNotEmpty &&
        titleParts[1].trim().isNotEmpty) {
      extractedTitle = titleParts[1].trim();
    } else {
      extractedTitle = cleanTitle;
    }

    final String extractedArtist;
    if (titleParts != null &&
        (same(titleParts[0], cleanArtist) ||
            same(titleParts[1], cleanArtist))) {
      extractedArtist = cleanArtist;
    } else if (titleParts != null && cleanArtist.trim().isEmpty) {
      extractedArtist = titleParts[0].trim();
    } else {
      extractedArtist = cleanArtist;
    }

    final titleWithoutBrackets = extractedTitle
        .replaceAll(_bracketedContent, ' ')
        .replaceAll(_nonAlphanumeric, ' ')
        .replaceAll(_whitespace, ' ')
        .trim();

    final attempts = <GeniusSearchAttempt>[];

    // 1. Extracted artist + extracted title.
    if (extractedArtist.isNotEmpty && extractedTitle.isNotEmpty) {
      attempts.add(GeniusSearchAttempt(
          '$extractedArtist $extractedTitle'.trim(),
          extractedTitle,
          extractedArtist));
    }
    // 2. Extracted artist + title without brackets.
    if (extractedArtist.isNotEmpty &&
        titleWithoutBrackets.isNotEmpty &&
        titleWithoutBrackets != extractedTitle) {
      attempts.add(GeniusSearchAttempt(
          '$extractedArtist $titleWithoutBrackets'.trim(),
          titleWithoutBrackets,
          extractedArtist));
    }
    // 3. Clean artist + clean title, in case the separator was not "Artist - Title".
    if (cleanTitle != extractedTitle) {
      attempts.add(GeniusSearchAttempt(
          '$cleanArtist $cleanTitle'.trim(), cleanTitle, cleanArtist));
      attempts.add(
          GeniusSearchAttempt(cleanTitle, extractedTitle, extractedArtist));
    }
    // 4. The title alone.
    if (titleWithoutBrackets.isNotEmpty) {
      attempts.add(GeniusSearchAttempt(
          titleWithoutBrackets, titleWithoutBrackets, extractedArtist));
    } else if (extractedTitle.isNotEmpty) {
      attempts.add(
          GeniusSearchAttempt(extractedTitle, extractedTitle, extractedArtist));
    }

    final seen = <String>{};
    return [
      for (final a in attempts)
        if (seen.add(a.query)) a,
    ];
  }

  static String _cleanQuery(String text) {
    var cleaned = text
        .replaceAll(_decorativeChars, ' ')
        .replaceAll(_noise, ' ')
        .replaceAll(_producerTags, ' ');
    final bar = cleaned.indexOf(' | ');
    if (bar >= 0) cleaned = cleaned.substring(0, bar);
    cleaned = cleaned.replaceAll(_whitespace, ' ').trim();
    return cleaned.isEmpty ? text.trim() : cleaned;
  }

  // ---------------------------------------------------------------------------
  // Search result selection
  // ---------------------------------------------------------------------------

  /// The song page URL that best matches, or null if none scores above zero.
  @visibleForTesting
  static String? bestMatchUrl(String searchBody, String title, String artist) {
    try {
      final root = jsonDecode(searchBody);
      if (root is! Map) return null;
      final response = root['response'];
      if (response is! Map) return null;
      final sections = response['sections'];
      if (sections is! List) return null;

      Map? songSection;
      for (final s in sections) {
        if (s is Map && s['type'] == 'song') {
          songSection = s;
          break;
        }
      }
      final hits = songSection?['hits'];
      if (hits is! List) return null;

      final candidates = <Map>[
        for (final h in hits)
          if (h is Map && h['result'] is Map) h['result'] as Map,
      ];
      final best = _bestMatch(candidates, title, artist);
      final url = best?['url'];
      return url is String && url.isNotEmpty ? url : null;
    } catch (_) {
      return null;
    }
  }

  static Map? _bestMatch(
      List<Map> candidates, String targetTitle, String targetArtist) {
    if (candidates.isEmpty) return null;
    final normTitle = targetTitle.toLowerCase();
    final normArtist = targetArtist.toLowerCase();

    Map? best;
    var bestScore = 0;
    for (final item in candidates) {
      final title = (item['title'] is String ? item['title'] as String : '')
          .toLowerCase();
      final artist =
          (item['artist_names'] is String ? item['artist_names'] as String : '')
              .toLowerCase();
      var score = 0;

      final titleMatches = normTitle.trim().isNotEmpty &&
          title.isNotEmpty &&
          (title == normTitle ||
              title.contains(normTitle) ||
              normTitle.contains(title));
      final artistMatches = normArtist.trim().isNotEmpty &&
          artist.isNotEmpty &&
          (artist == normArtist ||
              artist.contains(normArtist) ||
              normArtist.contains(artist));

      if (!titleMatches && !artistMatches) continue;

      if (title == normTitle) {
        score += 50;
      } else if (titleMatches) {
        score += 25;
      }

      if (artistMatches) {
        score += artist == normArtist ? 40 : 20;
      }

      // Translations, trackless pages and the like are other pages ABOUT the
      // song. Penalised unless the listener asked for exactly that.
      final path =
          (item['path'] is String ? item['path'] as String : '').toLowerCase();
      if (path.contains('translation') && !normTitle.contains('translation')) {
        score -= 30;
      }
      if (path.contains('türkçe') || path.contains('polskie-tlumaczenie')) {
        score -= 40;
      }
      if (path.contains('tracklist') || path.contains('album-art')) {
        score -= 50;
      }

      if (score <= 0) continue;
      if (score > bestScore) {
        best = item;
        bestScore = score;
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // Page parsing
  // ---------------------------------------------------------------------------

  /// Plain lyric lines out of a Genius song page, or null if it has none.
  ///
  /// Every `data-lyrics-container="true"` element is read, in order: a page
  /// splits the lyrics across several, with ad slots between them. Anything the
  /// page puts inside one that is not lyric - the contributors header, the song
  /// bio, buttons, ads - is dropped first.
  static List<LyricsEntry>? parseHtml(String html) {
    try {
      final root = _HtmlParser(html).parse();

      var containers = <_Element>[];
      _findAll(
          root, (e) => e.attrs['data-lyrics-container'] == 'true', containers);
      if (containers.isEmpty) {
        // Older pages.
        _findAll(
            root, (e) => e.tag == 'div' && e.hasClass('lyrics'), containers);
      }
      if (containers.isEmpty) return null;

      final full = StringBuffer();
      for (final container in containers) {
        final text = _wholeText(container);
        if (text.trim().isNotEmpty) full.write('$text\n');
      }
      final raw = full.toString();
      if (raw.trim().isEmpty) return null;

      final entries = textToEntries(stripArtifacts(raw));
      return entries.isEmpty ? null : entries;
    } catch (e) {
      if (kDebugMode) debugPrint('GeniusProvider: parse failed: $e');
      return null;
    }
  }

  static final RegExp _youMightAlsoLike =
      RegExp(r'\d*You might also like', caseSensitive: false);
  static final RegExp _trailingEmbed =
      RegExp(r'\d*Embed\s*$', caseSensitive: false);

  /// Every space-like character Genius puts in lyrics: no-break, the U+2000
  /// block (it writes U+2005 between words), zero-width space, narrow no-break,
  /// medium mathematical space and the byte-order mark.
  ///
  /// They render as a space but are not one, so left alone they break wrapping,
  /// searching and the word boundaries translation relies on.
  static final RegExp _oddSpaces =
      RegExp('[\u00A0\u2000-\u200B\u202F\u205F\uFEFF]');
  static final RegExp _runOfSpaces = RegExp(r'[ \t]{2,}');

  /// Removes scraper debris: recommendation inserts, the glued-on "123Embed",
  /// and the non-breaking and zero-width spaces Genius uses.
  static String stripArtifacts(String raw) => raw
      .replaceAll(_oddSpaces, ' ')
      .replaceAll(_runOfSpaces, ' ')
      .replaceAll(_youMightAlsoLike, '')
      .trim()
      .replaceAll(_trailingEmbed, '')
      .trim();

  /// One entry per non-blank line, all at `timeMs: 0`.
  ///
  /// Blank lines (stanza gaps) are not emitted: a zero-time empty entry reads as
  /// an instrumental break to the lyric view, and the `[Chorus]` headers already
  /// mark where each stanza starts.
  static List<LyricsEntry> textToEntries(String text) {
    final lines = <LyricsEntry>[];
    for (final raw in text.split(RegExp(r'\r\n|\r|\n'))) {
      final line = raw.trim();
      // A page can glue "123Embed" onto the end of a container; a line that is
      // only that is debris, but a lyric that merely ends in the word is not.
      if (line.isEmpty ||
          RegExp(r'^\d*Embed$', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      lines.add(LyricsEntry(timeMs: 0, text: line));
    }
    return lines;
  }

  // ---------------------------------------------------------------------------
  // Tree helpers
  // ---------------------------------------------------------------------------

  static const Set<String> _droppedTags = {'button', 'script', 'style'};
  static const List<String> _droppedClassPrefixes = [
    'LyricsHeader__Container',
    'SongBioPreview__Container',
    'InreadAd__Container',
  ];

  static bool _isDropped(_Element e) {
    if (_droppedTags.contains(e.tag)) return true;
    if (e.attrs['data-exclude-from-selection'] == 'true') return true;
    for (final token in e.classes) {
      for (final prefix in _droppedClassPrefixes) {
        if (token == prefix || token.startsWith('$prefix-')) return true;
      }
    }
    return false;
  }

  /// Every matching element, outermost first. A match is not searched inside.
  static void _findAll(
      _Element node, bool Function(_Element) test, List<_Element> out) {
    for (final child in node.children) {
      if (child is! _Element) continue;
      if (test(child)) {
        out.add(child);
      } else {
        _findAll(child, test, out);
      }
    }
  }

  static String _wholeText(_Element container) {
    final out = StringBuffer();
    void walk(_Element node) {
      for (final child in node.children) {
        if (child is _Text) {
          out.write(_decodeEntities(child.text));
        } else if (child is _Element) {
          if (_isDropped(child)) continue;
          if (child.tag == 'br') {
            out.write('\n');
          } else {
            if (child.tag == 'p') out.write('\n');
            walk(child);
          }
        }
      }
    }

    walk(container);
    return out.toString();
  }

  // ---------------------------------------------------------------------------
  // Entities
  // ---------------------------------------------------------------------------

  static final RegExp _entity =
      RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[A-Za-z][A-Za-z0-9]*);');

  static String _decodeEntities(String text) {
    if (!text.contains('&')) return text;
    return text.replaceAllMapped(_entity, (m) {
      final body = m.group(1)!;
      if (body.startsWith('#')) {
        final code = (body[1] == 'x' || body[1] == 'X')
            ? int.tryParse(body.substring(2), radix: 16)
            : int.tryParse(body.substring(1));
        if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
        return String.fromCharCode(code);
      }
      final code = _namedEntities[body];
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
  }

  static const Map<String, int> _namedEntities = {
    'amp': 0x26,
    'lt': 0x3C,
    'gt': 0x3E,
    'quot': 0x22,
    'apos': 0x27,
    'nbsp': 0xA0,
    'iexcl': 0xA1,
    'iquest': 0xBF,
    'copy': 0xA9,
    'reg': 0xAE,
    'deg': 0xB0,
    'middot': 0xB7,
    'laquo': 0xAB,
    'raquo': 0xBB,
    'para': 0xB6,
    'sect': 0xA7,
    'hellip': 0x2026,
    'mdash': 0x2014,
    'ndash': 0x2013,
    'lsquo': 0x2018,
    'rsquo': 0x2019,
    'sbquo': 0x201A,
    'ldquo': 0x201C,
    'rdquo': 0x201D,
    'bdquo': 0x201E,
    'bull': 0x2022,
    'trade': 0x2122,
    'agrave': 0xE0,
    'aacute': 0xE1,
    'acirc': 0xE2,
    'atilde': 0xE3,
    'auml': 0xE4,
    'aring': 0xE5,
    'aelig': 0xE6,
    'ccedil': 0xE7,
    'egrave': 0xE8,
    'eacute': 0xE9,
    'ecirc': 0xEA,
    'euml': 0xEB,
    'igrave': 0xEC,
    'iacute': 0xED,
    'icirc': 0xEE,
    'iuml': 0xEF,
    'ntilde': 0xF1,
    'ograve': 0xF2,
    'oacute': 0xF3,
    'ocirc': 0xF4,
    'otilde': 0xF5,
    'ouml': 0xF6,
    'oslash': 0xF8,
    'ugrave': 0xF9,
    'uacute': 0xFA,
    'ucirc': 0xFB,
    'uuml': 0xFC,
    'yacute': 0xFD,
    'yuml': 0xFF,
    'szlig': 0xDF,
    'Agrave': 0xC0,
    'Aacute': 0xC1,
    'Acirc': 0xC2,
    'Atilde': 0xC3,
    'Auml': 0xC4,
    'Aring': 0xC5,
    'AElig': 0xC6,
    'Ccedil': 0xC7,
    'Egrave': 0xC8,
    'Eacute': 0xC9,
    'Ecirc': 0xCA,
    'Euml': 0xCB,
    'Igrave': 0xCC,
    'Iacute': 0xCD,
    'Icirc': 0xCE,
    'Iuml': 0xCF,
    'Ntilde': 0xD1,
    'Ograve': 0xD2,
    'Oacute': 0xD3,
    'Ocirc': 0xD4,
    'Otilde': 0xD5,
    'Ouml': 0xD6,
    'Oslash': 0xD8,
    'Ugrave': 0xD9,
    'Uacute': 0xDA,
    'Ucirc': 0xDB,
    'Uuml': 0xDC,
    'Yacute': 0xDD,
  };
}

/// One query to send to Genius's search, and what to score the hits against.
@immutable
class GeniusSearchAttempt {
  const GeniusSearchAttempt(this.query, this.title, this.artist);

  final String query;
  final String title;
  final String artist;

  @override
  String toString() => 'GeniusSearchAttempt("$query" => "$title" / "$artist")';
}

// -----------------------------------------------------------------------------
// A small, forgiving HTML tree builder.
//
// There is no HTML package in the dependency list, and a regex cannot find
// where a `<div>` ends: that is the bug this replaces. This builds just enough
// of a tree to count nesting properly - void elements, raw-text elements,
// comments, attributes with quotes, and stray or unclosed tags - and nothing
// more. It is not a conforming HTML5 parser and does not try to be.
// -----------------------------------------------------------------------------

abstract class _Node {}

class _Text extends _Node {
  _Text(this.text);
  final String text;
}

class _Element extends _Node {
  _Element(this.tag, this.attrs);

  final String tag;
  final Map<String, String> attrs;
  final List<_Node> children = <_Node>[];

  late final List<String> classes = (attrs['class'] ?? '')
      .split(RegExp(r'\s+'))
      .where((c) => c.isNotEmpty)
      .toList();

  bool hasClass(String name) => classes.contains(name);
}

class _HtmlParser {
  _HtmlParser(this._s);

  final String _s;
  int _i = 0;

  static const Set<String> _void = {
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'param',
    'source',
    'track',
    'wbr',
  };
  static const Set<String> _rawText = {'script', 'style'};

  _Element parse() {
    final root = _Element('#root', const {});
    final stack = <_Element>[root];

    void addText(String text) {
      if (text.isEmpty) return;
      stack.last.children.add(_Text(text));
    }

    while (_i < _s.length) {
      final lt = _s.indexOf('<', _i);
      if (lt < 0) {
        addText(_s.substring(_i));
        break;
      }
      if (lt > _i) addText(_s.substring(_i, lt));
      _i = lt;

      if (_s.startsWith('<!--', _i)) {
        final end = _s.indexOf('-->', _i + 4);
        _i = end < 0 ? _s.length : end + 3;
        continue;
      }
      if (_s.startsWith('<!', _i) || _s.startsWith('<?', _i)) {
        final end = _s.indexOf('>', _i);
        _i = end < 0 ? _s.length : end + 1;
        continue;
      }
      if (_s.startsWith('</', _i)) {
        final nameStart = _i + 2;
        var p = nameStart;
        while (p < _s.length && _isNameChar(_s.codeUnitAt(p))) {
          p++;
        }
        final name = _s.substring(nameStart, p).toLowerCase();
        final end = _s.indexOf('>', p);
        _i = end < 0 ? _s.length : end + 1;
        if (name.isEmpty) continue;
        // Close the nearest open element of that name, and anything left open
        // inside it. An end tag with no open partner is ignored.
        for (var k = stack.length - 1; k > 0; k--) {
          if (stack[k].tag == name) {
            stack.removeRange(k, stack.length);
            break;
          }
        }
        continue;
      }
      if (_i + 1 < _s.length && _isNameStart(_s.codeUnitAt(_i + 1))) {
        final element = _readOpenTag();
        stack.last.children.add(element.node);
        if (_rawText.contains(element.node.tag) && !element.selfClosing) {
          // Skip the body without interpreting it: script text is full of '<'.
          final closeTag =
              RegExp('</${element.node.tag}', caseSensitive: false);
          final matches = closeTag.allMatches(_s, _i).iterator;
          if (!matches.moveNext()) {
            _i = _s.length;
          } else {
            final end = _s.indexOf('>', matches.current.start);
            _i = end < 0 ? _s.length : end + 1;
          }
        } else if (!element.selfClosing && !_void.contains(element.node.tag)) {
          stack.add(element.node);
        }
        continue;
      }
      // A '<' that opens nothing is just a character.
      addText('<');
      _i++;
    }
    return root;
  }

  ({_Element node, bool selfClosing}) _readOpenTag() {
    _i++; // '<'
    final nameStart = _i;
    while (_i < _s.length && _isNameChar(_s.codeUnitAt(_i))) {
      _i++;
    }
    final tag = _s.substring(nameStart, _i).toLowerCase();
    final attrs = <String, String>{};
    var selfClosing = false;

    while (_i < _s.length) {
      _skipSpace();
      if (_i >= _s.length) break;
      final c = _s[_i];
      if (c == '>') {
        _i++;
        break;
      }
      if (c == '/') {
        _i++;
        if (_i < _s.length && _s[_i] == '>') {
          selfClosing = true;
          _i++;
          break;
        }
        continue;
      }
      // Attribute name.
      final attrStart = _i;
      while (_i < _s.length) {
        final ch = _s[_i];
        if (ch == '=' || ch == '>' || ch == '/' || _isSpace(_s.codeUnitAt(_i))) {
          break;
        }
        _i++;
      }
      final name = _s.substring(attrStart, _i).toLowerCase();
      if (name.isEmpty) {
        _i++; // never stall on a stray character
        continue;
      }
      _skipSpace();
      var value = '';
      if (_i < _s.length && _s[_i] == '=') {
        _i++;
        _skipSpace();
        if (_i < _s.length && (_s[_i] == '"' || _s[_i] == "'")) {
          final quote = _s[_i];
          final end = _s.indexOf(quote, _i + 1);
          if (end < 0) {
            value = _s.substring(_i + 1);
            _i = _s.length;
          } else {
            value = _s.substring(_i + 1, end);
            _i = end + 1;
          }
        } else {
          final valueStart = _i;
          while (
              _i < _s.length && !_isSpace(_s.codeUnitAt(_i)) && _s[_i] != '>') {
            _i++;
          }
          value = _s.substring(valueStart, _i);
        }
      }
      attrs.putIfAbsent(name, () => value);
    }
    return (node: _Element(tag, attrs), selfClosing: selfClosing);
  }

  void _skipSpace() {
    while (_i < _s.length && _isSpace(_s.codeUnitAt(_i))) {
      _i++;
    }
  }

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C;

  static bool _isNameStart(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  static bool _isNameChar(int c) =>
      _isNameStart(c) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x2D ||
      c == 0x3A ||
      c == 0x5F;
}
