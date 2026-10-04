import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/innertube/track_artist_credit.dart';

void main() {
  group('resolveTrackArtistCredit', () {
    test('a row that names its own artist keeps it', () {
      expect(
        resolveTrackArtistCredit(
            rowArtist: 'Daft Punk', pageCredit: 'Random Access Memories'),
        'Daft Punk',
      );
    });

    test('a compilation row overrides the page credit', () {
      // The whole point of the resolution order: the page credit is a LAST
      // resort, so a track that knows better is never overruled.
      expect(
        resolveTrackArtistCredit(
            rowArtist: 'Skrillex', pageCredit: 'Various Artists'),
        'Skrillex',
      );
    });

    test('a placeholder row falls back to the page credit', () {
      // The reported bug: album rows name no artist, only the header does.
      expect(
        resolveTrackArtistCredit(
          rowArtist: kUnknownArtist,
          pageCredit: 'Tame Impala',
        ),
        'Tame Impala',
      );
    });

    test('a blank row falls back to the page credit', () {
      expect(
        resolveTrackArtistCredit(rowArtist: '', pageCredit: 'Tame Impala'),
        'Tame Impala',
      );
    });

    test('a whitespace-only row falls back to the page credit', () {
      expect(
        resolveTrackArtistCredit(rowArtist: '   ', pageCredit: 'Tame Impala'),
        'Tame Impala',
      );
    });

    test('a placeholder with no page credit stays the placeholder', () {
      expect(
          resolveTrackArtistCredit(rowArtist: kUnknownArtist), kUnknownArtist);
    });

    test('a null page credit is not treated as a name', () {
      expect(resolveTrackArtistCredit(rowArtist: '', pageCredit: null),
          kUnknownArtist);
    });

    test('a placeholder page credit does not become the name', () {
      // Guards the recursion trap: if the page credit is itself the placeholder,
      // adopting it would render the literal under a header that has no name.
      expect(
        resolveTrackArtistCredit(
          rowArtist: kUnknownArtist,
          pageCredit: kUnknownArtist,
        ),
        kUnknownArtist,
      );
    });

    test('a blank page credit falls through to the placeholder', () {
      expect(resolveTrackArtistCredit(rowArtist: '', pageCredit: '   '),
          kUnknownArtist);
    });

    test('the page credit is trimmed', () {
      expect(
        resolveTrackArtistCredit(
          rowArtist: kUnknownArtist,
          pageCredit: '  Radiohead  ',
        ),
        'Radiohead',
      );
    });

    test('the row credit is trimmed', () {
      expect(resolveTrackArtistCredit(rowArtist: '  Gorillaz  '), 'Gorillaz');
    });
  });

  group('isUsableArtistName', () {
    test('accepts a real name', () {
      expect(isUsableArtistName('Kendrick Lamar'), isTrue);
    });

    test('accepts a real name with surrounding whitespace', () {
      expect(isUsableArtistName('  Kendrick Lamar  '), isTrue);
    });

    test('rejects the placeholder', () {
      expect(isUsableArtistName(kUnknownArtist), isFalse);
    });

    test('rejects a padded placeholder', () {
      expect(isUsableArtistName('  Unknown Artist  '), isFalse);
    });

    test('rejects empty and null', () {
      expect(isUsableArtistName(''), isFalse);
      expect(isUsableArtistName('   '), isFalse);
      expect(isUsableArtistName(null), isFalse);
    });
  });
}
