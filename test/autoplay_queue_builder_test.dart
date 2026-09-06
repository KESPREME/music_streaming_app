import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/recommendation/queue_builder.dart';

void main() {
  group('QueueBuilder', () {
    Track t(String id, String title, String artist) => Track(
          id: id,
          trackName: title,
          artistName: artist,
          albumName: 'Album',
          previewUrl: '',
        );

    test('normalisedTitle strips video noise parentheticals and punctuation', () {
      expect(
        QueueBuilder.normalisedTitle('Kesariya (From "Brahmastra") | Official Video'),
        'kesariya',
      );
      expect(
        QueueBuilder.normalisedTitle('Blinding Lights [Official Music Video]'),
        'blinding lights',
      );
      expect(
        QueueBuilder.normalisedTitle('Starboy (Lyrics / Lyric Video)'),
        'starboy',
      );
      expect(
        QueueBuilder.normalisedTitle('Save Your Tears (Audio)'),
        'save your tears',
      );
    });

    test('artistSet extracts individual artist names regardless of billing format', () {
      final set1 = QueueBuilder.artistSet('Pritam, Arijit Singh & Shilpa Rao');
      expect(set1, containsAll(['pritam', 'arijit singh', 'shilpa rao']));

      final set2 = QueueBuilder.artistSet('The Weeknd feat. Daft Punk');
      expect(set2, containsAll(['the weeknd', 'daft punk']));

      final set3 = QueueBuilder.artistSet('Artist A x Artist B with Artist C');
      expect(set3, containsAll(['artist a', 'artist b', 'artist c']));
    });

    test('isSameRecording identifies video vs audio cuts of the same song', () {
      final cut1 = t('id1', 'Kesariya | Official Music Video', 'Arijit Singh, Pritam');
      final cut2 = t('id2', 'Kesariya', 'Pritam & Arijit Singh');
      final cut3 = t('id3', 'Tum Se Hi', 'Pritam');

      expect(QueueBuilder.isSameRecording(cut1, cut2), isTrue);
      expect(QueueBuilder.isSameRecording(cut1, cut3), isFalse);
    });

    test('extend drops duplicate recordings already queued', () {
      final existing = [
        t('seed1', 'Blinding Lights', 'The Weeknd'),
      ];
      final candidates = [
        t('dup1', 'Blinding Lights [Official Audio]', 'The Weeknd'),
        t('next1', 'Starboy', 'The Weeknd'),
        t('next2', 'Save Your Tears', 'The Weeknd'),
      ];

      final extended = QueueBuilder.extend(existing, candidates, limit: 10);
      expect(extended.map((e) => e.id), isNot(contains('dup1')));
      expect(extended.map((e) => e.id), containsAll(['next1', 'next2']));
    });

    test('extend enforces artist diversity caps (seed artist max 4, others max 2)', () {
      final seed = t('seed', 'Seed Song', 'The Weeknd');
      final existing = [seed];

      final candidates = [
        // 5 songs by seed artist (The Weeknd) - only 4 should be allowed
        t('w1', 'Track W1', 'The Weeknd'),
        t('w2', 'Track W2', 'The Weeknd'),
        t('w3', 'Track W3', 'The Weeknd'),
        t('w4', 'Track W4', 'The Weeknd'),
        t('w5', 'Track W5', 'The Weeknd'),

        // 3 songs by Drake - only 2 should be allowed
        t('d1', 'Drake 1', 'Drake'),
        t('d2', 'Drake 2', 'Drake'),
        t('d3', 'Drake 3', 'Drake'),

        // 2 songs by Dua Lipa
        t('l1', 'Lipa 1', 'Dua Lipa'),
        t('l2', 'Lipa 2', 'Dua Lipa'),
      ];

      final extended = QueueBuilder.extend(existing, candidates, limit: 10);

      final weekndTracks = extended.where((t) => t.artistName == 'The Weeknd').length;
      final drakeTracks = extended.where((t) => t.artistName == 'Drake').length;
      final lipaTracks = extended.where((t) => t.artistName == 'Dua Lipa').length;

      expect(weekndTracks, lessThanOrEqualTo(QueueBuilder.seedArtistLimit));
      expect(drakeTracks, lessThanOrEqualTo(QueueBuilder.perArtistLimit));
      expect(lipaTracks, lessThanOrEqualTo(QueueBuilder.perArtistLimit));
      expect(extended.map((e) => e.id), isNot(contains('d3')));
      expect(extended.map((e) => e.id), isNot(contains('w5')));
    });
  });
}
