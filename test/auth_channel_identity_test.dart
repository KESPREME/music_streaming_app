import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/auth_models.dart';
import 'package:music_streaming_app/services/auth_service.dart';
import 'package:music_streaming_app/services/innertube/innertube_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression coverage for the channel identity reaching InnerTube.
///
/// `context.user` used to be sent as `{}`. That is correct for a personal
/// channel and wrong for a brand one: the request gets attributed to the
/// personal channel, so a brand-channel account is served the wrong feed, or
/// answered with a 401 that looks identical to a broken app.
void main() {
  // The registry is stored as a bare JSON list of accounts.
  const accountsKey = 'youtube_account_sessions_v2';

  Map<String, dynamic> account(
    String id,
    String ssid, {
    List<Map<String, dynamic>> profiles = const [],
    String? activeProfileId,
  }) =>
      {
        'id': id,
        'cookies': [
          {'name': 'SSID', 'value': ssid},
          {'name': 'SAPISID', 'value': 'sapisid_$ssid'},
        ],
        'profiles': profiles,
        if (activeProfileId != null) 'activeProfileId': activeProfileId,
      };

  Future<AuthService> loadWith(List<Map<String, dynamic>> accounts) async {
    SharedPreferences.setMockInitialValues({
      accountsKey: jsonEncode(accounts),
    });
    final auth = AuthService();
    auth.debugResetRestoreFlag();
    await auth.init();
    return auth;
  }

  group('browseUserContext', () {
    test('a brand channel sends onBehalfOfUser', () {
      expect(
        InnerTubeService.browseUserContext('dsync123')['onBehalfOfUser'],
        'dsync123',
      );
    });

    test('anonymous sends no onBehalfOfUser at all', () {
      // Not defaulted, not guessed. A wrong value here is a 401.
      for (final value in <String?>[null, '', '   ', '\n\t']) {
        expect(
          InnerTubeService.browseUserContext(value).containsKey('onBehalfOfUser'),
          isFalse,
          reason: 'value: "$value"',
        );
      }
    });

    test('a padded id is trimmed rather than sent verbatim', () {
      expect(
        InnerTubeService.browseUserContext('  dsync123  ')['onBehalfOfUser'],
        'dsync123',
      );
    });

    test('lockedSafetyMode is always present', () {
      // Omitting it narrows which results are eligible, silently.
      expect(InnerTubeService.browseUserContext(null)['lockedSafetyMode'],
          isFalse);
      expect(InnerTubeService.browseUserContext('x')['lockedSafetyMode'],
          isFalse);
    });
  });

  group('identityKey', () {
    test('anonymous is its own bucket', () async {
      SharedPreferences.setMockInitialValues({});
      AuthService().debugResetRestoreFlag();
      await AuthService().init();
      expect(AuthService().identityKey, 'anon');
    });

    test('a signed-in account does not collide with anonymous', () async {
      final auth = await loadWith([account('acct_a', 's1')]);
      expect(auth.isLoggedIn, isTrue);
      expect(auth.identityKey, isNot('anon'));
      expect(auth.identityKey, 'acct_a');
    });

    test('the key carries no cookie material', () async {
      // This string becomes a preferences key, and preferences are plaintext
      // on disk - so a cookie value here would be a leaked session.
      final auth = await loadWith([account('acct_a', 'secret_ssid')]);
      expect(auth.identityKey, isNot(contains('secret')));
      expect(auth.identityKey, isNot(contains('sapisid')));
    });

    test('a channel switch is a different bucket from the account', () async {
      final auth = await loadWith([
        account(
          'acct_a',
          's1',
          profiles: [
            {'id': 'page_UC1', 'name': 'Personal'},
            {'id': 'page_UC2', 'name': 'Brand'},
          ],
          activeProfileId: 'page_UC1',
        ),
      ]);

      final personal = auth.identityKey;
      await auth.selectIdentity('acct_a', 'page_UC2');
      final brand = auth.identityKey;

      // Two channels on one Google login have different feeds. Sharing a cache
      // bucket would serve one channel's recommendations to the other.
      expect(brand, isNot(personal));
      expect(brand, 'acct_a_page_UC2');
    });

    test('two accounts never share a bucket', () async {
      final auth = await loadWith([
        account('acct_a', 'a'),
        account('acct_b', 'b'),
      ]);
      final first = auth.identityKey;
      await auth.selectIdentity('acct_b', null);
      expect(auth.identityKey, isNot(first));
    });

    test('an account with no unexpired signing cookie is not a bucket', () async {
      // Reporting a bucket for a session that cannot sign would let a stale
      // cookie keep reading a cache as though it were still valid.
      SharedPreferences.setMockInitialValues({
        accountsKey: jsonEncode([
          {
            'id': 'acct_dead',
            'cookies': [
              {'name': 'SID', 'value': 'v'},
            ],
            'profiles': [],
          },
        ]),
      });
      AuthService().debugResetRestoreFlag();
      await AuthService().init();
      expect(AuthService().identityKey, 'anon');
    });
  });

  group('cookie domain scoping', () {
    test('a parent-domain cookie reaches a subdomain', () {
      const c = AuthCookie(name: 'SID', value: 'v', domain: '.youtube.com');
      expect(c.appliesTo('music.youtube.com'), isTrue);
      expect(c.appliesTo('youtube.com'), isTrue);
    });

    test('a host-specific cookie does not escape its host', () {
      const c =
          AuthCookie(name: 'SID', value: 'v', domain: 'music.youtube.com');
      expect(c.appliesTo('music.youtube.com'), isTrue);
      expect(c.appliesTo('youtube.com'), isFalse);
    });
  });
}