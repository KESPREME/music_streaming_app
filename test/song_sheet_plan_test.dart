import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/widgets/song_sheet_plan.dart';

/// WHICH ROWS A SONG'S SHEET OFFERS, BY WHERE IT WAS OPENED.
///
/// The plan is pure data, so the whole matrix is a table. If a row appears where it
/// cannot do anything useful (Sleep Timer on a Home card, Download for a file that
/// is already on the phone, Go to album on the album you are on), this fails.

Track song({
  String id = 'abcdefghijk',
  String album = 'Troubadour',
  String artist = "K'naan",
  String source = 'youtube',
}) =>
    Track(
      id: id,
      trackName: 'Wavin Flag',
      artistName: artist,
      albumName: album,
      previewUrl: '',
      source: source,
    );

SongSheetPlan plan(
  SongSheetOrigin origin, {
  Track? track,
  bool isCurrent = false,
  bool inUpNext = false,
  bool hasDislike = false,
  bool hasPlaylistId = false,
  bool isHistory = false,
}) =>
    planSongSheet(
      origin: origin,
      track: track ?? song(),
      isCurrent: isCurrent,
      inUpNext: inUpNext,
      hasDislike: hasDislike,
      hasPlaylistId: hasPlaylistId,
      isHistory: isHistory,
    );

void main() {
  group('discovery (Home, Search, Explore): the listener has not kept the song yet', () {
    for (final o in [SongSheetOrigin.home, SongSheetOrigin.search, SongSheetOrigin.explore]) {
      test('$o offers what you do with a song you have just met', () {
        final p = plan(o);
        expect(p.tiles, [SongAction.playNext, SongAction.addToQueue, SongAction.download, SongAction.share]);
        expect(p.has(SongAction.addToPlaylist), isTrue);
        expect(p.has(SongAction.goToAlbum), isTrue);
        expect(p.has(SongAction.goToArtist), isTrue);
      });

      test('$o does not offer Sleep Timer or Song Info', () {
        final p = plan(o);
        expect(p.has(SongAction.sleepTimer), isFalse, reason: 'a global setting, not about this song');
        expect(p.has(SongAction.songInfo), isFalse);
      });
    }

    test('Not interested only where the origin supplies it', () {
      expect(plan(SongSheetOrigin.explore, hasDislike: true).has(SongAction.notInterested), isTrue);
      expect(plan(SongSheetOrigin.explore).has(SongAction.notInterested), isFalse);
      expect(plan(SongSheetOrigin.home).has(SongAction.notInterested), isFalse);
    });
  });

  group('the player', () {
    for (final o in [SongSheetOrigin.nowPlaying, SongSheetOrigin.lyrics]) {
      test('$o does not offer to queue the song that is playing', () {
        final p = plan(o, isCurrent: true);
        expect(p.has(SongAction.playNext), isFalse);
        expect(p.has(SongAction.addToQueue), isFalse);
        expect(p.tiles, [SongAction.download, SongAction.share]);
      });

      test('$o is where Sleep Timer and Song Info live', () {
        final p = plan(o, isCurrent: true);
        expect(p.has(SongAction.sleepTimer), isTrue);
        expect(p.has(SongAction.songInfo), isTrue);
      });
    }

    test('the queue header opens the PLAYING song: no Play next, and Remove only if it is upcoming', () {
      expect(plan(SongSheetOrigin.queue, isCurrent: true).has(SongAction.playNext), isFalse);
      expect(plan(SongSheetOrigin.queue, isCurrent: true).has(SongAction.removeFromQueue), isFalse,
          reason: 'the playing song is not in the queue: removing it would do nothing');
      expect(plan(SongSheetOrigin.queue, inUpNext: true).has(SongAction.removeFromQueue), isTrue);
      expect(plan(SongSheetOrigin.queue).has(SongAction.sleepTimer), isTrue);
    });
  });

  group('the listener\'s own music', () {
    test('Downloads: the Download tile becomes Remove', () {
      final p = plan(SongSheetOrigin.downloads);
      expect(p.has(SongAction.removeDownload), isTrue);
      expect(p.has(SongAction.download), isFalse);
      expect(p.has(SongAction.sleepTimer), isFalse);
    });

    test('a file on this phone: no Download, no Share, no code, no Go to album / artist', () {
      final p = plan(SongSheetOrigin.device, track: song(source: 'local'));
      expect(p.has(SongAction.download), isFalse, reason: 'it is already here');
      expect(p.has(SongAction.share), isFalse, reason: 'no link anyone else can open');
      expect(p.has(SongAction.code), isFalse);
      expect(p.has(SongAction.goToAlbum), isFalse, reason: 'its tags would be searched on YouTube Music');
      expect(p.has(SongAction.goToArtist), isFalse);
      expect(p.has(SongAction.addToPlaylist), isTrue);
      expect(p.has(SongAction.playNext), isTrue);
      expect(p.has(SongAction.songInfo), isTrue);
    });

    test('a local file is treated as local from any origin', () {
      for (final o in SongSheetOrigin.values.where((o) => o != SongSheetOrigin.auto)) {
        final p = plan(o, track: song(source: 'local'));
        expect(p.has(SongAction.download), isFalse, reason: '$o');
        expect(p.has(SongAction.removeDownload), isFalse, reason: '$o');
      }
    });

    test('its own playlist: Remove from playlist, only there', () {
      expect(plan(SongSheetOrigin.playlist, hasPlaylistId: true).danger, [SongAction.removeFromPlaylist]);
      expect(plan(SongSheetOrigin.liked).danger, isEmpty);
    });

    test('History: Remove from history', () {
      expect(plan(SongSheetOrigin.history, isHistory: true).danger, [SongAction.removeFromHistory]);
    });
  });

  group('pages about the song\'s own album or artist', () {
    test('on the album page there is no Go to album; the artist is still one tap away', () {
      final p = plan(SongSheetOrigin.album);
      expect(p.has(SongAction.goToAlbum), isFalse);
      expect(p.has(SongAction.goToArtist), isTrue);
    });

    test('on the artist page there is no Go to artist; the album is still one tap away', () {
      final p = plan(SongSheetOrigin.artist);
      expect(p.has(SongAction.goToArtist), isFalse);
      expect(p.has(SongAction.goToAlbum), isTrue);
    });
  });

  group('unknown tags and unknown callers', () {
    test('an unknown album / artist is not offered as a destination', () {
      final p = plan(SongSheetOrigin.home, track: song(album: 'Unknown Album', artist: 'Unknown Artist'));
      expect(p.has(SongAction.goToAlbum), isFalse);
      expect(p.has(SongAction.goToArtist), isFalse);
      expect(songTagIsUnknown('<unknown>'), isTrue);
      expect(songTagIsUnknown('  '), isTrue);
      expect(songTagIsUnknown('Tame Impala'), isFalse);
    });

    test('generic - an unclassified caller - keeps everything that could apply, as before', () {
      final p = plan(SongSheetOrigin.generic);
      for (final a in [
        SongAction.playNext,
        SongAction.addToQueue,
        SongAction.download,
        SongAction.share,
        SongAction.addToPlaylist,
        SongAction.goToAlbum,
        SongAction.goToArtist,
        SongAction.code,
        SongAction.songInfo,
        SongAction.sleepTimer,
      ]) {
        expect(p.has(a), isTrue, reason: '$a');
      }
    });

    test('the current song is never offered "Play next"', () {
      for (final o in SongSheetOrigin.values.where((o) => o != SongSheetOrigin.auto)) {
        expect(plan(o, isCurrent: true).has(SongAction.playNext), isFalse, reason: '$o');
      }
    });

    test('no row is offered twice', () {
      for (final o in SongSheetOrigin.values.where((o) => o != SongSheetOrigin.auto)) {
        final all = plan(o, hasDislike: true, hasPlaylistId: true, isHistory: true, inUpNext: true).all.toList();
        expect(all.toSet().length, all.length, reason: '$o');
      }
    });
  });
}
