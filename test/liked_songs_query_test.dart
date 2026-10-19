import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/presentation/liked/liked_songs_query.dart';

Track t(String id, String title, String artist,
        {String album = 'Album', String? genre, String source = 'youtube', int? ms}) =>
    Track(
      id: id,
      trackName: title,
      artistName: artist,
      albumName: album,
      previewUrl: '',
      genre: genre,
      source: source,
      durationMs: ms,
    );

void main() {
  // Stored order = recently added (newest first).
  final liked = [
    t('1', 'oh yeah?', 'Steve Lacy', album: 'Gemini Rights'),
    t('2', 'Blinding Lights', 'The Weeknd', album: 'After Hours', genre: 'Pop'),
    t('3', 'Café', 'Beyoncé', album: 'Renaissance', genre: 'Pop'),
    t('4', 'Save Your Tears', 'The Weeknd', album: 'After Hours'),
    t('5', 'Get Lucky', 'Daft Punk & Pharrell', album: 'Random Access Memories'),
    t('6', 'Lose Yourself to Dance', 'Daft Punk', album: 'Random Access Memories'),
  ];
  List<String> ids(List<Track> l) => l.map((e) => e.id).toList();

  group('sort', () {
    test('recently added keeps stored order', () {
      expect(ids(applyLikedQuery(liked, const LikedQuery())), ['1', '2', '3', '4', '5', '6']);
    });

    test('title ignores case and accents', () {
      expect(ids(applyLikedQuery(liked, const LikedQuery(sort: LikedSort.title))),
          ['2', '3', '5', '6', '1', '4']);
    });

    test('artist, then album, then stored order', () {
      expect(ids(applyLikedQuery(liked, const LikedQuery(sort: LikedSort.artist))),
          ['3', '6', '5', '1', '2', '4']);
    });

    test('album', () {
      expect(ids(applyLikedQuery(liked, const LikedQuery(sort: LikedSort.album))).first, '2');
    });

    test('most played, unplayed keep stored order after', () {
      final r = applyLikedQuery(liked, const LikedQuery(sort: LikedSort.mostPlayed),
          playCounts: {'4': 9, '6': 3});
      expect(ids(r), ['4', '6', '1', '2', '3', '5']);
    });

    test('a stored sort name round-trips; unknown falls back', () {
      expect(LikedSort.fromName('artist'), LikedSort.artist);
      expect(LikedSort.fromName('nope'), LikedSort.recentlyAdded);
      expect(LikedSort.fromName(null), LikedSort.recentlyAdded);
    });
  });

  group('search', () {
    test('every word must match title, artist or album', () {
      expect(ids(applyLikedQuery(liked, const LikedQuery(search: 'weeknd tears'))), ['4']);
      expect(ids(applyLikedQuery(liked, const LikedQuery(search: 'random'))), ['5', '6']);
    });

    test('accents and case do not matter, either way round', () {
      expect(ids(applyLikedQuery(liked, const LikedQuery(search: 'BEYONCE'))), ['3']);
      expect(ids(applyLikedQuery(liked, const LikedQuery(search: 'cafe'))), ['3']);
      expect(normalizeForSearch('  Héllo   Wörld '), 'hello world');
    });

    test('no match is an empty list, not an error', () {
      expect(applyLikedQuery(liked, const LikedQuery(search: 'zzz')), isEmpty);
    });

    test('search composes with sort', () {
      expect(ids(applyLikedQuery(liked, const LikedQuery(search: 'weeknd', sort: LikedSort.title))),
          ['2', '4']);
    });
  });

  group('filters', () {
    test('artist filter credits both artists of a duet', () {
      final r = applyLikedQuery(liked, const LikedQuery(filter: LikedFilter.artist('Daft Punk')));
      expect(ids(r), ['5', '6']);
    });

    test('downloaded filter uses the downloads check, local files always pass', () {
      final withLocal = [...liked, t('7', 'Home Demo', 'Me', source: 'local')];
      final r = applyLikedQuery(withLocal, const LikedQuery(filter: LikedFilter.downloaded()),
          isDownloaded: (id) => id == '2');
      expect(ids(r), ['2', '7']);
    });

    test('genre filter', () {
      expect(ids(applyLikedQuery(liked, const LikedQuery(filter: LikedFilter.genre('pop')))), ['2', '3']);
    });

    test('chips: downloaded only when something is, artists and genres with 2+', () {
      final chips = likedFilterChips(liked);
      expect(chips.map((c) => c.label), ['Daft Punk', 'The Weeknd', 'Pop'],
          reason: 'both artists have 2 songs, so the tie sorts by name');
      final withDl = likedFilterChips(liked, isDownloaded: (id) => id == '1');
      expect(withDl.first.kind, LikedFilterKind.downloaded);
    });

    test('filter equality ignores case so a chip stays selected', () {
      expect(const LikedFilter.artist('The Weeknd'), const LikedFilter.artist('the weeknd'));
      expect(const LikedFilter.artist('A'), isNot(const LikedFilter.genre('A')));
    });

    test('narrowed and signature', () {
      expect(const LikedQuery().isNarrowed, isFalse);
      expect(const LikedQuery(search: '  ').isNarrowed, isFalse);
      expect(const LikedQuery(search: 'x').isNarrowed, isTrue);
      expect(const LikedQuery(search: 'Café').signature, const LikedQuery(search: 'cafe').signature);
      final q = const LikedQuery(filter: LikedFilter.downloaded()).copyWith(clearFilter: true);
      expect(q.filter, isNull);
    });
  });

  group('duration', () {
    test('shown only when most durations are known', () {
      final known = [for (var i = 0; i < 5; i++) t('$i', 'x', 'y', ms: 52 * 60000)];
      expect(formatCollectionDuration(known), '4 hr 20 min');
      expect(formatCollectionDuration([t('a', 'x', 'y', ms: 48 * 60000)]), '48 min');
      expect(formatCollectionDuration([t('a', 'x', 'y', ms: 120 * 60000)]), '2 hr');
      expect(formatCollectionDuration([t('a', 'x', 'y', ms: 60000), t('b', 'x', 'y')]), isNull);
      expect(formatCollectionDuration(const []), isNull);
    });
  });
}
