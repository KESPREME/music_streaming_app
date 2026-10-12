import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/services/lyrics/lyric_clock.dart';
import 'package:music_streaming_app/services/lyrics/lyric_sub_line.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_translation_service.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_sub_line_view.dart';

const TextStyle _style = TextStyle(fontSize: 20, height: 1.0);

/// A reveal pinned at a fixed progress, so a test can state the value instead of
/// driving timers.
class _FrozenReveal extends ChangeNotifier implements SubLineReveal {
  _FrozenReveal(this._progress);

  double _progress;

  @override
  double get progress => _progress;

  void set(double value) {
    _progress = value;
    notifyListeners();
  }
}

LyricsEntry _line(String text, {int timeMs = 0, int endMs = 2000}) =>
    LyricsEntry(
      timeMs: timeMs,
      endMs: endMs,
      text: text,
      words: [
        for (final w in text.split(' ').asMap().entries)
          WordTiming(
            timeMs: timeMs + w.key * 400,
            durationMs: 400,
            text: w.value,
          ),
      ],
    );

/// An original line with its transform underneath, as the panel builds them.
Widget _row({
  required LyricClock clock,
  required LyricsEntry original,
  required LyricsEntry? transform,
  required SubLineReveal reveal,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LyricLine(entry: original, clock: clock, style: _style),
                LyricSubLineView(
                  controller: reveal,
                  clock: clock,
                  style: _style,
                  original: original,
                  entryProvider: () => transform,
                  alpha: 1.0,
                  lit: 1.0,
                  blurSigma: 0.0,
                ),
              ],
            ),
          ),
        ),
      ),
    );

List<RenderLyricLine> _lines(WidgetTester tester) => [
      for (final e in find.byType(LyricLine).evaluate())
        tester.renderObject<RenderLyricLine>(find.byWidget(e.widget)),
    ];

void main() {
  late LyricClock clock;
  setUp(() => clock = LyricClock(now: () => 0));
  tearDown(() => clock.dispose());

  group('the transform is a sub-line, never a replacement', () {
    testWidgets('the original text stays exactly as it was', (tester) async {
      // THE REGRESSION THIS PINS: replacing the line's text makes every word
      // timing index the wrong characters, because those timings are spans of the
      // ORIGINAL string. The wipe then lights words that are not being sung.
      final original = _line('so here I am');
      await tester.pumpWidget(_row(
        clock: clock,
        original: original,
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: _FrozenReveal(1),
      ));

      final lines = _lines(tester);
      expect(lines.length, 2, reason: 'the original and, beneath it, its transform');
      expect(lines[0].entry.text, 'so here I am');
      expect(lines[1].entry.text, 'ich bin wieder da');
      expect(lines[0].entry.timedWords.length, 4,
          reason: 'the original keeps its own word timings');
    });

    testWidgets('the transform sweeps IN STEP with the original it sits under',
        (tester) async {
      final original = _line('so here I am'); // 4 words, 400ms each
      await tester.pumpWidget(_row(
        clock: clock,
        original: original,
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: _FrozenReveal(1),
      ));
      final sub = _lines(tester)[1]..debugRecordClips = true;

      // Half way through the ORIGINAL's words.
      clock.reset(800);
      await tester.pump();

      final litRight = sub.debugLitClips.map((c) => c.right).fold<double>(0, (a, b) => a > b ? a : b);
      final width = sub.geometry.rows.single.right;
      expect(litRight, greaterThan(width * 0.3));
      expect(litRight, lessThan(width * 0.9),
          reason: 'a translation has no timings of its own: it follows the '
              'original proportionally rather than sitting fully lit');
    });
  });

  group('the reveal', () {
    testWidgets('a closed transform reserves no height and draws nothing',
        (tester) async {
      await tester.pumpWidget(_row(
        clock: clock,
        original: _line('so here I am'),
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: _FrozenReveal(0),
      ));

      expect(_lines(tester).length, 1,
          reason: 'hidden: not even built, so a list of thirty rows pays nothing');
      expect(tester.getSize(find.byType(LyricSubLineView)).height, 0);
    });

    testWidgets('no transform available draws nothing', (tester) async {
      await tester.pumpWidget(_row(
        clock: clock,
        original: _line('so here I am'),
        transform: null,
        reveal: _FrozenReveal(1),
      ));
      expect(_lines(tester).length, 1);
    });

    testWidgets('the height opens with the reveal', (tester) async {
      final reveal = _FrozenReveal(1);
      await tester.pumpWidget(_row(
        clock: clock,
        original: _line('so here I am'),
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: reveal,
      ));
      final full = tester.getSize(find.byType(LyricSubLineView)).height;
      expect(full, greaterThan(0));

      reveal.set(0.5);
      await tester.pump();
      expect(tester.getSize(find.byType(LyricSubLineView)).height,
          closeTo(full * 0.5, 1.0));
    });

    testWidgets('it fades in SQUARED: faint for most of the travel, full on '
        'arrival', (tester) async {
      final reveal = _FrozenReveal(0.5);
      await tester.pumpWidget(_row(
        clock: clock,
        original: _line('so here I am'),
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: reveal,
      ));
      final sub = _lines(tester)[1];
      // 0.85 (sub-line alpha) * 0.5 * 0.5
      expect(sub.debugAlpha, closeTo(0.85 * 0.25, 0.01));

      reveal.set(1.0);
      await tester.pump();
      expect(_lines(tester)[1].debugAlpha, closeTo(0.85, 0.01));
    });

    testWidgets('the sliding sub-line is CLIPPED, so it cannot draw over the '
        'original while it travels', (tester) async {
      // The old reveal let the text slide up over the line above it, which drew
      // two lines of text on top of each other when a translation was toggled.
      await tester.pumpWidget(_row(
        clock: clock,
        original: _line('so here I am'),
        transform: LyricsEntry(timeMs: 0, text: 'ich bin wieder da'),
        reveal: _FrozenReveal(0.4),
      ));
      expect(
        find.descendant(
          of: find.byType(LyricSubLineView),
          matching: find.byType(ClipRect),
        ),
        findsOneWidget,
      );
    });
  });

  group('the controller', () {
    test('a transform for the wrong track is refused', () {
      // Painting the previous song's translation under this one is worse than
      // having no sub-line, and nothing about that is recoverable by looking at it.
      final c = SubLineController();
      addTearDown(c.dispose);
      c.onTrackChanged('t1');
      expect(c.lines, isNull);
      expect(c.mode, SubLineMode.original);
    });

    test('a track change resets the mode with the transform', () {
      final c = SubLineController();
      addTearDown(c.dispose);
      c.onTrackChanged('t2');
      // Leaving it on "translated" would label the originals as a translation.
      expect(c.mode, SubLineMode.original);
      expect(c.progress, 0);
    });

    test('the same track does not clear a transform it still owns', () {
      final c = SubLineController();
      addTearDown(c.dispose);
      c.onTrackChanged('t1');
      c.onTrackChanged('t1');
      expect(c.mode, SubLineMode.original);
    });

    test('which transform each mode fetches', () {
      expect(transformFor(SubLineMode.original), isNull);
      expect(transformFor(SubLineMode.romanized), isNotNull);
      expect(transformFor(SubLineMode.translated), isNotNull);
    });

    test('the mode enum holds exactly one value at a time', () {
      // Two transforms sharing the gap under the same line would leave the
      // reader with no way to tell which is which.
      expect(SubLineMode.values.length, 3,
          reason: 'one mode at a time is what makes the sub-line unambiguous');
    });
  });

  group('the state machine', () {
    // The reference keys every bit of this on (track, language, lyric) and lets
    // exactly one transform run at a time (`rememberLyricsTranslation`). A
    // recorded transformer stands in for the network, so what is asserted is the
    // controller's own behaviour.

    const lyric = ['ねこが 好き', 'これは テスト です'];
    const english = ['I like cats', 'this is a test'];
    const roman = ['Neko ga suki', 'kore wa tesutodesu'];

    late _Wire wire;
    late List<SubLineHaptic> haptics;
    late SubLineController controller;

    setUp(() {
      wire = _Wire();
      haptics = [];
      controller = SubLineController(
        transformer: wire.call,
        haptics: haptics.add,
      );
    });
    tearDown(() => controller.dispose());

    Future<SubLineTap> tap(
      SubLineMode mode, {
      String track = 'track-1',
      List<String> lines = lyric,
      String language = 'en',
    }) =>
        controller.toggle(
          mode,
          trackKey: track,
          sourceLines: lines,
          targetLanguage: language,
        );

    LyricsTransformReady done(List<String> lines) => LyricsTransformReady(
          lines: lines,
          sourceLanguage: 'ja',
          fromCache: false,
        );

    test('idle -> loading -> ready, then the transform is the requested mode',
        () async {
      expect(controller.status(SubLineMode.translated), SubLineStatus.idle);

      final pending = tap(SubLineMode.translated);
      expect(controller.status(SubLineMode.translated), SubLineStatus.loading);
      expect(controller.isBusy, isTrue);
      expect(controller.loadingMode, SubLineMode.translated);
      expect(controller.mode, SubLineMode.original,
          reason: 'nothing is shown until there is something to show');

      wire.answer(0, done(english));
      expect(await pending, SubLineTap.shown);

      expect(controller.status(SubLineMode.translated), SubLineStatus.ready);
      expect(controller.isBusy, isFalse);
      expect(controller.mode, SubLineMode.translated);
      expect(controller.displayedLines, english);
      expect(controller.lines, english);
    });

    test('the request carries the track, the lines and the language', () async {
      final pending = tap(SubLineMode.translated, language: ' fr ');
      expect(wire.calls.single.kind, LyricsTransform.translate);
      expect(wire.calls.single.trackId, 'track-1');
      expect(wire.calls.single.lines, lyric);
      expect(wire.calls.single.target, 'fr');
      wire.answer(0, done(english));
      await pending;
    });

    test('when ready, a tap toggles the original and the transform, with no '
        'new request', () async {
      final first = tap(SubLineMode.translated);
      wire.answer(0, done(english));
      await first;

      expect(await tap(SubLineMode.translated), SubLineTap.hidden);
      expect(controller.mode, SubLineMode.original);
      expect(controller.displayedLines, isNull,
          reason: 'the strip goes back to the originals at once');

      expect(await tap(SubLineMode.translated), SubLineTap.shown);
      expect(controller.mode, SubLineMode.translated);
      expect(controller.displayedLines, english);

      expect(wire.calls.length, 1, reason: 'the answer was kept');
    });

    test('a haptic on a successful toggle, and none for a tap that did nothing',
        () async {
      final first = tap(SubLineMode.translated);
      expect(haptics, [SubLineHaptic.tap], reason: 'the ask is acknowledged');

      // Tapped again while it loads: ignored, and silent.
      expect(await tap(SubLineMode.translated), SubLineTap.ignored);
      expect(haptics, [SubLineHaptic.tap]);

      wire.answer(0, done(english));
      await first;
      expect(haptics, [SubLineHaptic.tap, SubLineHaptic.toggleOn]);

      await tap(SubLineMode.translated); // back to the original
      await tap(SubLineMode.translated); // and on again
      expect(haptics.skip(2), [SubLineHaptic.select, SubLineHaptic.select]);
    });

    test('taps on a loading disc are ignored: one request, not two', () async {
      final first = tap(SubLineMode.romanized);
      expect(await tap(SubLineMode.romanized), SubLineTap.ignored);
      expect(await tap(SubLineMode.romanized), SubLineTap.ignored);
      expect(wire.calls.length, 1);
      wire.answer(0, done(roman));
      await first;
    });

    test('starting one mode cancels the other\'s request', () async {
      final translating = tap(SubLineMode.translated);
      final translateCall = wire.calls[0];
      expect(translateCall.token.isCancelled, isFalse);

      final romanizing = tap(SubLineMode.romanized);
      expect(translateCall.token.isCancelled, isTrue,
          reason: 'a slow translation must not land after the reader moved on '
              'to the globe');
      expect(controller.status(SubLineMode.translated), SubLineStatus.idle,
          reason: 'the cancelled disc stops spinning');
      expect(controller.status(SubLineMode.romanized), SubLineStatus.loading);
      expect(controller.loadingMode, SubLineMode.romanized,
          reason: 'at most one request at a time');

      // The cancelled request answers anyway; it must not be shown.
      wire.answer(0, done(english));
      expect(await translating, SubLineTap.superseded);
      expect(controller.mode, SubLineMode.original);
      expect(controller.lines, isNull);
      expect(controller.status(SubLineMode.translated), SubLineStatus.idle);

      wire.answer(1, done(roman));
      expect(await romanizing, SubLineTap.shown);
      expect(controller.mode, SubLineMode.romanized);
      expect(controller.displayedLines, roman,
          reason: 'only the romanization, never the translation');
    });

    test('and the other way round', () async {
      final romanizing = tap(SubLineMode.romanized);
      final translating = tap(SubLineMode.translated);
      expect(wire.calls[0].token.isCancelled, isTrue);
      expect(wire.calls[1].token.isCancelled, isFalse);

      wire.answer(1, done(english));
      expect(await translating, SubLineTap.shown);
      wire.answer(0, done(roman));
      expect(await romanizing, SubLineTap.superseded);
      expect(controller.mode, SubLineMode.translated);
      expect(controller.displayedLines, english);
    });

    test('only one mode is requested at a time, even with both ready', () async {
      final a = tap(SubLineMode.translated);
      wire.answer(0, done(english));
      await a;
      final b = tap(SubLineMode.romanized);
      wire.answer(1, done(roman));
      await b;

      expect(controller.mode, SubLineMode.romanized);
      expect(controller.displayedLines, roman);

      // Tapping the translate disc while the globe is on goes straight to the
      // translation: it is Ready, so there is nothing to fetch and no reason to
      // pass through the original.
      expect(await tap(SubLineMode.translated), SubLineTap.shown);
      expect(controller.mode, SubLineMode.translated);
      expect(controller.displayedLines, english);
      expect(wire.calls.length, 2);
    });

    test('the outgoing sub-line is gone before the incoming one opens',
        () async {
      final a = tap(SubLineMode.translated);
      wire.answer(0, done(english));
      await a;
      await _until(() => controller.progress >= 1);
      final b = tap(SubLineMode.romanized);
      wire.answer(1, done(roman));

      final seen = <(SubLineMode, double)>[];
      controller.addListener(
        () => seen.add((controller.shownMode, controller.progress)),
      );
      await b;
      await _until(
        () =>
            controller.shownMode == SubLineMode.romanized &&
            controller.progress >= 1,
      );

      final firstRoman =
          seen.firstWhere((s) => s.$1 == SubLineMode.romanized);
      expect(firstRoman.$2, 0,
          reason: 'the translation had folded to nothing before the '
              'romanization began to open - never two scripts in one gap');
      expect(
        seen
            .takeWhile((s) => s.$1 != SubLineMode.romanized)
            .every((s) => s.$1 == SubLineMode.translated),
        isTrue,
        reason: 'and until then the translation stays painted, folding away',
      );
    });

    test('a failed request leaves the original alone and a tap tries again',
        () async {
      final first = tap(SubLineMode.translated);
      wire.answer(0, const LyricsTransformUnavailable());
      expect(await first, SubLineTap.unavailable);
      expect(controller.status(SubLineMode.translated), SubLineStatus.unavailable);
      expect(controller.mode, SubLineMode.original);
      expect(controller.lines, isNull);
      expect(controller.alreadyInLanguage, isFalse,
          reason: 'a fault of ours is not a fact about the song');

      final second = tap(SubLineMode.translated);
      expect(controller.status(SubLineMode.translated), SubLineStatus.loading);
      wire.answer(1, done(english));
      expect(await second, SubLineTap.shown);
      expect(wire.calls.length, 2);
    });

    test('a transformer that throws is unavailable, not an error', () async {
      final throwing = SubLineController(
        transformer: ({
          required trackId,
          required lines,
          required kind,
          required targetLanguage,
          cancel,
        }) async =>
            throw StateError('boom'),
        haptics: (_) {},
      );
      addTearDown(throwing.dispose);
      expect(
        await throwing.toggle(
          SubLineMode.translated,
          trackKey: 't',
          sourceLines: lyric,
          targetLanguage: 'en',
        ),
        SubLineTap.unavailable,
      );
    });

    test('same-language is remembered: a tap explains and asks nothing',
        () async {
      final first = tap(SubLineMode.translated);
      wire.answer(0, const LyricsTransformSameLanguage('en'));
      expect(await first, SubLineTap.sameLanguage);
      expect(controller.status(SubLineMode.translated), SubLineStatus.sameLanguage);
      expect(controller.alreadyInLanguage, isTrue);
      expect(controller.hasText, isFalse);

      haptics.clear();
      expect(await tap(SubLineMode.translated), SubLineTap.sameLanguage);
      expect(wire.calls.length, 1);
      expect(haptics, [SubLineHaptic.tap]);
    });

    test('an all-Latin lyric is answered without a request', () async {
      expect(
        await tap(SubLineMode.romanized, lines: const ['hello', 'world']),
        SubLineTap.sameLanguage,
      );
      expect(wire.calls, isEmpty);
      expect(controller.status(SubLineMode.romanized), SubLineStatus.sameLanguage);
      expect(controller.isBusy, isFalse);
    });

    test('an answer of the wrong length is refused, not painted', () async {
      final pending = tap(SubLineMode.translated);
      wire.answer(0, done(['only one']));
      expect(await pending, SubLineTap.unavailable);
      expect(controller.lines, isNull);
    });

    test('no lyric, no request', () async {
      expect(await tap(SubLineMode.translated, lines: const ['', ' ']),
          SubLineTap.empty);
      expect(wire.calls, isEmpty);
    });

    test('a track change drops the answer in flight and what was shown',
        () async {
      final pending = tap(SubLineMode.translated);
      controller.onTrackChanged('track-2');
      expect(wire.calls.single.token.isCancelled, isTrue);
      expect(controller.status(SubLineMode.translated), SubLineStatus.idle);
      expect(controller.mode, SubLineMode.original);

      wire.answer(0, done(english));
      expect(await pending, SubLineTap.superseded);
      expect(controller.lines, isNull,
          reason: "the previous song's translation under this one is worse than "
              'no sub-line');
    });

    test('state is per (track, language, lyric): changing any one resets it',
        () async {
      Future<void> ready(String track, List<String> lines, String language) async {
        final index = wire.calls.length;
        final pending = tap(SubLineMode.translated,
            track: track, lines: lines, language: language);
        wire.answer(index, done(lines.map((l) => 'T:$l').toList()));
        await pending;
      }

      await ready('track-1', lyric, 'en');
      expect(controller.status(SubLineMode.translated), SubLineStatus.ready);

      // Same track and lyric, different language.
      await ready('track-1', lyric, 'fr');
      expect(wire.calls.length, 2, reason: 'asked again for the new language');
      expect(wire.calls.last.target, 'fr');
      expect(controller.targetLanguage, 'fr');

      // Same track and language, different words (a provider switch).
      await ready('track-1', const ['uno', 'dos'], 'fr');
      expect(wire.calls.length, 3);
      expect(controller.displayedLines, ['T:uno', 'T:dos']);

      // Same words, different track.
      await ready('track-2', const ['uno', 'dos'], 'fr');
      expect(wire.calls.length, 4);

      // And the same triple again is NOT a reset: it toggles off.
      final hide = tap(SubLineMode.translated,
          track: 'track-2', lines: const ['uno', 'dos'], language: 'fr');
      expect(await hide, SubLineTap.hidden);
      expect(wire.calls.length, 4);
    });

    test('a changed lyric hides the old sub-line and resets the discs',
        () async {
      final pending = tap(SubLineMode.translated);
      wire.answer(0, done(english));
      await pending;

      final entries = [
        for (final text in lyric) LyricsEntry(timeMs: 0, text: text),
      ];
      final replaced = [
        for (final text in const ['uno', 'dos']) LyricsEntry(timeMs: 0, text: text),
      ];
      await _until(() => controller.shownMode == SubLineMode.translated);

      expect(controller.matchesLyrics(entries), isTrue);
      expect(controller.linesFor(entries), english);
      expect(controller.displayedLinesFor(entries), english);
      expect(controller.displayedLinesFor(replaced), isNull,
          reason: 'the strip must not show the old words\' translation under '
              'the new lyric, even for the frame before the reset lands');
      expect(controller.matchesLyrics(replaced), isFalse,
          reason: 'compared by CONTENT: two providers often have the same '
              'number of lines');
      expect(controller.linesFor(replaced), isNull);

      controller.onSourceChanged();
      expect(controller.mode, SubLineMode.original);
      expect(controller.shownMode, SubLineMode.original);
      expect(controller.progress, 0);
      expect(controller.status(SubLineMode.translated), SubLineStatus.idle);
      expect(controller.matchesLyrics(replaced), isTrue,
          reason: 'with nothing on hand there is nothing to mismatch');
    });

    test('the caption says what the transform is doing', () async {
      expect(controller.statusText, isNull);

      final translating = tap(SubLineMode.translated, language: 'ja');
      expect(controller.statusText, 'Translating to Japanese…');
      wire.answer(0, done(english));
      await translating;
      expect(controller.statusText, 'Translated to Japanese');

      await tap(SubLineMode.translated, language: 'ja'); // off
      expect(controller.statusText, isNull);

      final romanizing = tap(SubLineMode.romanized, language: 'ja');
      expect(controller.statusText, 'Romanizing lyrics…');
      wire.answer(1, done(roman));
      await romanizing;
      expect(controller.statusText, 'Romanized pronunciation');
    });

    test('the caption explains a no-op', () async {
      const latin = ['hello', 'there'];
      final a = tap(SubLineMode.translated, lines: latin, language: 'en');
      wire.answer(0, const LyricsTransformSameLanguage('en'));
      await a;
      expect(controller.statusText, 'Already in English');

      await tap(SubLineMode.romanized, lines: latin, language: 'en');
      expect(controller.statusText, 'Already in English',
          reason: 'translation comes first, as in the reference');

      // With only the globe having nothing to do:
      final other = SubLineController(transformer: wire.call, haptics: (_) {});
      addTearDown(other.dispose);
      await other.toggle(SubLineMode.romanized,
          trackKey: 't', sourceLines: latin, targetLanguage: 'en');
      expect(other.statusText, 'These lyrics already use Latin characters');
    });

    test('an answer arriving after dispose is dropped quietly', () async {
      final other = SubLineController(
        transformer: wire.call,
        haptics: (_) {},
      );
      final pending = other.toggle(
        SubLineMode.translated,
        trackKey: 't',
        sourceLines: lyric,
        targetLanguage: 'en',
      );
      other.dispose();
      wire.answer(0, done(english));
      expect(await pending, SubLineTap.superseded);
    });

    test('show() never toggles off', () async {
      final a = controller.show(
        SubLineMode.translated,
        trackKey: 'track-1',
        sourceLines: lyric,
        targetLanguage: 'en',
      );
      wire.answer(0, done(english));
      await a;
      expect(
        await controller.show(
          SubLineMode.translated,
          trackKey: 'track-1',
          sourceLines: lyric,
          targetLanguage: 'en',
        ),
        SubLineTap.shown,
      );
      expect(controller.mode, SubLineMode.translated);
    });
  });
}

/// One request the controller made.
class _Call {
  _Call(this.kind, this.trackId, this.lines, this.target, this.token);

  final LyricsTransform kind;
  final String trackId;
  final List<String> lines;
  final String target;
  final LyricsCancelToken token;
  final Completer<LyricsTransformResult> reply =
      Completer<LyricsTransformResult>();
}

/// A transformer that records each request and answers it when told to.
class _Wire {
  final List<_Call> calls = [];

  Future<LyricsTransformResult> call({
    required String trackId,
    required List<String> lines,
    required LyricsTransform kind,
    required String targetLanguage,
    LyricsCancelToken? cancel,
  }) {
    final call = _Call(kind, trackId, lines, targetLanguage, cancel!);
    calls.add(call);
    return call.reply.future;
  }

  void answer(int index, LyricsTransformResult result) =>
      calls[index].reply.complete(result);
}

/// Polls until [condition] holds, so a test waits for an animation to finish
/// rather than guessing how long it takes.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
