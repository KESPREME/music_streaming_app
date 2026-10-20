// lib/widgets/lyric_line/lyric_typography.dart
// Every lyric TextStyle, in one place.
//
// No other file builds a lyric style. When the type was chosen at each call
// site, the panel, the strip and the sub-line drifted apart (28/w700 here,
// 26/w800 there) and a "same line" read at three sizes.
//
// THE FACE
//
// Plus Jakarta Sans, which is the app's face (`main.dart` builds its whole text
// theme from it). Switching the lyric screen to another family would break
// identity on the most-seen surface of a music player. Its ExtraBold has the
// dense, slightly condensed display feel of BitChord's screenshots, but it is
// wider with a taller x-height, so it reads LARGER at the same size: 32sp here
// sits optically where BitChord's 34sp does, and wraps at about the same words
// on a ~440dp phone.
//
// The face is bundled (`assets/google_fonts/`), so google_fonts resolves it from
// the asset bundle. Fetched at runtime, the lines re-laid out mid-sweep when it
// arrived.
//
// ONE STYLE PER ROLE, NEVER PER STATE
//
// An active line and an inactive one are the SAME size and weight. Changing the
// font between them invalidates the cached glyph geometry on every handover (a
// TextPainter layout pass per line, mid-animation). Emphasis is alpha, blur and
// scale, which cost nothing.

import 'package:flutter/material.dart';
import '../../theme/app_font.dart';

/// Builds a base style for a size and weight. Injected so tests can run without
/// resolving the real face.
typedef LyricFontBuilder = TextStyle Function(double fontSize, FontWeight weight);

TextStyle _defaultLyricFont(double fontSize, FontWeight weight) =>
    AppFont.style(fontSize: fontSize, fontWeight: weight);

/// The lyric type scale.
class LyricTypography {
  const LyricTypography._();

  /// Synced lyric line, every distance from the active one.
  static const double syncedSize = 32;
  static const double syncedHeight = 1.22;

  /// Tracking is -2% of the size, which tightens ExtraBold into the dense
  /// display setting the reference has.
  static const double syncedTracking = -0.64;

  static TextStyle synced({LyricFontBuilder? fontBuilder}) =>
      (fontBuilder ?? _defaultLyricFont)(syncedSize, FontWeight.w800).copyWith(
        height: syncedHeight,
        letterSpacing: syncedTracking,
      );

  /// Plain (unsynced) lyrics: smaller, because there is no sweep to hold the
  /// eye and a whole song of 32sp ExtraBold is a wall.
  static TextStyle unsynced({LyricFontBuilder? fontBuilder}) =>
      (fontBuilder ?? _defaultLyricFont)(28, FontWeight.w800).copyWith(
        height: 1.25,
        letterSpacing: -0.5,
      );

  /// A translation or romanization under its original.
  static TextStyle subLine({LyricFontBuilder? fontBuilder}) =>
      (fontBuilder ?? _defaultLyricFont)(19, FontWeight.w700).copyWith(
        height: 1.3,
        letterSpacing: -0.2,
      );

  /// The answering vocal under the lead.
  static TextStyle background({LyricFontBuilder? fontBuilder}) =>
      (fontBuilder ?? _defaultLyricFont)(22, FontWeight.w800).copyWith(
        height: 1.3,
        letterSpacing: -0.4,
      );

  /// The single line above the seek bar.
  static TextStyle strip({LyricFontBuilder? fontBuilder}) =>
      (fontBuilder ?? _defaultLyricFont)(17, FontWeight.w600).copyWith(
        height: 1.25,
        letterSpacing: -0.2,
      );

  /// "Lyrics by X" and the other status captions.
  static TextStyle caption({LyricFontBuilder? fontBuilder}) =>
      (fontBuilder ?? _defaultLyricFont)(15, FontWeight.w500).copyWith(
        height: 1.2,
      );
}
