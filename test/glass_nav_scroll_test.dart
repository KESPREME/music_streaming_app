import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/widgets/liquid_glass_nav_bar.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('GlassTabBar.minimizable expands and minimizes with scroll and accessory placement', (tester) async {
    final minimizeController = GlassTabBarMinimizeController(
      behavior: GlassBarMinimizeBehavior.onScrollDown,
    );

    GlassTabBarAccessoryPlacement? capturedPlacement;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              minimizeController.handleNotification(n);
              return false;
            },
            child: ListView.builder(
              itemCount: 100,
              itemBuilder: (context, index) => SizedBox(
                height: 60,
                child: Text('Item $index'),
              ),
            ),
          ),
          bottomNavigationBar: GlassTabBar.minimizable(
            tabs: const [
              GlassTab(icon: Icon(Icons.home), label: 'Home'),
              GlassTab(icon: Icon(Icons.explore), label: 'Explore'),
              GlassTab(icon: Icon(Icons.library_music), label: 'Library'),
            ],
            selectedIndex: 0,
            onTabSelected: (_) {},
            minimizeController: minimizeController,
            trailingButton: GlassTabBarTrailingButton(
              icon: const Icon(Icons.search),
              onTap: () {},
            ),
            bottomAccessory: Builder(
              builder: (context) {
                capturedPlacement = GlassTabBarAccessoryPlacementScope.of(context);
                return Container(
                  key: const ValueKey('accessory_pill'),
                  height: 56,
                  color: Colors.red,
                  child: Text('Placement: ${capturedPlacement?.name}'),
                );
              },
            ),
            bottomAccessoryHeight: 56,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(capturedPlacement, GlassTabBarAccessoryPlacement.expanded);
    expect(find.byKey(const ValueKey('accessory_pill')), findsOneWidget);

    // Realistic touch drag with TestGesture (emits UserScrollNotification)
    final gesture = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(capturedPlacement, GlassTabBarAccessoryPlacement.inline);

    // Drag back up to expand
    final upGesture = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await upGesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await upGesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await upGesture.up();
    await tester.pumpAndSettle();

    expect(capturedPlacement, GlassTabBarAccessoryPlacement.expanded);
  });

  testWidgets('LiquidGlassNavBar docks MiniPlayer on scroll down and expands on scroll up', (tester) async {
    final track = Track(
      id: 'test_track',
      trackName: 'Starboy',
      artistName: 'The Weeknd',
      albumName: 'Starboy',
      previewUrl: '',
    );

    final musicProvider = _TestMusicProvider(track: track);
    final minimizeController = GlassTabBarMinimizeController(
      behavior: GlassBarMinimizeBehavior.onScrollDown,
    );

    bool playerExpandedCalled = false;
    bool searchToggled = false;

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: musicProvider,
        child: MaterialApp(
          home: Scaffold(
            body: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                minimizeController.handleNotification(n);
                return false;
              },
              child: ListView.builder(
                itemCount: 100,
                itemBuilder: (context, index) => SizedBox(
                  height: 60,
                  child: Text('Song $index'),
                ),
              ),
            ),
            bottomNavigationBar: LiquidGlassNavBar(
              currentIndex: 0,
              onTap: (_) {},
              searchMode: false,
              minimizeController: minimizeController,
              onMinimizedTabTap: minimizeController.expand,
              onExpandPlayer: () => playerExpandedCalled = true,
              onSearchToggle: (val) => searchToggled = val,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Explore'),
                BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Library'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Initial expanded state: both title and artist are visible
    expect(find.text('Starboy'), findsOneWidget);
    expect(find.text('The Weeknd'), findsOneWidget);
    expect(find.byKey(const ValueKey('mini_expanded_content')), findsOneWidget);

    // 2. Scroll down to trigger minimize
    final gesture = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 3. Inline state: title is visible, artist is omitted, inline content key is present
    expect(find.text('Starboy'), findsOneWidget);
    expect(find.byKey(const ValueKey('mini_inline_content')), findsOneWidget);

    // 4. Play control works in inline mode
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect(musicProvider.resumeCalls, 1);

    // 5. Scroll back up to expand
    final upGesture = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await upGesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await upGesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await upGesture.up();
    await tester.pumpAndSettle();

    // 6. Restored to expanded: artist visible again
    expect(find.text('The Weeknd'), findsOneWidget);
    expect(find.byKey(const ValueKey('mini_expanded_content')), findsOneWidget);

    // 7. Tap on mini player triggers full player expand callback
    await tester.tap(find.byKey(const ValueKey('mini_player_lens')));
    await tester.pump();
    expect(playerExpandedCalled, isTrue);
  });

  testWidgets('LiquidGlassNavBar does NOT minimize on scroll down when there is no mini player (track is null)', (tester) async {
    final musicProvider = _TestMusicProvider(track: null);
    final minimizeController = GlassTabBarMinimizeController(
      behavior: GlassBarMinimizeBehavior.onScrollDown,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: musicProvider,
        child: MaterialApp(
          home: Scaffold(
            body: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                final music = musicProvider;
                if (music.currentTrack != null && !music.hideMiniPlayer) {
                  minimizeController.handleNotification(n);
                }
                return false;
              },
              child: ListView.builder(
                itemCount: 100,
                itemBuilder: (context, index) => SizedBox(
                  height: 60,
                  child: Text('Song $index'),
                ),
              ),
            ),
            bottomNavigationBar: LiquidGlassNavBar(
              currentIndex: 0,
              onTap: (_) {},
              searchMode: false,
              minimizeController: minimizeController,
              onMinimizedTabTap: minimizeController.expand,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Explore'),
                BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Library'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Initial state: all tabs visible, no mini player
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Explore'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.byKey(const ValueKey('mini_player_lens')), findsNothing);

    // Scroll down vigorously
    final gesture = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await gesture.moveBy(const Offset(0, -150));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -150));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // MUST NOT MINIMIZE: all tabs remain fully visible, minimizeController remains not minimized
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Explore'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(minimizeController.minimized, isFalse);
  });

  testWidgets('LiquidGlassNavBar does NOT minimize on scroll down when hideMiniPlayer is true', (tester) async {
    final track = Track(
      id: 'test_track_2',
      trackName: 'Blinding Lights',
      artistName: 'The Weeknd',
      albumName: 'After Hours',
      previewUrl: '',
    );

    final musicProvider = _TestMusicProvider(track: track, hide: true);
    final minimizeController = GlassTabBarMinimizeController(
      behavior: GlassBarMinimizeBehavior.onScrollDown,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MusicProvider>.value(
        value: musicProvider,
        child: MaterialApp(
          home: Scaffold(
            body: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                final music = musicProvider;
                if (music.currentTrack != null && !music.hideMiniPlayer) {
                  minimizeController.handleNotification(n);
                }
                return false;
              },
              child: ListView.builder(
                itemCount: 100,
                itemBuilder: (context, index) => SizedBox(
                  height: 60,
                  child: Text('Song $index'),
                ),
              ),
            ),
            bottomNavigationBar: LiquidGlassNavBar(
              currentIndex: 0,
              onTap: (_) {},
              searchMode: false,
              minimizeController: minimizeController,
              onMinimizedTabTap: minimizeController.expand,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Explore'),
                BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Library'),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // All tabs visible, mini player hidden
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Explore'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.byKey(const ValueKey('mini_player_lens')), findsNothing);

    // Scroll down vigorously
    final gesture = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await gesture.moveBy(const Offset(0, -150));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -150));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // MUST NOT MINIMIZE: all tabs remain fully visible
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Explore'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(minimizeController.minimized, isFalse);
  });
}

class _TestMusicProvider extends MusicProvider {
  _TestMusicProvider({this.track, bool playing = false, this.hide = false}) : _playing = playing;

  Track? track;
  bool _playing;
  bool hide;
  int resumeCalls = 0;
  int pauseCalls = 0;

  @override
  Track? get currentTrack => track;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isMiniPlayerVisible => track != null && !hide;

  @override
  bool get hideMiniPlayer => hide;

  @override
  Duration get duration => const Duration(minutes: 3);

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  void updateTrack(Track? newTrack) {
    track = newTrack;
    notifyListeners();
  }

  void updateHide(bool value) {
    hide = value;
    notifyListeners();
  }

  @override
  Future<void> resumeTrack() async {
    resumeCalls++;
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> pauseTrack() async {
    pauseCalls++;
    _playing = false;
    notifyListeners();
  }
}


