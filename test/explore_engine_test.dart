import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/explore/explore_engine.dart';
import 'package:music_streaming_app/services/explore/explore_policy.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart';
import 'package:music_streaming_app/services/recommendation/ranker.dart';
import 'package:music_streaming_app/services/recommendation/taste_profile.dart';

Track _t(String id,
    {String? artist, String? album, String? genre}) {
  final valid = RegExp(r'^[a-z0-9]{11}$').hasMatch(id);
  return Track(
    id: id,
    trackName: valid ? 'Song $id' : (id.isEmpty ? '' : 'Song $id'),
    artistName: artist ?? 'Artist $id',
    albumName: album ?? 'Album $id',
    previewUrl: '',
    source: 'youtube',
    albumArt: 'https://img/$id.jpg',
    durationMs: 180000,
    genre: genre,
  );
}

TrackEvent _event(String id, String artist,
        {double completion = 0.9, int plays = 4}) =>
    TrackEvent(
      trackId: id,
      artistName: artist,
      completionRate: completion,
      playCount: plays,
      replayCount: 1,
      lastPlayed: DateTime.now(),
    );

void main() {
  group('ExploreEngine pool validation', () {
    test('filters invalid ids and dedupes first-wins across pools', () {
      final engine = ExploreEngine();
      final bad = _t('MPREb1234567');
      final short = _t('abc');
      final shared = _t('sharedtrack', artist: 'Shared');
      final unique = _t('uniquetrack', artist: 'Unique');
      final items = engine.generateSync(
        profile: TasteProfile.build(events: const []),
        sources: ExploreSources(
          seedRelated: [bad, shared],
          quickPicks: [shared, short],
          regionalChart: [unique],
        ),
        limit: 10,
        generation: 0,
      );
      final ids = items.map((i) => i.track.id).toSet();
      expect(ids, containsAll(['sharedtrack', 'uniquetrack']));
      expect(items.any((i) => i.track.id == bad.id), isFalse);
      expect(items.any((i) => i.track.id == short.id), isFalse);
      // shared appears once, from the higher-priority pool.
      expect(items.where((i) => i.track.id == 'sharedtrack').length, 1);
      expect(items.firstWhere((i) => i.track.id == 'sharedtrack').source,
          'native_home');
    });

    test('exclude set removes already-shown ids', () {
      final engine = ExploreEngine();
      final a = _t('aaa11111111');
      final b = _t('bbb11111111');
      final items = engine.generateSync(
        profile: TasteProfile.build(events: const []),
        sources: ExploreSources(
            regionalChart: [a, b], globalChart: [a]),
        exclude: {'aaa11111111'},
        limit: 10,
        generation: 0,
      );
      expect(items.map((i) => i.track.id), ['bbb11111111']);
    });

    test('filters out incompatible foreign scripts when user profile has no history', () {
      final engine = ExploreEngine();
      final englishTrack = _t('eng11111111', artist: 'Dua Lipa');
      final hindiTrack = Track(
        id: 'hin11111111',
        trackName: 'Chikni Chameli',
        artistName: 'Shreya Ghoshal',
        albumName: '',
        previewUrl: '',
        source: 'youtube',
      );
      final cyrillicTrack = Track(
        id: 'cyr11111111',
        trackName: 'Инстасамка',
        artistName: 'INSTASAMKA',
        albumName: '',
        previewUrl: '',
        source: 'youtube',
      );
      final thaiTrack = Track(
        id: 'tha11111111',
        trackName: 'เพลงรัก',
        artistName: 'ศิลปินไทย',
        albumName: '',
        previewUrl: '',
        source: 'youtube',
      );
      final hangulTrack = Track(
        id: 'kor11111111',
        trackName: '르세라핌',
        artistName: 'LE SSERAFIM',
        albumName: '',
        previewUrl: '',
        source: 'youtube',
      );

      final items = engine.generateSync(
        profile: TasteProfile.build(events: const []),
        sources: ExploreSources(
          regionalChart: [englishTrack, hindiTrack, cyrillicTrack, thaiTrack, hangulTrack],
        ),
        limit: 10,
        generation: 0,
      );

      final ids = items.map((i) => i.track.id).toList();
      expect(ids, containsAll(['eng11111111', 'hin11111111', 'kor11111111']));
      expect(ids, isNot(contains('cyr11111111')));
      expect(ids, isNot(contains('tha11111111')));
    });

    test('preserves foreign scripts when user has explicit profile affinity with that script', () {
      final engine = ExploreEngine();
      final cyrillicTrack = Track(
        id: 'cyr11111111',
        trackName: 'Песня года',
        artistName: 'Виктор Цой',
        albumName: '',
        previewUrl: '',
        source: 'youtube',
      );
      final profile = TasteProfile.build(
        events: [
          TrackEvent(
            trackId: 'old11111111',
            artistName: 'Виктор Цой',
            completionRate: 1.0,
            playCount: 5,
            lastPlayed: DateTime.now(),
          ),
        ],
      );

      final items = engine.generateSync(
        profile: profile,
        sources: ExploreSources(
          regionalChart: [cyrillicTrack],
        ),
        limit: 10,
        generation: 0,
      );

      expect(items.map((i) => i.track.id), contains('cyr11111111'));
    });
  });

  group('ExploreEngine ranking behavior', () {
    test('cold profile: chart popularity dominates unproven pools', () {
      final engine = ExploreEngine();
      final chartTop = _t('charttop111', artist: 'Chart A');
      final qpUnknown = _t('qpunknown11', artist: 'Unknown B');
      final items = engine.generateSync(
        profile: TasteProfile.build(events: const []),
        sources: ExploreSources(
            quickPicks: [qpUnknown], regionalChart: [chartTop]),
        limit: 2,
        generation: 0,
      );
      expect(items.first.track.id, 'charttop111');
      expect(items.first.reason, CandidateReason.regionalTrending);
      // Chart rank propagates as popularity + editorial evidence.
      expect(items.first.score, greaterThan(items.last.score));
    });

    test('seed anchor: seed track wins ties via personal floor', () {
      final engine = ExploreEngine();
      final seed = _t('seedtrack11', artist: 'Seed Artist');
      final other = _t('othertrack1', artist: 'Seed Artist');
      final items = engine.generateSync(
        profile: TasteProfile.build(events: const []),
        sources: ExploreSources(quickPicks: [other, seed]),
        seed: seed,
        limit: 2,
        generation: 0,
      );
      expect(items.first.track.id, 'seedtrack11');
    });

    test('warm profile lifts seed-artist candidates from related pool', () {
      final engine = ExploreEngine();
      final events = List.generate(
          12, (i) => _event('ev0000000$i', 'Beloved Artist'));
      final profile = TasteProfile.build(
          events: events, favoriteArtists: const ['Beloved Artist']);
      final beloved = _t('beloved0001', artist: 'Beloved Artist');
      final stranger = _t('stranger001', artist: 'Stranger X');
      final items = engine.generateSync(
        profile: profile,
        sources: ExploreSources(seedRelated: [stranger, beloved]),
        seed: _t('seedwarm000', artist: 'Beloved Artist'),
        limit: 2,
        generation: 0,
      );
      // Seed sits on page 0 as the anchor ("you are here") — related
      // artist track should lead the DISCOVERY stream after it.
      expect(items.first.track.id, 'seedwarm000');
      expect(items[1].track.id, 'beloved0001');
    });

    test('global chart reason maps per pool', () {
      final engine = ExploreEngine();
      final g = _t('globaltrk11', artist: 'G');
      final r = _t('regional11', artist: 'R');
      final items = engine.generateSync(
        profile: TasteProfile.build(events: const []),
        sources: ExploreSources(globalChart: [g], regionalChart: [r]),
        limit: 5,
        generation: 0,
      );
      expect(
          items.firstWhere((i) => i.track.id == 'globaltrk11').reason,
          CandidateReason.globalTrending);
    });

    test('deterministic: identical inputs produce identical order', () {
      final engine = ExploreEngine();
      List<String> run() {
        final items = engine.generateSync(
          profile: TasteProfile.build(events: const []),
          sources: ExploreSources(
            regionalChart: List.generate(
                6, (i) => _t('chart0000$i'.padRight(11, '0'), artist: 'C$i')),
            newReleases: List.generate(
                4, (i) => _t('newrel000$i'.padRight(11, '0'), artist: 'N$i')),
          ),
          limit: 8,
          generation: 0,
        );
        return items.map((i) => i.track.id).toList();
      }

      expect(run(), equals(run()));
    });
  });

  group('ExplorePolicy', () {
    test('reason map covers pool sources', () {
      expect(ExplorePolicy.reasonFor('native_home'),
          CandidateReason.nativeRecommendation);
      expect(ExplorePolicy.reasonFor('local_favorites'),
          CandidateReason.favoriteArtist);
      expect(ExplorePolicy.reasonFor('local_history'),
          CandidateReason.recentlyPlayed);
      expect(ExplorePolicy.reasonFor('new_release'),
          CandidateReason.newReleaseArtist);
      expect(ExplorePolicy.reasonFor('mystery_source'),
          CandidateReason.exploration);
    });

    test('discovery tilt caps personal blend below quick picks warm', () {
      final events = List.generate(
          40, (i) => _event('ev0000000$i', 'Artist $i'));
      final hot = TasteProfile.build(events: events);
      final exploreConfig = ExplorePolicy.ranking(hot);
      final qpConfig = RankingConfig.forConfidence(
          hot.personalizationConfidence);
      expect(exploreConfig.weights['personalAffinity']!,
          lessThan(qpConfig.weights['personalAffinity']!));
      expect(exploreConfig.weights['popularity']!,
          greaterThan(qpConfig.weights['popularity']!));
      // Cold start: popularity-heavy, minimal personal.
      final coldConfig = ExplorePolicy.ranking(TasteProfile.build(events: const []));
      expect(coldConfig.weights['popularity']!, greaterThan(0.25));
    });
  });
}
