// lib/services/lyrics/lyrics_translation_service.dart
// Translation and romanization of lyric lines.
//
// Reference: BitChord `LyricsTranslation.kt`. This is a port of its rules, so a
// change here should be checked against that file first.
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
// BATCHING, AND WHY THE ANSWER IS SPLIT ON MARKERS RATHER THAN ON SEGMENTS
//
// Lines are joined with a numbered private-use marker and sent as one request:
// three hundred separate calls would get the track rate-limited partway, which
// is how a lyric ends up half translated, top to bottom.
//
// The answer is a list of SEGMENTS, but a segment is a sentence as the endpoint
// sees it, not a lyric line. One line can come back as two segments, two short
// lines as one, and each marker as a segment of its own (see the captured
// fixtures under `test/fixtures/lyrics/translate_*`). An earlier version read
// one segment per line and demanded the counts match; against a real response
// that is nearly always false, so every batch "failed" and the lyric stayed
// untranslated. The segments are therefore concatenated and the markers are the
// only thing that says where a line ends.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/lyrics_entry.dart';
import 'genius_provider.dart' show isGeniusSectionHeader;

/// What the service was asked for.
enum LyricsTransform {
  /// Translate into a target language.
  translate,

  /// Transliterate into Latin script, keeping the language.
  romanize,
}

/// The three ways a request can end.
///
/// A sealed type rather than a nullable list: the reference distinguishes
/// `SameLanguage`/`AlreadyRomanized` from `Unavailable` because they deserve
/// different words. "These lyrics already use Latin characters" is a fact about
/// the song; "translation failed" is a fault of ours, and one `null` for both
/// tells the reader their lyrics are in the wrong script.
sealed class LyricsTransformResult {
  const LyricsTransformResult();
}

/// The transform worked. [lines] is parallel to the input, so it can be indexed
/// against the entries it came from; blank input lines stay blank.
final class LyricsTransformReady extends LyricsTransformResult {
  const LyricsTransformReady({
    required this.lines,
    required this.sourceLanguage,
    required this.fromCache,
  });

  final List<String> lines;

  /// Base language the lyrics were detected as (`ja`), possibly empty for a
  /// romanization served from a cache written by an older build.
  final String sourceLanguage;
  final bool fromCache;
}

/// There was nothing to do: the lyrics are already in the target language
/// (translate) or already use only Latin letters (romanize, where [language] is
/// empty because the target is irrelevant).
final class LyricsTransformSameLanguage extends LyricsTransformResult {
  const LyricsTransformSameLanguage([this.language = '']);
  final String language;
}

/// The request could not be completed. The original lyric stays as it is.
final class LyricsTransformUnavailable extends LyricsTransformResult {
  const LyricsTransformUnavailable();
}

/// A flag a caller flips to say "stop - nobody wants this answer any more".
///
/// Dart cannot cancel a Future, so cancellation is cooperative: the service checks
/// it before it starts each request and before it commits an answer to the cache.
/// A request already on the wire still completes, and its answer is thrown away.
class LyricsCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class LyricsTranslationService {
  /// Pass a client to test against a recorded response; production uses
  /// [LyricsTranslationService.instance].
  ///
  /// [cacheDirectory] is the ROOT the cache directory is made under
  /// (`getApplicationCacheDirectory()` in production). Returning null keeps the
  /// cache in memory only, which is also what a platform without that directory
  /// gets.
  ///
  /// [settingReader] answers "what is the `translation_language` setting" (null or
  /// blank for unset). A seam for the same reason as the client: a widget test
  /// that seeds the real store leaks it into every later test in the file.
  LyricsTranslationService({
    http.Client? client,
    Future<Directory?> Function()? cacheDirectory,
    Future<String?> Function()? settingReader,
    Duration? timeout,
  })  : _client = client ?? _defaultClient(),
        _cacheRoot = cacheDirectory ?? _defaultCacheRoot,
        _settingReader = settingReader ?? _readStoredSetting,
        _timeout = timeout ?? const Duration(seconds: 12);

  static LyricsTranslationService _instance = LyricsTranslationService();
  static LyricsTranslationService get instance => _instance;

  /// Swaps the shared instance, so a widget test can drive the real screen
  /// against a recorded response. Pass null to restore a fresh default.
  @visibleForTesting
  static void debugOverrideInstance(LyricsTranslationService? service) {
    _instance = service ?? LyricsTranslationService();
  }

  static const String _endpoint =
      'https://translate.googleapis.com/translate_a/single';
  static const String _inputToolsEndpoint =
      'https://inputtools.google.com/request';
  static final Uri _endpointUri = Uri.parse(_endpoint);
  static final Uri _inputToolsUri = Uri.parse(_inputToolsEndpoint);

  /// The `translation_language` setting: a language code, blank to follow the
  /// app. Stored by the settings screen, read here on every tap so a change takes
  /// effect without restarting the player.
  static const String translationLanguagePrefKey = 'translation_language';

  /// Each line is separated from the next by `\n`, one of these markers, `\n`.
  ///
  /// Private-use code points: they cannot occur in a lyric, so a line that
  /// genuinely contains something similar is still split correctly. Matching on a
  /// printable delimiter would corrupt any lyric that used it.
  static const String _markerStart = '\uE000';
  static const String _markerEnd = '\uE001';

  /// Matches a marker whatever its digits became.
  ///
  /// Input Tools rewrites ASCII digits into the destination script
  /// (`0001` -> `०००१`), so a pattern that expected `\d{4}` would lose every
  /// marker on exactly the retry that exists to fix Hindi. The private-use
  /// wrapper survives, so the wrapper is what is matched.
  static final RegExp _markerPattern = RegExp('\uE000[^\uE001]*\uE001');

  /// Which field of a response segment carries the answer.
  ///
  /// A segment is `[translated, source?, phonetic?, transliterated, ...]` and the
  /// mode decides which one is wanted. Asking `dt=rm` and then reading the
  /// translation field is the mistake this pair exists to prevent.
  static const int _translatedSegmentField = 0;
  static const int _romanizedSegmentField = 3;

  /// Google refuses very long single strings. 3.5k characters is comfortably
  /// inside the limit and still a useful amount of lyric per request.
  static const int maxBatchChars = 3500;

  /// Two at a time. Higher trips the endpoint's rate limit, which costs more in
  /// retries than it saves in latency.
  static const int maxParallelRequests = 2;

  /// The length of `\n` + marker + `\n`, which every line after the first costs.
  static const int _separatorChars = 8;

  /// Cache format version. Bumped whenever the stored shape or the rules that
  /// produce it change, so a stale entry is discarded rather than misread.
  ///
  /// 3 invalidates answers cached before the Latin-script retry existed:
  /// otherwise a song that once came back untranslated would never take the
  /// repaired path after the app is updated.
  static const int cacheVersion = 3;
  static const String cacheDirectoryName = 'lyrics_translation_v3';

  /// In-memory entries kept, least recently USED evicted first.
  static const int maxMemoryEntries = 12;

  /// The disk budget; the newest entries are kept and older ones deleted.
  static const int maxDiskBytes = 2 * 1024 * 1024;

  final http.Client _client;
  final Future<Directory?> Function() _cacheRoot;
  final Future<String?> Function() _settingReader;
  final Duration _timeout;

  static const Map<String, String> _headers = {
    'User-Agent': 'MusicStreamingApp/1.0.0',
    'Accept': 'application/json',
    'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
  };

  /// Bounds connecting separately from the whole call.
  ///
  /// An unbounded POST is how a test isolate is left holding an open socket at
  /// exit, and how a stalled endpoint leaves the footer spinner up for ever.
  static http.Client _defaultClient() =>
      IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 5));

  static Future<Directory?> _defaultCacheRoot() async {
    // Under the CACHE directory so the platform may reclaim it. Storing
    // translations in app storage would make them survive for ever, which is
    // exactly the growth this feature must not have.
    try {
      return await getApplicationCacheDirectory();
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsTranslation: no cache directory: $e');
      return null;
    }
  }

  // ── The target language ────────────────────────────────────────────────────

  /// Which language to translate into.
  ///
  /// The `translation_language` setting wins where it was set, exactly as typed:
  /// `zh-TW` and `zh-CN` are different targets, and narrowing either to `zh`
  /// would hand back Simplified whichever one was asked for. Blank means follow
  /// the app, and only THAT path is reduced to a base language.
  ///
  /// Reduced because `Platform.localeName` is `en_US`, not `en`. The screen used
  /// to pass it straight through as `tl=en_US`, which the endpoint is not
  /// obliged to understand, and which [sameLanguage] would only have matched by
  /// luck of its own normalization.
  ///
  /// `en` when neither says anything usable (the POSIX `C` locale, an empty
  /// string).
  static String resolveTargetLanguage({String? setting, String? localeName}) {
    final chosen = setting?.trim() ?? '';
    if (chosen.isNotEmpty) return chosen;
    final base = _baseOfLocale(localeName);
    return base.isEmpty ? 'en' : base;
  }

  static String _baseOfLocale(String? localeName) {
    if (localeName == null) return '';
    // `en_US.UTF-8`, `de_DE@euro`: drop the encoding and modifier first.
    final head = localeName.trim().split(RegExp(r'[.@]')).first;
    final base = canonicalLanguage(head);
    // A language subtag is two or three letters. `C` and `POSIX` are not
    // languages, and sending them as `tl` is a request that cannot succeed.
    return RegExp(r'^[a-z]{2,3}$').hasMatch(base) ? base : '';
  }

  static Future<String?> _readStoredSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(translationLanguagePrefKey);
    } catch (e) {
      // An unreadable setting is "not set", never a reason to refuse to translate.
      if (kDebugMode) debugPrint('LyricsTranslation: setting unreadable: $e');
      return null;
    }
  }

  /// The language to translate into right now: the stored setting, else the
  /// device's language, else `en`. Reads the setting on every call, so a change
  /// in Settings takes effect on the next tap.
  Future<String> targetLanguage({String? localeName}) async =>
      resolveTargetLanguage(
        setting: await _settingReader(),
        localeName:
            localeName ?? PlatformDispatcher.instance.locale.toLanguageTag(),
      );

  // ── The two operations ─────────────────────────────────────────────────────

  /// Transforms [lines] and returns what happened.
  ///
  /// [trackId] is part of the cache key so two songs that happen to share a line
  /// do not share an answer. [cancel] is checked between requests.
  ///
  /// Never throws: every failure is [LyricsTransformUnavailable].
  Future<LyricsTransformResult> transform({
    required String trackId,
    required List<String> lines,
    required LyricsTransform kind,
    required String targetLanguage,
    LyricsCancelToken? cancel,
  }) async {
    try {
      return switch (kind) {
        LyricsTransform.translate =>
          await _translate(trackId, lines, targetLanguage, cancel),
        LyricsTransform.romanize =>
          await _romanize(trackId, lines, targetLanguage, cancel),
      };
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsTranslation: $kind failed: $e');
      return const LyricsTransformUnavailable();
    }
  }

  Future<LyricsTransformResult> _translate(
    String trackId,
    List<String> lines,
    String targetLanguage,
    LyricsCancelToken? cancel,
  ) async {
    final target = targetLanguage.trim();
    if (target.isEmpty || lines.isEmpty) return const LyricsTransformUnavailable();
    final slots = _flatten(lines);
    if (slots.isEmpty) return const LyricsTransformUnavailable();

    final key = _cacheKeyFor(LyricsTransform.translate, trackId, target, slots);
    final cached = await _readCache(key, slots.length);
    if (cached != null) {
      // The same-language answer is cached too, so a song already in the target
      // language costs no request on the second tap either.
      return sameLanguage(cached.sourceLanguage, target)
          ? LyricsTransformSameLanguage(cached.sourceLanguage)
          : LyricsTransformReady(
              lines: _rebuild(lines, slots, cached.texts),
              sourceLanguage: cached.sourceLanguage,
              fromCache: true,
            );
    }

    final batches = _batches(slots);
    final answers = await _runBatches(
      batches,
      (batch) => _requestBatch(
        batch,
        kind: LyricsTransform.translate,
        target: target,
      ),
      cancel,
    );
    if (answers == null) return const LyricsTransformUnavailable();

    final source = _majoritySource(answers);
    if (source.isEmpty) return const LyricsTransformUnavailable();

    var translated = [for (final answer in answers) ...answer.texts];
    if (translated.length != slots.length) {
      return const LyricsTransformUnavailable();
    }

    // The endpoint's ordinary auto-detection understands many Latin-script
    // Hindi/Urdu/Punjabi lyrics, but its model sometimes returns whole phrases
    // unchanged ("tera hone laga hoon"). When a sizeable part of a Latin-script
    // source survived untouched, ask Input Tools for the detected language's
    // native script and translate THAT. The retry is kept only if it actually
    // transforms more of the song: names and genuinely bilingual lyrics contain
    // Latin text that is supposed to stay, and must not get worse for it.
    if (!sameLanguage(source, target) &&
        _predominantlyLatin(slots) &&
        _unchangedWeight(slots, translated) * 3 >= _totalLength(slots)) {
      final retried = await _retryWithNativeScript(
        batches,
        source,
        target,
        cancel,
      );
      if (retried != null &&
          retried.length == slots.length &&
          _unchangedWeight(slots, retried) <
              _unchangedWeight(slots, translated)) {
        translated = retried;
      }
    }

    if (cancel?.isCancelled ?? false) return const LyricsTransformUnavailable();

    await _writeCache(
      key,
      _CachedTransform(
        sourceLanguage: source,
        targetLanguage: target,
        texts: translated,
      ),
    );

    return sameLanguage(source, target)
        ? LyricsTransformSameLanguage(source)
        : LyricsTransformReady(
            lines: _rebuild(lines, slots, translated),
            sourceLanguage: source,
            fromCache: false,
          );
  }

  Future<LyricsTransformResult> _romanize(
    String trackId,
    List<String> lines,
    String targetLanguage,
    LyricsCancelToken? cancel,
  ) async {
    if (lines.isEmpty) return const LyricsTransformUnavailable();
    final slots = _flatten(lines);
    if (slots.isEmpty) return const LyricsTransformUnavailable();

    // Romanizing text that is already Latin cannot produce anything the reader
    // does not have on screen. Decided HERE, before any request, because the
    // endpoint will happily echo the original back and the caller cannot tell a
    // genuine no-op from a transliteration that happened to be identical.
    if (!_hasNonLatinLetters(slots.map((s) => s.text))) {
      return const LyricsTransformSameLanguage();
    }

    // Romanization always ends in Latin script. The translation destination is
    // still sent as `tl` because the endpoint requires one, but it is
    // deliberately excluded from this cache key: changing "translate to" cannot
    // change how the source language is pronounced, and keying on it would
    // refetch the same pronunciation for every language the reader tried.
    final key = _cacheKeyFor(LyricsTransform.romanize, trackId, '', slots);
    final cached = await _readCache(key, slots.length);
    if (cached != null) {
      return LyricsTransformReady(
        lines: _rebuild(lines, slots, cached.texts),
        sourceLanguage: cached.sourceLanguage,
        fromCache: true,
      );
    }

    final target = targetLanguage.trim().isEmpty ? 'en' : targetLanguage.trim();
    final answers = await _runBatches(
      _batches(slots),
      (batch) => _requestBatch(
        batch,
        kind: LyricsTransform.romanize,
        target: target,
      ),
      cancel,
    );
    if (answers == null) return const LyricsTransformUnavailable();

    final source = _majoritySource(answers);
    final romanized = [for (final answer in answers) ...answer.texts];
    if (source.isEmpty || romanized.length != slots.length) {
      return const LyricsTransformUnavailable();
    }
    if (_unchangedWeight(slots, romanized) == _totalLength(slots)) {
      // Non-Latin input reached this point, so an unchanged response is an
      // unsupported or failed romanization rather than an already-Latin lyric.
      // The check above handles the real no-op case.
      return const LyricsTransformUnavailable();
    }
    if (cancel?.isCancelled ?? false) return const LyricsTransformUnavailable();

    await _writeCache(
      key,
      _CachedTransform(
        sourceLanguage: source,
        targetLanguage: 'Latn',
        texts: romanized,
      ),
    );
    return LyricsTransformReady(
      lines: _rebuild(lines, slots, romanized),
      sourceLanguage: source,
      fromCache: false,
    );
  }

  // ── Requests ───────────────────────────────────────────────────────────────

  /// Runs [request] for every batch, at most [maxParallelRequests] at a time.
  ///
  /// Null if ANY batch failed or the caller cancelled. A partly translated
  /// lyric is worse than none: the top of the song in one language and the rest
  /// in another reads as a bug, and the offsets of the missing part would have to
  /// be guessed. It also stops issuing requests after the first failure, rather
  /// than spending the rest of the budget on an answer that will be discarded.
  Future<List<BatchAnswer>?> _runBatches(
    List<_Batch> batches,
    Future<BatchAnswer?> Function(_Batch batch) request,
    LyricsCancelToken? cancel,
  ) async {
    final answers = List<BatchAnswer?>.filled(batches.length, null);
    var next = 0;
    var failed = false;

    Future<void> worker() async {
      while (!failed && !(cancel?.isCancelled ?? false)) {
        final index = next++;
        if (index >= batches.length) return;
        final answer = await request(batches[index]);
        if (answer == null) {
          failed = true;
          return;
        }
        answers[index] = answer;
      }
    }

    await Future.wait([
      for (var i = 0; i < maxParallelRequests && i < batches.length; i++)
        worker(),
    ]);

    if (failed || (cancel?.isCancelled ?? false)) return null;
    if (answers.any((a) => a == null)) return null;
    return [for (final answer in answers) answer!];
  }

  Future<BatchAnswer?> _requestBatch(
    _Batch batch, {
    required LyricsTransform kind,
    required String target,
    String sourceLanguage = 'auto',
  }) async {
    try {
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
            headers: _headers,
            body: {
              'client': 'dict-chrome-ex',
              // `auto` for the first pass; the detected language on the retry,
              // so the endpoint is not asked to re-detect native-script text it
              // has just been told the language of.
              'sl': sourceLanguage,
              // Sent as given rather than reduced to a base language: zh-CN and
              // zh-TW are different targets, and collapsing them asks for the
              // wrong script.
              'tl': target,
              // `dt=rm` is what makes this a transliteration rather than a
              // translation. Without it the endpoint answers with the original
              // text translated into the target language, which is the wrong
              // request entirely.
              'dt': kind == LyricsTransform.romanize ? 'rm' : 't',
              'q': batch.payload,
            },
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      // Decoded from bytes rather than via `response.body`, which trusts the
      // Content-Type charset and mangles UTF-8 served as latin-1.
      return parseBatchReply(
        utf8.decode(response.bodyBytes, allowMalformed: true),
        kind: kind,
        expectedSlots: batch.slots.length,
        weight: batch.payload.length,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsTranslation: request failed: $e');
      return null;
    }
  }

  /// Re-asks for the lyric after restoring its native script.
  ///
  /// Null on any failure, which leaves the first answer standing: the retry is an
  /// improvement attempt, never a requirement.
  Future<List<String>?> _retryWithNativeScript(
    List<_Batch> batches,
    String sourceLanguage,
    String target,
    LyricsCancelToken? cancel,
  ) async {
    final source = canonicalLanguage(sourceLanguage);
    // English written in Latin is not a transliteration of anything.
    if (source.isEmpty || source == 'en') return null;

    final answers = await _runBatches(batches, (batch) async {
      final native = await _requestNativeScript(batch.payload, source);
      if (native == null) return null;
      return _requestBatch(
        batch.withPayload(native),
        kind: LyricsTransform.translate,
        target: target,
        sourceLanguage: source,
      );
    }, cancel);
    if (answers == null) return null;
    return [for (final answer in answers) ...answer.texts];
  }

  /// Input Tools: Latin-script text back into [sourceLanguage]'s own script.
  Future<String?> _requestNativeScript(
    String text,
    String sourceLanguage,
  ) async {
    try {
      final response = await _client
          .post(
            _inputToolsUri,
            headers: _headers,
            body: {
              'text': text,
              'itc': '$sourceLanguage-t-i0-und',
              'num': '1',
              'cp': '0',
              'cs': '1',
              'ie': 'utf-8',
              'oe': 'utf-8',
            },
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return parseNativeScriptReply(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsTranslation: input tools failed: $e');
      return null;
    }
  }

  // ── Reading answers ────────────────────────────────────────────────────────

  /// Reads one translate/romanize response back out.
  ///
  /// The body is a JSON array whose first element is the segment list and whose
  /// third is the detected language. WHICH field of a segment holds the answer
  /// depends on the mode (0 translated, 3 transliterated); the fields of every
  /// segment are concatenated and split on the markers, because segments are
  /// sentences and not lines.
  ///
  /// Null unless the number of parts is EXACTLY [expectedSlots] and none is blank.
  /// A lost marker means the endpoint merged two lines, and handing back a short
  /// list would put each line's text on its neighbour - silently wrong, and not
  /// detectable afterwards. A null sends the caller back to the originals, which
  /// is at least visibly true.
  ///
  /// Defensive throughout: a shape change must degrade to "no transform" rather
  /// than throw into the lyrics screen.
  @visibleForTesting
  static BatchAnswer? parseBatchReply(
    String body, {
    required LyricsTransform kind,
    required int expectedSlots,
    int weight = 0,
  }) {
    try {
      final root = jsonDecode(body);
      if (root is! List || root.isEmpty) return null;
      final segments = root.first;
      if (segments is! List) return null;

      final field = kind == LyricsTransform.romanize
          ? _romanizedSegmentField
          : _translatedSegmentField;

      final joined = StringBuffer();
      for (final segment in segments) {
        if (segment is! List || segment.length <= field) continue;
        final text = segment[field];
        if (text is String) joined.write(text);
      }

      final detected =
          root.length > 2 && root[2] is String ? root[2] as String : '';
      final parts = joined
          .toString()
          .split(_markerPattern)
          .map((part) => part.trim())
          .toList();

      if (parts.length != expectedSlots || parts.any((p) => p.isEmpty)) {
        return null;
      }
      // A romanization with no detected language cannot be attributed to a
      // source, and the cache entry would carry an empty one.
      if (kind == LyricsTransform.romanize && detected.isEmpty) return null;
      return BatchAnswer(parts, detected, weight);
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsTranslation: bad body: $e');
      return null;
    }
  }

  /// Reads an Input Tools answer: `["SUCCESS", [[input, [native], ...]]]`.
  @visibleForTesting
  static String? parseNativeScriptReply(String body) {
    try {
      final root = jsonDecode(body);
      if (root is! List || root.length < 2 || root[0] != 'SUCCESS') return null;
      final text = ((((root[1] as List)[0] as List)[1]) as List)[0];
      return text is String && text.trim().isNotEmpty ? text : null;
    } catch (e) {
      return null;
    }
  }

  /// The language the payload-weighted majority of batches was detected as.
  ///
  /// By characters sent, not by batch count: a three-line chorus batch must not
  /// outvote four thousand characters of verses.
  static String _majoritySource(List<BatchAnswer> answers) {
    final weights = <String, int>{};
    for (final answer in answers) {
      weights.update(
        canonicalLanguage(answer.sourceLanguage),
        (total) => total + answer.weight,
        ifAbsent: () => answer.weight,
      );
    }
    var best = '';
    var bestWeight = -1;
    for (final entry in weights.entries) {
      if (entry.value > bestWeight) {
        best = entry.key;
        bestWeight = entry.value;
      }
    }
    return best;
  }

  // ── Slots and batches ──────────────────────────────────────────────────────

  /// The non-blank lines, in order, with section headers unwrapped.
  ///
  /// `[Chorus]` is sent as `Chorus` and put back in brackets afterwards: the
  /// brackets make the endpoint treat it as markup, and a translated header with
  /// its brackets lost reads as a lyric line. A header with nothing inside
  /// (`[ ]`) is dropped like a blank line - sent, it would come back as an empty
  /// part and fail the whole song.
  static List<_Slot> _flatten(List<String> lines) {
    final slots = <_Slot>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      if (isGeniusSectionHeader(line)) {
        final inner = line.trim();
        final text = inner.substring(1, inner.length - 1).trim();
        if (text.isEmpty) continue;
        slots.add(_Slot(i, text, true));
      } else {
        slots.add(_Slot(i, line, false));
      }
    }
    return slots;
  }

  /// Splits [slots] into batches under [maxBatchChars].
  ///
  /// A single line longer than the limit is sent on its own rather than being
  /// split mid-sentence. One over-long line is a bad request; a lyric broken in
  /// half is worse. The length counted is the PAYLOAD's, markers included, so the
  /// cap holds for what is actually sent.
  static List<_Batch> _batches(List<_Slot> slots) {
    final batches = <_Batch>[];
    var current = <_Slot>[];
    var length = 0;

    for (final slot in slots) {
      final withSeparator =
          slot.text.length + (current.isEmpty ? 0 : _separatorChars);
      if (current.isNotEmpty && length + withSeparator > maxBatchChars) {
        batches.add(_Batch(current));
        current = <_Slot>[];
        length = 0;
      }
      // Counted AFTER the flush: the first line of a batch has no separator in
      // front of it, so charging it one would end every batch eight characters
      // early.
      length += slot.text.length + (current.isEmpty ? 0 : _separatorChars);
      current.add(slot);
    }
    if (current.isNotEmpty) batches.add(_Batch(current));
    return batches;
  }

  /// `\uE000` + a four-digit counter + `\uE001`.
  static String _marker(int index) =>
      '$_markerStart${index.toString().padLeft(4, '0')}$_markerEnd';

  static String _payloadOf(List<_Slot> slots) {
    final out = StringBuffer();
    for (var i = 0; i < slots.length; i++) {
      // The first line has no marker before it; the counter is the index of the
      // line it introduces, so it starts at 0001.
      if (i > 0) out.write('\n${_marker(i)}\n');
      out.write(slots[i].text);
    }
    return out.toString();
  }

  /// Puts the transformed text back at the line each slot came from.
  static List<String> _rebuild(
    List<String> original,
    List<_Slot> slots,
    List<String> texts,
  ) {
    final out = List<String>.of(original);
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      out[slot.lineIndex] = slot.sectionHeader ? '[${texts[i]}]' : texts[i];
    }
    return out;
  }

  // ── Script and language rules ──────────────────────────────────────────────

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);

  /// Whether [cp] is a letter of the Latin SCRIPT (accented, Vietnamese, fullwidth
  /// included). The ranges below are the Latin blocks; the caller has already
  /// established that [cp] is a letter.
  static bool _isLatinLetterCodePoint(int cp) {
    if (cp < 0x80) return true; // A-Z / a-z, the only ASCII letters
    return cp == 0xAA ||
        cp == 0xBA ||
        // Latin-1, Extended A/B, IPA and the modifier letters. The modifiers
        // (U+02B9-02FF) are Common-script rather than Latin, but they turn up
        // INSIDE Latin words - the okina in Hawaiian, the apostrophe in
        // Uzbek - and must not make an all-Latin lyric look romanizable.
        (cp >= 0xC0 && cp <= 0x2FF) ||
        (cp >= 0x1D00 && cp <= 0x1D25) ||
        (cp >= 0x1D2C && cp <= 0x1D5C) ||
        (cp >= 0x1D62 && cp <= 0x1D65) ||
        (cp >= 0x1D6B && cp <= 0x1D77) ||
        (cp >= 0x1D79 && cp <= 0x1DBE) ||
        (cp >= 0x1E00 && cp <= 0x1EFF) || // Latin Extended Additional
        cp == 0x2071 ||
        cp == 0x207F ||
        (cp >= 0x2090 && cp <= 0x209C) ||
        cp == 0x212A ||
        cp == 0x212B ||
        cp == 0x2132 ||
        cp == 0x214E ||
        (cp >= 0x2C60 && cp <= 0x2C7F) ||
        (cp >= 0xA722 && cp <= 0xA787) ||
        (cp >= 0xA78B && cp <= 0xA7FF) ||
        (cp >= 0xAB30 && cp <= 0xAB5A) ||
        (cp >= 0xAB5C && cp <= 0xAB64) ||
        (cp >= 0xFB00 && cp <= 0xFB06) ||
        (cp >= 0xFF21 && cp <= 0xFF3A) ||
        (cp >= 0xFF41 && cp <= 0xFF5A);
  }

  static bool _isLetter(int cp) {
    if (cp < 0x80) {
      return (cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A);
    }
    return _letter.hasMatch(String.fromCharCode(cp));
  }

  /// Whether any LETTER in [texts] is not Latin.
  ///
  /// Letters only, so punctuation, digits, symbols and emoji can never decide it.
  /// The first version here called anything at or above U+0250 non-Latin, which
  /// included the curly apostrophe in "don’t", every en dash and every music note:
  /// an ordinary English lyric was offered a romanization that could only echo it
  /// back.
  static bool _hasNonLatinLetters(Iterable<String> texts) {
    for (final text in texts) {
      for (final cp in text.runes) {
        if (_isLetter(cp) && !_isLatinLetterCodePoint(cp)) return true;
      }
    }
    return false;
  }

  /// Whether the lyric is mostly Latin: Latin letters at least 4x the others.
  ///
  /// This gates the native-script retry, which only makes sense for a Latin
  /// rendering of some other language. A lyric with real Hindi or Japanese in it
  /// is already in its own script and has nothing to restore.
  static bool _predominantlyLatin(List<_Slot> slots) {
    var latin = 0;
    var other = 0;
    for (final slot in slots) {
      for (final cp in slot.text.runes) {
        if (!_isLetter(cp)) continue;
        if (_isLatinLetterCodePoint(cp)) {
          latin++;
        } else {
          other++;
        }
      }
    }
    return latin > 0 && latin >= other * 4;
  }

  static int _totalLength(List<_Slot> slots) =>
      slots.fold(0, (total, slot) => total + slot.text.length);

  /// The characters (not lines) whose transformed text equals the source.
  ///
  /// Weighted by length so one long untouched verse counts for more than several
  /// untouched interjections.
  static int _unchangedWeight(List<_Slot> slots, List<String> transformed) {
    var weight = 0;
    final count =
        slots.length < transformed.length ? slots.length : transformed.length;
    for (var i = 0; i < count; i++) {
      if (_comparable(slots[i].text) == _comparable(transformed[i])) {
        weight += slots[i].text.length;
      }
    }
    return weight;
  }

  static String _comparable(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Whether a line is already in Latin script.
  ///
  /// Used to skip a romanization request that could only echo the original back:
  /// the answer would cost a round trip to produce text identical to what is
  /// already showing. Empty and symbol-only text counts as Latin.
  static bool isLatinScript(String text) => !_hasNonLatinLetters([text]);

  /// Whether every line is already Latin, so romanization has nothing to do.
  ///
  /// ALL of them, not any: a lyric is a single artefact and one Japanese line
  /// among thirty English ones still needs transliterating. Reporting the whole
  /// song as already-romanized because most of it is would leave that one line
  /// wrong with no way back.
  ///
  /// Public because the disc needs the answer BEFORE the tap resolves, to tint
  /// itself the moment the reader looks at it rather than after a round trip. Two
  /// callers, one rule.
  static bool isAlreadyRomanizable(List<String> lines) {
    var anyText = false;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      anyText = true;
      if (_hasNonLatinLetters([line])) return false;
    }
    // All blank: nothing to romanize, and nothing worth reporting as a miss.
    return anyText;
  }

  static final Expando<bool> _latinMemo = Expando<bool>('lyricsAreLatin');

  /// [isAlreadyRomanizable] over a lyric, remembered per list.
  ///
  /// The disc asks on every rebuild, and the controller notifies at frame rate
  /// during a reveal; scanning a few thousand characters sixty times a second to
  /// re-learn the same answer is waste. The list a provider hands out is replaced,
  /// never mutated, so identity is a safe key.
  static bool entriesAreLatin(List<LyricsEntry> entries) {
    final known = _latinMemo[entries];
    if (known != null) return known;
    final result = isAlreadyRomanizable([for (final e in entries) e.text]);
    _latinMemo[entries] = result;
    return result;
  }

  // ── Language names ─────────────────────────────────────────────────────────

  /// English names for the languages lyrics are most often written in, keyed by
  /// base subtag.
  static const Map<String, String> _languageNames = <String, String>{
    'af': 'Afrikaans',
    'ar': 'Arabic',
    'az': 'Azerbaijani',
    'bg': 'Bulgarian',
    'bn': 'Bengali',
    'ca': 'Catalan',
    'cs': 'Czech',
    'cy': 'Welsh',
    'da': 'Danish',
    'de': 'German',
    'el': 'Greek',
    'en': 'English',
    'es': 'Spanish',
    'et': 'Estonian',
    'fa': 'Persian',
    'fi': 'Finnish',
    'fil': 'Filipino',
    'fr': 'French',
    'ga': 'Irish',
    'gu': 'Gujarati',
    'he': 'Hebrew',
    'hi': 'Hindi',
    'hr': 'Croatian',
    'hu': 'Hungarian',
    'hy': 'Armenian',
    'id': 'Indonesian',
    'is': 'Icelandic',
    'it': 'Italian',
    'ja': 'Japanese',
    'ka': 'Georgian',
    'kk': 'Kazakh',
    'kn': 'Kannada',
    'ko': 'Korean',
    'la': 'Latin',
    'lt': 'Lithuanian',
    'lv': 'Latvian',
    'mk': 'Macedonian',
    'ml': 'Malayalam',
    'mn': 'Mongolian',
    'mr': 'Marathi',
    'ms': 'Malay',
    'my': 'Burmese',
    'ne': 'Nepali',
    'nl': 'Dutch',
    'no': 'Norwegian',
    'pa': 'Punjabi',
    'pl': 'Polish',
    'pt': 'Portuguese',
    'ro': 'Romanian',
    'ru': 'Russian',
    'si': 'Sinhala',
    'sk': 'Slovak',
    'sl': 'Slovenian',
    'sq': 'Albanian',
    'sr': 'Serbian',
    'sv': 'Swedish',
    'sw': 'Swahili',
    'ta': 'Tamil',
    'te': 'Telugu',
    'th': 'Thai',
    'tl': 'Filipino',
    'tr': 'Turkish',
    'uk': 'Ukrainian',
    'ur': 'Urdu',
    'uz': 'Uzbek',
    'vi': 'Vietnamese',
    'yi': 'Yiddish',
    'zh': 'Chinese',
    'zu': 'Zulu',
  };

  /// A human-readable English name for a language [code], for the toast and the
  /// caption ("Already in Japanese", "Translated to Hindi").
  ///
  /// The code is reduced to its base subtag first, and the legacy codes the
  /// endpoint still answers with are folded (`iw` -> Hebrew, `in` ->
  /// Indonesian, `ji` -> Yiddish), so the name agrees with what [sameLanguage]
  /// decided. Chinese is the one place the region/script is kept, because
  /// "Chinese" alone does not say which script the reader asked for: `zh-CN` and
  /// `zh-Hans` read "Chinese (Simplified)", `zh-TW`, `zh-HK` and `zh-Hant` read
  /// "Chinese (Traditional)".
  ///
  /// An unknown code is returned upper-cased rather than hidden or guessed at:
  /// "Already in XX" is ugly but true, "Already in English" would be a lie.
  static String languageName(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.toLowerCase().split(RegExp(r'[-_]'));
    final base = canonicalLanguage(trimmed);
    if (base == 'zh') {
      final rest = parts.skip(1).toSet();
      if (rest.any(const {'tw', 'hk', 'mo', 'hant'}.contains)) {
        return 'Chinese (Traditional)';
      }
      if (rest.any(const {'cn', 'sg', 'hans'}.contains)) {
        return 'Chinese (Simplified)';
      }
    }
    return _languageNames[base] ?? trimmed.toUpperCase();
  }

  /// The base subtag of a language tag, with the legacy codes folded.
  ///
  /// `iw` -> `he`, `in` -> `id`, `ji` -> `yi`: the endpoint and older platform
  /// locales still say the old ones, and comparing them raw would call Hebrew
  /// detected as `iw` a different language from a `he` target. Lower-cased, and
  /// `_` is accepted as a separator because `Platform.localeName` uses it
  /// (`pt_BR`).
  static String canonicalLanguage(String tag) {
    final base = tag.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    return switch (base) {
      'iw' => 'he',
      'in' => 'id',
      'ji' => 'yi',
      _ => base,
    };
  }

  /// Whether [first] and [second] are the same language once reduced to a base
  /// subtag. Asks a different question from the one the request asks: the
  /// request keeps `zh-TW` as typed (the script matters to the reader), this
  /// only decides whether there is anything to translate.
  static bool sameLanguage(String first, String second) {
    final a = canonicalLanguage(first);
    final b = canonicalLanguage(second);
    return a.isNotEmpty && a == b;
  }

  // ── Applying the answer ────────────────────────────────────────────────────

  /// Replaces the text of each entry, keeping every timestamp.
  ///
  /// The timings are never translated. Word and syllable spans are dropped
  /// deliberately: they index into the ORIGINAL characters and would clip the
  /// wrong letters against a translation. The line keeps its timestamps and falls
  /// back to whole-line reveal.
  static List<LyricsEntry> applyText(List<LyricsEntry> entries, List<String> texts) {
    if (texts.length != entries.length) return entries;
    return [
      for (var i = 0; i < entries.length; i++)
        LyricsEntry(
          timeMs: entries[i].timeMs,
          endMs: entries[i].endMs,
          text: texts[i].isEmpty ? entries[i].text : texts[i],
          lyricWords: null,
          words: null,
        ),
    ];
  }

  // ── The cache ──────────────────────────────────────────────────────────────

  /// The cache key, as a SHA-256 hex digest.
  ///
  /// Hashed so the key is a safe filename and carries no lyric text into a path.
  /// Includes the track and the text itself, so a different provider's version of
  /// the same song (different words) cannot be served the wrong answer.
  ///
  /// The target language is part of a TRANSLATE key and deliberately not of a
  /// ROMANIZE key: see [_romanize].
  static String _cacheKeyFor(
    LyricsTransform kind,
    String trackId,
    String target,
    List<_Slot> slots,
  ) {
    // The kind is in the key as well as the target: Kotlin used the literal
    // "romanize" in the target's place, so a translation target that was ever
    // spelled that way would have been served a romanization from the cache.
    final source = StringBuffer()
      ..write(trackId)
      ..write('\u0000')
      ..write(kind.name)
      ..write('\u0000')
      ..write(kind == LyricsTransform.romanize ? '' : target);
    for (final slot in slots) {
      source
        ..write('\u0000')
        ..write(slot.text);
    }
    return sha256.convert(utf8.encode(source.toString())).toString();
  }

  /// The key a request would be cached under, for tests that pin the rules.
  @visibleForTesting
  static String cacheKeyForTest({
    required LyricsTransform kind,
    required String trackId,
    required String targetLanguage,
    required List<String> lines,
  }) =>
      _cacheKeyFor(kind, trackId, targetLanguage.trim(), _flatten(lines));

  final Map<String, _CachedTransform> _memory = <String, _CachedTransform>{};

  /// A tail of the disk operations, so two never interleave.
  ///
  /// A read that lands between a write's temp file and its rename, or a trim that
  /// deletes a file a read has just opened, would otherwise surface as a corrupt
  /// entry.
  ///
  /// Null until the first operation rather than `Future.value()`: a future made
  /// when the service is constructed belongs to THAT zone, and one operation
  /// started from another (a widget test's fake-async zone) would wait on it for
  /// ever.
  Future<void>? _diskTail;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _diskTail;
    final result = previous == null ? action() : previous.then((_) => action());
    _diskTail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  _CachedTransform? _memoryGet(String key) {
    final hit = _memory.remove(key);
    // Re-inserted so it becomes the most recently USED, not merely the most
    // recently written: the entry the reader keeps flipping back to must not be
    // the one evicted.
    if (hit != null) _memory[key] = hit;
    return hit;
  }

  void _memoryPut(String key, _CachedTransform value) {
    _memory.remove(key);
    _memory[key] = value;
    while (_memory.length > maxMemoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<_CachedTransform?> _readCache(String key, int expectedTexts) async {
    final cached = _memoryGet(key) ?? await _readDisk(key);
    if (cached == null || cached.texts.length != expectedTexts) return null;
    _memoryPut(key, cached);
    return cached;
  }

  Future<void> _writeCache(String key, _CachedTransform value) async {
    _memoryPut(key, value);
    await _writeDisk(key, value);
  }

  Future<Directory?> _directory({required bool create}) async {
    final root = await _cacheRoot();
    if (root == null) return null;
    final dir = Directory('${root.path}/$cacheDirectoryName');
    if (create && !await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<_CachedTransform?> _readDisk(String key) => _serialized(() async {
        try {
          final dir = await _directory(create: false);
          if (dir == null) return null;
          final file = File('${dir.path}/$key.json.gz');
          if (!await file.exists()) return null;
          final decoded =
              jsonDecode(utf8.decode(gzip.decode(await file.readAsBytes())));
          final cached = _CachedTransform.tryParse(decoded);
          if (cached == null) return null;
          // Touched, so the trim below keeps what is being used rather than what
          // was merely written longest ago.
          try {
            await file.setLastModified(DateTime.now());
          } catch (_) {}
          return cached;
        } catch (e) {
          // A cache miss is always recoverable by refetching.
          return null;
        }
      });

  Future<void> _writeDisk(String key, _CachedTransform value) =>
      _serialized(() async {
        File? temp;
        try {
          final dir = await _directory(create: true);
          if (dir == null) return;
          final destination = File('${dir.path}/$key.json.gz');
          // Written beside the destination and renamed over it, so a reader never
          // sees half a file.
          temp = File('${dir.path}/$key.tmp');
          await temp.writeAsBytes(
            gzip.encode(utf8.encode(jsonEncode(value.toJson()))),
            flush: true,
          );
          try {
            await temp.rename(destination.path);
          } on FileSystemException {
            await temp.copy(destination.path);
            await temp.delete();
          }
          await _trim(dir);
        } catch (e) {
          if (kDebugMode) debugPrint('LyricsTranslation: disk write: $e');
          try {
            await temp?.delete();
          } catch (_) {}
        }
      });

  /// Keeps the newest entries that fit in [maxDiskBytes] and deletes the rest.
  ///
  /// Newest first: once the running total passes the budget, that file and every
  /// older one go. Deleting the largest instead (as this once did) throws away
  /// the song the reader is looking at whenever it happens to be long.
  Future<void> _trim(Directory dir) async {
    final entries = <({File file, DateTime modified, int length})>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.gz')) continue;
      entries.add((
        file: entity,
        modified: await entity.lastModified(),
        length: await entity.length(),
      ));
    }
    entries.sort((a, b) => b.modified.compareTo(a.modified));
    var kept = 0;
    for (final entry in entries) {
      kept += entry.length;
      if (kept > maxDiskBytes) {
        try {
          await entry.file.delete();
        } catch (_) {}
      }
    }
  }

  /// Clears every cached transform, memory and disk.
  Future<void> clear() async {
    _memory.clear();
    await _serialized(() async {
      try {
        final dir = await _directory(create: false);
        if (dir != null && await dir.exists()) await dir.delete(recursive: true);
      } catch (e) {
        if (kDebugMode) debugPrint('LyricsTranslation: clear: $e');
      }
    });
  }

  // ── Test seams ─────────────────────────────────────────────────────────────

  /// Exposes the batching for tests, as the lines of each batch.
  ///
  /// The split is the part with real rules in it - the character cap, the
  /// refusal to break a single over-long line - so it is worth testing directly
  /// rather than only through a live request.
  @visibleForTesting
  List<List<String>> batchesForTest(List<String> lines) => [
        for (final batch in _batches(_flatten(lines)))
          [for (final slot in batch.slots) slot.text],
      ];

  /// Exposes the exact payload of each batch: lines joined by numbered markers.
  @visibleForTesting
  List<String> payloadsForTest(List<String> lines) =>
      [for (final batch in _batches(_flatten(lines))) batch.payload];

  /// Exposes the translate reader for tests.
  @visibleForTesting
  static List<String>? parseReplyForTest(String body, int expectedLines) =>
      parseBatchReply(
        body,
        kind: LyricsTransform.translate,
        expectedSlots: expectedLines,
      )?.texts;

  /// Exposes the mode-aware reader, because WHICH field is read is the whole
  /// point: a test that only checked translation would pass while romanization
  /// returned un-romanized text.
  @visibleForTesting
  static List<String>? parseRomanizedForTest(String body, int expectedLines) =>
      parseBatchReply(
        body,
        kind: LyricsTransform.romanize,
        expectedSlots: expectedLines,
      )?.texts;

  /// The memory cache's keys, least recently used first.
  @visibleForTesting
  List<String> get memoryKeysForTest => List<String>.of(_memory.keys);

  /// Whether Latin letters are at least four times all the others.
  @visibleForTesting
  static bool predominantlyLatinForTest(List<String> lines) =>
      _predominantlyLatin(_flatten(lines));

  void close() => _client.close();
}

/// One line of the lyric, as sent.
class _Slot {
  const _Slot(this.lineIndex, this.text, this.sectionHeader);

  final int lineIndex;
  final String text;
  final bool sectionHeader;
}

/// Lines sent in one request.
class _Batch {
  _Batch(this.slots) : payload = LyricsTranslationService._payloadOf(slots);
  _Batch._(this.slots, this.payload);

  final List<_Slot> slots;
  final String payload;

  /// The same lines with a different text to send: the native-script retry.
  _Batch withPayload(String payload) => _Batch._(slots, payload);
}

/// What one batch came back as.
@visibleForTesting
class BatchAnswer {
  const BatchAnswer(this.texts, this.sourceLanguage, this.weight);

  final List<String> texts;
  final String sourceLanguage;

  /// Characters sent, which is how much this answer counts toward the source
  /// language.
  final int weight;
}

/// What is stored under a cache key.
class _CachedTransform {
  const _CachedTransform({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.texts,
  });

  final String sourceLanguage;
  final String targetLanguage;
  final List<String> texts;

  Map<String, Object?> toJson() => {
        'version': LyricsTranslationService.cacheVersion,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'texts': texts,
      };

  /// Null for anything that is not a current-version entry.
  static _CachedTransform? tryParse(Object? json) {
    if (json is! Map) return null;
    if (json['version'] != LyricsTranslationService.cacheVersion) return null;
    final texts = json['texts'];
    final source = json['sourceLanguage'];
    final target = json['targetLanguage'];
    if (texts is! List || source is! String || target is! String) return null;
    if (!texts.every((t) => t is String)) return null;
    return _CachedTransform(
      sourceLanguage: source,
      targetLanguage: target,
      texts: texts.cast<String>(),
    );
  }
}
