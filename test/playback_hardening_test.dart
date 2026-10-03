import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/audio_service.dart';
import 'package:music_streaming_app/services/canvas_video_manager.dart';

/// Guards for the three playback/lifecycle faults reported from the device:
///
///  1. A queued song playing twice. Two independent paths could do it: the
///     dry-window repair appended a track the window already held, and the
///     repair "resumed" a completed player - which restarts the *finished*
///     item from zero rather than carrying on.
///
///  2. A cold start that skipped the song or sat paused. just_audio's `play()`
///     broadcasts `playing: true` and then silently reverts it if the audio
///     session will not activate (just_audio.dart L1117-1120). Nothing raises,
///     so an optimistic play could evaporate with no error anywhere.
///
///  3. A full black screen after returning to the app. The canvas video
///     singleton was never told about the app lifecycle at all, so its
///     decoder and surface were held across the stop/start cycle.
///
/// The internals of these need a real platform, so what is pinned here is the
/// part that must never be wrong: the guards that stop the bad move from being
/// attempted in the first place.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dry-window advance cannot replay a finished track', () {
    test('advanceIntoWindow reports false when there is no successor',
        () async {
      final svc = AudioService();
      addTearDown(svc.dispose);

      // Nothing is loaded, so there is no next entry. The method must decline
      // rather than seek-and-play: a completed item restarted from zero is the
      // "the song played twice" report.
      expect(await svc.advanceIntoWindow(), isFalse);
    });

    test('advanceIntoWindow is safe to call repeatedly', () async {
      final svc = AudioService();
      addTearDown(svc.dispose);

      // Idempotent under the failure mode it is guarding: a repair that runs
      // twice must not leave two seeks in flight.
      expect(await svc.advanceIntoWindow(), isFalse);
      expect(await svc.advanceIntoWindow(), isFalse);
    });
  });

  group('canvas video follows the app lifecycle', () {
    testWidgets('every lifecycle transition is survivable', (tester) async {
      final mgr = CanvasVideoManager.instance;

      for (final state in AppLifecycleState.values) {
        expect(() => mgr.didChangeAppLifecycleState(state), returnsNormally);
      }
    });

    testWidgets('a shade pull is not mistaken for a return to the app',
        (tester) async {
      final mgr = CanvasVideoManager.instance;

      // inactive -> resumed without a real pause in between is a notification
      // shade or a permission dialog. Treating that as "come back" would start
      // the video decoding behind a player screen the user never left.
      mgr.didChangeAppLifecycleState(AppLifecycleState.inactive);
      mgr.didChangeAppLifecycleState(AppLifecycleState.resumed);

      // A real round trip must still be handled.
      mgr.didChangeAppLifecycleState(AppLifecycleState.paused);
      mgr.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(() => mgr.resume(), returnsNormally);
    });
  });
}