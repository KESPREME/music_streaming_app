import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/core/navigation/root_navigator.dart';
import 'package:music_streaming_app/core/navigation/shell_back.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/user_playlist_detail_screen.dart';
import 'package:music_streaming_app/screens/user_playlist_screen.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BACK GOES WHERE YOU CAME FROM, AND DELETE DELETES.
///
/// The shell answers the system back for pages on its nested navigator. It
/// used to read "can a page be closed?" once per build - MainScreen does not
/// rebuild on a push, so back on Library > Your Playlists jumped to Home - and
/// to close it with pop(), which ignored the page's own back handling. These
/// pin the tracker it now reads, the order it decides in, and that the page
/// under the finger decides.

Track _t(String id) => Track(id: id, trackName: 'Song $id', artistName: 'A', albumName: 'B', previewUrl: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShellPageTracker', () {
    setUp(ShellPageTracker.debugReset);

    testWidgets('knows when a page is open on the nested navigator, live', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        home: Navigator(
          key: nav,
          observers: [ShellPageTracker.instance],
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Text('tab')),
        ),
      ));
      expect(ShellPageTracker.canPop.value, isFalse, reason: 'the tab itself is not a page above it');

      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('page 1')));
      await tester.pumpAndSettle();
      expect(ShellPageTracker.canPop.value, isTrue);

      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('page 2')));
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(ShellPageTracker.canPop.value, isTrue, reason: 'page 1 is still open');
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(ShellPageTracker.canPop.value, isFalse);
    });

    testWidgets('a sheet is not a page', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        home: Navigator(
          key: nav,
          observers: [ShellPageTracker.instance],
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('tab'))),
        ),
      ));
      showModalBottomSheet<void>(context: nav.currentContext!, builder: (_) => const SizedBox(height: 100));
      await tester.pumpAndSettle();
      expect(ShellPageTracker.canPop.value, isFalse);
    });
  });

  group('resolveShellBack', () {
    test('an open page wins over search and over going Home', () {
      expect(
          resolveShellBack(isPanelOpen: false, playerCanPop: false, detailCanPop: true, searchMode: true, tabIndex: 2),
          ShellBackAction.popDetail);
      expect(
          resolveShellBack(isPanelOpen: false, playerCanPop: false, detailCanPop: false, searchMode: false, tabIndex: 2),
          ShellBackAction.goHome);
      expect(
          resolveShellBack(isPanelOpen: true, playerCanPop: false, detailCanPop: true, searchMode: false, tabIndex: 2),
          ShellBackAction.collapsePlayer,
          reason: 'the player sits above any page');
    });
  });

  testWidgets('forwarding with maybePop lets the page decide (selection closes first)', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    var selecting = true;
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        key: nav,
        onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Text('tab')),
      ),
    ));
    nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => selecting = false);
          },
          child: Text(selecting ? 'selecting' : 'page'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await nav.currentState!.maybePop(); // what the shell now does
    await tester.pumpAndSettle();
    expect(find.text('page'), findsOneWidget, reason: 'first back leaves selection, page stays');
    await nav.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('tab'), findsOneWidget);
  });

  group('delete playlist', () {
    late MusicProvider p;

    setUpAll(() async {
      UserPlaylistDetailScreen.defaultUsePalette = false;
      SharedPreferences.setMockInitialValues({});
      final ready = Completer<void>();
      final original = debugPrint;
      debugPrint = (msg, {wrapWidth}) {
        if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) ready.complete();
      };
      p = MusicProvider();
      await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      debugPrint = original;
    });

    setUp(() {
      for (final pl in List.of(p.userPlaylists)) {
        p.deletePlaylistWithUndo(pl.id);
      }
    });

    test('a playlist with songs is gone the moment delete is pressed', () async {
      final pl = await p.createPlaylistWith(name: 'Full', tracks: [_t('a'), _t('b')]);
      var notified = 0;
      void l() => notified++;
      p.addListener(l);
      final f = p.deletePlaylist(pl!.id); // not awaited: the UI must not have to wait
      expect(p.playlistById(pl.id), isNull);
      expect(notified, greaterThan(0));
      await f;
      p.removeListener(l);
    });

    testWidgets('deleting from a playlist\'s own menu returns to the list, not past it', (tester) async {
      final pl = await tester.runAsync(() => p.createPlaylistWith(name: 'Road', tracks: [_t('a'), _t('b')]));
      await tester.binding.setSurfaceSize(const Size(412, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
        value: p,
        child: MaterialApp(theme: GlassTheme.build(AccentColors.peach), home: const Scaffold(body: Text('library'))),
      ));
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => const UserPlaylistScreen()));
      await tester.pumpAndSettle();
      nav.push(MaterialPageRoute<void>(builder: (_) => UserPlaylistDetailScreen(playlistId: pl!.id)));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete playlist'));
      await tester.pumpAndSettle();

      expect(p.playlistById(pl!.id), isNull);
      expect(find.byType(UserPlaylistScreen), findsOneWidget, reason: 'one step back, to the list');
      expect(find.byType(UserPlaylistDetailScreen), findsNothing);
      expect(find.text('Road'), findsNothing);
    });
  });
}
