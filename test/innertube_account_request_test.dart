import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/innertube/innertube_service.dart';

/// Regression: the first device run of sign-in validation failed for every
/// signed-in user.
///
/// The candidate jar contributes `Cookie` and `Authorization`. Those were being
/// handed to the request as the ENTIRE header map, which dropped User-Agent,
/// X-YouTube-Client-Name/Version, Origin and Referer. Google answered 200 with
/// an envelope that was not an `activeAccountHeaderRenderer`, the parser
/// correctly reported nothing, and a genuinely signed-in user was told "That
/// sign-in could not be verified".
///
/// Nothing about the parser or the cookies was wrong. The request was.
void main() {
  const standard = <String, String>{
    'Content-Type': 'application/json',
    'X-Goog-Api-Format-Version': '1',
    'X-YouTube-Client-Name': '67',
    'X-YouTube-Client-Version': '1.20250101.01.00',
    'X-Origin': 'https://music.youtube.com',
    'Referer': 'https://music.youtube.com/',
    'Origin': 'https://music.youtube.com',
    'User-Agent': 'Mozilla/5.0',
  };
  const session = <String, String>{
    'Cookie': 'SAPISID=abc; SID=def',
    'Authorization': 'SAPISIDHASH 123_abc',
  };

  group('mergeAuthHeaders', () {
    test('a candidate session does not remove the standard headers', () {
      final merged =
          InnerTubeService.mergeAuthHeaders(standard, session);

      for (final key in standard.keys) {
        expect(merged.containsKey(key), isTrue,
            reason: '$key was dropped, which is what broke sign-in');
      }
      expect(merged['User-Agent'], 'Mozilla/5.0');
      expect(merged['X-YouTube-Client-Name'], '67');
    });

    test('the session headers are present', () {
      final merged = InnerTubeService.mergeAuthHeaders(standard, session);
      expect(merged['Cookie'], contains('SAPISID=abc'));
      expect(merged['Authorization'], contains('SAPISIDHASH'));
    });

    test('session headers win on conflict', () {
      // Validating a jar other than the loaded one is the entire point, so a
      // stale Cookie must not survive the merge.
      final merged = InnerTubeService.mergeAuthHeaders(
        {...standard, 'Cookie': 'SAPISID=stale'},
        session,
      );
      expect(merged['Cookie'], 'SAPISID=abc; SID=def');
      expect(merged['Cookie'], isNot(contains('stale')));
    });

    test('a null session leaves the standard set untouched', () {
      final merged = InnerTubeService.mergeAuthHeaders(standard, null);
      expect(merged.length, standard.length);
      expect(merged['Cookie'], isNull);
    });

    test('an empty session map is a no-op, not a wipe', () {
      final merged = InnerTubeService.mergeAuthHeaders(standard, const {});
      expect(merged.length, standard.length);
    });

    test('does not mutate the standard map it is given', () {
      final base = Map<String, String>.of(standard);
      InnerTubeService.mergeAuthHeaders(base, session);
      expect(base.containsKey('Cookie'), isFalse,
          reason: 'the shared header builder must not be contaminated');
    });
  });
}