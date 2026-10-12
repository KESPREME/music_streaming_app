// YouTube transcript parsing. The payloads are HAND-WRITTEN to the shape of a
// get_transcript response (actions[0].updateEngagementPanelAction...cueGroups),
// since get_transcript needs a video with captions and was not captured.
//
// The bug: `cue['startOffsetMs'] as int?` throws on the numeric STRING YouTube
// actually sends ("12340"), the surrounding try/catch swallowed it, and the
// whole transcript came back null. And the cue text was read from `simpleText`
// only, where the transcript uses `runs[].text`.

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/innertube/innertube_service.dart';

Map<String, dynamic> transcript(List<Map<String, dynamic>> cues) => {
      'actions': [
        {
          'updateEngagementPanelAction': {
            'content': {
              'transcriptRenderer': {
                'body': {
                  'transcriptBodyRenderer': {
                    'cueGroups': [
                      for (final cue in cues)
                        {
                          'transcriptCueGroupRenderer': {
                            'cues': [
                              {'transcriptCueRenderer': cue},
                            ],
                          },
                        },
                    ],
                  },
                },
              },
            },
          },
        },
      ],
    };

void main() {
  final service = InnerTubeService();

  group('transcript parsing', () {
    test('a numeric-string startOffsetMs is read (it used to throw)', () {
      final lrc = service.parseTranscriptForTest(transcript([
        {
          'startOffsetMs': '12340',
          'durationMs': '2000',
          'cue': {'simpleText': 'Gone a little far'},
        },
        {
          'startOffsetMs': '75005',
          'cue': {'simpleText': 'How was I to know'},
        },
      ]));

      expect(lrc, isNotNull);
      expect(lrc!.split('\n'), [
        '[00:12.340]Gone a little far',
        '[01:15.005]How was I to know',
      ]);
    });

    test('a plain numeric startOffsetMs still works', () {
      final lrc = service.parseTranscriptForTest(transcript([
        {
          'startOffsetMs': 5250,
          'cue': {'simpleText': 'Numeric'},
        },
      ]));
      expect(lrc, '[00:05.250]Numeric');
    });

    test('cue text is read from runs[].text as well as simpleText', () {
      final lrc = service.parseTranscriptForTest(transcript([
        {
          'startOffsetMs': '1000',
          'cue': {
            'runs': [
              {'text': 'Hello '},
              {'text': 'world'},
            ],
          },
        },
        {
          'startOffsetMs': '2000',
          'cue': {'simpleText': 'Simple'},
        },
      ]));

      expect(lrc!.split('\n'), [
        '[00:01.000]Hello world',
        '[00:02.000]Simple',
      ]);
    });

    test('music-note cues and blank cues are dropped', () {
      final lrc = service.parseTranscriptForTest(transcript([
        {
          'startOffsetMs': '0',
          'cue': {'simpleText': '♪'},
        },
        {
          'startOffsetMs': '1000',
          'cue': {'runs': []},
        },
        {
          'startOffsetMs': '2000',
          'cue': {'simpleText': '♪ Sing ♪'},
        },
      ]));
      expect(lrc, '[00:02.000]Sing');
    });

    test('one unreadable cue does not lose the others', () {
      final lrc = service.parseTranscriptForTest(transcript([
        {
          'startOffsetMs': 'soon',
          'cue': {'simpleText': 'No usable time'},
        },
        {
          'startOffsetMs': '3000',
          'cue': {'simpleText': 'Fine'},
        },
      ]));
      expect(lrc, '[00:03.000]Fine');
    });

    test('no cues, or an unexpected shape, is null rather than an exception',
        () {
      expect(service.parseTranscriptForTest(transcript(const [])), isNull);
      expect(service.parseTranscriptForTest(<String, dynamic>{}), isNull);
      expect(
        service.parseTranscriptForTest({
          'actions': [<String, dynamic>{}],
        }),
        isNull,
      );
    });
  });
}
