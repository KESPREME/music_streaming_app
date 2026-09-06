import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/metadata/track_metadata_enricher.dart';

void main() {
  group('TrackMetadataEnricher', () {
    test('separates artist and album when concatenated with a bullet', () {
      final result = TrackMetadataEnricher.sanitize(
        title: 'Blinding Lights',
        artist: 'The Weeknd • After Hours',
        album: '',
      );

      expect(result.title, 'Blinding Lights');
      expect(result.artist, 'The Weeknd');
      expect(result.album, 'After Hours');
    });

    test('strips album leaking into artist field when album is known', () {
      final result = TrackMetadataEnricher.sanitize(
        title: 'Blinding Lights',
        artist: 'The Weeknd, After Hours',
        album: 'After Hours',
      );

      expect(result.title, 'Blinding Lights');
      expect(result.artist, 'The Weeknd');
      expect(result.album, 'After Hours');
    });

    test('preserves collaborating artists separated by comma', () {
      final result = TrackMetadataEnricher.sanitize(
        title: 'Rush',
        artist: 'Ayra Starr, Rema',
        album: '',
      );

      expect(result.title, 'Rush');
      expect(result.artist, 'Ayra Starr, Rema');
      expect(result.album, '');
    });

    test('separates artist and album when concatenated with a bullet', () {
      final result = TrackMetadataEnricher.sanitize(
        title: 'Starboy',
        artist: 'The Weeknd • Starboy',
        album: '',
      );

      expect(result.title, 'Starboy');
      expect(result.artist, 'The Weeknd');
      expect(result.album, 'Starboy');
    });

    test('separates artist and album when concatenated with dash in artist field', () {
      final result = TrackMetadataEnricher.sanitize(
        title: 'Save Your Tears',
        artist: 'The Weeknd - After Hours',
        album: 'Unknown Album',
      );

      expect(result.artist, 'The Weeknd');
      expect(result.album, 'After Hours');
    });

    test('strips song title leaking into artist field', () {
      final result = TrackMetadataEnricher.sanitize(
        title: 'Blinding Lights',
        artist: 'Blinding Lights, The Weeknd',
        album: 'After Hours',
      );

      expect(result.title, 'Blinding Lights');
      expect(result.artist, 'The Weeknd');
      expect(result.album, 'After Hours');
    });

    test('strips generic "Song" or "Video" label from artist field', () {
      final result = TrackMetadataEnricher.sanitize(
        title: 'Less Than Zero',
        artist: 'Song • The Weeknd',
        album: 'Dawn FM',
      );

      expect(result.artist, 'The Weeknd');
      expect(result.album, 'Dawn FM');
    });

    test('strips artist repetition from album field ("by Artist" or "Artist - Album")', () {
      final result = TrackMetadataEnricher.sanitize(
        title: 'After Hours',
        artist: 'The Weeknd',
        album: 'After Hours by The Weeknd',
      );

      expect(result.album, 'After Hours');
      expect(result.artist, 'The Weeknd');

      final result2 = TrackMetadataEnricher.sanitize(
        title: 'After Hours',
        artist: 'The Weeknd',
        album: 'The Weeknd - After Hours',
      );

      expect(result2.album, 'After Hours');
      expect(result2.artist, 'The Weeknd');
    });

    test('strips noise prefixes from album names', () {
      final r1 = TrackMetadataEnricher.sanitize(
        title: 'Track A',
        artist: 'Artist A',
        album: 'Album - Great Hits',
      );
      expect(r1.album, 'Great Hits');

      final r2 = TrackMetadataEnricher.sanitize(
        title: 'Track B',
        artist: 'Artist B',
        album: 'Single • Summer Anthem',
      );
      expect(r2.album, 'Summer Anthem');

      final r3 = TrackMetadataEnricher.sanitize(
        title: 'Track C',
        artist: 'Artist C',
        album: 'EP: Early Sessions',
      );
      expect(r3.album, 'Early Sessions');
    });

    test('strips "- Topic" suffix from artist name', () {
      final result = TrackMetadataEnricher.sanitize(
        title: 'Song',
        artist: 'The Weeknd - Topic',
        album: 'Album',
      );

      expect(result.artist, 'The Weeknd');
    });

    test('sanitizeTrack updates Track instance correctly', () {
      final track = Track(
        id: 'abc12345678',
        trackName: 'Blinding Lights',
        artistName: 'The Weeknd • After Hours',
        albumName: '',
        previewUrl: '',
      );

      final cleaned = TrackMetadataEnricher.sanitizeTrack(track);
      expect(cleaned.trackName, 'Blinding Lights');
      expect(cleaned.artistName, 'The Weeknd');
      expect(cleaned.albumName, 'After Hours');
    });
  });
}
