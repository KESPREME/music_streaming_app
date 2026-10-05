import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:music_streaming_app/screens/account_screen.dart';
import 'package:music_streaming_app/services/auth_service.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The account screen is the only place a user can see or change WHICH identity
/// the app is acting as, so the states that used to be invisible are pinned
/// here: an account with no name, a channel choice that only appears when there
/// is a choice, and the fact that switching really switches.
void main() {
  const accountsKey = 'youtube_account_sessions_v2';

  setUpAll(() {
    // The type tokens render through GoogleFonts, which fetches the font at
    // runtime when it is not loaded. In a test there is no font server and the
    // fetch does not fail fast, so it hangs the isolate. Off means fall back to
    // the platform default, which is all a widget test needs.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Map<String, dynamic> account(
    String id, {
    String name = '',
    String email = '',
    List<Map<String, dynamic>> profiles = const [],
    String? activeProfileId,
  }) =>
      {
        'id': id,
        'name': name,
        'email': email,
        'cookies': [
          {'name': 'SSID', 'value': 'ssid_$id'},
          {'name': 'SAPISID', 'value': 'sapisid_$id'},
        ],
        'profiles': profiles,
        if (activeProfileId != null) 'activeProfileId': activeProfileId,
      };

  /// Load the singleton session, then show the screen.
  ///
  /// The load MUST happen inside [WidgetTester.runAsync]: `init()` reaches for
  /// the secure-storage platform channel, and inside a widget test the binding
  /// is a fake-async zone, so awaiting a real channel reply there never
  /// completes - the test hangs with no error rather than failing.
  Future<AuthService> pumpScreen(
    WidgetTester tester, {
    List<Map<String, dynamic>>? accounts,
    bool rawPrefs = false,
    Map<String, dynamic>? singleAccount,
  }) async {
    late AuthService auth;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(
        singleAccount != null
            ? {accountsKey: jsonEncode([singleAccount])}
            : accounts == null
                ? {}
                : {accountsKey: jsonEncode(accounts)},
      );
      auth = AuthService();
      auth.debugResetRestoreFlag();
      await auth.init();
    });
    if (rawPrefs) expect(auth.isLoggedIn, isFalse);

    await tester.pumpWidget(
      // Providers sit ABOVE MaterialApp, matching main().
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: MaterialApp(
          theme: GlassTheme.build(AccentColors.peach),
          home: const AccountScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return auth;
  }

  testWidgets('signed out offers a way in', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('an account with no name still renders a real label',
      (tester) async {
    // Google does not hand us a display name from the jar. An empty Text is
    // what made the old tile look broken.
    await pumpScreen(tester, accounts: [account('acct_a')]);
    expect(find.text('YouTube account'), findsOneWidget);
  });

  testWidgets('a named account shows its name', (tester) async {
    await pumpScreen(tester, accounts: [
      account('acct_a', name: 'Ada', email: 'ada@example.com'),
    ]);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Active account'), findsOneWidget);
  });

  testWidgets('no channel list when there is only one channel', (tester) async {
    await pumpScreen(tester, accounts: [
      account('acct_a', name: 'Ada', profiles: [
        {'id': 'page_UC1', 'name': 'Ada'}
      ]),
    ]);
    // A one-item "Channels" list is noise.
    expect(find.text('Channels'), findsNothing);
  });

  testWidgets('channel list appears and switching changes identity',
      (tester) async {
    final auth = await pumpScreen(tester, accounts: [
      account(
        'acct_a',
        name: 'Ada',
        profiles: [
          {'id': 'page_UC1', 'name': 'Personal'},
          {'id': 'page_UC2', 'name': 'Brand', 'pageId': 'UC2'},
        ],
        activeProfileId: 'page_UC1',
      ),
    ]);

    expect(find.text('Channels'), findsOneWidget);
    expect(auth.activeProfileId, 'page_UC1');

    await tester.tap(find.text('Brand'));
    await tester.pumpAndSettle();

    // The selection has to move, not just repaint - otherwise nothing tells the
    // user which channel the app is now acting as.
    expect(auth.activeProfileId, 'page_UC2');
    expect(auth.channelPageId, 'UC2');
  });

  testWidgets('two accounts are listed', (tester) async {
    await pumpScreen(tester, accounts: [
      account('acct_a', name: 'Ada'),
      account('acct_b', name: 'Grace'),
    ]);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Grace'), findsOneWidget);
    expect(find.text('Sign out of all accounts'), findsOneWidget);
  });

  testWidgets('removal asks first, then removes', (tester) async {
    final auth = await pumpScreen(tester, accounts: [
      account('acct_a', name: 'Ada'),
      account('acct_b', name: 'Grace'),
    ]);

    await tester.tap(find.byTooltip('Remove account').first);
    await tester.pumpAndSettle();
    expect(find.text('Remove this account?'), findsOneWidget);

    // Cancelling must not destroy anything.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(auth.accounts, hasLength(2));

    await tester.tap(find.byTooltip('Remove account').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(auth.accounts, hasLength(1));
  });

  testWidgets('sign out of the last account returns to signed out',
      (tester) async {
    final auth = await pumpScreen(tester, accounts: [
      account('acct_a', name: 'Ada'),
    ]);

    expect(find.text('Sign out'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(auth.isLoggedIn, isFalse);
    expect(find.text('Not signed in'), findsOneWidget);
  });

  testWidgets('an expired jar is not presented as a usable account',
      (tester) async {
    // If the signing cookie is gone the app is anonymous no matter what is on
    // disk, and offering to "manage" that account would be a lie.
    await pumpScreen(
      tester,
      singleAccount: {
        'id': 'acct_dead',
        'cookies': [
          {
            'name': 'SAPISID',
            'value': 'v',
            // Epoch milliseconds, which is what AuthCookie serialises. An
            // ISO-8601 string parses as "no expiry" and the account would look
            // live.
            'expiresAt': DateTime.now()
                .subtract(const Duration(days: 2))
                .millisecondsSinceEpoch,
          },
        ],
        'profiles': [],
      },
    );
    expect(find.text('Not signed in'), findsOneWidget);
  });
}