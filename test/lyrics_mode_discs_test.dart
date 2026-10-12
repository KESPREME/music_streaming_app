import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/widgets/lyrics_mode_discs.dart';

/// THE DISC THIS FILE PINS.
///
/// Reference: `TranslationToggleButton` / `RomanizationToggleButton`
/// (`PlayerLyrics.kt:1226-1330`): a 34dp circle, white at 0.18 alpha rising to 0.34
/// when its transform is on OR being fetched, a 19dp glyph tinted 1.0 / 0.78 / 0.42
/// (on / idle / nothing to do), and a 16dp spinner that REPLACES the glyph while a
/// request is in flight.
///
/// A TransformDisc is not glass - it has no BackdropFilter - so the fade it
/// carries is allowed (non-negotiable 1).

Widget _disc({
  required TransformButtonState state,
  bool active = false,
  VoidCallback? onTap,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: TransformDisc(
            icon: Icons.translate_rounded,
            semanticLabel: 'Translate',
            state: state,
            active: active,
            onTap: onTap ?? () {},
          ),
        ),
      ),
    );

/// The disc's fill alpha, read off the painted decoration.
double _discAlpha(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byType(TransformDisc),
      matching: find.byType(Container),
    ),
  );
  return ((box.decoration! as BoxDecoration).color!).a;
}

Icon _glyph(WidgetTester tester) => tester.widget<Icon>(find.byType(Icon));

void main() {
  group('the disc spec', () {
    testWidgets('is a 34dp circle', (tester) async {
      await tester.pumpWidget(_disc(state: TransformButtonState.idle));
      final box = tester.widget<Container>(
        find.descendant(
          of: find.byType(TransformDisc),
          matching: find.byType(Container),
        ),
      );
      expect(tester.getSize(find.byType(Container).last), const Size(34, 34));
      expect((box.decoration! as BoxDecoration).shape, BoxShape.circle);
    });

    testWidgets('the glyph is 19dp', (tester) async {
      await tester.pumpWidget(_disc(state: TransformButtonState.idle));
      expect(_glyph(tester).size, 19);
    });

    testWidgets('idle: white at 0.18, glyph at 0.78', (tester) async {
      await tester.pumpWidget(_disc(state: TransformButtonState.idle));
      expect(_discAlpha(tester), closeTo(0.18, 0.001));
      expect(_glyph(tester).color!.a, closeTo(0.78, 0.001));
      expect(_glyph(tester).color!.r, 1.0);
    });

    testWidgets('on: white at 0.34, glyph at full white', (tester) async {
      await tester.pumpWidget(
        _disc(state: TransformButtonState.ready, active: true),
      );
      expect(_discAlpha(tester), closeTo(0.34, 0.001));
      expect(_glyph(tester).color!.a, 1.0);
    });

    testWidgets('nothing to do: glyph at 0.42, and the disc stays tappable',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _disc(state: TransformButtonState.sameLanguage, onTap: () => taps++),
      );
      expect(_glyph(tester).color!.a, closeTo(0.42, 0.001));
      expect(_discAlpha(tester), closeTo(0.18, 0.001));

      await tester.tap(find.byType(TransformDisc));
      expect(taps, 1,
          reason: 'a dim disc that swallows the tap is a dead control; the tap '
              'is how the reader finds out WHY it is dim');
    });

    testWidgets('0.42 wins over "on": an on disc with nothing to do is dim',
        (tester) async {
      await tester.pumpWidget(
        _disc(state: TransformButtonState.sameLanguage, active: true),
      );
      expect(_glyph(tester).color!.a, closeTo(0.42, 0.001));
    });

    testWidgets('loading: the spinner REPLACES the glyph, 16dp, on the lit disc',
        (tester) async {
      await tester.pumpWidget(_disc(state: TransformButtonState.loading));

      expect(find.byType(Icon), findsNothing);
      final spinner = find.byType(CircularProgressIndicator);
      expect(spinner, findsOneWidget);
      expect(tester.getSize(spinner), const Size(16, 16));
      expect(tester.widget<CircularProgressIndicator>(spinner).strokeWidth, 1.7);

      // Lit although `active` was not passed: the reference lights the disc while
      // the request is in flight (`active = showing || state is Loading`).
      expect(_discAlpha(tester), closeTo(0.34, 0.001));
    });

    testWidgets('the disc brightens when its request starts, and dims when it '
        'ends', (tester) async {
      await tester.pumpWidget(_disc(state: TransformButtonState.idle));
      expect(_discAlpha(tester), closeTo(0.18, 0.001));

      await tester.pumpWidget(_disc(state: TransformButtonState.loading));
      await tester.pump(lyricsDiscFadeIn + const Duration(milliseconds: 20));
      expect(_discAlpha(tester), closeTo(0.34, 0.001));

      await tester.pumpWidget(_disc(state: TransformButtonState.idle));
      await tester.pump(lyricsDiscFadeOut + const Duration(milliseconds: 20));
      expect(_discAlpha(tester), closeTo(0.18, 0.001));
    });

    test('lit means on OR loading', () {
      for (final state in TransformButtonState.values) {
        expect(transformDiscLit(active: true, state: state), isTrue);
        expect(
          transformDiscLit(active: false, state: state),
          state == TransformButtonState.loading,
        );
      }
    });
  });

  group('feedback', () {
    testWidgets('the disc itself makes none: the controller decides',
        (tester) async {
      // A tap on a loading disc is ignored, and an ignored tap must be silent. The
      // disc used to buzz on every tap, so the controller's own feedback on a
      // successful toggle would have doubled up on it.
      final haptics = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      var taps = 0;
      await tester.pumpWidget(
        _disc(state: TransformButtonState.idle, onTap: () => taps++),
      );
      await tester.tap(find.byType(TransformDisc));
      await tester.pump();

      expect(taps, 1);
      expect(haptics, isEmpty);
    });

    testWidgets('no handler means a disabled disc', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: TransformDisc(
                icon: Icons.translate_rounded,
                semanticLabel: 'Translate',
                state: TransformButtonState.idle,
                active: false,
                onTap: null,
              ),
            ),
          ),
        ),
      );
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(TransformDisc),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.enabled, isFalse);
      expect(semantics.properties.button, isTrue);
    });
  });
}
