import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart'
    show CandidateReason;
import 'package:music_streaming_app/services/recommendation/candidate_metadata.dart';
import 'package:music_streaming_app/services/recommendation/section_engines_v2.dart';
import 'package:music_streaming_app/services/recommendation/taste_profile.dart';

Track _t(String id, String title, String artist, {int? year}) => Track(
      id: id,
      trackName: title,
      artistName: artist,
      albumName: '',
      previewUrl: '',
      albumArt: 'https://example.com/$id.jpg',
      source: 'youtube',
    );

RichCandidate _release(
  String id,
  String title,
  String artist, {
  int? releaseYear,
  double? popularity,
  SourceTrust trust = SourceTrust.high,
}) =>
    RichCandidate(
      id: id,
      title: title,
      artists: [artist],
      source: 'new_release',
      releaseYear: releaseYear,
      chartRank: popularity == null ? null : ((1 - popularity) * 10).round(),
      chartSize: popularity == null ? null : 10,
      sourceTrust: trust,
    );

void main() {
  final now = DateTime.now();
  final thisYear = now.year;

  group('NewReleasesEngineV2 — validation (#41)', () {
    test('stale releases excluded, missing year from trusted source kept', () {
      final engine = NewReleasesEngineV2();
      final picks = engine.generate(
        releases: [
          _release('newr000001', 'New Hit', 'A', releaseYear: thisYear),
          _release('newr000002', 'Old Song', 'B', releaseYear: thisYear - 5),
          _release('newr000003', 'Unknown Year', 'C'),
        ],
        profile: TasteProfile.empty(),
        limit: 5,
      );
      final ids = picks.map((c) => c.trackId).toList();
      expect(ids.contains('newr000002'), isFalse); // obviously stale
      expect(ids.contains('newr000003'), isTrue); // trusted source, no year
      expect(ids.contains('newr000001'), isTrue);
    });
  });

  group('NewReleasesEngineV2 — freshness bands (#44)', () {
    test('veryRecent > recent > aging ordering within equal relevance', () {
      final engine = NewReleasesEngineV2();
      final picks = engine.generate(
        releases: [
          _release('newr000001', 'Very recent', 'A',
              releaseYear: thisYear, popularity: 0.5),
          _release('newr000002', 'Recent', 'B',
              releaseYear: thisYear - 1, popularity: 0.5),
          _release('newr000003', 'Aging', 'C',
              releaseYear: thisYear - 2, popularity: 0.5),
        ],
        profile: TasteProfile.empty(),
        limit: 3,
      );
      expect(picks.map((c) => c.trackId),
          ['newr000001', 'newr000002', 'newr000003']);
    });
  });

  group('NewReleasesEngineV2 — affinity ranking (#42)', () {
    test('favorite-artist release ranks above equal-freshness unknown', () {
      final engine = NewReleasesEngineV2();
      final profile = TasteProfile.build(events: [
        for (var i = 0; i < 10; i++)
          TrackEvent(
            trackId: 'weeknd00$i',
            artistName: 'The Weeknd',
            completionRate: 0.9,
            playCount: 4,
            lastPlayed: now,
          ),
      ]);
      final picks = engine.generate(
        releases: [
          _release('newr000001', 'Unknown New', 'Stranger',
              releaseYear: thisYear, popularity: 0.5),
          _release('newr000002', 'Weeknd New Single', 'The Weeknd',
              releaseYear: thisYear, popularity: 0.5),
        ],
        profile: profile,
        limit: 2,
      );
      expect(picks.first.trackId, 'newr000002');
      expect(picks.first.reason, CandidateReason.newReleaseArtist);
    });

    test('diversity: soft artist cap (#45)', () {
      final engine = NewReleasesEngineV2();
      final picks = engine.generate(
        releases: [
          for (var i = 1; i <= 5; i++)
            _release('newr00000$i', 'Weeknd Release $i', 'The Weeknd',
                releaseYear: thisYear, popularity: 0.9),
          _release('newr000006', 'Other Release', 'Other Artist',
              releaseYear: thisYear, popularity: 0.8),
        ],
        profile: TasteProfile.empty(),
        limit: 4,
      );
      final weekndCount =
          picks.where((c) => c.track.artistName == 'The Weeknd').length;
      expect(weekndCount, lessThanOrEqualTo(3));
      expect(picks.any((c) => c.track.artistName == 'Other Artist'), isTrue);
    });
  });

  group('TrendingEngineV2 — popularity only (#47/#48/#77)', () {
    test('chart order dominates; personal favorite does not become trending',
        () {
      final engine = TrendingEngineV2();
      final picks = engine.generate(
        regionalChart: [
          _t('trendreg001', 'Regional #1', 'Regional Superstar'),
          _t('trendreg002', 'Regional #2', 'Star B'),
        ],
        globalChart: [
          _t('trendglob01', 'Global #1', 'Global Superstar'),
        ],
        userFavorite: [_t('trendfav001', 'Obscure Fav', 'Nobody')],
        limit: 3,
      );
      expect(picks.map((c) => c.trackId),
          ['trendreg001', 'trendglob01', 'trendreg002']);
      expect(picks.any((c) => c.trackId == 'trendfav01'), isFalse);
    });

    test('regional above global at equal rank position (#49/#50)', () {
      final engine = TrendingEngineV2();
      final picks = engine.generate(
        regionalChart: [_t('trendreg001', 'R1', 'A')],
        globalChart: [_t('trendglob01', 'G1', 'B')],
        limit: 2,
      );
      expect(picks.first.trackId, 'trendreg001');
    });
  });
}
