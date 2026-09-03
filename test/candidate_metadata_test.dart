import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/recommendation/candidate_metadata.dart';

void main() {
  group('artist parsing (#6)', () {
    test('comma-separated collaboration splits into distinct artists', () {
      expect(
        parseArtists('The Weeknd, Playboi Carti'),
        ['The Weeknd', 'Playboi Carti'],
      );
    });

    test('ampersand and x are NOT split (conservative, no false splits)', () {
      // 'Simon & Garfunkel' is one act; splitting would fabricate artists.
      expect(parseArtists('Simon & Garfunkel'), ['Simon & Garfunkel']);
      expect(parseArtists('Artist A x Artist B'), ['Artist A x Artist B']);
    });

    test('caps at 4 and trims empties', () {
      expect(
        parseArtists('A, B, C, D, E, F'),
        ['A', 'B', 'C', 'D'],
      );
      expect(parseArtists('  Solo  '), ['Solo']);
      expect(parseArtists(''), isEmpty);
      expect(parseArtists(',,'), isEmpty);
    });
  });

  group('genre normalization (#7/#52)', () {
    test('known mood titles map into clusters', () {
      expect(normalizeGenre('Chill'), 'chill');
      expect(normalizeGenre('Bollywood'), 'bollywood');
      expect(normalizeGenre('Hip-Hop'), 'hip-hop');
      expect(normalizeGenre('Indie Pop'), 'indie-pop');
      expect(normalizeGenre('Devotional & Spiritual'), 'devotional');
    });

    test('unknown genres pass through lowercased, never dropped', () {
      expect(normalizeGenre('Tamil Film'), 'tamil film');
      expect(normalizeGenre('  Lo-Fi  '), 'lofi'); // curated normalization
    });

    test('empty/null stays null — no fabrication', () {
      expect(normalizeGenre(''), isNull);
      expect(normalizeGenre(null), isNull);
    });
  });

  group('popularity normalization (#27)', () {
    test('chart rank position → 0-1 popularity, rank 1 = 1.0', () {
      expect(popularityFromChartRank(0, 10), 1.0);
      expect(popularityFromChartRank(9, 10), closeTo(0.1, 1e-9));
      expect(popularityFromChartRank(4, 20), closeTo(0.8, 1e-9));
    });

    test('unknown rank → null (never fabricate)', () {
      expect(popularityFromChartRank(null, 10), isNull);
    });

    test('degenerate chart size → null', () {
      expect(popularityFromChartRank(0, 0), isNull);
    });
  });

  group('RichCandidate', () {
    test('primary artist = first parsed artist', () {
      final c = RichCandidate.fromTrack(
        trackId: 'valid000001',
        title: 'Timeless',
        artistName: 'The Weeknd, Playboi Carti',
        source: 'local_history',
      );
      expect(c.artists, ['The Weeknd', 'Playboi Carti']);
      expect(c.primaryArtist, 'The Weeknd');
    });

    test('source trust: native+chart high, history high, native-only medium',
        () {
      expect(
        RichCandidate.fromTrack(
                trackId: 'valid000001',
                title: 'A',
                artistName: 'X',
                source: 'native_home')
            .sourceTrust,
        SourceTrust.medium,
      );
      expect(
        RichCandidate.fromTrack(
                trackId: 'valid000002',
                title: 'B',
                artistName: 'X',
                source: 'chart')
            .sourceTrust,
        SourceTrust.high,
      );
      expect(
        RichCandidate.fromTrack(
                trackId: 'valid000003',
                title: 'C',
                artistName: 'X',
                source: 'local_history')
            .sourceTrust,
        SourceTrust.high,
      );
    });
  });
}
