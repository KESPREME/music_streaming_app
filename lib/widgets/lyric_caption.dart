// lib/widgets/lyric_caption.dart
// The one-line status under the lyric: what is being done to the words, or who
// they came from.
//
// ONE LINE, ONE DECISION
//
// The caption used to be a row of two things - "Lyrics by X" and a chevron - that
// could each be wrong on its own. It is now one string chosen by
// [LyricCaption.resolve] in a fixed order, so the same state always says the same
// thing, and the order is a function a test can read rather than a nest of ifs in
// a build:
//
//   1. Translating… / Romanizing…       work is in flight
//   2. Translated to {language} / Romanized   the transform on screen
//   3. Lyrics by {source}               the ordinary answer
//   4. No lyrics found                  the lookup finished with nothing
//   5. Finding lyrics…                  the lookup has not finished
//
// (BitChord `LyricsStatusWithChange`, PlayerLyrics.kt:424. It draws a status and
// a separate underlined "Change" link; here the whole caption is the link, so
// there is no second target and no icon to fight the text for the eye.)
//
// "No lyrics found" and "Finding lyrics…" are told apart by `loading`, never by
// order alone: saying the lookup found nothing while it is still looking is how
// a song with lyrics used to read as having none.
//
// Typography is [LyricTypography.caption] and nothing else - this file builds no
// TextStyle of its own, for the reason that file gives.

import 'package:flutter/material.dart';

import '../services/lyrics/lyrics_translation_service.dart';
import 'lyric_line/lyric_typography.dart';

/// What the lyric panel is doing to the words.
enum LyricTransformPhase {
  none,
  translating,
  romanizing,
  translated,
  romanized
}

/// The transform state the caption needs, and no more.
///
/// A small value the panel publishes and the player reads. It exists so the
/// player does not have to know how a translation is fetched, cached or
/// cancelled - only what to SAY about it.
@immutable
class LyricTransformStatus {
  const LyricTransformStatus(this.phase, {this.language = ''});

  /// Nothing is being done to the words.
  static const LyricTransformStatus none =
      LyricTransformStatus(LyricTransformPhase.none);

  final LyricTransformPhase phase;

  /// The language the translation targets, as typed (`fr`, `pt_BR`). Empty when
  /// unknown. Only read for [LyricTransformPhase.translated].
  final String language;

  @override
  bool operator ==(Object other) =>
      other is LyricTransformStatus &&
      other.phase == phase &&
      other.language == language;

  @override
  int get hashCode => Object.hash(phase, language);

  @override
  String toString() => 'LyricTransformStatus($phase, $language)';
}

/// Which sentence the caption is saying.
enum LyricCaptionKind {
  translating,
  romanizing,
  translated,
  romanized,
  source,

  /// Lyrics are on screen but nobody can say whose they are (a cached answer
  /// from a provider this build no longer has). Said plainly rather than
  /// guessing: attributing them to whichever source is first today is a lie.
  sourceUnknown,
  noLyrics,
  loading,
}

/// A decided caption: the sentence, and what it is.
@immutable
class LyricCaptionData {
  const LyricCaptionData(this.kind, this.text);

  final LyricCaptionKind kind;
  final String text;

  /// Whether tapping it opens the provider sheet.
  ///
  /// Everything but the quiet loading text: a miss is exactly when a reader wants
  /// to try another source.
  bool get opensProviders => kind != LyricCaptionKind.loading;

  @override
  bool operator ==(Object other) =>
      other is LyricCaptionData && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);
}

/// The caption's decision, as a pure function.
abstract final class LyricCaption {
  static const String translating = 'Translating…';
  static const String romanizing = 'Romanizing…';
  static const String romanized = 'Romanized';
  static const String noLyrics = 'No lyrics found';
  static const String loading = 'Finding lyrics…';

  /// Chooses what the caption says.
  ///
  /// [hasLyrics] is whether lyric lines are on screen; [source] the provider's
  /// display name, or null when it is not known; [loading] whether a lookup is
  /// still in flight. [languageName] maps a language code to a name and is
  /// injectable so a test need not depend on the table behind it.
  static LyricCaptionData resolve({
    required LyricTransformStatus transform,
    required bool hasLyrics,
    required String? source,
    required bool loading,
    String Function(String code) languageName =
        LyricsTranslationService.languageName,
  }) {
    // Work in flight outranks everything, lyrics on screen or not: it is the one
    // thing happening RIGHT NOW, and the caption is where the reader looks for it.
    switch (transform.phase) {
      case LyricTransformPhase.translating:
        return const LyricCaptionData(
          LyricCaptionKind.translating,
          LyricCaption.translating,
        );
      case LyricTransformPhase.romanizing:
        return const LyricCaptionData(
          LyricCaptionKind.romanizing,
          LyricCaption.romanizing,
        );
      case LyricTransformPhase.translated when hasLyrics:
        final name = languageName(transform.language);
        return LyricCaptionData(
          LyricCaptionKind.translated,
          name.isEmpty ? 'Translated' : 'Translated to $name',
        );
      case LyricTransformPhase.romanized when hasLyrics:
        return const LyricCaptionData(
          LyricCaptionKind.romanized,
          LyricCaption.romanized,
        );
      case LyricTransformPhase.translated:
      case LyricTransformPhase.romanized:
      case LyricTransformPhase.none:
        break;
    }

    if (hasLyrics) {
      return source == null || source.isEmpty
          ? const LyricCaptionData(LyricCaptionKind.sourceUnknown, 'Lyrics')
          : LyricCaptionData(LyricCaptionKind.source, 'Lyrics by $source');
    }
    return loading
        ? const LyricCaptionData(
            LyricCaptionKind.loading,
            LyricCaption.loading,
          )
        : const LyricCaptionData(
            LyricCaptionKind.noLyrics,
            LyricCaption.noLyrics,
          );
  }
}

/// Draws a [LyricCaptionData] on one line.
///
/// Underlined when it opens the provider sheet, plain and quieter when it is only
/// a status. No icon and no chevron: the underline is the whole affordance.
class LyricCaptionText extends StatelessWidget {
  const LyricCaptionText({super.key, required this.data, this.onTap});

  final LyricCaptionData data;

  /// Opens the provider sheet. Ignored for a caption that is only a status.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final interactive = data.opensProviders && onTap != null;
    final alpha = switch (data.kind) {
      LyricCaptionKind.loading => 0.45,
      LyricCaptionKind.noLyrics => 0.55,
      _ => 0.72,
    };
    final color = Colors.white.withValues(alpha: alpha);
    final text = Text(
      data.text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: LyricTypography.caption().copyWith(
        color: color,
        decoration:
            interactive ? TextDecoration.underline : TextDecoration.none,
        decorationColor: color,
      ),
    );

    if (!interactive) {
      return Align(alignment: Alignment.centerLeft, child: text);
    }

    return Semantics(
      button: true,
      label: data.text,
      hint: 'Change lyrics provider',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // A caption this small is a fingertip-sized target only with a little
        // air around it. Vertical only: the width is the text's own.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Align(alignment: Alignment.centerLeft, child: text),
        ),
      ),
    );
  }
}
