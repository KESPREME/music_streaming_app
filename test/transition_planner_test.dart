import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/transition/track_analysis.dart';
import 'package:music_streaming_app/services/transition/transition_planner.dart';
import 'package:music_streaming_app/services/transition/transition_settings.dart';

/// THE PLANNER THIS FILE PINS.
///
/// How one song joins the next is decided by a pure function, so every rule -
/// where the incoming song starts, how long they overlap, when nothing happens
/// at all - is a table test rather than something to be heard on a phone.

PlanRequest _req({
  int durationMs = 200000,
  int nextDurationMs = 200000,
  TransitionStyle style = TransitionStyle.crossfade,
  int crossfadeMs = 6000,
  bool crossfadeAlbums = false,
  bool matchTempo = false,
  bool albumSequential = false,
  TrackAnalysis? outgoing,
  TrackAnalysis? incoming,
}) =>
    PlanRequest(
      durationMs: durationMs,
      nextDurationMs: nextDurationMs,
      style: style,
      crossfadeMs: crossfadeMs,
      crossfadeAlbums: crossfadeAlbums,
      matchTempo: matchTempo,
      albumSequential: albumSequential,
      outgoing: outgoing,
      incoming: incoming,
    );

/// Beats every [beatMs] from [firstBeatMs]; a bar line every fourth.
TrackAnalysis _analysis(
  String id, {
  int durationMs = 200000,
  int audibleStartMs = 0,
  int outroStartMs = 0,
  int contentEndMs = 0,
  double bpm = 0,
  double confidence = 0,
  int firstBeatMs = 0,
}) {
  final beats = <int>[];
  final downbeats = <int>[];
  if (bpm > 0) {
    final beatMs = 60000.0 / bpm;
    var i = 0;
    for (var t = firstBeatMs.toDouble(); t < durationMs; t += beatMs, i++) {
      beats.add(t.round());
      if (i % 4 == 0) downbeats.add(t.round());
    }
  }
  return TrackAnalysis(
    trackId: id,
    durationMs: durationMs,
    audibleStartMs: audibleStartMs,
    outroStartMs: outroStartMs,
    contentEndMs: contentEndMs,
    bpm: bpm,
    beatConfidence: confidence,
    beatsMs: beats,
    downbeatsMs: downbeats,
  );
}

void main() {
  group('crossfade', () {
    test('ends 250ms before the file does, so the player never reads on', () {
      final p = TransitionPlanner.plan(_req());
      expect(p.kind, PlanKind.crossfade);
      expect(p.endAtMs, 199750);
      expect(p.startAtMs, 193750);
      expect(p.fadeMs, 6000);
      expect(p.cueMs, 0);
      expect(p.incomingRate, 1.0);
    });

    test('a song under six seconds is left alone', () {
      expect(TransitionPlanner.plan(_req(durationMs: 5000)).isNone, isTrue);
    });

    test('a fade never swallows more than a third of the song', () {
      final p = TransitionPlanner.plan(_req(durationMs: 12000, crossfadeMs: 12000));
      expect(p.fadeMs, 4000);
    });

    test('albums stay gapless unless the listener asks otherwise', () {
      final off = TransitionPlanner.plan(_req(albumSequential: true));
      expect(off.isNone, isTrue);
      expect(off.reason, 'album-gapless');

      final on =
          TransitionPlanner.plan(_req(albumSequential: true, crossfadeAlbums: true));
      expect(on.kind, PlanKind.crossfade);
    });
  });

  group('automix without evidence', () {
    test('an unanalysed pair gets a clean crossfade, not nothing', () {
      final p = TransitionPlanner.plan(_req(style: TransitionStyle.automix));
      expect(p.kind, PlanKind.crossfade);
      expect(p.reason, 'automix-fallback');
    });

    test('an analysis of a different cut of the song is not used', () {
      final p = TransitionPlanner.plan(_req(
        style: TransitionStyle.automix,
        outgoing: _analysis('a', durationMs: 195000, outroStartMs: 185000, contentEndMs: 192000),
        incoming: _analysis('b'),
      ));
      expect(p.reason, 'automix-fallback');
    });

    test('an implausible "the music ends here" distrusts the whole analysis',
        () {
      final p = TransitionPlanner.plan(_req(
        style: TransitionStyle.automix,
        outgoing: _analysis('a', contentEndMs: 50000),
        incoming: _analysis('b'),
      ));
      expect(p.reason, 'automix-fallback');
    });
  });

  group('smart (AutoMix with analysis)', () {
    test('the fade sits over the song\'s own outro', () {
      final p = TransitionPlanner.plan(_req(
        style: TransitionStyle.automix,
        outgoing: _analysis('a', outroStartMs: 190000, contentEndMs: 197000),
        incoming: _analysis('b', audibleStartMs: 1200),
      ));
      expect(p.kind, PlanKind.smart);
      expect(p.endAtMs, 197000, reason: 'dead air after the music is skipped');
      expect(p.startAtMs, 190000);
      expect(p.cueMs, 1200, reason: 'the incoming song starts at its first sound');
    });

    test('a song that just stops uses the listener\'s length', () {
      final p = TransitionPlanner.plan(_req(
        style: TransitionStyle.automix,
        crossfadeMs: 5000,
        outgoing: _analysis('a'),
        incoming: _analysis('b'),
      ));
      expect(p.kind, PlanKind.smart);
      expect(p.fadeMs, 5000);
      expect(p.endAtMs, 199750);
    });

    test('a very long outro is capped at ten seconds', () {
      final p = TransitionPlanner.plan(_req(
        style: TransitionStyle.automix,
        outgoing: _analysis('a', outroStartMs: 170000, contentEndMs: 199000),
        incoming: _analysis('b'),
      ));
      expect(p.fadeMs, 10000);
    });

    test('silence at the head of the incoming song is skipped, within reason',
        () {
      final p = TransitionPlanner.plan(_req(
        style: TransitionStyle.automix,
        outgoing: _analysis('a'),
        incoming: _analysis('b', audibleStartMs: 20000),
      ));
      expect(p.cueMs, 8000, reason: 'a long silence may be deliberate');
    });

    test('never starts in the first third of the song', () {
      final p = TransitionPlanner.plan(_req(
        style: TransitionStyle.automix,
        durationMs: 20000,
        crossfadeMs: 10000,
        outgoing: _analysis('a', durationMs: 20000, outroStartMs: 1000, contentEndMs: 19000),
        incoming: _analysis('b'),
      ));
      expect(p.startAtMs, greaterThanOrEqualTo(6000));
    });
  });

  group('beat matching', () {
    TrackAnalysis out({double conf = 0.9, double bpm = 120}) => _analysis('a',
        outroStartMs: 190000, contentEndMs: 197000, bpm: bpm, confidence: conf);
    TrackAnalysis inc({double conf = 0.9, double bpm = 121}) => _analysis('b',
        audibleStartMs: 1200, bpm: bpm, confidence: conf, firstBeatMs: 1000);

    PlanRequest request({
      bool matchTempo = true,
      TrackAnalysis? o,
      TrackAnalysis? i,
    }) =>
        _req(
          style: TransitionStyle.automix,
          matchTempo: matchTempo,
          outgoing: o ?? out(),
          incoming: i ?? inc(),
        );

    test('both songs enter on a bar line and the tempo is matched', () {
      final p = TransitionPlanner.plan(request());
      expect(p.kind, PlanKind.beatmatched);
      expect(p.reason, 'beats-matched');
      expect(p.startAtMs % 2000, 0, reason: 'a bar line of the 120 BPM song');
      expect(p.fadeMs % 2000, 0, reason: 'a whole number of bars');
      expect(p.endAtMs, lessThanOrEqualTo(197000), reason: 'inside the music');
      expect((p.cueMs - 1000) % (4 * 60000 / 121).round(), lessThan(5),
          reason: 'a bar line of the incoming song');
      expect(p.cueMs, greaterThanOrEqualTo(1200));
      expect(p.incomingRate, closeTo(120 / 121, 1e-4));
    });

    test('without permission to stretch, tempos must already agree', () {
      final close = TransitionPlanner.plan(request(matchTempo: false));
      expect(close.kind, PlanKind.beatmatched);
      expect(close.incomingRate, 1.0);
      expect(close.reason, 'beats-aligned');

      final apart = TransitionPlanner.plan(request(matchTempo: false, i: inc(bpm: 124)));
      expect(apart.kind, PlanKind.smart,
          reason: 'aligned bars of two different tempos drift apart in seconds');
    });

    test('tempos more than four percent apart are not stretched together', () {
      final p = TransitionPlanner.plan(request(i: inc(bpm: 130)));
      expect(p.kind, PlanKind.smart);
      expect(p.incomingRate, 1.0);
    });

    test('half and double time count as the same tempo', () {
      final p = TransitionPlanner.plan(request(i: inc(bpm: 60.5)));
      expect(p.kind, PlanKind.beatmatched);
      expect(p.incomingRate, closeTo(120 / 121, 1e-4));
    });

    test('a beat grid that is not trusted is not acted on', () {
      expect(TransitionPlanner.plan(request(o: out(conf: 0.4))).kind, PlanKind.smart);
      expect(TransitionPlanner.plan(request(i: inc(conf: 0.4))).kind, PlanKind.smart);
    });

    test('alignOctave folds toward the outgoing tempo', () {
      expect(TransitionPlanner.alignTempoOctave(126, 63), 126);
      expect(TransitionPlanner.alignTempoOctave(63, 126), 63);
      expect(TransitionPlanner.alignTempoOctave(120, 100), 100);
    });
  });
}
