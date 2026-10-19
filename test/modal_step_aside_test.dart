import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/core/navigation/root_navigator.dart';

/// THE PILL NEVER SITS ON TOP OF A SHEET.
///
/// The mini pill is painted above the root navigator and the nav bar above the
/// shell's navigator, so no modal could cover them. Each navigator now reports
/// its sheets and dialogs, and the chrome steps aside while one is open. And a
/// sheet is not a page: it no longer flips `isAtRoot`, which is what made the
/// overlay draw a second, floating pill over the Home sign-in sheet.

void main() {
  setUp(ModalRouteTracker.debugReset);

  Widget app({required List<NavigatorObserver> observers, required Widget home}) => MaterialApp(
        navigatorObservers: observers,
        builder: (context, child) => Stack(children: [
          child!,
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: StepAsideForModals(child: SizedBox(height: 60, child: Text('PILL'))),
          ),
        ]),
        home: home,
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  bool pillShown(WidgetTester tester) =>
      tester.widget<IgnorePointer>(find.ancestor(of: find.text('PILL'), matching: find.byType(IgnorePointer)).first)
          .ignoring ==
      false;

  testWidgets('a bottom sheet on the root navigator hides the pill, and only a page counts as leaving root',
      (tester) async {
    final observer = AppRouteObserver.instance;
    late BuildContext ctx;
    await tester.pumpWidget(app(
      observers: [observer],
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: Text('home'));
      }),
    ));
    expect(pillShown(tester), isTrue);

    showModalBottomSheet<void>(context: ctx, builder: (_) => const SizedBox(height: 200, child: Text('sheet')));
    await settle(tester);
    expect(ModalRouteTracker.anyModalOpen.value, isTrue);
    expect(pillShown(tester), isFalse);
    expect(observer.isAtRoot.value, isTrue, reason: 'a sheet is not a page');

    Navigator.of(ctx).pop();
    await settle(tester);
    expect(ModalRouteTracker.anyModalOpen.value, isFalse);
    expect(pillShown(tester), isTrue);

    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('page'))));
    await tester.pumpAndSettle();
    expect(observer.isAtRoot.value, isFalse);
    Navigator.of(tester.element(find.text('page'))).pop();
    await tester.pumpAndSettle();
    expect(observer.isAtRoot.value, isTrue);
  });

  testWidgets('a sheet on the shell''s nested navigator hides it too', (tester) async {
    final nested = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(
      observers: const [],
      home: Navigator(
        key: nested,
        observers: [ModalRouteTracker.shell],
        onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('tab'))),
      ),
    ));
    // showModalBottomSheet opens on the NEAREST navigator - the nested one -
    // which is exactly where the sign-in and liked-songs sheets landed.
    showModalBottomSheet<void>(context: nested.currentContext!, builder: (_) => const SizedBox(height: 200));
    await settle(tester);
    expect(pillShown(tester), isFalse);
    nested.currentState!.pop();
    await settle(tester);
    expect(pillShown(tester), isTrue);
  });
}
