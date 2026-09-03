import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/explore/explore_engine.dart';
import 'package:music_streaming_app/services/explore/explore_session.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart';

ExploreItem _item(String id, {String artist = 'A'}) {
  final valid = RegExp(r'^[a-z0-9]{11}$').hasMatch(id);
  return ExploreItem(
    track: Track(
      id: id,
      trackName: valid ? 'T $id' : id,
      artistName: artist,
      albumName: '',
      previewUrl: '',
      source: 'youtube',
    ),
    reason: CandidateReason.exploration,
    score: 1,
    source: 'test',
  );
}

void main() {
  group('ExploreSession dedupe', () {
    test('appendBatch marks shown; duplicate ids dropped', () {
      final s = ExploreSession(sessionId: 1, startedAt: DateTime.now());
      s.appendBatch([_item('aaa11111111'), _item('bbb11111111')]);
      s.appendBatch([_item('aaa11111111'), _item('ccc11111111')]);
      expect(s.items.map((i) => i.track.id).toList(),
          ['aaa11111111', 'bbb11111111', 'ccc11111111']);
    });

    test('cross-refill dedupe A B C A D B E → A B C D E', () {
      final s = ExploreSession(sessionId: 1, startedAt: DateTime.now());
      s.appendBatch(
          [_item('aaa11111111'), _item('bbb11111111'), _item('ccc11111111')]);
      s.appendBatch([
        _item('aaa11111111'),
        _item('ddd11111111'),
        _item('bbb11111111'),
        _item('eee11111111'),
      ]);
      expect(s.items.map((i) => i.track.id).toList(), [
        'aaa11111111',
        'bbb11111111',
        'ccc11111111',
        'ddd11111111',
        'eee11111111'
      ]);
    });

    test('same song-identity (title+artist) dedupes across ids', () {
      final s = ExploreSession(sessionId: 1, startedAt: DateTime.now());
      final v1 = _item('aaa11111111');
      final v2 = ExploreItem(
        track: Track(
          id: 'bbb22222222',
          trackName: v1.track.trackName,
          artistName: v1.track.artistName,
          albumName: '',
          previewUrl: '',
          source: 'youtube',
        ),
        reason: CandidateReason.exploration,
        score: 1,
        source: 'test',
      );
      s.appendBatch([v1, v2]);
      expect(s.items.length, 1);
    });

    test('artist run cap: breaks runs when other artists available', () {
      final s = ExploreSession(sessionId: 1, startedAt: DateTime.now());
      s.appendBatch([
        _item('aaa11111111', artist: 'Same'),
        _item('bbb11111111', artist: 'Same'),
        _item('ccc11111111', artist: 'Other'),
        _item('ddd11111111', artist: 'Same'),
      ]);
      final artists = s.items.map((i) => i.track.artistName).toList();
      var run = 1;
      for (var i = 1; i < artists.length; i++) {
        final r = artists[i] == artists[i - 1] ? run + 1 : 1;
        expect(r, lessThanOrEqualTo(ExploreSession.maxArtistRun));
        run = r;
      }
      expect(s.items.length, 4);
    });

    test('starvation escape: all-same-artist stream still fills', () {
      final s = ExploreSession(sessionId: 1, startedAt: DateTime.now());
      s.appendBatch([
        _item('aaa11111111', artist: 'Same'),
        _item('bbb11111111', artist: 'Same'),
        _item('ccc11111111', artist: 'Same'),
      ]);
      // Soft cap yields — better one artist than an empty stream.
      expect(s.items.length, 3);
      expect(s.items.last.track.id, 'ccc11111111');
    });

    test('deferred items rejoin after later batch dilutes artist', () {
      final s = ExploreSession(sessionId: 1, startedAt: DateTime.now());
      s.appendBatch([
        _item('aaa11111111', artist: 'Same'),
        _item('bbb11111111', artist: 'Other'),
        _item('ccc11111111', artist: 'Same'),
        _item('ddd11111111', artist: 'Same'),
      ]);
      expect(s.items.map((i) => i.track.id).toSet(),
          {'aaa11111111', 'bbb11111111', 'ccc11111111', 'ddd11111111'});
      final artists =
          s.items.map((i) => i.track.artistName).toList();
      var run = 1;
      for (var i = 1; i < artists.length; i++) {
        final r = artists[i] == artists[i - 1] ? run + 1 : 1;
        expect(r, lessThanOrEqualTo(ExploreSession.maxArtistRun));
        run = r;
      }
    });
  });

  group('ExploreSession navigation', () {
    test('remaining / needsRefill thresholds', () {
      final s = ExploreSession(sessionId: 1, startedAt: DateTime.now());
      s.appendBatch(
          List.generate(8, (i) => _item('id00000000$i'.padRight(11, '0'))));
      s.advanceTo(0);
      expect(s.remaining.length, 7);
      expect(s.needsRefill, isFalse);
      s.advanceTo(5);
      expect(s.remaining.length, 2);
      expect(s.needsRefill, isTrue);
    });

    test('advanceTo clamps and marks played', () {
      final s = ExploreSession(sessionId: 1, startedAt: DateTime.now());
      s.appendBatch([_item('aaa11111111'), _item('bbb11111111')]);
      s.advanceTo(0);
      expect(s.active?.track.id, 'aaa11111111');
      expect(s.playedItemIds, {'aaa11111111'});
      s.advanceTo(99);
      expect(s.currentIndex, 1);
      expect(s.playedItemIds, {'aaa11111111', 'bbb11111111'});
    });

    test('active null before advance', () {
      final s = ExploreSession(sessionId: 1, startedAt: DateTime.now());
      s.appendBatch([_item('aaa11111111')]);
      expect(s.active, isNull);
    });
  });
}
