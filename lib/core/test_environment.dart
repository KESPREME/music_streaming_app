import 'package:flutter/widgets.dart';

/// Single source of truth for "are we running under `flutter test`".
///
/// Why this exists instead of a framework constant:
/// - Flutter removed `kIsTest`; `foundation.dart` no longer exports it
///   (only `kReleaseMode`, `kProfileMode`, `kDebugMode`, `kIsWeb`, `kIsWasm`).
/// - `flutter_test` signals itself with an *environment variable*
///   (`FLUTTER_TEST`, see `flutter_test/src/binding.dart`), not a compile-time
///   define, so `bool.fromEnvironment` cannot see it from library code.
/// - `dart:io`'s `Platform.environment` would work but makes this file
///   non-web-safe, and it costs a map lookup on every call.
///
/// So the binding's runtime type is the only signal available from `lib/`.
/// Under `flutter test` the binding is always a `*TestWidgetsFlutterBinding`,
/// and a release build never installs one — so this is false on device.
///
/// This replaces six copies of an inline
/// `WidgetsBinding.instance.runtimeType.toString().contains('Test')` sniff.
///
/// IMPORTANT: keep this for *behaviour gating only* (skipping animation
/// drivers, network calls, timers). Never let it decide whether a widget is
/// built — doing so makes that widget untestable, which is how the Explore
/// equalizer lost its coverage.
class TestEnvironment {
  TestEnvironment._();

  static bool get isTest =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  /// Test-only override, for the rare case a test needs to simulate the
  /// opposite environment. Left null in production.
  static bool? override;

  static bool get isTesting => override ?? isTest;
}
