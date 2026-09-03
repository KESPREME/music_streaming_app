import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart'
    show CandidateReason;
import 'package:music_streaming_app/services/recommendation/candidate_metadata.dart';
import 'package:music_streaming_app/services/recommendation/quick_picks_engine.dart';
import 'package:music_streaming_app/services/recommendation/ranker.dart';
import 'package:music_streaming_app/services/recommendation/taste_profile.dart';

Track _t(String id, String title, String artist, {String? genre}) => Track(
      id: id,
      trackName: title,
      artistName: artist,
      albumName: '',
      previewUrl: '',
      albumArt: 'https://example.com/$id.jpg',
      source: 'youtube',
      genre: genre,
    );

TrackEvent _ev(String id,
    {String artist = 'A',
    String? genre,
    double completion = 0.9,
    int plays = 4,
    DateTime? lastPlayed}) {
  return TrackEvent(
    trackId: id,
    artistName: artist,
    genre: genre,
    completionRate: completion,
    playCount: plays,
    lastPlayed: lastPlayed ?? DateTime.now(),
  );
}

/// Spec #94 golden profile: Weeknd favorite, Kendrick/Tame Impala plays,
/// pop/hip-hop/alternative genres, English, India region.
TasteProfile _goldenProfile() => TasteProfile.build(
      events: [
        for (var i = 0; i < 8; i++)
          _ev('weeknd00$i', artist: 'The Weeknd', genre: 'Pop'),
        for (var i = 0; i < 5; i++)
          _ev('kendrick0$i', artist: 'Kendrick Lamar', genre: 'Hip-Hop'),
        for (var i = 0; i < 5; i++)
          _ev('tame0000$i', artist: 'Tame Impala', genre: 'Alternative'),
      ],
      favoriteArtists: ['The Weeknd'],
    );

void main() {
  group('QuickPicksEngine v2 — native-origin demotion (#31)', () {
    test('native-only candidate loses to chart candidate of equal obscurity',
        () {
      final engine = QuickPicksEngine();
      final picks = engine.generate(
        nativeTracks: [
          _t('natives0001', 'Home Shelf Song', 'Unknown Shelf Artist'),
        ],
        chartTracks: [
          _t('chart000001', 'Chart Song', 'Chart Artist'),
        ],
        favorites: [],
        recentlyPlayed: [],
        newReleases: [],
        profile: TasteProfile.empty(),
        limit: 2,
      );
      expect(picks.first.trackId, 'chart000001');
    });

    test('native candidate WITH artist affinity beats chart candidate', () {
      final engine = QuickPicksEngine();
      final picks = engine.generate(
        nativeTracks: [
          _t('nativeweek1', 'Home Song by Weeknd', 'The Weeknd'),
        ],
        chartTracks: [
          _t('chart000001', 'Chart Song', 'Chart Artist'),
        ],
        favorites: [],
        recentlyPlayed: [],
        newReleases: [],
        profile: _goldenProfile(),
        limit: 2,
      );
      expect(picks.first.trackId, 'nativeweek1');
    });
  });

  group('QuickPicksEngine v2 — cold start (#21/#73)', () {
    test('empty profile → popularity-driven, no fake personalization', () {
      final engine = QuickPicksEngine();
      final picks = engine.generate(
        nativeTracks: [
          _t('nativecold1', 'Editorial Song', 'Editorial Artist'),
        ],
        chartTracks: [
          _t('chartreg001', 'Regional Hit', 'Regional Star'),
          _t('chartglob01', 'Global Hit', 'Global Star'),
        ],
        favorites: [],
        recentlyPlayed: [],
        newReleases: [],
        profile: TasteProfile.empty(),
        limit: 3,
      );
      // Chart items (trusted popularity) fill ahead of unproven native.
      expect(picks.map((c) => c.trackId),
          ['chartreg001', 'chartglob01', 'nativecold1']);
      expect(picks.first.reason, CandidateReason.regionalTrending);
    });
  });

  group('QuickPicksEngine v2 — golden scenario (#94/#72)', () {
    test('personal + popular + related beat obscure unrelated', () {
      final engine = QuickPicksEngine();
      final picks = engine.generate(
        nativeTracks: [
          _t('obscure0001', 'Obscure Shelf Song', 'Nobody Knows'),
          _t('weekndrel01', 'Weeknd Collab', 'The Weeknd, Some Feature'),
          _t('kendrrel001', 'Kendrick Feature', 'Kendrick Lamar'),
        ],
        chartTracks: [
          _t('chartglob01', 'Current Global Hit', 'Big Star'),
        ],
        favorites: [_t('weekndfav01', 'Fav Weeknd Song', 'The Weeknd')],
        recentlyPlayed: [],
        newReleases: [],
        profile: _goldenProfile(),
        limit: 6,
      );
      final ids = picks.map((c) => c.trackId).toList();
      // Personal favorites and affinity matches rank above obscure native.
      expect(
          ids.indexOf('obscure0001'), greaterThan(ids.indexOf('weekndfav01')));
      expect(
          ids.indexOf('obscure0001'), greaterThan(ids.indexOf('weekndrel01')));
      // A Weeknd-taste user sees Weeknd in top 3, not bottom.
      expect(ids.indexOf('weekndfav01'), lessThan(3));
    });
  });

  group('QuickPicksEngine v2 — rotation & exposure (#35-38/#75)', () {
    final engine = QuickPicksEngine();
    final natives = [
      _t('natives0001', 'Shelf A', 'Artist A'),
      _t('natives0002', 'Shelf B', 'Artist B'),
      _t('natives0003', 'Shelf C', 'Artist C'),
      _t('natives0004', 'Shelf D', 'Artist D'),
    ];
    final charts = [
      _t('chart000001', 'Hit 1', 'S1'),
      _t('chart000002', 'Hit 2', 'S2'),
      _t('chart000003', 'Hit 3', 'S3'),
      _t('chart000004', 'Hit 4', 'S4'),
      _t('chart000005', 'Hit 5', 'S5'),
      _t('chart000006', 'Hit 6', 'S6'),
    ];

    List<String> runWith(ExposureLedger ledger, int generation) {
      final picks = engine.generate(
        nativeTracks: natives,
        chartTracks: charts,
        favorites: [],
        recentlyPlayed: [],
        newReleases: [],
        profile: TasteProfile.empty(),
        exposure: ledger,
        generation: generation,
        limit: 6,
      );
      ledger.recordGeneration(generation, picks.map((c) => c.trackId));
      return picks.map((c) => c.trackId).toList();
    }

    test('refresh keeps stable top, rotates tail, fully deterministic', () {
      final exposure = ExposureLedger();
      final g1 = runWith(exposure, 1);
      final g2 = runWith(exposure, 2);
      final g3 = runWith(exposure, 3);
      final g4 = runWith(exposure, 4);
      final g5 = runWith(exposure, 5);

      // Not identical forever (#38) and not chaotic (#75): every
      // generation shares most of its content with the previous one.
      for (final (prev, next) in [(g1, g2), (g2, g3), (g3, g4), (g4, g5)]) {
        expect(next, isNot(prev));
        expect(
          next.toSet().intersection(prev.toSet()).length,
          greaterThanOrEqualTo(3),
        );
      }
      // Deterministic: a fresh ledger replays the exact same sequence.
      final replay = ExposureLedger();
      expect(runWith(replay, 1), g1);
      expect(runWith(replay, 2), g2);
      expect(runWith(replay, 3), g3);
    });

    test('recently shown candidates are demoted, not banned (#35)', () {
      final exposure = ExposureLedger();
      final g1 = runWith(exposure, 1);
      final g2 = runWith(exposure, 2);
      // Shown items can reappear (demoted), unseen ones get slots.
      expect(g2.toSet().difference(g1.toSet()), isNotEmpty);
      // But the pool is shared — previously-shown items still appear.
      expect(g1.toSet().intersection(g2.toSet()), isNotEmpty);
    });
  });

  group('QuickPicksEngine v2 — distinctness (#39)', () {
    test('quick picks differ from recently played when alternatives exist', () {
      final engine = QuickPicksEngine();
      final profile = TasteProfile.build(events: [
        _ev('played00001', artist: 'A'),
        _ev('played00002', artist: 'B'),
      ]);
      final picks = engine.generate(
        nativeTracks: [],
        chartTracks: [
          _t('chart000001', 'Hit 1', 'S1'),
          _t('chart000002', 'Hit 2', 'S2'),
          _t('chart000003', 'Hit 3', 'S3'),
          _t('chart000004', 'Hit 4', 'S4'),
          _t('chart000005', 'Hit 5', 'S5'),
        ],
        favorites: [],
        recentlyPlayed: [
          _t('played00001', 'Played 1', 'A'),
          _t('played00002', 'Played 2', 'B'),
        ],
        newReleases: [],
        profile: profile,
        limit: 6,
      );
      final recents = {'played00001', 'played00002'};
      final recentsInPicks = picks.where((c) => recents.contains(c.trackId));
      // Prediction, not history: recents may overlap but must not dominate.
      expect(recentsInPicks.length, lessThanOrEqualTo(2));
    });
  });

  group('QuickPicksEngine v2 — search follow-up (#12/#61)', () {
    test('searched-and-played track gets search-followup reason', () {
      final engine = QuickPicksEngine();
      final picks = engine.generate(
        nativeTracks: [],
        chartTracks: [],
        favorites: [],
        recentlyPlayed: [
          _t('searchhit01', 'Sicko Mode', 'Travis Scott'),
        ],
        newReleases: [],
        profile: TasteProfile.build(events: [
          _ev('searchhit01', artist: 'Travis Scott', genre: 'Hip-Hop'),
        ], searchQueries: [
          'travis scott'
        ]),
        limit: 4,
      );
      final hit = picks.firstWhere((c) => c.trackId == 'searchhit01');
      expect(hit.reason, CandidateReason.searchFollowup);
    });
  });

  group('QuickPicksEngine v2 — soft caps (#32/#33/#34)', () {
    test('artist cap 2 for normal profiles, relaxed for dominant taste', () {
      final engine = QuickPicksEngine();
      final dominant = TasteProfile.build(events: [
        for (var i = 0; i < 20; i++)
          _ev('dom00000$i', artist: 'Drake', completion: 1.0),
      ]);
      final normal = TasteProfile.build(events: [
        _ev('normal001', artist: 'Drake'),
      ]);
      final pool = [
        _t('drake000001', 'D1', 'Drake'),
        _t('drake000002', 'D2', 'Drake'),
        _t('drake000003', 'D3', 'Drake'),
        _t('other000001', 'O1', 'Not Drake'),
      ];

      int drakeCount(TasteProfile profile) => engine
          .generate(
            nativeTracks: pool,
            chartTracks: [],
            favorites: [],
            recentlyPlayed: [],
            newReleases: [],
            profile: profile,
            limit: 4,
          )
          .where((c) => c.track.artistName == 'Drake')
          .length;

      expect(drakeCount(normal), lessThanOrEqualTo(2));
      expect(drakeCount(dominant), 3); // affinity-relaxed soft cap (#33)
    });

    test('album cap: not 8 songs from one album (#34)', () {
      final engine = QuickPicksEngine();
      final albumTracks = [
        for (var i = 1; i <= 5; i++)
          RichCandidate(
            id: 'albumsong0$i',
            title: 'Song $i',
            artists: const ['One Album Artist'],
            albumName: 'Same Album',
            source: 'chart',
            chartRank: i - 1,
            chartSize: 5,
          ),
      ];
      final picks = engine.generateRich(
        candidates: albumTracks,
        profile: TasteProfile.empty(),
        limit: 5,
      );
      final albumCount =
          picks.where((c) => c.trackId.startsWith('albumsong')).length;
      expect(albumCount, lessThanOrEqualTo(3));
    });

    group('v2.1 fixes — artwork, reasons, editorial rank', () {
      test('artwork URL survives the pipeline (cover-not-loading fix)', () {
        final engine = QuickPicksEngine();
        final track = _t('artwork0001', 'Has Art', 'Artist A');
        final picks = engine.generate(
          nativeTracks: [track],
          chartTracks: [],
          favorites: [],
          recentlyPlayed: [],
          newReleases: [],
          profile: TasteProfile.empty(),
          limit: 2,
        );
        expect(picks.first.track.albumArtUrl, isNotEmpty);
      });

      test(
          'favorited song that also charts gets favorite reason (not trending)',
          () {
        final engine = QuickPicksEngine();
        final both = _t('chartfav001', 'Chart Favorite', 'Star');
        final picks = engine.generate(
          nativeTracks: [],
          chartTracks: [both],
          favorites: [both],
          recentlyPlayed: [],
          newReleases: [],
          profile: TasteProfile.empty(),
          limit: 2,
        );
        expect(picks.first.trackId, 'chartfav001');
        expect(picks.first.reason, CandidateReason.favoriteArtist);
      });

      test(
          'cold start with empty chart: native shelf order breaks ties '
          '(no random feel)', () {
        final engine = QuickPicksEngine();
        final picks = engine.generate(
          nativeTracks: [
            _t('editorial01', 'First On Shelf', 'A'),
            _t('editorial02', 'Second On Shelf', 'B'),
            _t('editorial03', 'Third On Shelf', 'C'),
          ],
          chartTracks: [],
          favorites: [],
          recentlyPlayed: [],
          newReleases: [],
          profile: TasteProfile.empty(),
          limit: 3,
        );
        expect(picks.map((c) => c.trackId).toList(),
            ['editorial01', 'editorial02', 'editorial03']);
      });
    });

    group('song-identity dedupe (live bug: "Loser" twice)', () {
      test('same title+artist under different ids collapses to one pick',
          () {
        final engine = QuickPicksEngine();
        final picks = engine.generate(
          nativeTracks: [
            _t('nativeLos01', 'Loser', 'Tame Impala'),
          ],
          chartTracks: [],
          favorites: [
            _t('favLoser001', 'Loser', 'Tame Impala, Deadbeat'),
          ],
          recentlyPlayed: [],
          newReleases: [],
          profile: TasteProfile.empty(),
          limit: 4,
        );
        final loserCount = picks
            .where((c) => c.track.trackName.toLowerCase() == 'loser')
            .length;
        expect(loserCount, 1);
        // Favorite pool wins the attribution.
        expect(picks.singleWhere((c) =>
            c.track.trackName.toLowerCase() == 'loser').reason,
            CandidateReason.favoriteArtist);
      });

      test('same title but different artist is NOT collapsed', () {
        final engine = QuickPicksEngine();
        final picks = engine.generate(
          nativeTracks: [
            _t('cover000001', 'Hurt', 'Johnny Cash'),
            _t('cover000002', 'Hurt', 'Nine Inch Nails'),
          ],
          chartTracks: [],
          favorites: [],
          recentlyPlayed: [],
          newReleases: [],
          profile: TasteProfile.empty(),
          limit: 4,
        );
        expect(
            picks
                .where((c) => c.track.trackName.toLowerCase() == 'hurt')
                .length,
            2);
      });
    });
  });
}
