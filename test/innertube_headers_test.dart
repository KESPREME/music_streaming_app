import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/services/innertube/innertube_service.dart';

/// Regression: after YouTube login, every /player leg returned 400 while
/// browse worked. Root cause — login Cookie/Authorization headers were
/// attached to ALL client types, including the ladder clients documented
/// as token-free/login-free (visionos/androidVr/tvEmbedded).
void main() {
  const loggedIn = {
    'Cookie': 'SAPISID=abc; SID=def',
    'Authorization': 'SAPISIDHASH 123_abc',
  };

  group('sessionHeadersFor (auth-attach policy)', () {
    test('webRemix keeps login headers when logged in', () {
      final headers = InnerTubeService.sessionHeadersFor(
        YouTubeClientType.webRemix,
        loggedIn,
      );
      expect(headers['Cookie'], contains('SAPISID'));
      expect(headers['Authorization'], contains('SAPISIDHASH'));
    });

    test('ladder clients never receive login headers', () {
      for (final client in [
        YouTubeClientType.visionos,
        YouTubeClientType.androidVr,
        YouTubeClientType.tvEmbedded,
        YouTubeClientType.ios,
      ]) {
        final headers = InnerTubeService.sessionHeadersFor(client, loggedIn);
        expect(headers, isEmpty, reason: '$client must stay login-free');
      }
    });

    test('anonymous webRemix stays empty (CONSENT applied downstream)', () {
      expect(
        InnerTubeService.sessionHeadersFor(YouTubeClientType.webRemix, {}),
        isEmpty,
      );
    });
  });

  group('InnerTubeService _parseTrackFromRenderer artist parsing', () {
    Map<String, dynamic> makeRenderer({
      required String videoId,
      required String title,
      required List<dynamic> artistRuns,
    }) {
      return {
        'playlistItemData': {'videoId': videoId},
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': title}
                ]
              }
            }
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': artistRuns,
              }
            }
          },
        ],
      };
    }

    test('parses clean string artist names from runs (not stringified maps)', () {
      final renderer = makeRenderer(
        videoId: 'abc12345678',
        title: 'Rush',
        artistRuns: [
          {'text': ' Ayra Starr '},
          {'text': ' & '},
          {'text': ' Rema '},
          {'text': ' • '},
          {'text': ' 100M views '},
        ],
      );

      final track =
          InnerTubeService.instance.parseTrackFromRendererForTest(renderer);
      expect(track, isNotNull);
      expect(track!.trackName, 'Rush');
      expect(track.artistName, 'Ayra Starr, Rema');
    });

    test('falls back to Unknown Artist if all runs are metadata or delimiters', () {
      final renderer = makeRenderer(
        videoId: 'abc12345678',
        title: 'No Artist Song',
        artistRuns: [
          {'text': ' • '},
          {'text': ' & '},
          {'text': ' 3:45 '},
          {'text': ' 50M views '},
        ],
      );

      final track =
          InnerTubeService.instance.parseTrackFromRendererForTest(renderer);
      expect(track, isNotNull);
      expect(track!.artistName, 'Unknown Artist');
    });

    test('ignores null or non-string run text safely', () {
      final renderer = makeRenderer(
        videoId: 'abc12345678',
        title: 'Safe Song',
        artistRuns: [
          {'text': null},
          {'text': 123},
          {'text': ' Burna Boy '},
        ],
      );

      final track =
          InnerTubeService.instance.parseTrackFromRendererForTest(renderer);
      expect(track, isNotNull);
      expect(track!.artistName, 'Burna Boy');
    });
  });
}
