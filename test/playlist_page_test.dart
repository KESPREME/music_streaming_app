import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/playlist_detail_screen.dart';
import 'package:music_streaming_app/widgets/bitchord_detail/bitchord_detail.dart';
import 'package:music_streaming_app/widgets/jelly_press.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The playlist page now has the album page's header and glass chrome. These
/// tests pin that: one full-bleed surface (no band layers), the meta line, the
/// glass Play / Shuffle / Download, the capsule's search and More, and that a row
/// plays from itself.
class _P extends MusicProvider {
  final played = <(List<String>, int)>[];
  final queuedDownloads = <String>[];

  @override
  Future<void> playTrackList(List<Track> tracks, {int initialIndex = 0, String? playlistId}) async {
    played.add(([for (final t in tracks) t.id], initialIndex));
  }

  @override
  Future<void> downloadTracks(List<Track> tracks, {bool skipDownloaded = true}) async {
    queuedDownloads.addAll(tracks.map((t) => t.id));
  }
}

Track _t(String id, {int ms = 180000, String? name}) => Track(
      id: id,
      trackName: name ?? 'Song $id',
      artistName: 'Tems',
      albumName: 'Mix',
      previewUrl: '',
      albumArtUrl: '',
      duration: Duration(milliseconds: ms),
    );

void main() {
  late _P p;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final ready = Completer<void>();
    final original = debugPrint;
    debugPrint = (msg, {wrapWidth}) {
      if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) {
        ready.complete();
      }
    };
    p = _P();
    await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    debugPrint = original;
  });

  setUp(() {
    p.played.clear();
    p.queuedDownloads.clear();
  });

  List<Track> tracks() => [
        _t('p1', ms: 240000, name: 'Zulu'),
        _t('p2', ms: 180000, name: 'Alpha'),
        _t('p3', ms: 300000, name: 'Mike'),
      ];

  PlaylistDetailScreen page({List<Track>? cached}) => PlaylistDetailScreen(
        playlistId: 'PLroad',
        playlistName: 'Road Trip',
        cachedTracks: cached ?? tracks(),
        artistNameHint: 'Tems',
      );

  Future<void> pump(WidgetTester tester, Widget w) async {
    // 400x900 logical at 3x. (setSurfaceSize does not apply in this Flutter.)
    tester.view.physicalSize = const Size(1200, 2700);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
      value: p,
      child: MaterialApp(home: w),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
  }

  testWidgets('FULL BLEED, one surface: the old band layers are gone', (tester) async {
    await pump(tester, page());
    final header = find.byType(ImmersiveHeader);
    expect(header, findsOneWidget);
    expect(tester.getSize(header).width, 400, reason: 'edge to edge');
    expect(tester.getTopLeft(header), Offset.zero, reason: 'behind the status bar');
    expect(find.byType(MergeBand), findsNothing);
    expect(find.byType(ArtworkFootFade), findsNothing);
    expect(find.byType(BitchordSliverAppBar), findsNothing);
    expect(find.byType(BitchordActionBar), findsNothing);
    expect(find.byType(DetailTopBar), findsOneWidget);
  });

  testWidgets('title, curator and one honest meta line', (tester) async {
    await pump(tester, page());
    expect(find.text('Road Trip'), findsWidgets);
    expect(tester.widget<Text>(find.byKey(const ValueKey('playlist_curator'))).data, 'Tems');
    expect(find.text('Playlist · 3 tracks · 12 min'), findsOneWidget);
  });

  testWidgets('glass Play, Shuffle and Download do what they say', (tester) async {
    await pump(tester, page());
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect(p.played.last.$1, ['p1', 'p2', 'p3']);
    expect(p.played.last.$2, 0);

    await tester.tap(find.bySemanticsLabel('Shuffle'));
    await tester.pump();
    expect(p.played.last.$1.toSet(), {'p1', 'p2', 'p3'});
    expect(p.played.last.$2, 0);

    await tester.tap(find.bySemanticsLabel('Download'));
    await tester.pump();
    expect(p.queuedDownloads, ['p1', 'p2', 'p3']);
  });

  testWidgets('a row plays the playlist from itself', (tester) async {
    await pump(tester, page());
    await tester.tap(find.text('Mike'));
    await tester.pump();
    expect(p.played.last.$1, ['p1', 'p2', 'p3']);
    expect(p.played.last.$2, 2);
  });

  testWidgets('search in the capsule filters, shows a miss, and closing restores the list', (tester) async {
    await pump(tester, page());
    await tester.tap(find.bySemanticsLabel('Search in playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'mik');
    await tester.pump();
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No songs match "zzz"'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Close search'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('the row menu button flexes and is findable by its tooltip', (tester) async {
    await pump(tester, page());
    final more = find.byTooltip('More options for Mike');
    expect(more, findsOneWidget);
    expect(find.ancestor(of: more, matching: find.byType(JellyPress)), findsOneWidget);
  });

  testWidgets('an empty cache with no id still builds the glass header (error path)', (tester) async {
    await pump(
      tester,
      const PlaylistDetailScreen(playlistId: '', playlistName: 'Gone'),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ImmersiveHeader), findsOneWidget);
    expect(find.text('Playlist not found'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });
}
