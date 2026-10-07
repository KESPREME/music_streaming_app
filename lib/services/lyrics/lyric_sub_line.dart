// lib/services/lyrics/lyric_sub_line.dart
// The transformed lyric drawn as a small line UNDER each original.
//
// WHY A SUB-LINE AND NOT A REPLACEMENT
//
// The sweep is driven by the ORIGINAL line's word timings: each timing is a span
// of characters in the original text, and the reveal clips the rendered glyphs to
// that span. Swap the line's text for a translation and every one of those spans
// now indexes the wrong characters - the wipe clips letters that are not the ones
// being sung, which is not a subtle bug, it is a lyric that highlights the wrong
// words.
//
// A translation is also not sung. There is nothing to sync it to.
//
// So the panel keeps the original as the line, always, and the transform goes
// underneath it in smaller type. The timings stay meaningful because the text they
// index never changed.
//
// ONE MODE AT A TIME BY CONSTRUCTION
//
// [SubLineMode] holds a single value. Switching closes the outgoing transform
// before opening the incoming one, so a romanization and a translation are never
// on screen together - which is what "the gap" below is about.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'lyrics_translation_service.dart';

/// Which transform, if any, is drawn under the original.
enum SubLineMode { original, romanized, translated }

/// The transform to fetch for a mode.
LyricsTransform? transformFor(SubLineMode mode) => switch (mode) {
      SubLineMode.original => null,
      SubLineMode.romanized => LyricsTransform.romanize,
      SubLineMode.translated => LyricsTransform.translate,
    };

/// How long the sub-line takes to open.
const int subLineOpenMs = 460;

/// How long it takes to close.
const int subLineCloseMs = 260;

/// Drives a sub-line reveal: a listenable that also carries the progress.
///
/// An interface so the lyric line can read the reveal without importing the
/// transform service or knowing how a translation is fetched.
abstract class SubLineReveal extends Listenable {
  /// 0..1 for the reveal. 0 hides the sub-line and reserves no height.
  double get progress;
}

/// Holds the transform for the current track and reveals it under the original.
///
/// The open/close pair is what makes the mode switch read as one movement rather
/// than a flicker: the outgoing transform is gone before the incoming one
/// starts, so the space between the original and the line below is never occupied
/// by both.
class SubLineController extends ChangeNotifier implements SubLineReveal {
  SubLineMode _mode = SubLineMode.original;
  SubLineMode _shown = SubLineMode.original;
  double _progress = 0;
  Timer? _close;
  Timer? _open;
  bool _busy = false;
  List<String>? _lines;
  String? _trackKey;
  String? _pendingTrackKey;
  bool _alreadyInLanguage = false;

  /// Set when the last request could not have produced anything new, so the disc
  /// can say so instead of pretending to be working.
  ///
  /// Named after the STATE rather than the action: the reference distinguishes
  /// `AlreadyRomanized` from `Unavailable` (`LyricsTranslation.kt:64`) because
  /// they deserve different words. "These lyrics already use Latin characters"
  /// is a fact about the song; "translation failed" is a fault of ours, and
  /// conflating them tells the reader their lyrics are in the wrong script.
  bool get alreadyInLanguage => _alreadyInLanguage;

  SubLineMode get mode => _mode;

  /// The mode actually on screen.
  ///
  /// Different from [mode] mid-transition: during a close-then-open the previous
  /// transform is still folding away.
  SubLineMode get shownMode => _shown;

  /// 0..1 for the reveal. The caller reads it outside build where it can.
  @override
  double get progress => _progress;

  bool get isBusy => _busy;

  /// The transform lines, parallel to the entries handed in, or null.
  List<String>? get lines => _lines;

  bool get hasText => _lines != null;

  /// Shows [mode], fetching the transform if it is not already here.
  Future<void> toggle(
    SubLineMode mode, {
    required String trackKey,
    required List<String> sourceLines,
    required String targetLanguage,
  }) async {
    // A tap on the transform that is already on turns it off. The discs are
    // toggles, not a stepper: getting back to the original must not take three
    // taps.
    if (_mode == mode) {
      _apply(SubLineMode.original);
      return;
    }
    if (_mode != SubLineMode.original) {
      _apply(SubLineMode.original);
      return;
    }
    await show(
      mode,
      trackKey: trackKey,
      sourceLines: sourceLines,
      targetLanguage: targetLanguage,
    );
  }

  /// Shows [mode], fetching if needed. No toggling.
  Future<void> show(
    SubLineMode mode, {
    required String trackKey,
    required List<String> sourceLines,
    required String targetLanguage,
  }) async {
    if (mode == SubLineMode.original) {
      _apply(SubLineMode.original);
      return;
    }

    if (_lines != null && _trackKey == trackKey) {
      _apply(mode);
      return;
    }

    final transform = transformFor(mode);
    if (transform == null) return;

    // Decided BEFORE the request, so the disc can be right immediately and the
    // round trip is never spent on an answer that cannot differ from the original.
    //
    // Was written and never wired: `reportAlreadyInLanguage` defaulted to false
    // and no caller passed it, so `_alreadyInLanguage` could only ever be false
    // and the whole guard - plus the disc tint and the message that hang off it -
    // was unreachable.
    if (transform == LyricsTransform.romanize &&
        LyricsTranslationService.isAlreadyRomanizable(sourceLines)) {
      _alreadyInLanguage = true;
      notifyListeners();
      return;
    }

    _busy = true;
    _pendingTrackKey = trackKey;
    notifyListeners();

    try {
      final result = await LyricsTranslationService.instance.transform(
        lines: sourceLines,
        kind: transform,
        targetLanguage: targetLanguage,
      );

      // The track moved while this was in flight. Dropping it is the only safe
      // answer: painting the previous song's translation under this one is worse
      // than having no sub-line.
      if (_pendingTrackKey != trackKey) return;

      if (result == null || result.length != sourceLines.length) {
        // Nothing usable. The original stays exactly as it is, which is the
        // point of this design - a failed transform costs a sub-line, not the
        // lyric.
        return;
      }

      _alreadyInLanguage = false;
      _lines = result;
      _trackKey = trackKey;
      _apply(mode);
    } finally {
      if (_pendingTrackKey == trackKey) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  /// Set once when a transform could not have produced anything new, because the
  /// text was already in the requested script. Drives the "already in English"
  /// message.

  /// Drops the transform because the track changed.
  ///
  /// The mode resets too: leaving it on "translated" after a track change shows
  /// the originals labelled as a translation, which is a lie with a UI attached.
  void onTrackChanged(String trackKey) {
    if (_trackKey == trackKey) return;
    _trackKey = null;
    _pendingTrackKey = null;
    _lines = null;
    _mode = SubLineMode.original;
    _shown = SubLineMode.original;
    _progress = 0;
    _alreadyInLanguage = false;
    _close?.cancel();
    _open?.cancel();
    notifyListeners();
  }

  void _apply(SubLineMode next) {
    _close?.cancel();
    _open?.cancel();

    // Close first. A transform folding away and another unfolding in overlap the
    // same gap for a few frames, and the reader sees two scripts where there
    // should be one.
    if (_shown != SubLineMode.original && _progress > 0) {
      final from = _progress;
      _mode = next;
      _shown = SubLineMode.original;
      _close = Timer.periodic(
        const Duration(milliseconds: 16),
        (timer) {
          final delta = 16 / subLineCloseMs;
          _progress = from - delta;
          if (_progress <= 0) {
            _progress = 0;
            timer.cancel();
            _close = null;
            if (_mode != SubLineMode.original) _grow();
            notifyListeners();
            return;
          }
          notifyListeners();
        },
      );
      return;
    }

    _mode = next;
    if (next == SubLineMode.original) {
      _progress = 0;
      _shown = SubLineMode.original;
      notifyListeners();
      return;
    }
    _grow();
  }

  void _grow() {
    _shown = _mode;
    _progress = 0;
    var elapsed = 0;
    _open = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      elapsed += 16;
      _progress = (elapsed / subLineOpenMs).clamp(0.0, 1.0);
      if (_progress >= 1) {
        timer.cancel();
        _open = null;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _close?.cancel();
    _open?.cancel();
    super.dispose();
  }
}