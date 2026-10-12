// lib/services/lyrics/paxsenix_provider.dart
// PaxSenix - Apple Music lyrics found by catalogue search, plus the keyed
// Spotify and Musixmatch routes.
//
// Port of `PaxSenix.kt`. Three routes, one parser:
//
//   keyless  Apple's own web catalogue is searched with a token scraped from
//            music.apple.com, then lyrics.paxsenix.org serves that song's TTML.
//   keyed    api.paxsenix.org's Spotify and Musixmatch routes, which need the
//            listener's own API key. With no key they return null WITHOUT
//            touching the network - a request that cannot succeed is not made.
//
// WHY THE OLD ONE NEVER ANSWERED
//
// It read the catalogue's song ids as numbers. Apple sends them as strings
// ("1497230972"), so every search produced no candidates at all. The token also
// has to be scraped: it is not a constant, it is embedded in the web player's
// script and rotates when Apple ships a new one.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/lyrics_entry.dart';
import '../../utils/lyrics_utils.dart';
import 'apple_lyrics_common.dart';
import 'better_lyrics_provider.dart';
import 'lyric_words.dart';
import 'lyrics_http.dart';
import 'paxsenix_key_store.dart';

class PaxSenixProvider {
  PaxSenixProvider({LyricsHttp? http}) : _http = http ?? LyricsHttp.shared;

  final LyricsHttp _http;

  static const String _api = 'https://api.paxsenix.org';
  static const String _publicProxy = 'https://lyrics.paxsenix.org';
  static const String _appleSearch =
      'https://amp-api.music.apple.com/v1/catalog/us/search';
  static const String _appleHome = 'https://music.apple.com';
  static const int _minimumMatchScore = 10;

  /// The web player's script is several megabytes and the page that names it
  /// is two. They are fetched once per process, so they are allowed longer than
  /// an ordinary lyric request rather than being abandoned at 6s on a slow
  /// connection and retried on the next track.
  static const Duration _scrapeTimeout = Duration(seconds: 12);

  static final RegExp _appleIndexScript = RegExp(r'/assets/index~[^"]+\.js');
  static final RegExp _appleToken =
      RegExp(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');

  String? _cachedToken;
  Future<String?>? _tokenInFlight;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// The keyless Apple route.
  ///
  /// Uses [AppleLyricsQuery.appleId] directly when the caller already has one,
  /// and otherwise searches Apple's catalogue for the recording.
  Future<List<LyricsEntry>?> getLyrics(AppleLyricsQuery query) async {
    try {
      var id = query.appleId?.trim();
      if (id == null || id.isEmpty) {
        id = await _searchAppleTrackId(
          query.title,
          query.artist,
          query.durationMs ?? 0,
        );
      }
      if (id == null) return null;

      final body = await _http.getText(_publicUrl('apple-music/lyrics', {
        'id': id,
        'ttml': 'true',
      }));
      if (body == null) return null;
      return parseResponse(body);
    } catch (e) {
      if (kDebugMode) debugPrint('PaxSenixProvider: apple route failed: $e');
      return null;
    }
  }

  /// Spotify's synced lyrics through PaxSenix's keyed route.
  ///
  /// Null without a network call when [apiKey] is blank.
  Future<List<LyricsEntry>?> getSpotifyLyrics({
    required String title,
    required String artist,
    int? durationMs,
    required String apiKey,
  }) async {
    final key = PaxSenixKeyStore.normalize(apiKey);
    if (key.isEmpty) return null;
    try {
      final id = await _searchTrackId(
        'spotify/search',
        title,
        artist,
        durationMs ?? 0,
        key,
      );
      if (id != null) {
        final body = await _http.getBearer(
          _apiUrl('lyrics/spotify', {'id': id}),
          key,
        );
        final parsed = body == null ? null : parseResponse(body);
        if (parsed != null) return parsed;
      }
      return await _genericLyrics(title, artist, durationMs ?? 0, key);
    } catch (e) {
      if (kDebugMode) debugPrint('PaxSenixProvider: spotify route failed: $e');
      return null;
    }
  }

  /// Musixmatch's synced lyrics through PaxSenix's keyed route.
  ///
  /// Null without a network call when [apiKey] is blank.
  Future<List<LyricsEntry>?> getMusixmatchLyrics({
    required String title,
    required String artist,
    int? durationMs,
    required String apiKey,
  }) async {
    final key = PaxSenixKeyStore.normalize(apiKey);
    if (key.isEmpty) return null;
    try {
      final seconds = (durationMs ?? 0) ~/ 1000;
      final body = await _http.getBearer(
        _apiUrl('lyrics/musixmatch', {
          't': title,
          'a': artist,
          if (seconds > 0) 'd': seconds.toString(),
        }),
        key,
      );
      final parsed = body == null ? null : parseResponse(body);
      if (parsed != null) return parsed;
      return await _genericLyrics(title, artist, durationMs ?? 0, key);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PaxSenixProvider: musixmatch route failed: $e');
      }
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Apple token
  // ---------------------------------------------------------------------------

  /// The cached web token, scraping it if there is none.
  ///
  /// Concurrent callers share one in-flight scrape; the first lookup after a
  /// launch typically has several providers asking at once.
  Future<String?> _appleBearer() {
    final cached = _cachedToken;
    if (cached != null) return Future<String?>.value(cached);
    return _tokenInFlight ??= _scrapeAppleToken().then((token) {
      _cachedToken = token;
      return token;
    }).whenComplete(() {
      _tokenInFlight = null;
    });
  }

  Future<String?> _scrapeAppleToken() async {
    final page =
        await _http.getText('$_appleHome/us/new', timeout: _scrapeTimeout);
    if (page == null) return null;
    final scriptPath = _appleIndexScript.firstMatch(page)?.group(0);
    if (scriptPath == null) return null;
    final script =
        await _http.getText('$_appleHome$scriptPath', timeout: _scrapeTimeout);
    if (script == null) return null;
    return _appleToken.firstMatch(script)?.group(0);
  }

  Future<String?> _searchAppleTrackId(
    String title,
    String artist,
    int durationMs,
  ) async {
    final hadCachedToken = _cachedToken != null;
    var token = await _appleBearer();
    if (token == null) return null;

    final url = _plainUrl(_appleSearch, {
      'term': '$title $artist',
      'types': 'songs',
      'limit': '10',
      'l': 'en-US',
    });

    var body = await _http.getAppleAuthorized(url, token);
    if (body == null && hadCachedToken) {
      // LyricsHttp reports every failure as null, so a rejected token (401) is
      // indistinguishable from a dead network here. A token that has worked
      // before is the likelier culprit, and one re-scrape is cheap; a token
      // that was only just scraped is not retried.
      _cachedToken = null;
      token = await _appleBearer();
      if (token == null) return null;
      body = await _http.getAppleAuthorized(url, token);
    }
    if (body == null) return null;

    final root = _tryDecode(body);
    if (root == null) return null;
    return bestCandidate(root, title, artist, durationMs)?.id;
  }

  // ---------------------------------------------------------------------------
  // Keyed routes
  // ---------------------------------------------------------------------------

  Future<String?> _searchTrackId(
    String path,
    String title,
    String artist,
    int durationMs,
    String key,
  ) async {
    final body = await _http.getBearer(
      _apiUrl(path, {'q': '$title $artist'}),
      key,
    );
    if (body == null) return null;
    final root = _tryDecode(body);
    if (root == null) return null;
    return bestCandidate(root, title, artist, durationMs)?.id;
  }

  Future<List<LyricsEntry>?> _genericLyrics(
    String title,
    String artist,
    int durationMs,
    String key,
  ) async {
    final body = await _http.getBearer(
      _apiUrl('lyrics/lrcget', {'q': '$title $artist'}),
      key,
    );
    if (body == null) return null;
    return parseLrcGet(body, title, artist, durationMs);
  }

  // ---------------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------------

  /// Structured Apple payload first, then whatever wrapper the route used.
  static List<LyricsEntry>? parseResponse(String raw) =>
      parseTimedApple(raw) ?? parseProviderLyrics(raw);

  /// The general endpoint returns search candidates, not lyric lines.
  ///
  /// Parsing its array as one document concatenates every candidate and makes
  /// each song's timestamps restart at zero, which shows as repeated lines that
  /// cannot stay in sync. One recording is selected before its lyrics are read.
  static List<LyricsEntry>? parseLrcGet(
    String raw,
    String title,
    String artist,
    int durationMs,
  ) {
    final root = _tryDecode(raw);
    if (root == null) return null;
    final payload = root is Map ? root['lyrics'] : null;
    final documents = payload is List ? payload : const <dynamic>[];
    if (documents.isEmpty) return parseResponse(raw);

    _ParsedDocument? best;
    for (final document in documents) {
      final lines = parseResponse(jsonEncode(document));
      if (lines == null) continue;
      final candidate = _ParsedDocument(
        lines: lines,
        metadataScore: document is Map
            ? _candidateFromDocument(document).score(title, artist, durationMs)
            : 0,
        durationDistanceMs: _durationDistance(lines, durationMs),
      );
      if (best == null || candidate.beats(best)) best = candidate;
    }
    return best?.lines;
  }

  /// Preserves word timestamps when PaxSenix returns its structured Apple
  /// payload: `content[{timestamp, text:[{text, timestamp, endtime, part}]}]`.
  static List<LyricsEntry>? parseTimedApple(String raw) {
    final root = _tryDecode(raw);
    if (root == null) return null;
    final content = _findTimedContent(root);
    if (content == null) return null;

    final rows = content.whereType<Map>().toList();
    final out = <LyricsEntry>[];
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final start = _asInt(row['timestamp']);
      if (start == null) continue;
      final wordRows = row['text'];
      if (wordRows is! List) continue;

      final texts = <String>[
        for (final w in wordRows)
          if (w is Map && _asString(w['text']) != null) _asString(w['text'])!,
      ];
      if (texts.isEmpty) continue;

      final nextLine =
          index + 1 < rows.length ? _asInt(rows[index + 1]['timestamp']) : null;

      // Each entry is a syllable. `part` marks one that runs straight into the
      // next ("e" then "nough"), so the space goes only where it is false.
      // Joined with a space throughout, that read "long e nough".
      final runs = <TimedRun>[];
      for (var wi = 0; wi < wordRows.length; wi++) {
        final word = wordRows[wi];
        if (word is! Map) continue;
        final text = _asString(word['text'])?.trim();
        if (text == null || text.isEmpty) continue;
        final wordStart = _asInt(word['timestamp']);
        if (wordStart == null) continue;
        final following = wi + 1 < wordRows.length ? wordRows[wi + 1] : null;
        final wordEnd = _asInt(word['endtime']) ??
            (following is Map ? _asInt(following['timestamp']) : null) ??
            nextLine ??
            wordStart + 800;
        final joinsNext = word['part'] == true;
        runs.add(TimedRun(
          startMs: wordStart,
          endMs: wordEnd,
          raw: joinsNext ? text : '$text ',
        ));
      }

      final timed = wordsFromRuns(runs, spacingIsExplicit: true);
      // A syllable with no stamp leaves nothing to time the line by; the text
      // is then the entries as they came.
      final nonBlank = texts.where((t) => t.trim().isNotEmpty).length;
      final untimed = runs.length != nonBlank || timed.isEmpty;

      final lineText = untimed
          ? texts.map((t) => t.trim()).where((t) => t.isNotEmpty).join(' ')
          : timed.map((w) => w.text).join(' ');
      if (lineText.isEmpty) continue;

      out.add(LyricsEntry(
        timeMs: untimed || timed.first.startMs > start
            ? start
            : timed.first.startMs,
        text: lineText,
        // Sung until the next line starts; the last line has no successor, so
        // it ends with its final word.
        endMs: nextLine ?? (untimed ? null : timed.last.endMs),
        lyricWords: untimed ? null : timed,
      ));
    }

    return out.any((e) => e.text.trim().isNotEmpty) ? out : null;
  }

  /// Turns the wire formats the smaller providers use into entries.
  ///
  /// The subset of `ProviderLyrics.parse` that PaxSenix's routes produce: TTML,
  /// stamped LRC, and plain text. Providers sometimes wrap the same lyric string
  /// in one or two JSON envelopes, which [_unwrap] peels off.
  static List<LyricsEntry>? parseProviderLyrics(String raw) {
    final unwrapped = _unwrap(raw);
    if (unwrapped == null) return null;
    final content = _unescapeTtml(unwrapped);

    final List<LyricsEntry> lines;
    if (RegExp(r'<tt(?:\s|>)', caseSensitive: false).hasMatch(content) ||
        content.toLowerCase().contains('http://www.w3.org/ns/ttml')) {
      lines = BetterLyricsProvider.parseTtml(content);
    } else if (content.trimLeft().startsWith('<')) {
      lines = const <LyricsEntry>[];
    } else if (_lrcStamp.hasMatch(content)) {
      lines = LyricsUtils.parseLrc(content);
    } else {
      lines = _plain(content);
    }
    return lines.any((e) => e.text.trim().isNotEmpty) ? lines : null;
  }

  static final RegExp _lrcStamp = RegExp(r'\[\d{1,2}:\d{2}[.:]\d{2,3}\]');

  static List<LyricsEntry> _plain(String content) {
    if (RegExp(r'\b(?:lyrics? (?:not found|unavailable)|error)\b',
            caseSensitive: false)
        .hasMatch(content)) {
      return const <LyricsEntry>[];
    }
    final metaTag = RegExp(r'^\[[A-Za-z]+:.*\]$');
    return [
      for (final line in content.split(RegExp(r'\r?\n')))
        if (line.trim().isNotEmpty && !metaTag.hasMatch(line.trim()))
          LyricsEntry(timeMs: 0, text: line.trim()),
    ];
  }

  static const List<String> _contentKeys = <String>[
    'ttml',
    'ttmlContent',
    'lyrics',
    'lrc',
    'content',
    'text',
    'plainLyrics',
    'syncedLyrics',
    'line',
    'lines',
    'lyric',
    'data',
    'result',
    'response',
  ];

  static String? _unwrap(String raw) {
    var value = raw.replaceAll('\uFEFF', '').trim();
    if (value.startsWith('```')) {
      final lines = value.split('\n').skip(1).toList();
      if (lines.isNotEmpty && lines.last.trim() == '```') lines.removeLast();
      value = lines.join('\n').trim();
    }
    if (value.isEmpty) return null;
    final json = _tryDecode(value);
    if (json == null) return value;
    final text = _extract(json)?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static String? _extract(Object? element) {
    if (element == null) return null;
    if (element is String) {
      final text = element.trim();
      final nested = _tryDecode(text);
      if (nested is Map || nested is List) return _extract(nested);
      return text;
    }
    if (element is List) {
      final parts = [
        for (final e in element)
          if (_extract(e) != null) _extract(e)!,
      ];
      final joined = parts.join('\n');
      return joined.trim().isEmpty ? null : joined;
    }
    if (element is Map) {
      final isError = element['isError'] == true ||
          element['ok'] == false ||
          (element['error'] != null &&
              element['error'] != false &&
              element['error'] != '');
      if (isError) return null;
      for (final key in _contentKeys) {
        final found = _extract(element[key]);
        if (found != null) return found;
      }
      final metadata = element['metadata'];
      if (metadata is Map) {
        final found = _extract(metadata);
        if (found != null) return found;
      }
      return _extract(element['words']);
    }
    return null;
  }

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

  static List<dynamic>? _findTimedContent(Object? node) {
    if (node is Map) {
      final content = node['content'];
      if (content is List &&
          content.any((e) => e is Map && e['timestamp'] != null)) {
        return content;
      }
      for (final value in node.values) {
        final found = _findTimedContent(value);
        if (found != null) return found;
      }
      return null;
    }
    if (node is List) {
      for (final value in node) {
        final found = _findTimedContent(value);
        if (found != null) return found;
      }
    }
    return null;
  }

  static int _durationDistance(List<LyricsEntry> lines, int durationMs) {
    if (durationMs <= 0) return 0;
    var last = 0;
    for (final line in lines) {
      var end = line.timeMs;
      if ((line.endMs ?? 0) > end) end = line.endMs!;
      final words = line.lyricWords;
      if (words != null) {
        for (final w in words) {
          if (w.endMs > end) end = w.endMs;
        }
      }
      if (end > last) last = end;
    }
    return (last - durationMs).abs();
  }

  // ---------------------------------------------------------------------------
  // Candidate selection
  // ---------------------------------------------------------------------------

  /// The best-scoring catalogue entry anywhere in [root], or null when nothing
  /// scores [_minimumMatchScore].
  ///
  /// Walks the whole document rather than a fixed path because the three
  /// catalogues (Apple, Spotify, general) nest their results differently, and
  /// every one of them describes a song as an object with an id and a name.
  @visibleForTesting
  static PaxSenixCandidate? bestCandidate(
    Object? root,
    String title,
    String artist,
    int durationMs,
  ) {
    final candidates = <PaxSenixCandidate>[];
    _collect(root, candidates);
    PaxSenixCandidate? best;
    var bestScore = -1 << 30;
    for (final c in candidates) {
      final score = c.score(title, artist, durationMs);
      if (score > bestScore) {
        best = c;
        bestScore = score;
      }
    }
    return (best != null && bestScore >= _minimumMatchScore) ? best : null;
  }

  static void _collect(Object? node, List<PaxSenixCandidate> into) {
    if (node is List) {
      for (final e in node) {
        _collect(e, into);
      }
    } else if (node is Map) {
      final candidate = _toCandidate(node);
      if (candidate != null) into.add(candidate);
      for (final v in node.values) {
        _collect(v, into);
      }
    }
  }

  static const List<String> _idKeys = ['id', 'trackId', 'track_id', 'realId'];
  static const List<String> _titleKeys = [
    'name',
    'title',
    'trackName',
    'track_name'
  ];
  static const List<String> _artistKeys = ['artistName', 'artist_name'];
  static const List<String> _durationKeys = [
    'durationInMillis',
    'durationMs',
    'duration_ms',
    'duration'
  ];

  static PaxSenixCandidate? _toCandidate(Map node) {
    final attributes = node['attributes'];
    final details = attributes is Map ? attributes : node;
    final id = _firstString(node, _idKeys) ?? _firstString(details, _idKeys);
    if (id == null) return null;
    final title = _firstString(details, _titleKeys);
    if (title == null) return null;
    final artist =
        _firstString(details, _artistKeys) ?? _artistNames(details) ?? '';
    return PaxSenixCandidate(
      id: id,
      title: title,
      artist: artist,
      durationMs: _toDurationMs(_firstInt(details, _durationKeys)),
    );
  }

  /// [_toCandidate] for a lrcget document, which may have no id at all.
  static PaxSenixCandidate _candidateFromDocument(Map document) {
    final attributes = document['attributes'];
    final details = attributes is Map ? attributes : document;
    return PaxSenixCandidate(
      id: _firstString(document, _idKeys) ?? '',
      title: _firstString(details, _titleKeys) ?? '',
      artist: _firstString(details, _artistKeys) ?? _artistNames(details) ?? '',
      durationMs: _toDurationMs(_firstInt(details, _durationKeys)),
    );
  }

  static String? _artistNames(Map node) {
    final artists = node['artists'] ?? node['artist'];
    const nameKeys = ['name', 'artistName', 'title'];
    if (artists is String) return artists;
    if (artists is Map) return _firstString(artists, nameKeys);
    if (artists is List) {
      final names = <String>[
        for (final a in artists)
          if (a is String)
            a
          else if (a is Map && _firstString(a, nameKeys) != null)
            _firstString(a, nameKeys)!,
      ];
      return names.isEmpty ? null : names.join(', ');
    }
    return null;
  }

  static String? _firstString(Map node, List<String> keys) {
    for (final key in keys) {
      final value = _asString(node[key])?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static int? _firstInt(Map node, List<String> keys) {
    for (final key in keys) {
      final value = node[key];
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static int _toDurationMs(int? value) {
    if (value == null || value <= 0) return 0;
    // Some catalogues report seconds, some milliseconds. Nothing real is under
    // ten seconds, so a smaller number is seconds.
    return value < 10000 ? value * 1000 : value;
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  static Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// A JSON primitive as text, however the source typed it.
  static String? _asString(Object? v) {
    if (v is String) return v;
    if (v is num || v is bool) return v.toString();
    return null;
  }

  /// Apple sends some numbers as strings; accept both.
  static int? _asInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  // OkHttp writes a space as %20, and this host's router is happiest with the
  // same. Dart's own query encoder would write '+'.
  static String _plainUrl(String base, Map<String, String> query) {
    if (query.isEmpty) return base;
    final q = query.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$base?$q';
  }

  static String _apiUrl(String path, [Map<String, String> query = const {}]) =>
      _plainUrl('$_api/$path', query);

  static String _publicUrl(String path,
          [Map<String, String> query = const {}]) =>
      _plainUrl('$_publicProxy/$path', query);
}

/// A catalogue entry that might be the track being looked up.
@immutable
class PaxSenixCandidate {
  const PaxSenixCandidate({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationMs,
  });

  final String id;
  final String title;
  final String artist;
  final int durationMs;

  /// Title 20 exact / 10 contains, artist 15 / 5, duration +10 within 3s and
  /// +5 within 10s.
  int score(String wantedTitle, String wantedArtist, int wantedDurationMs) {
    var score = _textScore(title, wantedTitle, 20, 10) +
        _textScore(artist, wantedArtist, 15, 5);
    if (wantedDurationMs > 0 && durationMs > 0) {
      final diff = (durationMs - wantedDurationMs).abs();
      if (diff < 3000) {
        score += 10;
      } else if (diff < 10000) {
        score += 5;
      }
    }
    return score;
  }

  static int _textScore(
      String candidate, String wanted, int exact, int partial) {
    if (candidate.trim().isEmpty || wanted.trim().isEmpty) return 0;
    final a = candidate.toLowerCase();
    final b = wanted.toLowerCase();
    if (a == b) return exact;
    if (a.contains(b) || b.contains(a)) return partial;
    return 0;
  }

  @override
  String toString() =>
      'PaxSenixCandidate($id, "$title" - "$artist", ${durationMs}ms)';
}

class _ParsedDocument {
  const _ParsedDocument({
    required this.lines,
    required this.metadataScore,
    required this.durationDistanceMs,
  });

  final List<LyricsEntry> lines;
  final int metadataScore;
  final int durationDistanceMs;

  int get _timed => lines.where((l) => l.timeMs > 0).length;
  int get _wordSynced => lines.where((l) => l.isWordSynced).length;

  /// Strictly better than [other]: metadata, then nearer in length, then more
  /// timed lines, then more word-synced ones. Ties keep the earlier document.
  bool beats(_ParsedDocument other) {
    if (metadataScore != other.metadataScore) {
      return metadataScore > other.metadataScore;
    }
    if (durationDistanceMs != other.durationDistanceMs) {
      return durationDistanceMs < other.durationDistanceMs;
    }
    if (_timed != other._timed) return _timed > other._timed;
    return _wordSynced > other._wordSynced;
  }
}
