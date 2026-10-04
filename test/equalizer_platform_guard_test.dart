import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/services/equalizer_service.dart';

/// Regression: playback was throwing on hardware that reports no equalizer.
///
/// `AudioEffect._activate` runs on every audio activation and the Android
/// equalizer reads its band count from the platform there. Where the platform
/// could not create the effect the handle is null, the read throws, and the
/// exception surfaces out of both `play()` and `pause()` - so a device with no
/// equalizer capability could not play anything at all.
///
/// The effect is now opt-in and out of the pipeline by default, and the service
/// refuses to switch on an effect it cannot reach rather than pretending.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('platform availability', () {
    test('defaults to unavailable before the device is asked', () {
      // Nothing has probed yet, so nothing may claim the effect works. Treating
      // "unknown" as "available" is what put a broken effect in the pipeline.
      expect(EqualizerService().isPlatformAvailable, isFalse);
    });

    test('stays unavailable with no audio service bound', () async {
      // main() calls initialize() before the player exists, so this is the real
      // boot shape rather than an edge case.
      await EqualizerService().initialize();
      expect(EqualizerService().isPlatformAvailable, isFalse);
      expect(EqualizerService().isEnabled, isFalse);
    });

    test('a persisted enabled flag does not fake availability', () async {
      // The dangerous state: a preference left over from a device that did
      // support it, restored onto one that does not.
      SharedPreferences.setMockInitialValues({'eq_enabled': true});
      await EqualizerService().initialize();
      expect(EqualizerService().isPlatformAvailable, isFalse);
    });
  });

  group('refusing to enable', () {
    test('leaves the equalizer off when the platform has none', () async {
      await EqualizerService().initialize();

      await EqualizerService().setEnabled(true);

      expect(
        EqualizerService().isEnabled,
        isFalse,
        reason: 'claiming to be on without a platform effect behind it is how '
            'the UI ends up lying about what is happening to the audio',
      );
    });

    test('does not throw when asked to enable', () async {
      await EqualizerService().initialize();
      // The old path awaited a Completer that can never complete once the effect
      // is out of the pipeline, so this is also the no-hang guard.
      await expectLater(EqualizerService().setEnabled(true), completes);
    });

    test('can still be disabled', () async {
      await EqualizerService().initialize();
      await EqualizerService().setEnabled(false);
      expect(EqualizerService().isEnabled, isFalse);
    });
  });
}
