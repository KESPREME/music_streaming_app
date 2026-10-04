import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/providers/music_provider.dart'
    show AuthSessionReset;
import 'package:music_streaming_app/services/auth_models.dart';
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

  /// Where a real save writes: the preferences mirror of the account registry.
  /// Seeded directly so a test can set up a session without a platform channel.
  const accountsKey = 'youtube_account_sessions_v2';

  /// The pre-migration flat jar.
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
      expect(AuthService().cookieHeader(), contains('SAPISID=saved_sapisid'));
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

    // Recompute from the timestamp the header carries. This asserts the signing
    // math, not just the string shape.
    final timestamp = parts.last.split('_').first;
    final expected = sha1.convert(utf8.encode(
      '$timestamp saved_sapisid https://music.youtube.com',
    ));
    expect(parts.last.split('_').last, expected.toString());
  });

  group('signing cookie names', () {
    test('a partitioned login holding only __Secure-3PAPISID can sign', () async {
      // The exact-key check is correct - a substring test for "SAPISID" also
      // matches "__Secure-3PAPISID", which is how an app declares itself signed
      // in while holding nothing it can sign with. But the failure mode of being
      // too strict is the mirror image: a partitioned login sets only the
      // __Secure- forms, so demanding plain SAPISID means it can never sign at
      // all.
      seedStoredSession({'__Secure-3PAPISID': 'partitioned_value'});
      await AuthService().init();

      expect(AuthService().isLoggedIn, isTrue);
      expect(AuthService().signingCookie, 'partitioned_value');
      expect(AuthService().getHeaders()['Authorization'],
          startsWith('SAPISIDHASH '));
    });

    test('__Secure-1PAPISID also counts', () async {
      seedStoredSession({'__Secure-1PAPISID': 'first_party_value'});
      await AuthService().init();
      expect(AuthService().isLoggedIn, isTrue);
      expect(AuthService().signingCookie, 'first_party_value');
    });

    test('plain SAPISID is preferred over the __Secure- forms', () async {
      // Signing with the wrong one produces a hash Google rejects, which reads as
      // a mysteriously broken session rather than as a wrong cookie choice.
      seedStoredSession({
        '__Secure-3PAPISID': 'partitioned_value',
        'SAPISID': 'plain_value',
      });
      await AuthService().init();
      expect(AuthService().signingCookie, 'plain_value');
    });

    test('an empty signing cookie value does not count', () async {
      seedStoredSession({'SAPISID': ''});
      await AuthService().init();
      expect(AuthService().isLoggedIn, isFalse);
    });
  });

  group('expiry', () {
    test('a fully expired jar is not a session', () async {
      // Without an expiry the app keeps reporting itself signed in and sending
      // cookies Google has already rejected, which surfaces to the listener as
      // "logged in but nothing works".
      SharedPreferences.setMockInitialValues({
        accountsKey: jsonEncode([
          {
            'id': 'acct_test',
            'cookies': [
              {
                'name': 'SAPISID',
                'value': 'stale',
                'expiresAt': DateTime.now()
                    .subtract(const Duration(days: 1))
                    .millisecondsSinceEpoch,
              },
            ],
            'profiles': [],
          },
        ]),
      });
      AuthService().debugResetRestoreFlag();
      await AuthService().init();

      expect(AuthService().isLoggedIn, isFalse);
      expect(AuthService().getHeaders(), isEmpty);
    });

    test('a jar that expires in the future still signs', () async {
      SharedPreferences.setMockInitialValues({
        accountsKey: jsonEncode([
          {
            'id': 'acct_test',
            'cookies': [
              {
                'name': 'SAPISID',
                'value': 'fresh',
                'expiresAt': DateTime.now()
                    .add(const Duration(days: 30))
                    .millisecondsSinceEpoch,
              },
            ],
            'profiles': [],
          },
        ]),
      });
      AuthService().debugResetRestoreFlag();
      await AuthService().init();

      expect(AuthService().isLoggedIn, isTrue);
      expect(AuthService().signingCookie, 'fresh');
    });
  });

  group('legacy migration', () {
    test('the old flat jar becomes one account and stays signed in', () async {
      // The previous implementation wrote a name->value map. An app update must
      // not sign anyone out, so that shape is still readable.
      SharedPreferences.setMockInitialValues({
        storedKey: jsonEncode({'SAPISID': 'legacy_sapisid', 'SID': 'legacy_sid'}),
      });
      AuthService().debugResetRestoreFlag();
      await AuthService().init();

      expect(AuthService().isLoggedIn, isTrue);
      expect(AuthService().signingCookie, 'legacy_sapisid');
      expect(AuthService().accounts, hasLength(1));
    });

    test('a signed-out jar with no signing cookie does not migrate', () async {
      SharedPreferences.setMockInitialValues({
        storedKey: jsonEncode({'SID': 'only_a_sid'}),
      });
      AuthService().debugResetRestoreFlag();
      await AuthService().init();

      expect(AuthService().accounts, isEmpty);
      expect(AuthService().isLoggedIn, isFalse);
    });
  });

  group('domain scoping', () {
    test('a cookie scoped to the parent domain reaches its subdomain', () async {
      // `.youtube.com` legitimately covers `music.youtube.com` - that is what
      // the dot prefix means. This is the common case for a YouTube sign-in and
      // must keep working.
      SharedPreferences.setMockInitialValues({
        accountsKey: jsonEncode([
          {
            'id': 'acct_test',
            'cookies': [
              {'name': 'SAPISID', 'value': 'scoped', 'domain': '.youtube.com'},
              {'name': 'SID', 'value': 'scoped_sid', 'domain': '.youtube.com'},
            ],
            'profiles': [],
          },
        ]),
      });
      AuthService().debugResetRestoreFlag();
      await AuthService().init();

      expect(AuthService().cookieHeader(host: 'music.youtube.com'),
          contains('SAPISID=scoped'));
    });

    test('a music-only cookie is not replayed to the parent domain', () async {
      // The leak this guards: comparing the domain tail in either direction let
      // a value scoped to `music.youtube.com` travel up to `youtube.com`.
      SharedPreferences.setMockInitialValues({
        accountsKey: jsonEncode([
          {
            'id': 'acct_test',
            'cookies': [
              {
                'name': 'SAPISID',
                'value': 'music_only',
                'domain': 'music.youtube.com'
              },
            ],
            'profiles': [],
          },
        ]),
      });
      AuthService().debugResetRestoreFlag();
      await AuthService().init();

      expect(AuthService().cookieHeader(host: 'youtube.com'),
          isNot(contains('SAPISID=music_only')));
      // It still works where it belongs.
      expect(AuthService().cookieHeader(host: 'music.youtube.com'),
          contains('SAPISID=music_only'));
    });

    test('a hostless cookie is sent anywhere', () async {
      seedStoredSession({'SAPISID': 'hostless'});
      await AuthService().init();
      expect(AuthService().cookieHeader(host: 'music.youtube.com'),
          contains('SAPISID=hostless'));
    });
  });

  group('channel context', () {
    test('headers carry the selected profile channel fields', () async {
      SharedPreferences.setMockInitialValues({
        accountsKey: jsonEncode([
          {
            'id': 'acct_test',
            'cookies': [
              {'name': 'SAPISID', 'value': 'v'},
            ],
            'profiles': [
              {
                'id': 'page_UC123',
                'name': 'My Channel',
                'pageId': 'UC123',
                'authUser': '3',
                'brand': true,
              },
            ],
            'activeProfileId': 'page_UC123',
          },
        ]),
      });
      AuthService().debugResetRestoreFlag();
      await AuthService().init();

      final headers = AuthService().getHeaders();
      expect(headers['X-Goog-PageId'], 'UC123');
      expect(headers['X-Goog-AuthUser'], '3');
      expect(AuthService().dataSyncId, isNull,
          reason: 'never inferred; only ever what a shell reported');
    });

    test('a personal profile sends no PageId', () async {
      SharedPreferences.setMockInitialValues({
        accountsKey: jsonEncode([
          {
            'id': 'acct_test',
            'cookies': [
              {'name': 'SAPISID', 'value': 'v'},
            ],
            'profiles': [
              {'id': 'profile:abc', 'name': 'Personal'},
            ],
            'activeProfileId': 'profile:abc',
          },
        ]),
      });
      AuthService().debugResetRestoreFlag();
      await AuthService().init();

      expect(AuthService().getHeaders().containsKey('X-Goog-PageId'), isFalse);
    });
  });

  group('multi-account', () {
    Future<void> seedTwoAccounts() async {
      SharedPreferences.setMockInitialValues({
        accountsKey: jsonEncode([
          {
            'id': 'acct_one',
            'cookies': [
              {'name': 'SAPISID', 'value': 'one'},
            ],
            'email': 'one@example.com',
            'profiles': [
              {'id': 'page_UCA', 'name': 'One', 'pageId': 'UCA'},
              {'id': 'page_UCB', 'name': 'One Brand', 'pageId': 'UCB'},
            ],
            'activeProfileId': 'page_UCA',
          },
          {
            'id': 'acct_two',
            'cookies': [
              {'name': 'SAPISID', 'value': 'two'},
            ],
            'email': 'two@example.com',
            'profiles': [
              {'id': 'page_UCC', 'name': 'Two', 'pageId': 'UCC'},
            ],
            'activeProfileId': 'page_UCC',
          },
        ]),
      });
      AuthService().debugResetRestoreFlag();
      await AuthService().init();
    }

    test('both accounts load and each keeps its own cookie', () async {
      await seedTwoAccounts();
      expect(AuthService().accounts, hasLength(2));

      await AuthService().selectIdentity('acct_one', null);
      expect(AuthService().signingCookie, 'one');

      await AuthService().selectIdentity('acct_two', null);
      expect(AuthService().signingCookie, 'two');
    });

    test('switching identity changes the channel header', () async {
      await seedTwoAccounts();
      await AuthService().selectIdentity('acct_one', 'page_UCB');
      expect(AuthService().getHeaders()['X-Goog-PageId'], 'UCB');

      await AuthService().selectIdentity('acct_two', null);
      expect(AuthService().getHeaders()['X-Goog-PageId'], 'UCC');
    });

    test('the flattened list is insertion then profile order', () async {
      await seedTwoAccounts();
      expect(AuthService().allIdentities, [
        ('acct_one', 'page_UCA'),
        ('acct_one', 'page_UCB'),
        ('acct_two', 'page_UCC'),
      ]);
    });

    test('stepping through identities does not wrap', () async {
      // Wrapping means the list silently rotates under the listener while they
      // are reading it.
      await seedTwoAccounts();
      final forward = AuthService().adjacentIdentity(
        forward: true,
        accountId: 'acct_one',
        profileId: 'page_UCA',
      );
      expect(forward, ('acct_one', 'page_UCB'));

      final last = AuthService().adjacentIdentity(
        forward: true,
        accountId: 'acct_two',
        profileId: 'page_UCC',
      );
      expect(last, isNull);

      final backward = AuthService().adjacentIdentity(
        forward: false,
        accountId: 'acct_one',
        profileId: 'page_UCA',
      );
      expect(backward, isNull);
    });

    test('removing an account falls back rather than signing out', () async {
      await seedTwoAccounts();
      await AuthService().selectIdentity('acct_two', null);

      await AuthService().removeAccount('acct_two');

      expect(AuthService().accounts, hasLength(1));
      expect(AuthService().activeAccountId, 'acct_one');
      expect(AuthService().isLoggedIn, isTrue,
          reason: 'one account leaving must not sign the other out');
    });

    test('removing the last account signs out', () async {
      await seedTwoAccounts();
      await AuthService().removeAccount('acct_one');
      await AuthService().removeAccount('acct_two');
      expect(AuthService().isLoggedIn, isFalse);
    });

    test('re-login under the same email upgrades rather than duplicating',
        () async {
      await seedTwoAccounts();
      await AuthService().saveSession(
        cookies: [
          const AuthCookie(name: 'SAPISID', value: 'rotated'),
        ],
        email: 'one@example.com',
        displayName: 'One',
      );
      expect(AuthService().accounts, hasLength(2));
      expect(AuthService().signingCookie, 'rotated');
    });

    test('a rotated jar keeps one account when no email was captured', () async {
      // The login screen hands over a bare cookie map with no email and no
      // dataSyncId, so the account id has to be derived from the session pair
      // alone. Google rewrites SAPISID on every sign-in, and deriving the id
      // from the whole jar silently created a second account each time.
      AuthService().debugResetRestoreFlag();
      SharedPreferences.setMockInitialValues({});
      await AuthService().init();

      await AuthService().saveCookies({
        'SSID': 'stable_ssid',
        'SID': 'stable_sid',
        'HSID': 'stable_hsid',
        'SAPISID': 'first_rotation',
      });
      await AuthService().saveCookies({
        'SSID': 'stable_ssid',
        'SID': 'stable_sid',
        'HSID': 'stable_hsid',
        'SAPISID': 'second_rotation',
      });

      expect(AuthService().accounts, hasLength(1),
          reason: 'a rotated SAPISID must not fork a duplicate account');
      expect(AuthService().signingCookie, 'second_rotation');
    });

    test('logout clears every account', () async {
      await seedTwoAccounts();
      await AuthService().logout();
      expect(AuthService().accounts, isEmpty);
      expect(AuthService().isLoggedIn, isFalse);
      expect(AuthService().getHeaders(), isEmpty);
    });
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
