import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/canvas_resolution_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CanvasResolutionService Official Video vs Lyric Video Scoring', () {
    final targetTrack = Track(
      id: 'target12345',
      trackName: 'Blinding Lights',
      artistName: 'The Weeknd',
      albumName: 'After Hours',
      previewUrl: '',
      albumArtUrl: 'https://example.com/art.jpg',
      durationMs: 200000,
    );

    test('Lyric and lyrical titles are strictly disqualified with 0 score', () {
      final lyricCandidate = Track(
        id: 'candidate01',
        trackName: 'The Weeknd - Blinding Lights (Lyrics)',
        artistName: 'The Weeknd',
        albumName: 'After Hours',
        previewUrl: '',
        albumArtUrl: '',
        durationMs: 200000,
      );

      final lyricalCandidate = Track(
        id: 'candidate02',
        trackName: 'Blinding Lights (Lyrical Video)',
        artistName: 'The Weeknd',
        albumName: 'After Hours',
        previewUrl: '',
        albumArtUrl: '',
        durationMs: 200000,
      );

      final karaokeCandidate = Track(
        id: 'candidate03',
        trackName: 'Blinding Lights Karaoke Version',
        artistName: 'The Weeknd',
        albumName: 'After Hours',
        previewUrl: '',
        albumArtUrl: '',
        durationMs: 200000,
      );

      expect(CanvasResolutionService.scoreCandidateForTest(lyricCandidate, targetTrack), equals(0));
      expect(CanvasResolutionService.scoreCandidateForTest(lyricalCandidate, targetTrack), equals(0));
      expect(CanvasResolutionService.scoreCandidateForTest(karaokeCandidate, targetTrack), equals(0));
    });

    test('Official music video uploads receive high scores', () {
      final officialCandidate = Track(
        id: 'candidate04',
        trackName: 'The Weeknd - Blinding Lights (Official Music Video)',
        artistName: 'TheWeekndVEVO',
        albumName: 'After Hours',
        previewUrl: '',
        albumArtUrl: '',
        durationMs: 200000,
      );

      final score = CanvasResolutionService.scoreCandidateForTest(officialCandidate, targetTrack);
      expect(score, greaterThan(150));
    });
  });
}
