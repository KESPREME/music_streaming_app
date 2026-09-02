import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/recommendation/candidate.dart';
import 'package:music_streaming_app/services/recommendation/quick_picks_engine.dart';
import 'package:music_streaming_app/services/recommendation/search_followup_graph.dart';

Track _t(String id, String title, String artist) => Track(
      id: id,
      trackName: title,
      artistName: artist,
      albumName: '',
      previewUrl: '',
      albumArt: 'https://example.com/$id.jpg',
      source: 'youtube',
    );

class _FakeSignalProvider implements QuickPicksSignalProvider {
  final Map<String, QuickPicksTrackSignal> signals;
  final List<String> artists;

  _FakeSignalProvider({this.signals = const {}, this.artists = const []});

  @override
  QuickPicksTrackSignal? signalFor(String trackId) => signals[trackId];

  @override
  List<String> topArtists({int limit = 10}) => artists.take(limit).toList();
}

void main() {
  group('QuickPicksEngine', () {
    test('favorites get strongest signal', () {
      final engine = QuickPicksEngine(
        signalProvider: _FakeSignalProvider(),
      );
      final picks = engine.generate(
        nativeTracks: [],
        chartTracks: [],
        favorites: [_t('favorite001', 'Favorite Song', 'Fav Artist')],
        recentlyPlayed: [],
        newReleases: [],
        limit: 4,
      );
      expect(picks, hasLength(1));
      expect(picks.first.reason, CandidateReason.favoriteArtist);
    });

    test('strong-completion recents rank above weak ones', () {
      final engine = QuickPicksEngine(
        signalProvider: _FakeSignalProvider(signals: {
          'strong00001': QuickPicksTrackSignal(
              trackId: 'strong00001',
              artistName: 'A',
              playCount: 5,
              completionRate: 0.9),
          'weak0000001': QuickPicksTrackSignal(
              trackId: 'weak0000001',
              artistName: 'B',
              playCount: 1,
              completionRate: 0.2),
        }),
      );
      final picks = engine.generate(
        nativeTracks: [],
        chartTracks: [],
        favorites: [],
        recentlyPlayed: [
          _t('strong00001', 'strong00001', 'A'),
          _t('weak0000001', 'weak0000001', 'B'),
        ],
        newReleases: [],
        limit: 4,
      );
      // Weak (< 0.6 completion, no replay) is excluded.
      expect(picks.map((c) => c.track.id), ['strong00001']);
      expect(picks.first.reason, CandidateReason.recentlyPlayed);
    });

    test('chart candidates fill when local signal is sparse (cold start)', () {
      final engine = QuickPicksEngine(
        signalProvider: _FakeSignalProvider(),
      );
      final picks = engine.generate(
        nativeTracks: [],
        chartTracks: [
          _t('chart100001', 'Chart Hit', 'Star'),
          _t('chart200002', 'Chart Hit 2', 'Star 2'),
        ],
        favorites: [],
        recentlyPlayed: [],
        newReleases: [],
        limit: 4,
      );
      expect(picks, hasLength(2));
      expect(picks.first.reason, CandidateReason.regionalTrending);
    });

    test('artist affinity boosts matching native tracks', () {
      final engine = QuickPicksEngine(
        signalProvider: _FakeSignalProvider(artists: ['The Weeknd']),
      );
      final picks = engine.generate(
        nativeTracks: [
          _t('weeknd10001', 'Save Your Tears', 'The Weeknd'),
          _t('other000001', 'Other Song', 'Different Artist'),
        ],
        chartTracks: [],
        favorites: [],
        recentlyPlayed: [],
        newReleases: [],
        limit: 4,
      );
      // Affinity match should be present and scored higher than discovery.
      final weeknd = picks.firstWhere((c) => c.track.id == 'weeknd10001');
      expect(weeknd.reason, CandidateReason.frequentArtist);
      expect(weeknd.score, greaterThan(0.10));
    });

    test('artist diversity: max 2 per artist', () {
      final engine = QuickPicksEngine(
        signalProvider: _FakeSignalProvider(artists: ['Drake']),
      );
      final picks = engine.generate(
        nativeTracks: [
          _t('drake00001', 'Drake 1', 'Drake'),
          _t('drake00002', 'Drake 2', 'Drake'),
          _t('drake00003', 'Drake 3', 'Drake'),
          _t('drake00004', 'Drake 4', 'Drake'),
          _t('other000001', 'Other', 'Not Drake'),
        ],
        chartTracks: [],
        favorites: [],
        recentlyPlayed: [],
        newReleases: [],
        limit: 8,
      );
      final drakeCount =
          picks.where((c) => c.track.artistName == 'Drake').length;
      expect(drakeCount, lessThanOrEqualTo(2));
    });

    test('non-video ids are rejected (MPREb, VL, UC prefixes)', () {
      final engine = QuickPicksEngine(
        signalProvider: _FakeSignalProvider(),
      );
      final picks = engine.generate(
        nativeTracks: [
          _t('MPREb_abc', 'Album', 'X'),
          _t('VLPLabc', 'Playlist', 'X'),
          _t('UCchannel', 'Artist', 'X'),
          _t('valid000001', 'Valid', 'X'),
        ],
        chartTracks: [],
        favorites: [],
        recentlyPlayed: [],
        newReleases: [],
        limit: 4,
      );
      expect(picks.map((c) => c.track.id), ['valid000001']);
    });

    test('skip penalty demotes frequently skipped tracks', () {
      final engine = QuickPicksEngine(
        signalProvider: _FakeSignalProvider(signals: {
          'skipped0001': QuickPicksTrackSignal(
              trackId: 'skipped0001',
              artistName: 'A',
              playCount: 5,
              skipCount: 4,
              completionRate: 0.2),
        }),
      );
      final picks = engine.generate(
        nativeTracks: [],
        chartTracks: [_t('skipped0001', 'Skipped Song', 'A')],
        favorites: [],
        recentlyPlayed: [],
        newReleases: [],
        limit: 4,
      );
      // The skipped track is present but its score is penalized.
      final skipped = picks.firstWhere((c) => c.track.id == 'skipped0001');
      expect(skipped.score, lessThan(0.10));
    });

    test('deterministic: same input → same output', () {
      final engine = QuickPicksEngine(
        signalProvider: _FakeSignalProvider(
          signals: {
            'atest000001':
                QuickPicksTrackSignal(trackId: 'atest000001', artistName: 'A'),
          },
          artists: ['Artist X'],
        ),
      );
      final native = [
        _t('native00001', 'Native', 'Artist X'),
        _t('native00002', 'Other', 'Y')
      ];
      final chart = [_t('chartX0001', 'Chart', 'Z')];
      final recent = [_t('atest000001', 'Recent', 'A')];

      final run1 = engine.generate(
        nativeTracks: native,
        chartTracks: chart,
        favorites: [],
        recentlyPlayed: recent,
        newReleases: [],
        limit: 6,
      );
      final run2 = engine.generate(
        nativeTracks: native,
        chartTracks: chart,
        favorites: [],
        recentlyPlayed: recent,
        newReleases: [],
        limit: 6,
      );
      expect(run1.map((c) => c.track.id), run2.map((c) => c.track.id));
    });
  });

  group('SearchFollowupGraph', () {
    test('affinity increases with repeated evidence', () {
      final graph = SearchFollowupGraph();
      graph.recordTransition('blinding lights', 'starboy', 'The Weeknd');
      graph.recordTransition('blinding lights', 'starboy', 'The Weeknd');
      final strong =
          graph.affinityFor('starboy', activeQuery: 'blinding lights');
      expect(strong, greaterThan(0.3));
    });

    test('one-off search yields weak affinity', () {
      final graph = SearchFollowupGraph();
      graph.recordTransition('random query', 'random123', 'Nobody');
      final weak = graph.affinityFor('random123');
      // Without active query, single evidence is weak (spec #9).
      expect(weak, lessThanOrEqualTo(0.5));
    });

    test('no evidence → zero affinity', () {
      final graph = SearchFollowupGraph();
      expect(graph.affinityFor('never_seen'), 0);
    });
  });
}
