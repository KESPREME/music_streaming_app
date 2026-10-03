import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:music_streaming_app/services/audio_service.dart';

/// Guards for the player-window rework (Phase A).
///
/// The single most dangerous regression in this phase is not a wrong track or a
/// missed advance — it is a window entry that reaches the player without a
/// [MediaItem] tag. The background media session does
///
///     queue.add(sequence.map((s) => s.tag as MediaItem).toList());
///
/// which is an *unchecked* cast over every entry in the sequence. A single
/// untagged entry throws inside the session and takes the notification, the
/// lock screen and Android Auto down with it, while audio keeps playing — the
/// hardest kind of bug to notice in a device test.
///
/// These tests pin the property that makes that impossible.
void main() {
  // AudioService constructs a real AudioPlayer, which touches method channels.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('window sources are always tagged', () {
    test('buildSource returns a MediaItem tag for a remote URL', () async {
      final svc = AudioService();
      addTearDown(svc.dispose);

      final src = await svc.buildSource(
        url: 'https://example.invalid/audio.m4a',
        title: 'Song',
        artist: 'Artist',
        artUri: 'https://example.invalid/art.jpg',
        id: 'abc12345678',
      );

      expect(src, isNotNull);
      expect(src!.tag, isA<MediaItem>(),
          reason: 'an untagged source would throw in the media session');
      final tag = src.tag! as MediaItem;
      expect(tag.id, 'abc12345678');
      expect(tag.title, 'Song');
      expect(tag.artist, 'Artist');
    });
    test('a source with no title still carries a tag', () async {
      final svc = AudioService();
      addTearDown(svc.dispose);

      final src = await svc.buildSource(
        url: 'https://example.invalid/audio.m4a',
        id: 'abc12345678',
      );

      expect(src!.tag, isA<MediaItem>());
      final tag = src.tag! as MediaItem;
      // A null title would leave the notification blank and would still be a
      // legal MediaItem, but an untagged source is not survivable.
      expect(tag.title, isNotNull);
      expect(tag.title, isNotEmpty);
    });

    test('a null url yields no source rather than an untagged one', () async {
      final svc = AudioService();
      addTearDown(svc.dispose);

      expect(await svc.buildSource(url: null), isNull);
      expect(await svc.buildSource(url: ''), isNull);
    });

    test('every source the media session would cast is a MediaItem', () async {
      final svc = AudioService();
      addTearDown(svc.dispose);

      // Mirrors what just_audio_background does to the whole sequence.
      final built = <IndexedAudioSource?>[
        await svc.buildSource(url: 'https://a.invalid/1', id: 'aaaaaaaaaaa'),
        await svc.buildSource(url: 'https://a.invalid/2', id: 'bbbbbbbbbbb'),
        await svc.buildSource(url: 'https://a.invalid/3', id: 'ccccccccccc'),
        await svc.buildSource(url: null), // must be dropped, not tagged null
      ].whereType<IndexedAudioSource>().toList();

      expect(built, hasLength(3));
      final cast = built.map((s) => s.tag as MediaItem).toList();
      expect(cast, hasLength(3));
      expect(cast.map((m) => m.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);
    });
  });

  group('window bookkeeping', () {
    test('windowTrackIds never reports an untagged entry', () async {
      final svc = AudioService();
      addTearDown(svc.dispose);
      // Before anything is installed the window is empty, not bogus.
      expect(svc.windowTrackIds, isEmpty);
      expect(svc.nextWindowTrackId, isNull);
      expect(svc.hasNextInWindow, isFalse);
    });
  });
}
