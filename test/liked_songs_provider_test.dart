import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'muzo_enhancements_test.dart' show MockMusicProvider;

Track _t(String id) => Track(id: id, trackName: 'Song $id', artistName: 'A', albumName: 'B', previewUrl: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MusicProvider p;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    p = MockMusicProvider();
    // Let initialisation (which loads liked songs) finish first.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  setUp(() {
    p.unlikeSongs(p.likedSongs.map((t) => t.id).toList());
    for (final id in ['a', 'b', 'c', 'd']) {
      p.likeSong(_t(id));
    }
  });

  List<String> ids() => p.likedSongs.map((t) => t.id).toList();

  test('liking puts the newest first', () {
    expect(ids(), ['d', 'c', 'b', 'a']);
  });

  test('unlike one and undo restores its position', () {
    var notified = 0;
    void l() => notified++;
    p.addListener(l);
    final removed = p.unlikeSongs(['c']);
    expect(ids(), ['d', 'b', 'a']);
    expect(removed.single.index, 1);
    p.restoreLikedSongs(removed);
    expect(ids(), ['d', 'c', 'b', 'a']);
    expect(notified, 2, reason: 'one notify per operation');
    p.removeListener(l);
  });

  test('batch remove and undo restores every position', () {
    final removed = p.unlikeSongs(['d', 'b', 'a']);
    expect(ids(), ['c']);
    expect(removed.map((r) => r.index), [0, 2, 3]);
    p.restoreLikedSongs(removed);
    expect(ids(), ['d', 'c', 'b', 'a']);
  });

  test('undo does not duplicate a song liked again in the meantime', () {
    final removed = p.unlikeSongs(['b']);
    p.likeSong(_t('b'));
    p.restoreLikedSongs(removed);
    expect(ids().where((id) => id == 'b'), hasLength(1));
  });

  test('unknown ids remove nothing and do not notify', () {
    var notified = 0;
    void l() => notified++;
    p.addListener(l);
    expect(p.unlikeSongs(['zzz']), isEmpty);
    expect(p.unlikeSongs(const []), isEmpty);
    expect(notified, 0);
    p.removeListener(l);
  });

  test('unlikeSong still works and persists', () async {
    p.unlikeSong('a');
    expect(p.isSongLiked('a'), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('likedSongs'), isNot(contains('"a"')));
  });
}
