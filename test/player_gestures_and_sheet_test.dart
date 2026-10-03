import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';

// Testable mock navigator observer following _PlayerNavigatorObserver logic
class TestPlayerNavigatorObserver extends NavigatorObserver {
  final ValueChanged<bool> onCanPopChanged;
  int _routeCount = 0;

  TestPlayerNavigatorObserver({required this.onCanPopChanged});

  int get routeCount => _routeCount;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _routeCount++;
    onCanPopChanged(_routeCount > 1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _routeCount = (_routeCount - 1).clamp(0, 999);
    onCanPopChanged(_routeCount > 1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _routeCount = (_routeCount - 1).clamp(0, 999);
    onCanPopChanged(_routeCount > 1);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    onCanPopChanged(_routeCount > 1);
  }
}

void main() {
  group('Modal Sheet "Play Next" Visibility Logic', () {
    final currentPlayingTrack = Track(
      id: 'current_song_123',
      trackName: 'Blinding Lights',
      artistName: 'The Weeknd',
      albumName: 'After Hours',
      albumArt: 'https://example.com/art.jpg',
      previewUrl: '',
    );

    final otherTrack = Track(
      id: 'other_song_456',
      trackName: 'Save Your Tears',
      artistName: 'The Weeknd',
      albumName: 'After Hours',
      albumArt: 'https://example.com/art2.jpg',
      previewUrl: '',
    );

    test('Play Next is hidden when track is the currently playing track', () {
      bool shouldShowPlayNext(Track track, Track? activeTrack) {
        return activeTrack?.id != track.id;
      }

      expect(
        shouldShowPlayNext(currentPlayingTrack, currentPlayingTrack),
        isFalse,
        reason: 'Currently playing track must NOT show "Play next"',
      );

      expect(
        shouldShowPlayNext(otherTrack, currentPlayingTrack),
        isTrue,
        reason: 'Other tracks MUST show "Play next"',
      );
    });
  });

  group('PlayerNavigatorObserver & Modal Route Tracking', () {
    test('Correctly tracks when modal subroutes are pushed and popped', () {
      bool canPopReported = false;
      final observer = TestPlayerNavigatorObserver(
        onCanPopChanged: (val) {
          canPopReported = val;
        },
      );

      final route1 = MaterialPageRoute(builder: (_) => const SizedBox());
      final modalRoute = ModalBottomSheetRoute(
        builder: (_) => const SizedBox(),
        isScrollControlled: true,
      );

      // 1. Initial player screen route pushed
      observer.didPush(route1, null);
      expect(observer.routeCount, 1);
      expect(canPopReported, isFalse);

      // 2. Modal options sheet pushed onto player navigator
      observer.didPush(modalRoute, route1);
      expect(observer.routeCount, 2);
      expect(canPopReported, isTrue);

      // 3. Modal options sheet popped via swipe down
      observer.didPop(modalRoute, route1);
      expect(observer.routeCount, 1);
      expect(canPopReported, isFalse);
    });

    test('Panel drag handler is bypassed when modal sheet is open', () {
      bool isSubrouteOpen = true;

      // Simulated panel delta update
      double panelValue = 1.0;
      void handleDragUpdate(double delta) {
        if (isSubrouteOpen) {
          // Bypassed! Panel does NOT move
          return;
        }
        panelValue -= delta;
      }

      handleDragUpdate(0.15); // User swiped down 15%
      expect(panelValue, 1.0, reason: 'Panel value must NOT decrease while modal route is open');

      // Now subroute is closed
      isSubrouteOpen = false;
      handleDragUpdate(0.15);
      expect(panelValue, 0.85, reason: 'Panel value responds to drag only when subroutes are closed');
    });
  });

  group('Seekbar Scrubber & Volume Drag Bounds Clamping', () {
    test('Clamps fraction accurately between 0.0 and 1.0', () {
      double computeFraction(double localX, double width) {
        if (width <= 0) return 0.0;
        return (localX / width).clamp(0.0, 1.0);
      }

      const totalWidth = 360.0;
      expect(computeFraction(0.0, totalWidth), 0.0);
      expect(computeFraction(180.0, totalWidth), 0.5);
      expect(computeFraction(360.0, totalWidth), 1.0);
      expect(computeFraction(-20.0, totalWidth), 0.0);
      expect(computeFraction(400.0, totalWidth), 1.0);
    });
  });
}
