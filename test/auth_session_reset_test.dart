import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/providers/music_provider.dart'
    show AuthSessionReset;
import 'package:music_streaming_app/services/auth_service.dart';
import 'package:music_streaming_app/services/innertube/innertube_service.dart';

/// Regression: after YouTube login, Home taps played nothing. Root cause —
/// the player pipeline binds visitorData to one session, but visitorData
/// was captured once (anonymous) and never refreshed, so /player received
/// login cookies + a stale anonymous visitor and rejected playback while
/// browse (cookies alone) kept working. The flip handler resets the
/// session and clears session-bound stream URLs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService().logout();
    InnerTubeService.instance.visitorData = null;
  });

  test('resetSession clears stale anonymous visitorData', () {
    InnerTubeService.instance.visitorData = 'anon_visitor';
    InnerTubeService.instance.resetSession();
    expect(InnerTubeService.instance.visitorData, isNull);
  });

  test('login flip resets the session and notifies once', () async {
    var flips = 0;
    final reset = AuthSessionReset(onIdentityFlipped: () async {
      flips++;
    });
    addTearDown(reset.dispose);
    InnerTubeService.instance.visitorData = 'anon_visitor';

    await AuthService().saveCookies({'SAPISID': 'test_sapisid'});

    expect(AuthService().isLoggedIn, isTrue);
    expect(InnerTubeService.instance.visitorData, isNull);
    expect(flips, 1);
  });

  test('logout flip resets the session and notifies', () async {
    var flips = 0;
    final reset = AuthSessionReset(onIdentityFlipped: () async {
      flips++;
    });
    addTearDown(reset.dispose);

    await AuthService().saveCookies({'SAPISID': 'test_sapisid'});
    InnerTubeService.instance.visitorData = 'logged_in_visitor';

    await AuthService().logout();

    expect(AuthService().isLoggedIn, isFalse);
    expect(InnerTubeService.instance.visitorData, isNull);
    expect(flips, 2);
  });

  test('no flip, no reset and no notify', () async {
    var flips = 0;
    final reset = AuthSessionReset(onIdentityFlipped: () async {
      flips++;
    });
    addTearDown(reset.dispose);
    InnerTubeService.instance.visitorData = 'keep_me';

    await AuthService().logout(); // already logged out (setUp)

    expect(InnerTubeService.instance.visitorData, 'keep_me');
    expect(flips, 0);
  });
}
