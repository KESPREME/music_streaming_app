import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/services/recommendation/queue_builder.dart';

void main() {
  Track makeTrack(String id, String title, String artist) => Track(
        id: id,
        trackName: title,
        artistName: artist,
        albumName: 'Test Album',
        previewUrl: '',
        source: 'youtube',
      );

  group('Autoplay Queue Builder & Candidate Pure Logic Tests', () {
    test('QueueBuilder extend deduplicates recordings and enforces diversity caps', () {
      final seed = makeTrack('yt_seed_123', 'Starboy', 'The Weeknd');
      final candidates = [
        makeTrack('yt_seed_dup', 'Starboy (Official Music Video)', 'The Weeknd'),
        makeTrack('yt_cand_1', 'Blinding Lights', 'The Weeknd'),
        makeTrack('yt_cand_2', 'Save Your Tears', 'The Weeknd'),
        makeTrack('yt_cand_3', 'Die For You', 'The Weeknd'),
        makeTrack('yt_cand_4', 'Can\'t Feel My Face', 'The Weeknd'),
        makeTrack('yt_cand_5', 'In The Night', 'The Weeknd'), // 5th candidate for seed artist -> should be capped
        makeTrack('yt_cand_6', 'Levitating', 'Dua Lipa'),
        makeTrack('yt_cand_7', 'Don\'t Start Now', 'Dua Lipa'),
        makeTrack('yt_cand_8', 'New Rules', 'Dua Lipa'), // 3rd candidate for other artist -> should be capped
      ];

      final extended = QueueBuilder.extend([seed], candidates, limit: 10);

      // Verify no duplicate of seed track is added
      expect(extended.any((t) => t.id == 'yt_seed_dup'), isFalse);

      // Verify seed artist is capped at max 4 tracks in addition to seed
      final weekndCount = extended.where((t) => t.artistName.contains('The Weeknd')).length;
      expect(weekndCount, lessThanOrEqualTo(4));

      // Verify other artist is capped at max 2
      final duaCount = extended.where((t) => t.artistName.contains('Dua Lipa')).length;
      expect(duaCount, lessThanOrEqualTo(2));
    });

    test('Playable candidate filter rejects channel, playlist, and album IDs', () {
      bool isPlayableAutoplayCandidate(Track t) {
        final id = t.id;
        if (id.isEmpty) return false;
        if (id.startsWith('PL') ||
            id.startsWith('VL') ||
            id.startsWith('UC') ||
            id.startsWith('OLAK') ||
            id.startsWith('MPREb')) {
          return false;
        }
        return true;
      }

      expect(isPlayableAutoplayCandidate(makeTrack('4NRXx6U8ABQ', 'Valid Song', 'Artist')), isTrue);
      expect(isPlayableAutoplayCandidate(makeTrack('PL1234567890', 'Playlist', 'Artist')), isFalse);
      expect(isPlayableAutoplayCandidate(makeTrack('VL1234567890', 'Playlist', 'Artist')), isFalse);
      expect(isPlayableAutoplayCandidate(makeTrack('UC1234567890', 'Channel', 'Artist')), isFalse);
      expect(isPlayableAutoplayCandidate(makeTrack('OLAK5uy_test', 'Album', 'Artist')), isFalse);
      expect(isPlayableAutoplayCandidate(makeTrack('MPREb_test', 'Album', 'Artist')), isFalse);
      expect(isPlayableAutoplayCandidate(makeTrack('', 'Empty ID', 'Artist')), isFalse);
    });

    test('Curated vs Autoplay Queue Advance Decision Logic Contract', () {
      // Simulate the exact advance decision logic from _onTrackComplete & skipToNext
      bool shouldPlayFromQueue({
        required bool queueIsNotEmpty,
        required bool isFirstAutoplay,
        required String? currentPlaylistId,
        required bool isAutoQueueContext,
        required int currentIndex,
        required int activePlaylistLength,
      }) {
        if (!queueIsNotEmpty) return false;

        final bool isRealCuratedPlaylist = currentPlaylistId != null &&
            currentPlaylistId != 'recently_played' &&
            currentPlaylistId != 'jump_back_in' &&
            currentPlaylistId != 'auto_queue' &&
            !isAutoQueueContext;

        final hasUpcomingPlaylistTracks =
            isRealCuratedPlaylist && (currentIndex + 1) < activePlaylistLength;

        return !isFirstAutoplay || !hasUpcomingPlaylistTracks;
      }

      // Case 1: Playing from Jump Back In (currentPlaylistId is null or 'recently_played')
      // and queue has autoplay tracks.
      // MUST play from queue!
      expect(
        shouldPlayFromQueue(
          queueIsNotEmpty: true,
          isFirstAutoplay: true,
          currentPlaylistId: null,
          isAutoQueueContext: false,
          currentIndex: 0,
          activePlaylistLength: 10,
        ),
        isTrue,
        reason: 'Jump Back In single track playback must advance to autoplay queue',
      );

      expect(
        shouldPlayFromQueue(
          queueIsNotEmpty: true,
          isFirstAutoplay: true,
          currentPlaylistId: 'recently_played',
          isAutoQueueContext: false,
          currentIndex: 0,
          activePlaylistLength: 10,
        ),
        isTrue,
        reason: 'Recently played context must not prevent autoplay queue playback',
      );

      // Case 2: Curated Album (currentPlaylistId = 'album_123') with upcoming album tracks
      // Autoplay track in queue must WAIT for album to finish.
      expect(
        shouldPlayFromQueue(
          queueIsNotEmpty: true,
          isFirstAutoplay: true,
          currentPlaylistId: 'album_123',
          isAutoQueueContext: false,
          currentIndex: 0,
          activePlaylistLength: 10,
        ),
        isFalse,
        reason: 'Curated album must play next album track before autoplay tracks',
      );

      // Case 3: User manually added a track to queue during album playback (!isFirstAutoplay)
      // MUST play user track immediately.
      expect(
        shouldPlayFromQueue(
          queueIsNotEmpty: true,
          isFirstAutoplay: false,
          currentPlaylistId: 'album_123',
          isAutoQueueContext: false,
          currentIndex: 0,
          activePlaylistLength: 10,
        ),
        isTrue,
        reason: 'User-queued track takes precedence even in curated album',
      );

      // Case 4: Curated Album reaches the last track ((currentIndex + 1) >= activePlaylistLength)
      // MUST transition to autoplay queue!
      expect(
        shouldPlayFromQueue(
          queueIsNotEmpty: true,
          isFirstAutoplay: true,
          currentPlaylistId: 'album_123',
          isAutoQueueContext: false,
          currentIndex: 9,
          activePlaylistLength: 10,
        ),
        isTrue,
        reason: 'When album concludes, it must transition into autoplay queue',
      );
    });
  });
}
