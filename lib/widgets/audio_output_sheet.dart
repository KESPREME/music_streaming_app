import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/audio_output_service.dart';
import 'device_volume_slider.dart';

/// Audio output picker: which sink the music reaches, and how loud.
///
/// Mirrors BitChord's sheet the way it matters. The route list is flat - every
/// available device stays visible, because on a phone there are usually two
/// and a disclosure would cost a tap merely to reveal a single row. The
/// playing row is marked with "Playing here" and a check. Volume follows the
/// routes because Android keeps one media index per output.
///
/// One honest limitation, stated here and nowhere in the UI: an unprivileged
/// app cannot move the system route, so tapping a row that is not active hands
/// off to the system page where that route is managed (Bluetooth settings for
/// headsets, sound settings for the rest) instead of pretending to switch. The
/// volume slider is fully ours - it writes the device media volume
/// (STREAM_MUSIC), not the player's internal gain.
class AudioOutputSheet extends StatelessWidget {
  const AudioOutputSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      isScrollControlled: true,
      sheetAnimationStyle: const AnimationStyle(
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
        duration: Duration(milliseconds: 320),
      ),
      builder: (_) => const AudioOutputSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioOutputService>();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Audio output',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 14),
              if (audio.outputs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text(
                      'No outputs found',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
              else
                ...audio.outputs.map(
                  (d) => _OutputRow(
                    device: d,
                    onTap: () => _onRowTap(context, audio, d),
                  ),
                ),
              const SizedBox(height: 10),
              _VolumeRow(audio: audio),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onRowTap(
    BuildContext context,
    AudioOutputService audio,
    AudioOutputDevice device,
  ) async {
    if (device.isActive) {
      Navigator.of(context).pop();
      return;
    }
    // An unprivileged app cannot move the system route itself, so a tap hands
    // off to the system page where that route is managed: Bluetooth settings
    // for headsets (connect/disconnect), sound settings for the rest.
    // BitChord can switch in-app only because it owns its ExoPlayer and calls
    // setPreferredAudioDevice on it; stock just_audio walls its player off.
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    if (device.kind == 'bluetooth') {
      await audio.openBluetoothSettings();
    } else {
      await audio.openSoundSettings();
    }
  }
}

class _OutputRow extends StatelessWidget {
  final AudioOutputDevice device;
  final VoidCallback onTap;

  const _OutputRow({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: device.isActive
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _iconFor(device.kind),
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.displayName,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (device.isActive)
                        Text(
                          'Playing here',
                          style: GoogleFonts.plusJakartaSans(
                            color:
                                Colors.white.withValues(alpha: 0.55),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                if (device.isActive)
                  const Icon(Icons.check_rounded,
                      color: Colors.white, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'bluetooth':
        return Icons.bluetooth_rounded;
      case 'wired':
        return Icons.headphones_rounded;
      case 'usb':
        return Icons.usb_rounded;
      case 'hdmi':
        return Icons.tv_rounded;
      case 'phone':
        return Icons.smartphone_rounded;
      default:
        return Icons.speaker_rounded;
    }
  }
}

class _VolumeRow extends StatelessWidget {
  final AudioOutputService audio;

  const _VolumeRow({required this.audio});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            audio.volume <= 0
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            color: Colors.white.withValues(alpha: 0.9),
            size: 22,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: DeviceVolumeSlider(
              idleHeight: 6.0,
              activeHeight: 10.0,
            ),
          ),
        ],
      ),
    );
  }
}
