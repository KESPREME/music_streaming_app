import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/providers/music_provider.dart'
    show AuthSessionReset;
import 'package:music_streaming_app/services/auth_service.dart';

/// Regression: the session was forgotten after every restart.
///
/// `AuthService.saveCookies` had always written the jar to preferences, and
/// `AuthService.init` had always been able to read it back - but nothing in the
/// app ever called `init`. The write path worked; the read path was dead code.
///
/// The subtle half is ordering. `MusicProvider` constructs an `AuthSessionReset`
/// whose constructor samples `AuthService().isLoggedIn` to decide whether a
/// later change is a genuine identity flip. That happens during `runApp`. So a
/// restore issued *after* that point is indistinguishable from a fresh login:
/// it resets the InnerTube session, clears the stream cache and refetches the
/// feed on a cold start that never changed identity. `main.dart` therefore
/// awaits `init()` before `runApp`, and the ordering is pinned here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storedKey = 'youtube_cookies';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService().logout();
    AuthService().debugResetRestoreFlag();
  });

  /// Put a session in storage the way a previous sign-in would have, and clear
  /// the one-shot restore flag so `init()` will read it.
  void seedStoredSession(Map<String, String> cookies) {
    SharedPreferences.setMockInitialValues({storedKey: jsonEncode(cookies)});
    AuthService().debugResetRestoreFlag();
  }

  group('restore', () {
    test('init() reads a saved session back and reports signed in', () async {
      seedStoredSession({'SAPISID': 'saved_sapisid', 'SID': 'saved_sid'});

      // Before the restore: anonymous. This is the state the app was stuck in.
      expect(AuthService().isLoggedIn, isFalse);

      await AuthService().init();

      expect(AuthService().isLoggedIn, isTrue);
      expect(AuthService().getCookie('SAPISID'), 'saved_sapisid');
      expect(AuthService().cookieHeader, contains('SAPISID=saved_sapisid'));
    });

    test('restored session produces signed request headers', () async {
      seedStoredSession({'SAPISID': 'saved_sapisid'});
      await AuthService().init();

      final headers = AuthService().getHeaders();

      expect(headers['Cookie'], contains('SAPISID=saved_sapisid'));
      // An empty Authorization header is the failure that made a restored
      // session behave exactly like an anonymous one.
      expect(headers['Authorization'], startsWith('SAPISIDHASH '));
    });

    test('the restored SAPISIDHASH is the real signature', () async {
      seedStoredSession({'SAPISID': 'saved_sapisid'});
      await AuthService().init();

      final auth = AuthService().getHeaders()['Authorization']!;
      final parts = auth.split(' ');
      expect(parts.first, 'SAPISIDHASH');
      expect(parts.last.split('_'), hasLength(2));

      // Recompute from the timestamp the header carries. This asserts the
      // signing math, not just the string shape.
      final timestamp = parts.last.split('_').first;
      final expected = sha1.convert(utf8.encode(
        '$timestamp saved_sapisid https://music.youtube.com',
      ));
      expect(parts.last.split('_').last, expected.toString());
    });

    test('a second init() does not notify again', () async {
      seedStoredSession({'SAPISID': 'saved_sapisid'});
      await AuthService().init();

      var notifications = 0;
      AuthService().addListener(() => notifications++);

      await AuthService().init();
      await AuthService().init();

      expect(notifications, 0,
          reason: 'a repeated restore must not look like an identity change');
    });

    test('a corrupt blob leaves the app anonymous instead of throwing',
        () async {
      SharedPreferences.setMockInitialValues({storedKey: 'not json {{{'});
      AuthService().debugResetRestoreFlag();

      await AuthService().init();

      expect(AuthService().isLoggedIn, isFalse);
      expect(AuthService().getHeaders(), isEmpty);
    });

    test('a stored jar without SAPISID is not a session', () async {
      // The check is an exact key lookup, not a substring search. That matters:
      // a substring test for "SAPISID" also matches "__Secure-3PAPISID", which
      // is how an app can declare itself signed in while holding no cookie it
      // can actually sign with.
      seedStoredSession({'SID': 'only_a_sid', 'HSID': 'only_an_hsid'});
      await AuthService().init();

      expect(AuthService().isLoggedIn, isFalse);
      expect(AuthService().getHeaders(), isEmpty);
    });

    test('an empty stored jar is not a session', () async {
      seedStoredSession({});
      await AuthService().init();

      expect(AuthService().isLoggedIn, isFalse);
    });

    test('logout wins over a stored session', () async {
      seedStoredSession({'SAPISID': 'saved_sapisid'});
      await AuthService().init();
      expect(AuthService().isLoggedIn, isTrue);

      await AuthService().logout();

      expect(AuthService().isLoggedIn, isFalse);
      // And a restore afterwards must not resurrect it.
      AuthService().debugResetRestoreFlag();
      await AuthService().init();
      expect(AuthService().isLoggedIn, isFalse);
    });
  });

  group('restore ordering', () {
    test('restoring before the session handle exists causes no flip', () async {
      // The shipped order: main() awaits init(), then runApp builds
      // MusicProvider, whose AuthSessionReset samples the restored identity.
      seedStoredSession({'SAPISID': 'saved_sapisid'});
      await AuthService().init();

      var flips = 0;
      final reset = AuthSessionReset(onIdentityFlipped: () async => flips++);
      addTearDown(reset.dispose);

      // Nothing changed identity after the handle latched, so a redundant
      // restore must stay silent.
      AuthService().debugResetRestoreFlag();
      await AuthService().init();

      expect(flips, 0,
          reason: 'a cold start that did not change identity must not reset '
              'the InnerTube session or refetch the feed');
    });

    test('restoring after the session handle exists is a phantom flip',
        () async {
      // The order we are fixing. Pinned deliberately: if this ever stops
      // flipping, the guard in the test above has stopped proving anything.
      SharedPreferences.setMockInitialValues({});

      var flips = 0;
      final reset = AuthSessionReset(onIdentityFlipped: () async => flips++);
      addTearDown(reset.dispose);

      // The handle was built while still anonymous...
      expect(AuthService().isLoggedIn, isFalse);

      // ...and only now does the session appear from storage.
      SharedPreferences.setMockInitialValues({
        storedKey: jsonEncode({'SAPISID': 'saved_sapisid'})
      });
      await AuthService().init();

      expect(flips, 1,
          reason: 'this is why main() must await init() before runApp');
    });
  });
}
