import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/audio_output_service.dart';
import 'thin_slider.dart';

/// Device-volume slider that stays buttery under a finger.
///
/// The rule, taken from BitChord's volume row: never update over a finger.
/// While dragging, the thumb position lives in this widget's local state and
/// writes go to the service *silently* (no `notifyListeners`, so the page
/// above does not rebuild 60 times a second). The service call itself is
/// index-deduped, so ticks inside one volume step send nothing. On release the
/// final value commits with a single notify. External changes (hardware keys,
/// route swaps) flow through the service and are picked up whenever no drag
/// is in flight - a drag in progress always wins.
///
/// Without a service in scope (tests, previews) it renders an inert slider
/// rather than crashing.
class DeviceVolumeSlider extends StatefulWidget {
  final double idleHeight;
  final double activeHeight;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const DeviceVolumeSlider({
    super.key,
    this.idleHeight = 6.0,
    this.activeHeight = 11.0,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x3DFFFFFF),
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  State<DeviceVolumeSlider> createState() => _DeviceVolumeSliderState();
}

class _DeviceVolumeSliderState extends State<DeviceVolumeSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final audio = Provider.of<AudioOutputService?>(context);
    if (audio == null) {
      return ThinSlider(
        value: 1.0,
        onValueChange: (_) {},
        idleHeight: widget.idleHeight,
        activeHeight: widget.activeHeight,
        activeColor: widget.activeColor,
        inactiveColor: widget.inactiveColor,
        semanticLabel: 'Volume',
      );
    }

    final value = (_dragValue ?? audio.volume).clamp(0.0, 1.0);
    return ThinSlider(
      value: value,
      idleHeight: widget.idleHeight,
      activeHeight: widget.activeHeight,
      activeColor: widget.activeColor,
      inactiveColor: widget.inactiveColor,
      semanticLabel: 'Volume',
      onValueChangeStart: widget.onDragStart,
      onValueChange: (v) {
        setState(() => _dragValue = v);
        audio.setDeviceVolume(v, notify: false);
      },
      onValueChangeFinished: () {
        final committed = _dragValue;
        setState(() => _dragValue = null);
        if (committed != null) {
          audio.setDeviceVolume(committed);
        }
        widget.onDragEnd?.call();
      },
    );
  }
}
