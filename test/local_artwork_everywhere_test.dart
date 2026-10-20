import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/mini_player.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A LOCAL SONG'S COVER reaches everything that shows the current track: the
/// provider swaps in a file of the embedded art, and the pill draws files.

class _Local extends MusicProvider {
  String? artFile;
  int artRequests = 0;

  @override
  Future<String?> localArtworkFile(Track track) async {
    artRequests++;
    return artFile;
  }
}

Track _local(String id, {String art = ''}) => Track(
      id: '/storage/Music/$id.mp3',
      trackName: 'Song $id',
      artistName: 'Artist',
      albumName: 'Album',
      previewUrl: '/storage/Music/$id.mp3',
      albumArtUrl: art,
      source: 'local',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Local p;
  late Directory dir;
  late File cover;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final ready = Completer<void>();
    final original = debugPrint;
    debugPrint = (msg, {wrapWidth}) {
      if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) ready.complete();
    };
    p = _Local();
    await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    debugPrint = original;
    dir = Directory.systemTemp.createTempSync('art');
    cover = File('${dir.path}/cover.png')
      // A 1x1 PNG.
      ..writeAsBytesSync(const [
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, //
        137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 15, 4, 0, 9, 251, 3, 253, 99, 38, 197, 143, 0, 0, 0, 0, 73, 69, //
        78, 68, 174, 66, 96, 130,
      ]);
  });

  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a local track that becomes current gets its cover file, once', () async {
    p.artFile = cover.path;
    p.artRequests = 0;
    p.debugSetCurrentTrack(_local('a'));
    p.notifyListeners();
    await Future<void>.delayed(Duration.zero);
    expect(p.currentTrack!.albumArtUrl, cover.path);
    p.notifyListeners();
    p.notifyListeners();
    await Future<void>.delayed(Duration.zero);
    expect(p.artRequests, 1);
  });

  test('a cover from a cleared temp dir is fetched again', () async {
    p.artFile = cover.path;
    p.artRequests = 0;
    p.debugSetCurrentTrack(_local('b', art: '${dir.path}/gone.jpg'));
    p.notifyListeners();
    await Future<void>.delayed(Duration.zero);
    expect(p.currentTrack!.albumArtUrl, cover.path);
  });

  test('a song with no embedded art is left alone; network tracks are never touched', () async {
    p.artFile = null;
    p.debugSetCurrentTrack(_local('c'));
    p.notifyListeners();
    await Future<void>.delayed(Duration.zero);
    expect(p.currentTrack!.albumArtUrl, '');

    p.artRequests = 0;
    p.debugSetCurrentTrack(Track(id: 'yt12345678a', trackName: 'x', artistName: 'y', albumName: '', previewUrl: ''));
    p.notifyListeners();
    expect(p.artRequests, 0);
  });

  testWidgets('the mini pill draws a file cover', (tester) async {
    p.debugSetCurrentTrack(_local('d', art: cover.path));
    await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
      value: p,
      child: MaterialApp(theme: GlassTheme.build(AccentColors.peach), home: const Scaffold(body: Center(child: MiniPlayer()))),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    final files = tester.widgetList<Image>(find.byType(Image)).where((i) {
      final img = i.image;
      return img is ResizeImage ? img.imageProvider is FileImage : img is FileImage;
    });
    expect(files, isNotEmpty);
  });
}
