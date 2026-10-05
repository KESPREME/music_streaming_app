import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/auth_models.dart';
import 'package:music_streaming_app/services/login_session_probe.dart';

const _hour = 3600;

void main() {
  final future =
      DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/
          1000;

  group('signing cookie detection', () {
    test('any of the three real names count', () {
      for (final name in const [
        'SAPISID',
        '__Secure-3PAPISID',
        '__Secure-1PAPISID',
      ]) {
        expect(isSigningCookieName(name), isTrue, reason: name);
      }
    });

    test('derived and unrelated cookies do not count', () {
      // The old inline check looked for the SAPISID prefix, which happily
      // matched SAPISIDHASH - a value derived FROM the signing cookie and
      // useless for producing a new one.
      for (final name in const [
        'SAPISIDHASH',
        'SAPISIDCOOKIE',
        '__Secure-3PSID',
        'SID',
        '__Secure-OSID',
        '',
      ]) {
        expect(isSigningCookieName(name), isFalse, reason: name);
      }
    });
  });

  group('hasSigningCookie', () {
    test('a jar missing __Secure-3PSID still counts as signed in', () {
      // This is the regression the old screen shipped: it demanded both
      // SAPISID and __Secure-3PSID and so never noticed a completed sign-in on
      // a WebView that only set the SAPISID family.
      final jar = [
        LoginSessionProbe.cookie(name: 'SID', value: 's'),
        LoginSessionProbe.cookie(name: '__Secure-3PSID', value: 'p'),
        LoginSessionProbe.cookie(name: 'SAPISID', value: 'v'),
      ];
      expect(LoginSessionProbe.hasSigningCookie(jar), isTrue);
    });

    test('an expired signing cookie is not a session', () {
      final jar = [
        LoginSessionProbe.cookie(
            // `future` is 30 days out, so this has to walk back past that:
            // 60 hours is only 2.5 days and lands in the future.
            name: 'SAPISID',
            value: 'v',
            expiresAt: future - 60 * 24 * _hour),
      ];
      expect(LoginSessionProbe.hasSigningCookie(jar), isFalse);
    });

    test('an empty value does not count', () {
      final jar = [LoginSessionProbe.cookie(name: 'SAPISID', value: '')];
      expect(LoginSessionProbe.hasSigningCookie(jar), isFalse);
    });
  });

  group('cookie construction', () {
    test('a missing or zero expiry stays a session cookie', () {
      // Defaulting an unknown expiry to 0 would date every session cookie in
      // the past and drop the whole jar on the next load.
      expect(LoginSessionProbe.cookie(name: 'SID', value: 'v').expiresAt, isNull);
      expect(
          LoginSessionProbe.cookie(name: 'SID', value: 'v', expiresAt: 0)
              .expiresAt,
          isNull);
      expect(LoginSessionProbe.cookie(name: 'SID', value: 'v', expiresAt: -5)
          .expiresAt, isNull);
    });

    test('the domain is kept, not discarded', () {
      final c = LoginSessionProbe.cookie(
          name: 'SID', value: 'v', domain: '.youtube.com');
      expect(c.domain, '.youtube.com');
      expect(c.appliesTo('music.youtube.com'), isTrue);
      expect(c.appliesTo('youtube.com'), isTrue);
    });

    test('a blank domain normalises to host-agnostic', () {
      expect(LoginSessionProbe.cookie(name: 'S', value: 'v', domain: '  ').domain,
          '');
    });
  });

  group('coalesce', () {
    test('music wins over the parent domain for the same name', () {
      // Flattening the jar to name -> value let whichever host was read last
      // silently win. The caller lists hosts in priority order, so later wins.
      final jar = [
        LoginSessionProbe.cookie(
            name: 'SID', value: 'music', domain: 'music.youtube.com'),
        LoginSessionProbe.cookie(
            name: 'SID', value: 'parent', domain: '.youtube.com'),
      ];
      final out = LoginSessionProbe.coalesce(jar);
      expect(out, hasLength(1));
      expect(out.single.value, 'parent');
    });

    test('nameless entries are dropped', () {
      final out =
          LoginSessionProbe.coalesce([LoginSessionProbe.cookie(name: '', value: 'v')]);
      expect(out, isEmpty);
    });
  });

  group('profileFromYtcfg', () {
    test('reads the delegated session id as the real identity', () {
      final p = LoginSessionProbe.profileFromYtcfg({
        'LOGGED_IN': true,
        'DELEGATED_SESSION_ID': '1234567890||1122334455',
      });
      expect(p, isNotNull);
      expect(p!.dataSyncId, '1122334455');
      expect(p.hasRealIdentity, isTrue);
    });

    test('an explicit not-logged-in yields nothing', () {
      expect(
        LoginSessionProbe.profileFromYtcfg({
          'LOGGED_IN': false,
          'DELEGATED_SESSION_ID': '1||2',
        }),
        isNull,
      );
    });

    test('a jar with no channel identity yields nothing rather than a guess', () {
      // Committing a fabricated profile would pin the account to an identity
      // Google never confirmed, which 401s on the next request.
      expect(LoginSessionProbe.profileFromYtcfg({'LOGGED_IN': true}), isNull);
      expect(LoginSessionProbe.profileFromYtcfg(null), isNull);
    });

    test('a brand channel is identified by its page id', () {
      final p = LoginSessionProbe.profileFromYtcfg({
        'LOGGED_IN': true,
        'PAGE_CL': 'UC123',
        'DELEGATED_SESSION_ID': '9||8',
      });
      expect(p!.pageId, 'UC123');
      expect(p.isBrandAccount, isTrue);
      expect(p.profileId, 'page_UC123');
    });

    test('a lone channel sends no auth-user index', () {
      final p = LoginSessionProbe.profileFromYtcfg({
        'LOGGED_IN': true,
        'SESSION_INDEX': 0,
        'DELEGATED_SESSION_ID': '5||6',
      });
      // With one channel there is nothing to select, and an index Google did
      // not ask for is a 401 risk for no benefit.
      expect(p!.authUser, isNull);
    });

    test('a second channel keeps its own profile id', () {
      final p = LoginSessionProbe.profileFromYtcfg({
        'LOGGED_IN': true,
        'SESSION_INDEX': 1,
        'DELEGATED_SESSION_ID': '5||6',
      });
      expect(p!.profileId, 'sync_6#1');
      expect(p.authUser, '01');
    });

    test('blank strings are not identities', () {
      final p = LoginSessionProbe.profileFromYtcfg({
        'LOGGED_IN': true,
        'PAGE_CL': '   ',
        'DELEGATED_SESSION_ID': '  ',
      });
      expect(p, isNull);
    });

    test('SESSION_INDEX tolerates a string value', () {
      final p = LoginSessionProbe.profileFromYtcfg({
        'LOGGED_IN': true,
        'SESSION_INDEX': '2',
        'DELEGATED_SESSION_ID': '7||8',
      });
      expect(p!.profileId, 'sync_8#2');
    });
  });
}