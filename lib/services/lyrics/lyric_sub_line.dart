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
// THE STATE MACHINE (reference: `rememberLyricsTranslation`, `PlayerLyrics.kt`)
//
// Each transform has its own status - idle -> loading -> ready | sameLanguage |
// unavailable - and the whole thing is scoped to a SESSION: the track, the target
// language and the exact lyric the transform was made for. Change any of the three
// and every status, every fetched line and every request in flight is dropped,
// because a translation of another song, of another language, or of a different
// provider's words is worse than none.
//
// ONE MODE AT A TIME BY CONSTRUCTION
//
// [mode] holds a single value. Starting one transform cancels the other's request,
// and switching closes the outgoing sub-line before opening the incoming one, so a
// romanization and a translation are never on screen together.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../models/lyrics_entry.dart';
import 'lyrics_translation_service.dart';

/// Which transform, if any, is drawn under the original.
enum SubLineMode { original, romanized, translated }

/// Where one transform is in its life.
enum SubLineStatus {
  /// Never asked, or the ask was withdrawn.
  idle,

  /// A request is in flight. Taps on the same disc are ignored.
  loading,

  /// Fetched. A tap toggles between the original and this transform.
  ready,

  /// Nothing to do: already in the target language, or already Latin script. A
  /// tap explains rather than asks again.
  sameLanguage,

  /// The request failed. The original is untouched, and a tap tries again.
  unavailable,
}

/// The feedback a tap earns, decided here so a tap that does nothing is silent.
enum SubLineHaptic { tap, select, toggleOn }

/// What a tap on a disc did, so the screen can answer it.
enum SubLineTap {
  /// The transform is now on screen.
  shown,

  /// The transform was on and the original is back.
  hidden,

  /// The same transform was already loading; the tap was ignored.
  ignored,

  /// There was nothing to transform (already in the language / already Latin).
  sameLanguage,

  /// The request failed.
  unavailable,

  /// Something newer replaced this request while it was in flight: another
  /// transform was started, or the track, language or lyric changed.
  superseded,

  /// No lyric to transform.
  empty,
}

/// Fetches a transform. A seam: production calls the service, a test hands in a
/// recorded answer and the network is never touched.
typedef LyricsTransformer = Future<LyricsTransformResult> Function({
  required String trackId,
  required List<String> lines,
  required LyricsTransform kind,
  required String targetLanguage,
  LyricsCancelToken? cancel,
});

typedef SubLineHaptics = void Function(SubLineHaptic kind);

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

/// What a request is scoped to.
class _Session {
  const _Session(this.trackKey, this.targetLanguage, this.sourceLines);

  final String trackKey;
  final String targetLanguage;
  final List<String> sourceLines;

  bool matches(String track, String language, List<String> lines) =>
      track == trackKey &&
      language == targetLanguage &&
      listEquals(lines, sourceLines);
}

/// One transform's status, answer and in-flight request.
class _Job {
  SubLineStatus status = SubLineStatus.idle;
  List<String>? lines;
  LyricsCancelToken? token;
}

/// Holds the transforms for the current track and reveals one under the original.
///
/// The open/close pair is what makes the mode switch read as one movement rather
/// than a flicker: the outgoing transform is gone before the incoming one
/// starts, so the space between the original and the line below is never occupied
/// by both.
class SubLineController extends ChangeNotifier implements SubLineReveal {
  /// [transformer] and [haptics] are seams for tests; production reads the
  /// shared service and the platform's feedback motors.
  SubLineController({LyricsTransformer? transformer, SubLineHaptics? haptics})
      : _transformer = transformer ?? _serviceTransformer,
        _haptics = haptics ?? _platformHaptics;

  // Resolved at CALL time, not captured: a test that swaps the shared service
  // after this controller exists still reaches its recorded answer.
  static Future<LyricsTransformResult> _serviceTransformer({
    required String trackId,
    required List<String> lines,
    required LyricsTransform kind,
    required String targetLanguage,
    LyricsCancelToken? cancel,
  }) =>
      LyricsTranslationService.instance.transform(
        trackId: trackId,
        lines: lines,
        kind: kind,
        targetLanguage: targetLanguage,
        cancel: cancel,
      );

  static void _platformHaptics(SubLineHaptic kind) {
    // Fire-and-forget: feedback is never worth waiting for, and a platform
    // without a motor must not fail a tap.
    switch (kind) {
      case SubLineHaptic.tap:
      case SubLineHaptic.select:
        HapticFeedback.selectionClick();
      case SubLineHaptic.toggleOn:
        HapticFeedback.lightImpact();
    }
  }

  final LyricsTransformer _transformer;
  final SubLineHaptics _haptics;

  SubLineMode _mode = SubLineMode.original;
  SubLineMode _shown = SubLineMode.original;
  double _progress = 0;
  Timer? _close;
  Timer? _open;

  _Session? _session;
  final Map<SubLineMode, _Job> _jobs = {
    SubLineMode.romanized: _Job(),
    SubLineMode.translated: _Job(),
  };

  // `matchesLyrics` is asked once per row per frame while a reveal runs; the
  // answer only changes when the list is replaced, so it is remembered by
  // identity.
  List<LyricsEntry>? _checkedEntries;
  _Session? _checkedSession;
  bool _checkedResult = true;

  /// The transform requested: what the discs light and what the strip reads.
  SubLineMode get mode => _mode;

  /// The mode actually on screen.
  ///
  /// Different from [mode] mid-transition: during a close-then-open the previous
  /// transform is still folding away, and its text stays painted until it has
  /// gone. (It used to be switched to the original the moment the fold started,
  /// so the sub-line vanished at once and the 260ms close was never seen.)
  SubLineMode get shownMode => _shown;

  /// 0..1 for the reveal. The caller reads it outside build where it can.
  @override
  double get progress => _progress;

  /// The status of [mode]'s transform. [SubLineMode.original] has none.
  SubLineStatus status(SubLineMode mode) =>
      _jobs[mode]?.status ?? SubLineStatus.idle;

  /// The mode whose request is in flight, if any. At most one: starting a
  /// transform cancels the other.
  SubLineMode? get loadingMode {
    for (final entry in _jobs.entries) {
      if (entry.value.status == SubLineStatus.loading) return entry.key;
    }
    return null;
  }

  bool get isBusy => loadingMode != null;

  /// The language the current session translates into (as typed), or empty.
  String get targetLanguage => _session?.targetLanguage ?? '';

  /// The lines of the transform ON SCREEN, parallel to the lyric, or null.
  List<String>? get lines {
    final job = _jobs[_shown];
    return job?.status == SubLineStatus.ready ? job!.lines : null;
  }

  bool get hasText => lines != null;

  /// The lines of the transform REQUESTED, or null when the original is the
  /// requested mode.
  ///
  /// What the one-line strip over the seek bar reads (BitChord's
  /// `displayedLyrics`). Switches the instant the mode does, not when the sub-line
  /// has finished folding, because the strip has no fold to wait for.
  List<String>? get displayedLines {
    final job = _jobs[_mode];
    return job?.status == SubLineStatus.ready ? job!.lines : null;
  }

  /// [displayedLines] for the lyric [entries], or null if they were made for a
  /// different one.
  ///
  /// What the strip should be handed. Plain [displayedLines] is stale for a frame
  /// after a provider switch (the reset waits for the end of the frame), and the
  /// strip would show the old words' translation under the new lyric.
  List<String>? displayedLinesFor(List<LyricsEntry> entries) {
    final shown = displayedLines;
    if (shown == null || !matchesLyrics(entries)) return null;
    return shown.length == entries.length ? shown : null;
  }

  /// Set when the last tap could not have produced anything new, so the disc can
  /// say so instead of pretending to be working.
  ///
  /// Named after the STATE rather than the action: the reference distinguishes
  /// `AlreadyRomanized` from `Unavailable` because they deserve different words.
  /// "These lyrics already use Latin characters" is a fact about the song;
  /// "translation failed" is a fault of ours, and conflating them tells the reader
  /// their lyrics are in the wrong script.
  bool get alreadyInLanguage => _jobs.values
      .any((job) => job.status == SubLineStatus.sameLanguage);

  /// What the caption under the player says about the transform, or null when
  /// there is nothing to say.
  ///
  /// The reference's order (`rememberLyricsTranslation`): work in flight first,
  /// then what is on screen, then the "nothing to do" facts.
  String? get statusText {
    final language = LyricsTranslationService.languageName(targetLanguage);
    final translated = status(SubLineMode.translated);
    final romanized = status(SubLineMode.romanized);
    if (translated == SubLineStatus.loading) {
      return language.isEmpty ? 'Translating…' : 'Translating to $language…';
    }
    if (romanized == SubLineStatus.loading) return 'Romanizing lyrics…';
    if (_mode == SubLineMode.translated && translated == SubLineStatus.ready) {
      return language.isEmpty ? 'Translated' : 'Translated to $language';
    }
    if (_mode == SubLineMode.romanized && romanized == SubLineStatus.ready) {
      return 'Romanized pronunciation';
    }
    if (translated == SubLineStatus.sameLanguage) {
      return language.isEmpty ? 'Already in this language' : 'Already in $language';
    }
    if (romanized == SubLineStatus.sameLanguage) {
      return 'These lyrics already use Latin characters';
    }
    return null;
  }

  // ── Taps ───────────────────────────────────────────────────────────────────

  /// What a tap on [mode]'s disc does.
  ///
  /// * loading: ignored.
  /// * ready: the transform if the original is showing, the original if this
  ///   transform is showing, this transform if the OTHER one is showing. The discs
  ///   are toggles, not a stepper: getting back to the original must not take
  ///   three taps.
  /// * sameLanguage: explained (the caller shows the message), not re-requested.
  /// * idle / unavailable: requested, cancelling the other transform's request.
  ///
  /// Resolves when the tap is settled, which for a request is when it answers.
  Future<SubLineTap> toggle(
    SubLineMode mode, {
    required String trackKey,
    required List<String> sourceLines,
    required String targetLanguage,
  }) =>
      _tap(
        mode,
        trackKey: trackKey,
        sourceLines: sourceLines,
        targetLanguage: targetLanguage,
        toggling: true,
      );

  /// Shows [mode], fetching if needed. No toggling: a ready transform that is
  /// already showing stays showing.
  Future<SubLineTap> show(
    SubLineMode mode, {
    required String trackKey,
    required List<String> sourceLines,
    required String targetLanguage,
  }) =>
      _tap(
        mode,
        trackKey: trackKey,
        sourceLines: sourceLines,
        targetLanguage: targetLanguage,
        toggling: false,
      );

  Future<SubLineTap> _tap(
    SubLineMode mode, {
    required String trackKey,
    required List<String> sourceLines,
    required String targetLanguage,
    required bool toggling,
  }) async {
    if (mode == SubLineMode.original) {
      _apply(SubLineMode.original);
      return SubLineTap.hidden;
    }
    if (!sourceLines.any((line) => line.trim().isNotEmpty)) {
      return SubLineTap.empty;
    }

    _syncSession(trackKey, targetLanguage.trim(), sourceLines);
    final job = _jobs[mode]!;

    switch (job.status) {
      case SubLineStatus.loading:
        return SubLineTap.ignored;

      case SubLineStatus.ready:
        final next = toggling && _mode == mode ? SubLineMode.original : mode;
        _apply(next);
        _haptics(SubLineHaptic.select);
        return next == SubLineMode.original ? SubLineTap.hidden : SubLineTap.shown;

      case SubLineStatus.sameLanguage:
        _haptics(SubLineHaptic.tap);
        return SubLineTap.sameLanguage;

      case SubLineStatus.idle:
      case SubLineStatus.unavailable:
        return _start(mode, job, sourceLines);
    }
  }

  Future<SubLineTap> _start(
    SubLineMode mode,
    _Job job,
    List<String> sourceLines,
  ) async {
    final session = _session!;
    _haptics(SubLineHaptic.tap);

    // Starting one cancels the other. Left running, a slow translation would land
    // after the reader had moved on to the globe and switch the display back.
    final other = _jobs[
        mode == SubLineMode.romanized
            ? SubLineMode.translated
            : SubLineMode.romanized]!;
    if (other.status == SubLineStatus.loading) {
      other.token?.cancel();
      other.status = SubLineStatus.idle;
    }

    // Decided BEFORE the request, so the answer is immediate and the round trip is
    // never spent on a result that cannot differ from the original. The service
    // applies the same rule; this is the same function, asked early.
    if (mode == SubLineMode.romanized &&
        LyricsTranslationService.isAlreadyRomanizable(sourceLines)) {
      job.status = SubLineStatus.sameLanguage;
      notifyListeners();
      return SubLineTap.sameLanguage;
    }

    final token = LyricsCancelToken();
    job
      ..status = SubLineStatus.loading
      ..token = token;
    notifyListeners();

    LyricsTransformResult result;
    try {
      result = await _transformer(
        trackId: session.trackKey,
        lines: sourceLines,
        kind: transformFor(mode)!,
        targetLanguage: session.targetLanguage,
        cancel: token,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('SubLineController: transform threw: $e');
      result = const LyricsTransformUnavailable();
    }

    // The session moved on, or the other transform took over, while this was in
    // flight. Dropping it is the only safe answer: painting the previous song's
    // translation under this one is worse than having no sub-line.
    if (token.isCancelled || !identical(job.token, token)) {
      return SubLineTap.superseded;
    }

    switch (result) {
      case LyricsTransformReady(:final lines):
        if (lines.length != sourceLines.length) {
          job.status = SubLineStatus.unavailable;
          notifyListeners();
          return SubLineTap.unavailable;
        }
        job
          ..status = SubLineStatus.ready
          ..lines = lines;
        _apply(mode);
        _haptics(SubLineHaptic.toggleOn);
        return SubLineTap.shown;

      case LyricsTransformSameLanguage():
        job.status = SubLineStatus.sameLanguage;
        notifyListeners();
        return SubLineTap.sameLanguage;

      case LyricsTransformUnavailable():
        // Nothing usable. The original stays exactly as it is, which is the point
        // of this design - a failed transform costs a sub-line, not the lyric.
        job.status = SubLineStatus.unavailable;
        notifyListeners();
        return SubLineTap.unavailable;
    }
  }

  // ── Scope ──────────────────────────────────────────────────────────────────

  /// Adopts the scope of a request, dropping everything made for another one.
  ///
  /// Per (track, language, lyric): the reference keys all of its state on exactly
  /// those three, so a changed setting or a provider switch cannot leave a
  /// translation of the old words under the new ones.
  void _syncSession(String trackKey, String language, List<String> lines) {
    final current = _session;
    if (current != null && current.matches(trackKey, language, lines)) return;
    // The display goes too, not just the answers: a disc left lit for a
    // translation that no longer exists is a control describing nothing.
    if (current != null) _resetAll();
    _session = _Session(trackKey, language, List<String>.of(lines));
    _checkedEntries = null;
  }

  /// Whether the transform on hand was made for [entries].
  ///
  /// True when there is no transform yet. Remembered per list, because the panel
  /// asks once per row per frame during a reveal.
  bool matchesLyrics(List<LyricsEntry> entries) {
    final session = _session;
    if (session == null) return true;
    if (identical(entries, _checkedEntries) && identical(session, _checkedSession)) {
      return _checkedResult;
    }
    _checkedEntries = entries;
    _checkedSession = session;
    _checkedResult = listEquals(
      [for (final entry in entries) entry.text],
      session.sourceLines,
    );
    return _checkedResult;
  }

  /// The sub-line text for [entries], or null if the transform on screen was made
  /// for different lyrics.
  List<String>? linesFor(List<LyricsEntry> entries) {
    final shown = lines;
    if (shown == null || !matchesLyrics(entries)) return null;
    return shown.length == entries.length ? shown : null;
  }

  /// Drops the transform because the lyric it belongs to was replaced (a provider
  /// switch). The mode resets with it: leaving it on "translated" would label the
  /// new words as a translation.
  void onSourceChanged() {
    if (_session == null) return;
    _resetAll();
  }

  /// Drops the transform because the track changed.
  ///
  /// The mode resets too: leaving it on "translated" after a track change shows
  /// the originals labelled as a translation, which is a lie with a UI attached.
  void onTrackChanged(String trackKey) {
    if (_session?.trackKey == trackKey) return;
    _resetAll();
  }

  void _resetJobs() {
    for (final job in _jobs.values) {
      job.token?.cancel();
      job
        ..token = null
        ..lines = null
        ..status = SubLineStatus.idle;
    }
  }

  void _resetAll() {
    _resetJobs();
    _session = null;
    _checkedEntries = null;
    _checkedSession = null;
    _close?.cancel();
    _open?.cancel();
    _close = null;
    _open = null;
    _mode = SubLineMode.original;
    _shown = SubLineMode.original;
    _progress = 0;
    notifyListeners();
  }

  // ── The reveal ─────────────────────────────────────────────────────────────

  void _apply(SubLineMode next) {
    _close?.cancel();
    _open?.cancel();
    _close = null;
    _open = null;
    _mode = next;

    // Close first. A transform folding away and another unfolding in overlap the
    // same gap for a few frames, and the reader sees two scripts where there
    // should be one.
    if (_shown != SubLineMode.original && _shown != next && _progress > 0) {
      _close = Timer.periodic(
        const Duration(milliseconds: 16),
        (timer) {
          _progress -= 16 / subLineCloseMs;
          if (_progress <= 0) {
            _progress = 0;
            timer.cancel();
            _close = null;
            _shown = SubLineMode.original;
            if (_mode != SubLineMode.original) _grow();
          }
          notifyListeners();
        },
      );
      notifyListeners();
      return;
    }

    if (_shown == next && _progress > 0) {
      // Already on screen: re-asking must not restart the unfold. But a fold
      // that was interrupted half way (the reader changed their mind) has left
      // the progress short of 1 and no timer to finish it, so carry on opening
      // from where it stopped.
      if (_progress < 1) {
        _grow(resume: true);
      } else {
        notifyListeners();
      }
      return;
    }

    if (next == SubLineMode.original) {
      _progress = 0;
      _shown = SubLineMode.original;
      notifyListeners();
      return;
    }
    _grow();
  }

  void _grow({bool resume = false}) {
    _shown = _mode;
    if (!resume) _progress = 0;
    var elapsed = (_progress * subLineOpenMs).round();
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
    for (final job in _jobs.values) {
      job.token?.cancel();
    }
    _close?.cancel();
    _open?.cancel();
    super.dispose();
  }
}
