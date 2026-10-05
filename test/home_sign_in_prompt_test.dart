import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:music_streaming_app/services/google_cookie_cleaner.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/home_sign_in_prompt.dart';

void main() {
  setUpAll(() {
    // The type tokens render through GoogleFonts, which fetches at runtime when
    // unloaded and hangs the isolate rather than failing.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pump(WidgetTester tester, {VoidCallback? onSignIn}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GlassTheme.build(AccentColors.peach),
        home: Scaffold(
          body: SignInPrompt(onSignIn: onSignIn ?? () {}),
        ),
      ),
    );
    await tester.pump();
  }

  group('SignInPrompt', () {
    testWidgets('offers a sign-in with an honest, complete line', (tester) async {
      await pump(tester);
      expect(find.text('Sign in to YouTube Music'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('the subtitle is not truncated to an ellipsis', (tester) async {
      await pump(tester);
      // The previous copy clamped to one line and rendered as "Get personali...",
      // which communicates less than nothing. Two lines are allotted.
      final sub = tester.widget<Text>(find.text('Get picks from your own listening'));
      expect(sub.maxLines, 2);
      expect(sub.overflow, TextOverflow.ellipsis);
      expect(find.textContaining('...'), findsNothing);
    });

    testWidgets('the whole row is the target, not just the button',
        (tester) async {
      var taps = 0;
      await pump(tester, onSignIn: () => taps++);

      // Tapping the card body, well away from the button.
      await tester.tap(find.text('Sign in to YouTube Music'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('exposes a button semantic for screen readers', (tester) async {
      await pump(tester);
      // The row is the target, so the row is what has to announce as a button.
      // Asserted on the Semantics node rather than the merged a11y tree, which
      // depends on how the inner Texts merge.
      final matches = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.label == 'Sign in to YouTube Music')
          .toList();
      expect(matches, hasLength(1),
          reason: 'the row is the target, so the row must announce as a button');
      expect(matches.single.properties.button, isTrue);
    });
  });

  group('GoogleCookieCleaner.plan', () {
    test('covers all three domain forms for every cookie', () {
      final plan = GoogleCookieCleaner.plan();
      final expected = GoogleCookieCleaner.origins.length *
          GoogleCookieCleaner.names.length *
          3;
      expect(plan, hasLength(expected));
    });

    test('expires host-only, Domain=host and Domain=.host', () {
      // The original cookie's scope is not recorded, so expiring only one form
      // leaves the other two alive - which is how "I signed out and it was
      // still signed in" happens.
      final forSapisid =
          GoogleCookieCleaner.plan().where((s) => s.name == 'SAPISID').toList();
      final domains = forSapisid.map((s) => s.domain).toSet();
      expect(domains, containsAll(<String?>[null, 'youtube.com', '.youtube.com']));
      expect(domains, containsAll(<String?>['music.youtube.com', '.music.youtube.com']));
    });

    test('clears the session pair, not only the signing cookie', () {
      // deriveAccountId reads SSID/SID/HSID. Clearing only SAPISID leaves a jar
      // that still hashes to a different "account".
      expect(GoogleCookieCleaner.names, containsAll(['SSID', 'SID', 'HSID']));
    });

    test('clears the partitioned SAPISID forms too', () {
      expect(GoogleCookieCleaner.names,
          containsAll(['__Secure-3PAPISID', '__Secure-1PAPISID']));
    });
  });
}