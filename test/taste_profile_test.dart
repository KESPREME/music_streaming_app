import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/recommendation/taste_profile.dart';

TrackEvent _event(
  String id, {
  String artist = 'A',
  String? genre,
  double completion = 0.9,
  int plays = 3,
  int skips = 0,
  int replays = 0,
  DateTime? lastPlayed,
}) =>
    TrackEvent(
      trackId: id,
      artistName: artist,
      genre: genre,
      completionRate: completion,
      playCount: plays,
      skipCount: skips,
      replayCount: replays,
      likeCount: 0,
      lastPlayed: lastPlayed ?? DateTime.now(),
    );

void main() {
  final now = DateTime.now();

  group('TasteProfile recency decay (#10)', () {
    test('recent play outweighs old play for same artist', () {
      final p = TasteProfile.build(events: [
        _event('songA00001',
            artist: 'Old Artist',
            lastPlayed: now.subtract(const Duration(days: 90))),
        _event('songB00002',
            artist: 'New Artist',
            lastPlayed: now.subtract(const Duration(days: 2))),
      ]);
      expect(p.artistAffinity('New Artist'),
          greaterThan(p.artistAffinity('Old Artist')));
    });

    test('long-term favorite is NOT erased by decay (#10)', () {
      final p = TasteProfile.build(events: [
        for (var i = 0; i < 30; i++)
          _event('hist00000$i',
              artist: 'Weeknd',
              lastPlayed: now.subtract(Duration(days: 40 + i))),
        _event('other00001',
            artist: 'Stranger',
            lastPlayed: now.subtract(const Duration(days: 1))),
      ]);
      // 30 strong historical plays still beat one recent play of a
      // stranger — long-term + recent coexist.
      expect(p.artistAffinity('Weeknd'),
          greaterThan(p.artistAffinity('Stranger')));
      expect(p.recentArtistKeys.contains('stranger'), isTrue);
      expect(p.recentArtistKeys.contains('weeknd'), isFalse);
    });
  });

  group('TasteProfile confidence (#28/#57/#58)', () {
    test('sparse history → low personalization confidence (#96)', () {
      final p = TasteProfile.build(events: [
        _event('sparse0001', artist: 'X'),
        _event('sparse0002', artist: 'Y'),
      ]);
      expect(p.personalizationConfidence, lessThan(0.2));
    });

    test('rich diverse history → high confidence (#97)', () {
      final p = TasteProfile.build(events: [
        for (var i = 0; i < 60; i++)
          _event('rich00000$i', artist: 'Artist ${i % 12}', genre: 'pop'),
      ]);
      expect(p.personalizationConfidence, greaterThan(0.7));
    });

    test('one play is a tiny signal, 3+ strong plays meaningful (#58)', () {
      final one = TasteProfile.build(events: [
        _event('oneplay001', artist: 'X', plays: 1),
      ]);
      final three = TasteProfile.build(events: [
        _event('threeplay1', artist: 'X', plays: 3),
        _event('threeplay2', artist: 'X', plays: 3),
        _event('threeplay3', artist: 'X', plays: 3),
      ]);
      expect(three.artistAffinity('X'), greaterThan(one.artistAffinity('X')));
      expect(one.personalizationConfidence, lessThan(0.15));
    });
  });

  group('TasteProfile aggregations', () {
    test('topArtists/topGenres ordered by decayed weight, deterministic', () {
      final p = TasteProfile.build(events: [
        _event('agg0000001', artist: 'Weeknd', genre: 'Pop'),
        _event('agg0000002', artist: 'Weeknd', genre: 'Pop'),
        _event('agg0000003', artist: 'Weeknd', genre: 'Pop'),
        _event('agg0000004', artist: 'Kendrick', genre: 'Hip-Hop'),
      ]);
      expect(p.topArtists(limit: 2), ['Weeknd', 'Kendrick']);
      expect(p.topGenres(limit: 2), ['pop', 'hip-hop']);
    });

    test('artist affinity case-insensitive', () {
      final p = TasteProfile.build(events: [
        _event('case000001', artist: 'The Weeknd'),
      ]);
      expect(p.artistAffinity('the weeknd'), greaterThan(0));
      expect(p.artistAffinity('THE WEEKND'), greaterThan(0));
    });

    test('skip-heavy track has near-zero track affinity (#59)', () {
      final p = TasteProfile.build(events: [
        _event('skipped001', artist: 'X', completion: 0.1, skips: 4, plays: 5),
      ]);
      expect(p.trackAffinity('skipped001'), lessThan(0.2));
    });

    test('favorites boost artist strongly (#60)', () {
      final base = TasteProfile.build(events: [
        _event('favbase001', artist: 'X'),
      ]);
      final boosted = TasteProfile.build(events: [
        _event('favbase001', artist: 'X'),
      ], favoriteArtists: [
        'X'
      ]);
      expect(
          boosted.artistAffinity('X'), greaterThan(base.artistAffinity('X')));
    });

    test('profileVersion grows with event volume (#67)', () {
      final small = TasteProfile.build(events: [_event('v00000001')]);
      final big = TasteProfile.build(events: [
        for (var i = 0; i < 40; i++) _event('v0000000$i'),
      ]);
      expect(big.profileVersion, greaterThan(small.profileVersion));
    });
  });
}

// TEMP DEBUG
