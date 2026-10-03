/// Harness for reviewing the mini-pill <-> player transition on a real device.
///
/// Two independent controls, both off unless the build asks for them by
/// `--dart-define`:
///
///   MORPH_FREEZE=[0..1]   park the transition at one progress value
///   MORPH_AUTOPEN=[ms]    open the player that long after first frame
///
/// Smoothness cannot be reviewed from a moving screencap: by the time the
/// capture lands, the animation has moved on, and a dropped frame is
/// indistinguishable from a slow capture. Every judgement about this
/// transition in the past was made on evidence of exactly that quality, which is
/// how a 290ms linear whole-screen scale survived as long as it did.
///
/// With [pinned] set, the controller is parked, the drag handlers are inert,
/// and nothing can drive it - so a frame can be captured, pulled and compared
/// byte-for-byte against the same frame on the previous build.
///
///     flutter build apk --profile --dart-define=MORPH_FREEZE=0.5
///
/// Known limitation, deliberate: this freezes the *transition*, not the
/// player's own ambient motion (mesh drift, the in-place canvas, gradient
/// tweens). Those are time-based and keep running. What the harness freezes is
/// the thing under test - the card's geometry, paint order and per-frame cost.
abstract final class MorphFreeze {
  const MorphFreeze._();

  static const String _raw = String.fromEnvironment('MORPH_FREEZE');

  /// True when the build was given any `MORPH_FREEZE` value, including `false`
  /// (which exists so a CI command line can carry the flag unconditionally).
  static bool get enabled =>
      _raw.isNotEmpty && _raw.toLowerCase() != 'false';

  /// The progress to park at, or null when the harness is off.
  static double? get pinned {
    if (!enabled) return null;
    final parsed = double.tryParse(_raw);
    if (parsed == null || !parsed.isFinite) return null;
    return parsed.clamp(0.0, 1.0);
  }

  /// True when [p] is one of the sampled flight positions rather than a rest
  /// state, i.e. when there is actually a transition to look at.
  static bool get isFlight => (pinned ?? 0.0) > 0.0 && (pinned ?? 1.0) < 1.0;

  /// Milliseconds after first frame to open the player on its own.
  ///
  /// Measuring this transition by tapping the pill does not work: the pill sits
  /// at a different height depending on whether the nav bar has minimized under
  /// the feed's scroll, playback advances on its own and can relocate it again,
  /// and a missed tap produces no trace at all rather than a bad one - so a
  /// flaky harness quietly becomes an argument about nothing. Driving the
  /// transition from inside the app takes the operator out of the measurement.
  ///
  /// Kept because it is the only reliable way to get a clean `pill-to-player`
  /// trace on a device nobody is touching. Zero (the default) disables it.
  static const int autoOpenMs =
      int.fromEnvironment('MORPH_AUTOPEN', defaultValue: 0);
}
