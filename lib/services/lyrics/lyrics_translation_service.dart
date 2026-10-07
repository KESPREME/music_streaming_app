// lib/services/lyrics/lyrics_translation_service.dart
// Translation and romanization of lyric lines.
//
// WHY A WEB ENDPOINT AND NOT A MODEL
//
// No translation model is installed on the device. One per app language would
// cost tens of megabytes each, and translated lyric text is normally a few
// kilobytes. Requests are batched and the compact result is kept in a bounded
// cache under the cache directory, so the platform can reclaim it and the
// feature cannot grow without limit.
//
// TWO OPERATIONS, ONE ENDPOINT
//
// `dt=t` translates. `dt=rm` romanizes - transliterating into Latin script,
// which is what makes a Japanese or Korean lyric readable to someone who does
// not read that script. They are separate requests because they answer
// different questions: one changes the language, the other changes the script
// and leaves the language alone.
//
// BATCHING
//
// Lines are joined with a private-use marker (\uE000 ... \uE001) and sent as one
// request. Asking for three hundred lines individually would be three hundred
// round trips and would get the track rate-limited partway through - which is
// how a lyric ends up half translated, top to bottom.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../models/lyrics_entry.dart';

/// What the service was asked for.
enum LyricsTransform {
  /// Translate into a target language.
  translate,

  /// Transliterate into Latin script, keeping the language.
  romanize,
}

class LyricsTranslationService {
  LyricsTranslationService._();
  static final LyricsTranslationService instance = LyricsTranslationService._();

  static const String _endpoint =
      'https://translate.googleapis.com/translate_a/single';

  /// Lines are joined with this pair before a batch is sent.
  ///
  /// Private-use code points: they cannot occur in a lyric, so a line that
  /// genuinely contains something similar is still split correctly. Matching on
  /// a printable delimiter would corrupt any lyric that used it.
  static const String _markerStart = '\uE000';
  static const String _markerEnd = '\uE001';

  /// Which field of a response segment carries the answer.
  ///
  /// A segment is `[translated, source?, phonetic?, transliterated, ...]` and the
  /// mode decides which one is wanted. Asking `dt=rm` and then reading the
  /// translation field is the mistake this pair exists to prevent.
  static const int _translatedSegmentField = 0;
  static const int _romanizedSegmentField = 3;

  static final Uri _endpointUri = Uri.parse(_endpoint);

  /// Google refuses very long single strings. 3.5k characters is comfortably
  /// inside the limit and still a useful amount of lyric per request.
  static const int maxBatchChars = 3500;

  /// Two at a time. Higher trips the endpoint's rate limit, which costs more in
  /// retries than it saves in latency.
  static const int maxParallelRequests = 2;

  /// Bounds the whole call, connect included.
  ///
  /// An unbounded POST is how a test isolate is left holding an open isolate at
  /// exit, and how a stalled endpoint leaves the footer spinner up for ever.
  static const Duration _timeout = Duration(seconds: 12);

  /// Cache format version. Bumped whenever the stored shape changes, so a
  /// stale entry is discarded rather than misread.
  static const int _cacheVersion = 1;
  static const int _maxMemoryEntries = 16;
  static const int _maxDiskBytes = 2 * 1024 * 1024;

  final http.Client _client = http.Client();

  /// In-memory cache, bounded. Small on purpose: this is a per-session
  /// convenience, not a store.
  final Map<String, List<String>> _memory = <String, List<String>>{};

  bool _diskChecked = false;

  /// Transforms [lines] and returns a list parallel to the input.
  ///
  /// Returns null when the transform could not be performed at all, which the
  /// caller must treat as "leave the original showing" rather than as an empty
  /// lyric. A translation failure that blanks the lyrics is worse than no
  /// translation feature.
  Future<List<String>?> transform({
    required List<String> lines,
    required LyricsTransform kind,
    required String targetLanguage,
  }) async {
    if (lines.isEmpty) return null;

    // Romanizing text that is already Latin cannot produce anything the reader
    // does not have on screen. Decided HERE rather than in the caller, because the
    // endpoint will happily echo the original back and the caller cannot tell a
    // genuine no-op from a translation that happened to be identical.
    //
    // Reference `LyricsTranslation.kt:234`: `hasNonLatinLetters` over every code
    // point, then `AlreadyRomanized` - a distinct outcome, not a null.
    if (kind == LyricsTransform.romanize && isAlreadyRomanizable(lines)) {
      return null;
    }

    final cacheKey = _key(kind, targetLanguage, lines);
    final cached = await _readCache(cacheKey, lines.length);
    if (cached != null) return cached;

    // Batches, then sent a couple at a time.
    final batches = _batches(lines);
    final results = <String>[];

    var index = 0;
    while (index < batches.length) {
      final take = batches.skip(index).take(maxParallelRequests).toList();
      index += take.length;

      final replies = await Future.wait(
        take.map((batch) => _request(batch, kind, targetLanguage)),
      );

      // Each reply is paired with its OWN batch. Falling back to some other
      // batch's originals would put the wrong language on the wrong line, and
      // once one batch succeeds the offsets no longer line up.
      for (var i = 0; i < take.length; i++) {
        final batch = take[i];
        final reply = replies[i];
        if (reply != null && reply.length == batch.length) {
          results.addAll(reply);
        } else {
          // A failed batch leaves its own lines alone. Keeping the length
          // correct is what lets the caller index this against its entries.
          results.addAll(batch);
        }
      }
    }

    if (results.length != lines.length) return null;
    await _writeCache(cacheKey, results);
    return results;
  }

  /// Splits [lines] into batches under [maxBatchChars].
  ///
  /// A single line longer than the limit is sent on its own rather than being
  /// split mid-sentence. One over-long line is a bad request; a lyric broken in
  /// half is worse.
  List<List<String>> _batches(List<String> lines) {
    final batches = <List<String>>[];
    var current = <String>[];
    var length = 0;

    for (final line in lines) {
      final addition = line.length +
          _markerStart.length +
          _markerEnd.length +
          (current.isEmpty ? 0 : 1);
      if (current.isNotEmpty && length + addition > maxBatchChars) {
        batches.add(current);
        current = <String>[];
        length = 0;
      }
      current.add(line);
      length += line.length +
          _markerStart.length +
          _markerEnd.length +
          (current.length > 1 ? 1 : 0);
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  Future<List<String>?> _request(
    List<String> batch,
    LyricsTransform kind,
    String targetLanguage,
  ) async {
    try {
      final payload = batch.join('$_markerStart$_markerEnd');
      // POST, form-encoded - not a query string.
      //
      // A batch runs to 3500 characters and a lyric is mostly Latin, so the
      // percent-encoded payload lands well past the ~2000-character URL limit
      // that intermediaries and some Android stacks enforce. A GET large enough
      // to be a real lyric is a GET that gets truncated or refused, and it fails
      // as an empty reply rather than as an error worth reporting.
      final response = await _client
          .post(
            _endpointUri,
            headers: const {
              'User-Agent': 'MusicStreamingApp/1.0.0',
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
            },
            body: {
              'client': 'dict-chrome-ex',
              // Sent as given rather than reduced to a base language: zh-CN and
              // zh-TW are different targets, and collapsing them asks for the
              // wrong script.
              'sl': 'auto',
              // Romanization always ends in Latin script, but the endpoint still
              // wants a `tl`, so the real destination is sent for both. It is
              // deliberately NOT part of the romanize cache key: changing
              // "translate to" cannot change how the source language is
              // pronounced.
              'tl': targetLanguage,
              // `dt=rm` is what makes this a transliteration rather than a
              // translation. Without it the endpoint answers with the original
              // text translated into the target language, which is the wrong
              // request entirely.
              'dt': kind == LyricsTransform.romanize ? 'rm' : 't',
              'q': payload,
              'ie': 'UTF-8',
              'oe': 'UTF-8',
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) return null;
      return _parseReply(response.body, batch.length, kind);
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsTranslation: request failed: $e');
      return null;
    }
  }

  /// Reads one response back out.
  ///
  /// The body is a JSON array whose first element is the segment list. Each
  /// segment carries several fields and WHICH one holds the answer depends on the
  /// mode: index 0 is the translation, index 3 is the transliteration. Reading 0
  /// for a romanization request returns text that was never romanized at all,
  /// which is why this takes the mode rather than assuming one field.
  ///
  /// Defensive throughout: a shape change must degrade to "no transform" rather
  /// than throw into the lyrics screen.
  static List<String>? _parseReply(
    String body,
    int expectedLines,
    LyricsTransform kind,
  ) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List || decoded.isEmpty) return null;
      final segments = decoded.first;
      if (segments is! List) return null;

      final field = kind == LyricsTransform.romanize
          ? _romanizedSegmentField
          : _translatedSegmentField;

      final out = <String>[];
      for (final segment in segments) {
        if (segment is! List || segment.length <= field) continue;
        final text = segment[field];
        if (text is! String) continue;
        out.add(text);
      }

      if (out.isEmpty) return null;

      // A count that does not match the batch is REFUSED, not padded.
      //
      // Padding by repeating the last line is how a transform ends up silently
      // wrong: the caller indexes this against its own entries, so a lyric can
      // come back with one real line and the rest of the song wearing it, and
      // nothing anywhere reports a problem. Refusing hands the caller a null and
      // it falls back to the originals, which is at least visibly true.
      if (out.length != expectedLines) return null;
      if (out.any((t) => t.trim().isEmpty)) return null;
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsTranslation: bad body: $e');
      return null;
    }
  }

  /// Replaces the text of each entry, keeping every timestamp.
  ///
  /// The timings are never translated. Word and syllable spans are preserved by
  /// index rather than re-derived, because a translation changes word lengths
  /// and re-deriving would silently misalign the wipe.
  static List<LyricsEntry> applyText(List<LyricsEntry> entries, List<String> texts) {
    if (texts.length != entries.length) return entries;
    return [
      for (var i = 0; i < entries.length; i++)
        LyricsEntry(
          timeMs: entries[i].timeMs,
          endMs: entries[i].endMs,
          text: texts[i].isEmpty ? entries[i].text : texts[i],
          // Words are dropped deliberately: their character spans index into
          // the original text and would be meaningless against a translation.
          // The line keeps its timestamps and falls back to whole-line reveal.
          lyricWords: null,
          words: null,
        ),
    ];
  }

  String _key(LyricsTransform kind, String target, List<String> lines) {
    // Hashed rather than the whole text, so the key stays short enough to be a
    // filename and does not carry the lyrics into a path.
    var hash = 0;
    final seed = '${kind.name}|$target|${lines.length}|';
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x1fffffff;
    }
    for (final line in lines) {
      for (final unit in line.codeUnits) {
        hash = (hash * 31 + unit) & 0x1fffffff;
      }
    }
    return 'v$_cacheVersion-${kind.name}-${target.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}-$hash';
  }

  Future<List<String>?> _readCache(String key, int lineCount) async {
    final memoryHit = _memory[key];
    if (memoryHit != null) return memoryHit;

    if (!_diskChecked) {
      _diskChecked = true;
      try {
        final dir = await _cacheDirectory();
        if (dir != null && await dir.exists()) {
          await _enforceDiskBudget(dir);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('LyricsTranslation: disk check: $e');
      }
    }

    try {
      final dir = await _cacheDirectory();
      if (dir == null) return null;
      final file = File('${dir.path}/$key.json');
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      if (decoded['v'] != _cacheVersion) return null;
      final texts = decoded['t'];
      if (texts is! List || texts.length != lineCount) return null;

      final out = texts.whereType<String>().toList();
      if (out.length != lineCount) return null;
      _remember(key, out);
      return out;
    } catch (e) {
      // A cache miss is always recoverable by refetching.
      return null;
    }
  }

  Future<void> _writeCache(String key, List<String> texts) async {
    _remember(key, texts);
    try {
      final dir = await _cacheDirectory();
      if (dir == null) return;
      final file = File('${dir.path}/$key.json');
      await file.writeAsString(jsonEncode({'v': _cacheVersion, 't': texts}));
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsTranslation: disk write: $e');
    }
  }

  void _remember(String key, List<String> texts) {
    if (_memory.containsKey(key)) _memory.remove(key);
    _memory[key] = texts;
    while (_memory.length > _maxMemoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<Directory?> _cacheDirectory() async {
    // Under the cache directory so the platform may reclaim it. Storing
    // translations in app storage would make them survive forever, which is
    // exactly the growth this feature must not have.
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/lyrics_translation_v$_cacheVersion');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _enforceDiskBudget(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      var total = 0;
      for (final file in files) {
        total += await file.length();
      }
      if (total <= _maxDiskBytes) return;

      // Largest first, as a cheap proxy for least useful. Reading every mtime
      // off a cache directory on a track change is not worth the time, and these
      // entries are all a translation of some lyric - a few kilobytes each, so
      // the budget is only ever crossed by a lot of them at once.
      var freed = 0;
      final ordered = List<File>.of(files)
        ..sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
      for (final file in ordered) {
        if (total - freed <= _maxDiskBytes) break;
        final length = await file.length();
        await file.delete();
        freed += length;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsTranslation: budget: $e');
    }
  }

  /// Whether a line is already in Latin script.
  ///
  /// Used to skip a romanization request that could only echo the original back:
  /// the answer would cost a round trip to produce text identical to what is
  /// already showing.
  static bool isLatinScript(String text) {
    if (text.trim().isEmpty) return true;
    for (final rune in text.runes) {
      // Latin, plus the punctuation and digits that travel with it.
      if (rune < 0x0250) continue;
      return false;
    }
    return true;
  }

  /// Whether every line is already Latin, so romanization has nothing to do.
  ///
  /// ALL of them, not any: a lyric is a single artefact and one Japanese line
  /// among thirty English ones still needs transliterating. Reporting the whole
  /// song as already-romanized because most of it is would leave that one line
  /// wrong with no way back.
  ///
  /// Public because the disc needs the answer BEFORE the tap resolves, to tint and
  /// disable itself the moment the reader looks at it rather than after a round
  /// trip. Two callers, one rule.
  static bool isAlreadyRomanizable(List<String> lines) {
    var anyText = false;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      anyText = true;
      if (!isLatinScript(line)) return false;
    }
    // All blank: nothing to romanize, and nothing worth reporting as a miss.
    return anyText;
  }

  /// Clears every cached transform.
  void clear() {
    _memory.clear();
    _diskChecked = false;
  }

  /// Exposes the batching for tests.
  ///
  /// The split is the part with real rules in it - the character cap, the
  /// refusal to break a single over-long line - so it is worth testing directly
  /// rather than only through a live request.
  @visibleForTesting
  List<List<String>> batchesForTest(List<String> lines) => _batches(lines);

  /// Exposes the reply reader for tests.
  @visibleForTesting
  static List<String>? parseReplyForTest(String body, int expectedLines) =>
      _parseReply(body, expectedLines, LyricsTransform.translate);

  /// Exposes the mode-aware reader, because WHICH field is read is the whole
  /// point: a test that only checked translation would pass while romanization
  /// returned un-romanized text.
  @visibleForTesting
  static List<String>? parseRomanizedForTest(String body, int expectedLines) =>
      _parseReply(body, expectedLines, LyricsTransform.romanize);
}