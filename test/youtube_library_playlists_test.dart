import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/screens/user_playlist_screen.dart';
import 'package:music_streaming_app/services/innertube/library_playlists_parser.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:music_streaming_app/widgets/collection/collection_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// YOUTUBE MUSIC PLAYLISTS: parsed from the library browse, cached per account,
/// shown apart from your own.

Map<String, dynamic> _item(String? browseId, String title, String subtitle, {String thumb = 'https://i.ytimg.com/a.jpg'}) => {
      'musicTwoRowItemRenderer': {
        'title': {
          'runs': [
            {'text': title}
          ]
        },
        'subtitle': {
          'runs': [
            {'text': subtitle}
          ]
        },
        'thumbnailRenderer': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': '${thumb}_small', 'width': 60, 'height': 60},
                {'url': thumb, 'width': 544, 'height': 544},
              ]
            }
          }
        },
        'navigationEndpoint': browseId == null
            ? {'createPlaylistEndpoint': {}}
            : {
                'browseEndpoint': {'browseId': browseId}
              },
      }
    };

/// The shape of FEmusic_liked_playlists (trimmed).
Map<String, dynamic> _response(List<Map<String, dynamic>> items) => {
      'contents': {
        'singleColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'gridRenderer': {'items': items}
                      }
                    ]
                  }
                }
              }
            }
          ]
        }
      }
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parser', () {
    test('playlists only, best thumbnail, song count, no "New playlist", no podcasts', () {
      final r = parseLibraryPlaylists(_response([
        _item(null, 'New playlist', ''),
        _item('VLLM', 'Liked Music', 'Auto playlist'),
        _item('VLPLabc', 'Late Night Drives', 'Playlist • 32 songs'),
        _item('VLSE', 'Episodes for Later', 'Podcast episodes'),
        _item('VLPLdef', 'Gym', 'Playlist • 1,204 songs', thumb: '//i.ytimg.com/b.jpg'),
        _item('VLPLabc', 'Late Night Drives', 'Playlist • 32 songs'), // duplicate
      ]));
      expect(r.map((p) => p.title), ['Liked Music', 'Late Night Drives', 'Gym']);
      expect(r[1].browseId, 'VLPLabc');
      expect(r[1].playlistId, 'PLabc');
      expect(r[1].songCount, 32);
      expect(r[1].thumbnailUrl, 'https://i.ytimg.com/a.jpg', reason: 'the largest thumbnail');
      expect(r[2].songCount, 1204);
      expect(r[2].thumbnailUrl, 'https://i.ytimg.com/b.jpg', reason: 'protocol-relative urls get https');
      expect(r[0].isLikedMusic, isTrue);
      expect(r[0].songCount, isNull);
    });

    test('finds items wherever the grid moved to, and tolerates junk', () {
      final moved = {
        'x': [
          {
            'itemSectionRenderer': {
              'contents': [_item('VLPL1', 'One', 'Playlist • 3 songs')]
            }
          },
          null,
          42,
          'text',
        ]
      };
      expect(parseLibraryPlaylists(moved).single.title, 'One');
      expect(parseLibraryPlaylists(null), isEmpty);
      expect(parseLibraryPlaylists({'musicTwoRowItemRenderer': {'title': 5}}), isEmpty);
    });

    test('song count wording', () {
      expect(songCountFrom('Playlist • 1 song'), 1);
      expect(songCountFrom('Playlist • 25 tracks'), 25);
      expect(songCountFrom('Auto playlist'), isNull);
    });
  });

  group('provider and screen', () {
    late MusicProvider p;
    String? who = 'acct_a';
    Object? response;
    var fetches = 0;
    Completer<void>? gate;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      final ready = Completer<void>();
      final original = debugPrint;
      debugPrint = (msg, {wrapWidth}) {
        if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) ready.complete();
      };
      p = MusicProvider();
      await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      debugPrint = original;
      p.debugYouTubeIdentity = () => who;
      p.debugYouTubeLibraryFetch = () async {
        fetches++;
        if (gate != null) await gate!.future;
        final r = response;
        if (r is Exception) throw r;
        return r;
      };
    });

    setUp(() {
      who = 'acct_a';
      fetches = 0;
      gate = null;
      response = _response([_item('VLPLa', 'Mine A', 'Playlist • 2 songs')]);
    });

    test('signed out: empty, says so, does not fetch', () async {
      who = null;
      await p.loadYouTubeLibraryPlaylists(force: true);
      expect(p.youtubeLibraryStatus, YouTubeLibraryStatus.signedOut);
      expect(p.youtubeLibraryPlaylists, isEmpty);
      expect(fetches, 0);
    });

    test('loads once per account; force refreshes', () async {
      await p.loadYouTubeLibraryPlaylists(force: true);
      expect(p.youtubeLibraryStatus, YouTubeLibraryStatus.ready);
      expect(p.youtubeLibraryPlaylists.single.title, 'Mine A');
      await p.loadYouTubeLibraryPlaylists();
      expect(fetches, 1, reason: 'cached for this account');
      await p.loadYouTubeLibraryPlaylists(force: true);
      expect(fetches, 2);
    });

    test('another account replaces the list, never mixes', () async {
      await p.loadYouTubeLibraryPlaylists(force: true);
      who = 'acct_b';
      response = _response([_item('VLPLb', 'Mine B', 'Playlist • 9 songs')]);
      await p.loadYouTubeLibraryPlaylists();
      expect(p.youtubeLibraryPlaylists.map((e) => e.title), ['Mine B']);
    });

    test('a response for an account that signed out meanwhile is dropped', () async {
      await p.loadYouTubeLibraryPlaylists(force: true); // ready for A
      gate = Completer<void>();
      who = 'acct_b';
      response = _response([_item('VLPLb', 'Mine B', 'Playlist • 9 songs')]);
      final f = p.loadYouTubeLibraryPlaylists();
      who = 'acct_c';
      final bFetches = fetches;
      response = _response([_item('VLPLc', 'Mine C', 'Playlist • 4 songs')]);
      gate!.complete();
      await f;
      expect(fetches, bFetches + 1, reason: 'loads again for the account signed in now');
      expect(p.youtubeLibraryPlaylists.map((e) => e.title), ['Mine C']);
      expect(p.youtubeLibraryStatus, YouTubeLibraryStatus.ready, reason: 'never stuck loading');
    });

    test('a failure is an error state, not an empty library', () async {
      response = Exception('offline');
      await p.loadYouTubeLibraryPlaylists(force: true);
      expect(p.youtubeLibraryStatus, YouTubeLibraryStatus.error);
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<MusicProvider>.value(value: p),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp(theme: GlassTheme.build(AccentColors.peach), home: const UserPlaylistScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('Your Playlists shows them in their own section, with their own chip', (tester) async {
      response = _response([
        _item('VLPLa', 'Late Night Drives', 'Playlist • 32 songs'),
        _item('VLPLb', 'Gym', 'Playlist • 12 songs'),
      ]);
      await tester.runAsync(() => p.loadYouTubeLibraryPlaylists(force: true));
      final mine = await tester.runAsync(() => p.createPlaylistWith(name: 'My Own'));
      await pump(tester);

      expect(find.text('From YouTube Music'), findsOneWidget);
      expect(find.text('Late Night Drives'), findsOneWidget);
      expect(find.text('Playlist • 32 songs'), findsOneWidget);
      expect(find.text('1 playlist · 2 from YouTube Music'), findsOneWidget);
      expect(tester.getTopLeft(find.text('My Own')).dy < tester.getTopLeft(find.text('Late Night Drives')).dy, isTrue,
          reason: 'yours first');

      await tester.drag(find.byType(CollectionChips), const Offset(-300, 0)); // chips scroll sideways
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Filter: YouTube Music'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('My Own'), findsNothing);
      expect(find.text('Gym'), findsOneWidget);

      await tester.drag(find.byType(CollectionChips), const Offset(300, 0));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Filter: Created by you'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('From YouTube Music'), findsNothing);
      expect(find.text('My Own'), findsOneWidget);
      p.deletePlaylistWithUndo(mine!.id);
    });

    testWidgets('error shows Retry, and Retry fetches again', (tester) async {
      response = Exception('offline');
      await tester.runAsync(() => p.loadYouTubeLibraryPlaylists(force: true));
      final mine = await tester.runAsync(() => p.createPlaylistWith(name: 'Mine'));
      await pump(tester);
      expect(find.text('Couldn\'t load your YouTube Music playlists.'), findsOneWidget);
      response = _response([_item('VLPLa', 'Back again', 'Playlist • 1 song')]);
      final before = fetches;
      await tester.tap(find.text('Retry'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(fetches, before + 1);
      expect(find.text('Back again'), findsOneWidget);
      p.deletePlaylistWithUndo(mine!.id);
    });
  });
}
