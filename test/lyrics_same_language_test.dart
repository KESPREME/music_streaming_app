import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/lyrics_screen.dart';
import 'package:music_streaming_app/services/lyrics/lyric_sub_line.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_translation_service.dart';
import 'package:music_streaming_app/widgets/lyric_line/lyric_line.dart';
import 'package:music_streaming_app/widgets/lyrics_mode_discs.dart';

import 'support/lyrics_fixtures.dart';

/// THE SAME-LANGUAGE GUARD THIS FILE PINS.
///
/// It was written and never wired. `reportAlreadyInLanguage` defaulted to false
/// and no caller passed it, so `_alreadyInLanguage` could only ever be false; and
/// `TransformButtonState.sameLanguage` - the state that tints the disc to 0.42
/// and disables its tap - had no producer anywhere in `lib/`.
///
/// The failure mode was worse than a missing feature. Tapping the globe on an
/// English lyric sent a request, the endpoint returned the text unchanged, and a
/// sub-line appeared UNDERNEATH the original looking identical to it. The reader
/// cannot tell a transliteration of Latin text from a failure.
///
/// Reference: `LyricsTranslation.kt:234` (`hasNonLatinLetters` ->
/// `AlreadyRomanized`), `PlayerLyrics.kt:1252-1255` (the 0.42 tint) and
/// `:2791-2794` (the transient message). All three were unreachable here.

const _english = <String>[
  'The only answer',
  'This high came rushing',
];

const _japanese = <String>[
  'ねこが 攻打 Acquisition',
  'これは テスト です',
];

/// A controller that can never reach the network: its transformer always fails.
///
/// The default reaches the shared service, which POSTs to a real host. These tests
/// are about what the controller REPORTS, and a test that depends on the network
/// being down is a test that depends on the network.
SubLineController _offlineController() => SubLineController(
      transformer: ({
        required trackId,
        required lines,
        required kind,
        required targetLanguage,
        cancel,
      }) async =>
          const LyricsTransformUnavailable(),
      haptics: (_) {},
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });


  group('the script check', () {
    test('Latin, digits and punctuation count as Latin', () {
      expect(LyricsTranslationService.isLatinScript("Don't stop - 42!"), isTrue);
      expect(LyricsTranslationService.isLatinScript('Café'), isTrue,
          reason: 'accented Latin is still Latin script');
    });

    test('kana, han and hangul do not', () {
      expect(LyricsTranslationService.isLatinScript('ねこ'), isFalse);
      expect(LyricsTranslationService.isLatinScript('测试'), isFalse);
      expect(LyricsTranslationService.isLatinScript('한글'), isFalse);
      expect(LyricsTranslationService.isLatinScript('Ελλάδα'), isFalse);
    });

    test('a lyric is romanizable unless EVERY line is Latin', () {
      // One Japanese line among thirty English ones still needs transliterating.
      // Reporting the song as already-romanized because most of it is would leave
      // that line wrong with no way back.
      expect(LyricsTranslationService.isAlreadyRomanizable(_english), isTrue);
      expect(
        LyricsTranslationService.isAlreadyRomanizable([..._english, ..._japanese]),
        isFalse,
      );
    });

    test('an empty lyric is not a miss', () {
      expect(LyricsTranslationService.isAlreadyRomanizable(const ['', '  ']),
          isFalse,
          reason: 'nothing to romanize is not the same as already romanized');
    });
  });

  group('the controller reports the state instead of silently failing', () {
    test('an English lyric leaves the controller in already-in-language',
        () async {
      final controller = _offlineController();
      addTearDown(controller.dispose);

      expect(controller.alreadyInLanguage, isFalse);

      await controller.show(
        SubLineMode.romanized,
        trackKey: 'track1234567',
        sourceLines: _english,
        targetLanguage: 'en',
      );

      expect(controller.alreadyInLanguage, isTrue);
      // And nothing was painted: the answer could not have differed from the
      // original, so a sub-line identical to it would be a lie.
      expect(controller.hasText, isFalse);
    });

    test('a Japanese lyric does not claim already-in-language', () async {
      final controller = _offlineController();
      addTearDown(controller.dispose);

      // The fetch fails (the transformer is offline), and that must NOT be
      // reported as "your lyrics are already in this language". It is a
      // different fact and deserves different words.
      final outcome = await controller.show(
        SubLineMode.romanized,
        trackKey: 'track1234567',
        sourceLines: _japanese,
        targetLanguage: 'en',
      );

      expect(outcome, SubLineTap.unavailable);
      expect(controller.alreadyInLanguage, isFalse);
    });

    test('a track change clears it', () async {
      final controller = _offlineController();
      addTearDown(controller.dispose);

      await controller.show(
        SubLineMode.romanized,
        trackKey: 'track1234567',
        sourceLines: _english,
        targetLanguage: 'en',
      );
      expect(controller.alreadyInLanguage, isTrue);

      controller.onTrackChanged('track7654321');
      expect(controller.alreadyInLanguage, isFalse,
          reason: 'one song being Latin says nothing about the next');
    });
  });

  group('the disc says so rather than doing nothing', () {
    testWidgets('an English lyric dims the globe but keeps it tappable',
        (tester) async {
      await tester.pumpWidget(_screen(_englishLyric()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final disc = tester.widget<TransformDisc>(find.byType(TransformDisc).first);
      expect(disc.state, TransformButtonState.sameLanguage,
          reason: 'the state existed with no producer; this is the producer');
      expect(disc.semanticLabel,
          'These lyrics already use Latin characters');
      expect(disc.onTap, isNotNull,
          reason: 'a dim disc that swallows the tap is a dead control, which '
              'reads as broken rather than as an answer');
    });

    testWidgets('a Japanese lyric leaves the globe live', (tester) async {
      await tester.pumpWidget(_screen(_japaneseLyric()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final disc = tester.widget<TransformDisc>(find.byType(TransformDisc).first);
      expect(disc.state, isNot(TransformButtonState.sameLanguage));
      expect(disc.semanticLabel, isNot(contains('already')));
    });

    testWidgets('tapping it explains, and changes nothing', (tester) async {
      await tester.pumpWidget(_screen(_englishLyric()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // The disc tap reads the `translation_language` setting before it asks;
      // this service answers from a reader instead of the real store (which a
      // test cannot seed without letting `MusicProvider` run on into timers).
      LyricsTranslationService.debugOverrideInstance(
        LyricsTranslationService(
          client: MockClient((_) async => status(500)),
          cacheDirectory: () async => null,
          settingReader: () async => null,
        ),
      );
      addTearDown(() => LyricsTranslationService.debugOverrideInstance(null));

      final before = find.byType(TransformDisc);
      expect(before, findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.language_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // A silent no-op is indistinguishable from a broken button. The reader is
      // told what the fact is about their song.
      expect(find.textContaining('already use Latin'), findsOneWidget);
      // Nothing was drawn under the lyric.
      expect(find.byType(TransformDisc), findsNWidgets(2));
    });

    testWidgets('an apostrophe or dash does not make English look foreign',
        (tester) async {
      // "don’t" and "–" sit above U+0250. The check once called any such code
      // point non-Latin, so the globe stayed bright on ordinary English lyrics.
      await tester.pumpWidget(_screen([
        LyricsEntry(timeMs: 0, endMs: 4000, text: 'I don’t know – really…'),
        LyricsEntry(timeMs: 4000, endMs: 8000, text: '♪ la la la ♪'),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final disc = tester.widget<TransformDisc>(find.byType(TransformDisc).first);
      expect(disc.state, TransformButtonState.sameLanguage);
    });
  });

  group('what a tap on the discs does', () {
    // The whole chain, through the real screen: the setting (or the device
    // language) -> the request -> the answer -> the toast and the disc. The
    // service is the real one, over a recorded client.
    late List<Map<String, String>> asked;
    late http.Response Function(Map<String, String> fields) respond;
    Completer<void>? gate;

    // The `translation_language` setting, as the settings screen would store it.
    // Injected rather than seeded into the real store: a seeded store lets the
    // MusicProvider these tests build run on to start timers of its own, and the
    // seed outlives the test that made it.
    String? setting;

    setUp(() {
      asked = [];
      gate = null;
      setting = null;
      respond = (_) => okBody(fixture('translate_japanese_to_english.json'));
      LyricsTranslationService.debugOverrideInstance(
        LyricsTranslationService(
          settingReader: () async => setting,
          client: MockClient((request) async {
            asked.add(request.bodyFields);
            if (gate != null) await gate!.future;
            return respond(request.bodyFields);
          }),
          cacheDirectory: () async => null,
        ),
      );
    });
    tearDown(() => LyricsTranslationService.debugOverrideInstance(null));

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(_screen(_japaneseLyric()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }

    List<String> subLineTexts(WidgetTester tester) => [
          for (final e in find.byType(LyricLine).evaluate())
            tester.renderObject<RenderLyricLine>(find.byWidget(e.widget)).entry.text,
        ];

    // By position, not by icon: while a disc loads, its spinner REPLACES the
    // glyph, so there is no icon to look for. The globe sits on the left.
    TransformDisc disc(WidgetTester tester, IconData icon) => tester
        .widgetList<TransformDisc>(find.byType(TransformDisc))
        .firstWhere((d) => d.icon == icon);

    testWidgets('translate asks for the device language as a BASE language',
        (tester) async {
      // Platform.localeName is "en_US"; the screen used to send tl=en_US.
      await open(tester);
      await tester.tap(find.byIcon(Icons.translate_rounded));
      await settle(tester);

      expect(asked.single['tl'], 'en');
      expect(asked.single['dt'], 't');
      expect(asked.single['sl'], 'auto');
    });

    testWidgets('the translation_language setting wins', (tester) async {
      setting = 'fr';
      await open(tester);
      await tester.tap(find.byIcon(Icons.translate_rounded));
      await settle(tester);

      expect(asked.single['tl'], 'fr');
    });

    testWidgets('a translation lands UNDER the original, which stays',
        (tester) async {
      await open(tester);
      await tester.tap(find.byIcon(Icons.translate_rounded));
      await settle(tester);

      final texts = subLineTexts(tester);
      expect(texts, containsAll(_japanese));
      expect(texts, contains('I like cats'));
      expect(texts, contains('this is a test'));
      expect(disc(tester, Icons.translate_rounded).active, isTrue);
      expect(disc(tester, Icons.translate_rounded).state, TransformButtonState.ready);
      expect(disc(tester, Icons.language_rounded).active, isFalse);
    });

    testWidgets('a second tap takes it away again, with no new request',
        (tester) async {
      await open(tester);
      await tester.tap(find.byIcon(Icons.translate_rounded));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.translate_rounded));
      await settle(tester);

      expect(subLineTexts(tester), isNot(contains('I like cats')));
      expect(disc(tester, Icons.translate_rounded).active, isFalse);
      expect(asked.length, 1);
    });

    testWidgets('romanize asks dt=rm and shows the pronunciation',
        (tester) async {
      respond = (_) => okBody(fixture('translate_romanize_japanese.json'));
      await open(tester);
      await tester.tap(find.byIcon(Icons.language_rounded));
      await settle(tester);

      expect(asked.single['dt'], 'rm');
      expect(asked.single['tl'], 'en');
      expect(subLineTexts(tester), contains('Neko ga suki'));
    });

    testWidgets('a lyric already in the target says "Already in Japanese"',
        (tester) async {
      setting = 'ja';
      await open(tester);
      await tester.tap(find.byIcon(Icons.translate_rounded));
      await settle(tester);

      expect(find.text('Already in Japanese'), findsOneWidget);
      expect(disc(tester, Icons.translate_rounded).state,
          TransformButtonState.sameLanguage,
          reason: 'dimmed to 0.42, and still tappable');
      expect(disc(tester, Icons.translate_rounded).onTap, isNotNull);

      // Tapped again once the toast has gone (it floats over the disc), it
      // explains again - and asks nothing.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
          .removeCurrentSnackBar();
      await tester.pump();
      expect(find.text('Already in Japanese'), findsNothing);
      await tester.tap(find.byIcon(Icons.translate_rounded));
      await settle(tester);
      expect(find.text('Already in Japanese'), findsOneWidget);
      expect(asked.length, 1);
    });

    testWidgets('a failure says so and leaves the lyric untouched',
        (tester) async {
      respond = (_) => status(503);
      await open(tester);
      await tester.tap(find.byIcon(Icons.translate_rounded));
      await settle(tester);


      expect(find.text('Translation is unavailable right now'), findsOneWidget);
      expect(subLineTexts(tester), _japanese);
      expect(disc(tester, Icons.translate_rounded).state, TransformButtonState.idle);
    });

    testWidgets('only the disc that was tapped spins, and a tap on it is ignored',
        (tester) async {
      gate = Completer<void>();
      await open(tester);
      await tester.tap(find.byIcon(Icons.translate_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(disc(tester, Icons.translate_rounded).state, TransformButtonState.loading);
      expect(disc(tester, Icons.language_rounded).state, isNot(TransformButtonState.loading),
          reason: 'one flag for both used to make the OTHER disc spin too');

      // The spinner replaced the glyph, so tap the disc itself.
      await tester.tap(find.byType(TransformDisc).last);
      await tester.pump();
      expect(asked.length, 1, reason: 'a tap while loading is ignored');

      gate!.complete();
      await settle(tester);
    });

    testWidgets('tapping the globe while a translation loads cancels it',
        (tester) async {
      gate = Completer<void>();
      respond = (fields) => fields['dt'] == 'rm'
          ? okBody(fixture('translate_romanize_japanese.json'))
          : okBody(fixture('translate_japanese_to_english.json'));
      await open(tester);

      await tester.tap(find.byIcon(Icons.translate_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byIcon(Icons.language_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(asked.length, 2);

      gate!.complete();
      await settle(tester);

      final texts = subLineTexts(tester);
      expect(texts, contains('Neko ga suki'), reason: 'the globe won');
      expect(texts, isNot(contains('I like cats')),
          reason: 'the cancelled translation must not land afterwards');
      expect(disc(tester, Icons.language_rounded).active, isTrue);
      expect(disc(tester, Icons.translate_rounded).active, isFalse);
    });
  });
}

class _Provider extends MusicProvider {
  _Provider(this.lines);

  final List<LyricsEntry> lines;

  @override
  Track? get currentTrack => Track(
        id: 'track1234567',
        trackName: 'Borderline',
        artistName: 'Tame Impala',
        albumName: 'Currents',
        previewUrl: '',
      );

  @override
  bool get isPlaying => true;

  @override
  Duration get duration => const Duration(minutes: 4);

  @override
  Duration get position => const Duration(seconds: 10);

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  bool get isLoadingLyrics => false;

  @override
  List<LyricsEntry>? get currentLyrics => lines;

  @override
  bool get hasSyncedLyrics => true;
}

List<LyricsEntry> _englishLyric() => [
      for (final line in _english)
        LyricsEntry(timeMs: 0, endMs: 4000, text: line),
    ];

List<LyricsEntry> _japaneseLyric() => [
      for (final line in _japanese)
        LyricsEntry(timeMs: 0, endMs: 4000, text: line),
    ];

Widget _screen(List<LyricsEntry> lines) => ChangeNotifierProvider<MusicProvider>.value(
      value: _Provider(lines),
      child: const MaterialApp(
        home: Scaffold(
          body: LyricsScreen(
            isEmbedded: true,
            showHeader: false,
            showBottomScrubber: false,
            trackKey: 'track1234567',
          ),
        ),
      ),
    );