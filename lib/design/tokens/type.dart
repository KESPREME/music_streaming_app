import 'package:flutter/material.dart';
import '../../theme/app_font.dart';

/// Typography scale on Outfit. Weights are deliberate; hierarchy comes from
/// size + weight + opacity, not from extra families or all-bold layouts.
abstract final class Type {
  // Display — full player track title.
  static TextStyle display(BuildContext context) => AppFont.style(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.15,
        color: _onSurface(context),
      );

  // Title — screen headers, section titles.
  static TextStyle title(BuildContext context) => AppFont.style(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: _onSurface(context),
      );

  // Section — rail headers inside screens.
  static TextStyle section(BuildContext context) => AppFont.style(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: _onSurface(context),
      );

  // Body — primary list rows.
  static TextStyle body(BuildContext context) => AppFont.style(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: _onSurface(context),
      );

  // Label — buttons, tabs, chips.
  static TextStyle label(BuildContext context) => AppFont.style(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: _onSurface(context),
      );

  // Metadata — artist names, durations, secondary info.
  static TextStyle metadata(BuildContext context) => AppFont.style(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: _onSurface(context, 0.62),
      );

  // Caption — timestamps, tiny annotations.
  static TextStyle caption(BuildContext context) => AppFont.style(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.2,
        color: _onSurface(context, 0.5),
      );

  // Search hint — inside the glass search pill.
  static TextStyle searchHint(BuildContext context) => AppFont.style(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.2,
        color: _onSurface(context, 0.45),
      );

  static Color _onSurface(BuildContext context, [double opacity = 0.95]) =>
      Colors.white.withValues(alpha: opacity);
}
