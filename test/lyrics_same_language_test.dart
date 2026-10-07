import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:music_streaming_app/models/lyrics_entry.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/lyrics_screen.dart';
import 'package:music_streaming_app/services/lyrics/lyric_sub_line.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_translation_service.dart';
import 'package:music_streaming_app/widgets/lyrics_mode_discs.dart';

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
      final controller = SubLineController();
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
      final controller = SubLineController();
      addTearDown(controller.dispose);

      // The fetch will fail in a test - there is no network - and that must NOT
      // be reported as "your lyrics are already in this language". It is a
      // different fact and deserves different words.
      await controller.show(
        SubLineMode.romanized,
        trackKey: 'track1234567',
        sourceLines: _japanese,
        targetLanguage: 'en',
      );

      expect(controller.alreadyInLanguage, isFalse);
    });

    test('a track change clears it', () async {
      final controller = SubLineController();
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