import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/explore/explore_controller.dart';
import 'package:music_streaming_app/services/explore/explore_engine.dart';
import 'package:music_streaming_app/services/explore/explore_session.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart';
import 'package:music_streaming_app/services/recommendation/taste_profile.dart';

Track _t(String id, {String artist = 'A'}) => Track(
      id: id,
      trackName: 'T $id',
      artistName: artist,
      albumName: '',
      previewUrl: '',
      source: 'youtube',
    );

ExploreItem _item(Track t) => ExploreItem(
      track: t,
      reason: CandidateReason.exploration,
      score: 1,
      source: 'test',
    );

class Harness {
  Harness({this.batches, this.delay, String? currentTrackId})
      : played = [],
        fetchCount = 0,
        feedback = [],
        autoplayCalls = [],
        currentTrackId = currentTrackId;

  final String? currentTrackId;
  final List<List<ExploreItem>>? batches;
  final Duration? delay;
  final List<Track> played;
  int fetchCount;
  final List<(String, bool)> feedback;
  final List<bool> autoplayCalls;

  bool Function(String) get isCurrentTrack => (id) =>
      currentTrackId != null && id == currentTrackId;

  ExploreController build({ExploreSession? existing, bool autoplay = true}) {
    var call = 0;
    return ExploreController(
      engine: ExploreEngine(),
      fetchSources: (anchor) async {
        fetchCount++;
        if (delay != null) await Future.delayed(delay!);
        final list = batches ?? [
          [_item(_t('aaa11111111')), _item(_t('bbb11111111')), _item(_t('ccc11111111'))],
          [_item(_t('ddd11111111')), _item(_t('eee11111111')), _item(_t('fff11111111'))],
          [_item(_t('ggg11111111')), _item(_t('hhh11111111')), _item(_t('iii11111111'))],
        ];
        return _sourcesFor(list[call.clamp(0, list.length - 1)]);
      },
      play: (track, upcoming) async {
        played.add(track);
        if (delay != null) await Future.delayed(delay!);
      },
      profileProvider: () => TasteProfile.build(events: const []),
      recordSwipeOutcome: (artist, {required wasAccepted}) =>
          feedback.add((artist, wasAccepted)),
      isCurrentTrack: isCurrentTrack,
      autoplayEnabled: autoplay,
      onAutoplayChanged: autoplayCalls.add,
      existingSession: existing,
    );
  }

  ExploreSources _sourcesFor(List<ExploreItem> items) => ExploreSources(
        regionalChart: items.map((i) => i.track).toList(),
      );
}

void main() {
  group('ExploreController autoplay on settle', () {
    test('start autoplays page 0; settle advances and plays', () async {
      final h = Harness();
      final c = h.build();
      await c.start();
      expect(h.played.map((t) => t.id), ['aaa11111111']);
      await c.settle(1);
      expect(h.played.map((t) => t.id), ['aaa11111111', 'bbb11111111']);
    });

    test('same-index settle is a no-op (no restart)', () async {
      final h = Harness();
      final c = h.build();
      await c.start();
      await c.settle(0);
      expect(h.played.length, 1);
    });

    test('rapid 0→1→2: only track 2 becomes active', () async {
      final h = Harness(delay: Duration(milliseconds: 30));
      final c = h.build();
      await c.start();
      h.played.clear();
      final f1 = c.settle(1);
      final f2 = c.settle(2);
      await Future.wait([f1, f2]);
      await Future.delayed(Duration(milliseconds: 80));
      // Track 1 may have started (queued), but 2 wins the generation race.
      expect(h.played.last.id, 'ccc11111111');
      expect(h.played.where((t) => t.id == 'bbb11111111').length,
          lessThanOrEqualTo(1));
    });

    test('superseded settle failure does not set error or disrupt state', () async {
      final controller = ExploreController(
        engine: ExploreEngine(),
        fetchSources: (anchor) async => ExploreSources(regionalChart: [
          _t('tra11111111'),
          _t('trb11111111'),
          _t('trc11111111'),
        ]),
        play: (track, upcoming) async {
          if (track.id == 'trb11111111') {
            await Future.delayed(Duration(milliseconds: 20));
            throw Exception('Resolution failed for trb11111111');
          }
        },
        profileProvider: () => TasteProfile.build(events: const []),
        recordSwipeOutcome: (_, {required wasAccepted}) {},
        isCurrentTrack: (_) => false,
        autoplayEnabled: true,
        onAutoplayChanged: (_) {},
      );
      await controller.start();
      // Rapid swipe: settle(1) then immediately settle(2)
      final f1 = controller.settle(1);
      final f2 = controller.settle(2);
      await Future.wait([f1, f2]);
      // Controller should NOT report error from trb11111111 since it was superseded by trc11111111
      expect(controller.error, isNull);
      expect(controller.session!.currentIndex, 2);
    });

    test('autoplay off: swipe advances, no play calls', () async {
      final h = Harness();
      final c = h.build(autoplay: false);
      await c.start();
      expect(h.played, isEmpty);
      await c.settle(0);
      expect(c.session!.currentIndex, 0);
      expect(h.played, isEmpty);
    });

    test('playGuard: current track never restarts', () async {
      final h = Harness(currentTrackId: 'aaa11111111');
      final c = h.build();
      await c.start();
      // Page 0 is the active provider track — skip the play call.
      expect(h.played, isEmpty);
      expect(c.session!.currentIndex, 0);
    });

    test('toggleAutoplay persists via callback and flips behavior',
        () async {
      final h = Harness();
      final c = h.build();
      await c.start();
      expect(h.autoplayCalls, isEmpty);
      c.toggleAutoplay();
      expect(c.autoplayEnabled, isFalse);
      expect(h.autoplayCalls, [false]);
      h.played.clear();
      await c.settle(1);
      expect(h.played, isEmpty);
    });
  });

  group('ExploreController refill + dedupe', () {
    test('refill triggers when remaining ≤ threshold; batches dedupe',
        () async {
      final h = Harness();
      final c = h.build();
      await c.start();
      // Batch1 gave 2 items; settle to the last → refill fetches batch2.
      await c.settle(1);
      expect(h.fetchCount, greaterThanOrEqualTo(2));
      final ids = c.session!.items.map((i) => i.track.id).toSet();
      expect(ids.length, c.session!.items.length);
    });

    test('two empty refill batches → exhausted, fetch stops', () async {
      final h = Harness(batches: [
        [_item(_t('aaa11111111'))],
        const [],
        const [],
      ]);
      final c = h.build();
      await c.start();
      expect(c.exhausted, isFalse);
      final before = h.fetchCount; // start + its settle(0) refill
      await c.settle(0);
      await c.maybeRefillForTest();
      await c.maybeRefillForTest();
      expect(c.exhausted, isTrue);
      // One more empty (streak 2) → exhausted; guards block further fetch.
      expect(h.fetchCount, before + 1);
    });

    test('restore: existing session not refetched', () async {
      final s = ExploreSession(sessionId: 9, startedAt: DateTime.now());
      s.appendBatch([_item(_t('zzz11111111'))]);
      s.advanceTo(0);
      final h = Harness();
      final c = h.build(existing: s);
      await c.start();
      expect(h.fetchCount, 0);
      expect(c.session!.sessionId, 9);
      expect(c.activeTrack!.id, 'zzz11111111');
    });

    test('refresh: new session anchored on active track', () async {
      final h = Harness();
      final c = h.build();
      await c.start();
      final oldId = c.session!.sessionId;
      await c.refresh();
      expect(c.session!.sessionId, isNot(oldId));
      expect(h.fetchCount, greaterThanOrEqualTo(3));
    });
  });

  group('ExploreController feedback', () {
    test('quick swipe-away = negative signal; long dwell neutral+', () async {
      final h = Harness();
      final c = h.build();
      await c.start();
      c.debugForceDwell(const Duration(seconds: 2));
      await c.settle(1);
      expect(h.feedback.last.$2, isFalse);
      c.debugForceDwell(const Duration(seconds: 12));
      await c.settle(2);
      expect(h.feedback.last.$2, isTrue);
    });

    test('dislikeCurrent records negative and advances', () async {
      final h = Harness();
      final c = h.build();
      await c.start();
      c.debugForceDwell(const Duration(seconds: 12));
      await c.settle(1);
      await c.dislikeCurrent();
      expect(h.feedback.last.$2, isFalse);
      expect(c.session!.currentIndex, 2);
    });
  });
}
