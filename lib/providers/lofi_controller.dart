import 'package:flutter/foundation.dart';

/// Lofi mode (v5.2): 0.9x speed + -1 semitone pitch on Android.
///
/// Speed drops to 0.9; pitch drops ~-1 semitone (2^(−1/12) ≈ 0.9439) so the
/// slowed audio doesn't sound chipmunk-treble-boosted. Pitch applies only on
/// Android (ExoPlayer); elsewhere silently no-op. Reverb deliberately out of
/// scope: just_audio 0.10 has no AndroidReverb — would need platform channel.
class LofiController extends ChangeNotifier {
  static const double speed = 0.9;
  static const double pitch =
      0.9439; // 2^(-1/12): one semitone down, keeps vocals natural
  static const double normalSpeed = 1.0;
  static const double normalPitch = 1.0;

  bool _enabled = false;

  bool get enabled => _enabled;

  /// Called by the owner after applying to the audio pipeline; persists.
  final void Function(bool enabled)? onChanged;

  LofiController({this.onChanged});

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    onChanged?.call(value);
  }

  void toggle() => setEnabled(!enabled);
}
