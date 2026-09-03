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
}
