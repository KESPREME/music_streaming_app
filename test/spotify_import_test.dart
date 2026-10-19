import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/models/playlist.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/providers/theme_provider.dart';
import 'package:music_streaming_app/screens/playlist_import_screen.dart';
import 'package:music_streaming_app/screens/user_playlist_detail_screen.dart';
import 'package:music_streaming_app/services/spotify_public.dart';
import 'package:music_streaming_app/services/spotify_service.dart';
import 'package:music_streaming_app/theme/glass_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SPOTIFY IMPORT: every page read, every song matched, progress you can watch
/// and stop, an honest result.

Map<String, dynamic> _sTrack(String id, {String? artist = 'Artist'}) => {
      'track': {
        'id': id,
        'name': 'Song $id',
        'artists': [
          if (artist != null) {'name': artist}
        ],
        'album': {
          'name': 'Album',
          'images': [
            {'url': 'https://i.scdn.co/$id.jpg'}
          ]
        },
        'duration_ms': 180000,
        'explicit': id == 's2',
      }
    };

/// A fake Spotify API: /me/playlists in two pages, and a playlist whose tracks
/// come in two pages (with a local file / removed song in between).
MockClient _api({void Function(Uri)? onRequest}) => MockClient((req) async {
      onRequest?.call(req.url);
      final u = req.url.toString();
      if (u.contains('/me/playlists')) {
        if (u.contains('offset=50')) {
          return http.Response(jsonEncode({
            'items': [
              {'id': 'p3', 'name': 'Third', 'images': [], 'tracks': {'total': 1}}
            ],
            'next': null,
          }), 200);
        }
        return http.Response(jsonEncode({
          'items': [
            {'id': 'p1', 'name': 'Chill', 'images': [], 'tracks': {'total': 3}, 'owner': {'display_name': 'Me'}},
            {'id': 'p2', 'name': 'Gym', 'images': [], 'tracks': {'total': 2}},
          ],
          'next': 'https://api.spotify.com/v1/me/playlists?offset=50&limit=50',
        }), 200);
      }
      if (u.contains('/playlists/p1/tracks')) {
        if (u.contains('offset=100')) {
          return http.Response(jsonEncode({
            'items': [_sTrack('s3')],
            'next': null
          }), 200);
        }
        return http.Response(jsonEncode({
          'items': [
            _sTrack('s1'),
            {'track': null},
            _sTrack('s2'),
          ],
          'next': 'https://api.spotify.com/v1/playlists/p1/tracks?offset=100&limit=100',
        }), 200);
      }
      if (u.contains('/playlists/p2/tracks')) {
        return http.Response(jsonEncode({'items': [_sTrack('g1'), _sTrack('g2')], 'next': null}), 200);
      }
      if (u.contains('/playlists/p1?')) {
        return http.Response(jsonEncode({'id': 'p1', 'name': 'Chill', 'images': []}), 200);
      }
      // Any other playlist (a pasted link): one song, named "Linked".
      final other = RegExp(r'/playlists/(\w+)(/tracks)?\?').firstMatch(u);
      if (other != null) {
        if (other.group(2) != null) {
          return http.Response(jsonEncode({'items': [_sTrack('l1')], 'next': null}), 200);
        }
        return http.Response(jsonEncode({'id': other.group(1), 'name': 'Linked', 'images': []}), 200);
      }
      return http.Response('not found', 404);
    });

/// Matches every song except "Song s2", the way YouTube Music would answer:
/// the same title and artist, the same length.
Future<List<Track>> _search(String q) async => q.startsWith('Song s2')
    ? const []
    : [
        Track(id: 'cover_${q.split(' ')[1]}', trackName: 'Totally different', artistName: 'Karaoke Kings', albumName: '', previewUrl: '', durationMs: 180000),
        Track(id: 'yt_${q.split(' ')[1]}', trackName: 'Song ${q.split(' ')[1]}', artistName: 'Artist', albumName: '', previewUrl: '', durationMs: 181000),
      ];

/// A Spotify embed page carrying [entity] (and the anonymous token).
String _embedPage(Map<String, dynamic> entity) => '<html><script id="__NEXT_DATA__" type="application/json">'
    '${jsonEncode({
      'props': {
        'pageProps': {
          'state': {
            'data': {'entity': entity},
            'settings': {
              'session': {'accessToken': 'anon', 'isAnonymous': true}
            },
          }
        }
      }
    })}</script></html>';

Map<String, dynamic> _embedTrack(String id) => {
      'uri': 'spotify:track:$id',
      'title': 'Song $id',
      'subtitle': 'Artist,\u00a0Guest',
      'duration': 180000,
      'isExplicit': id == 'e1',
    };

/// The public (no account) endpoints: a 2-song playlist "pubsmall", and a
/// 102-song one "publarge" whose embed shows 100 and whose spclient list has
/// all 102.
MockClient _publicApi() => MockClient((req) async {
      final u = req.url.toString();
      if (u.contains('/embed/playlist/pubsmall')) {
        return http.Response(
            _embedPage({
              'type': 'playlist',
              'name': 'Public Mix',
              'coverArt': {
                'sources': [
                  {'url': 'https://i.scdn.co/pub.jpg'}
                ]
              },
              'trackList': [_embedTrack('a1'), _embedTrack('e1')],
            }),
            200);
      }
      if (u.contains('/embed/playlist/publarge')) {
        return http.Response(
            _embedPage({
              'type': 'playlist',
              'name': 'Big One',
              'trackList': [for (var i = 0; i < 100; i++) _embedTrack('n$i')],
            }),
            200);
      }
      if (u.contains('spclient.wg.spotify.com/playlist/v2/playlist/publarge')) {
        expect(req.headers['Authorization'], 'Bearer anon');
        return http.Response(
            jsonEncode({
              'length': 102,
              'contents': {
                'items': [
                  for (var i = 0; i < 100; i++) {'uri': 'spotify:track:n$i'},
                  {'uri': 'spotify:track:x1'},
                  {'uri': 'spotify:episode:pod'},
                  {'uri': 'spotify:track:x2'},
                ]
              }
            }),
            200);
      }
      final track = RegExp(r'/embed/track/(\w+)').firstMatch(u);
      if (track != null) {
        final id = track.group(1)!;
        return http.Response(
            _embedPage({
              'type': 'track',
              'id': id,
              'name': 'Song $id',
              'artists': [
                {'name': 'Artist'}
              ],
              'duration': 180000,
              'visualIdentity': {
                'image': [
                  {'url': 'https://i.scdn.co/$id.jpg', 'maxWidth': 300}
                ]
              },
            }),
            200);
      }
      return http.Response('nope', 404);
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('service', () {
    SpotifyService service({void Function(Uri)? onRequest, Future<List<Track>> Function(String)? search}) =>
        SpotifyService(client: _api(onRequest: onRequest), tokenProvider: () async => 'tok', search: search ?? _search);

    test('reads every page of your playlists', () async {
      final list = await service().getUserPlaylists();
      expect(list.map((m) => m['name']), ['Chill', 'Gym', 'Third']);
    });

    test('reads every page of a playlist, skips non-songs, matches, keeps the unmatched', () async {
      final progress = <(int, int)>[];
      final pl = await service().getPlaylistWithTracks('p1', 'Chill', '', onProgress: (d, t) => progress.add((d, t)));
      expect(pl.tracks.map((t) => t.id), ['yt_s1', 's2', 'yt_s3']);
      expect(pl.tracks.map((t) => t.source), ['youtube', 'spotify', 'youtube']);
      expect(pl.tracks.first.trackName, 'Song s1', reason: 'the Spotify name is kept');
      expect(pl.tracks[1].isExplicit, isTrue);
      expect(pl.tracks.first.durationMs, 180000);
      expect(progress.first, (0, 3));
      expect(progress.last, (3, 3));
    });

    test('cancel stops between songs and saves nothing', () async {
      var n = 0;
      expect(
        () => service(search: (q) async {
          n++;
          return _search(q);
        }).getPlaylistWithTracks('p1', 'Chill', '', isCancelled: () => n >= 1),
        throwsA(isA<ImportCancelled>()),
      );
    });

    test('a failed search keeps the song rather than dropping it', () async {
      final pl = await service(search: (_) async => throw Exception('net'))
          .getPlaylistWithTracks('p2', 'Gym', '');
      expect(pl.tracks.map((t) => t.id), ['g1', 'g2']);
    });

    test('link parsing', () {
      expect(spotifyPlaylistIdFrom('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc'),
          '37i9dQZF1DXcBWIGoYBM5M');
      expect(spotifyPlaylistIdFrom('open.spotify.com/intl-de/playlist/37i9dQZF1DXcBWIGoYBM5M'), '37i9dQZF1DXcBWIGoYBM5M');
      expect(spotifyPlaylistIdFrom('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'), '37i9dQZF1DXcBWIGoYBM5M');
      expect(spotifyPlaylistIdFrom('https://open.spotify.com/album/37i9dQZF1DXcBWIGoYBM5M'), isNull);
      expect(spotifyPlaylistIdFrom('hello'), isNull);
    });

    test('summary wording', () {
      ImportResult r(int m, int t, [int? all]) => ImportResult(
          playlist: Playlist(id: 'x', name: 'x', imageUrl: '', tracks: const []), matched: m, total: t, spotifyTotal: all);
      expect(importSummary(r(3, 3)), 'All 3 songs matched');
      expect(importSummary(r(2, 3)), '2 of 3 matched · 1 will be looked up when played');
      expect(importSummary(r(0, 0)), 'No songs in this playlist');
      expect(importSummary(r(100, 100, 150)), 'All 100 songs matched · Spotify shared 100 of its 150 songs');
      expect(importSummary(r(3, 3, 3)), 'All 3 songs matched');
    });
  });

  group('matching', () {
    Track s(String title, String artist, [int? ms]) =>
        Track(id: 's', trackName: title, artistName: artist, albumName: '', previewUrl: '', durationMs: ms, source: 'spotify');

    test('the same song scores high whatever the decoration', () {
      expect(spotifyMatchScore(s('Bohemian Rhapsody - Remastered 2011', 'Queen', 354000),
          s('Bohemian Rhapsody', 'Queen', 355000)), greaterThan(0.9));
      expect(spotifyMatchScore(s('expectations (feat. Chappell Roan)', 'Olivia Rodrigo, Chappell Roan', 223000),
          s('expectations', 'Olivia Rodrigo', 224000)), greaterThan(0.9));
    });

    test('a cover or a different song stays below the bar', () {
      expect(spotifyMatchScore(s('Yellow', 'Coldplay', 266000), s('Yellow (Karaoke Version)', 'Sing King', 300000)),
          lessThan(kSpotifyMatchThreshold));
      expect(spotifyMatchScore(s('Yellow', 'Coldplay', 266000), s('Fix You', 'Coldplay', 295000)),
          lessThan(kSpotifyMatchThreshold));
    });

    test('a length far off rules it out', () {
      expect(spotifyMatchScore(s('Intro', 'The xx', 128000), s('Intro', 'The xx', 600000)), lessThan(0));
    });

    test('non-Latin titles still compare', () {
      expect(spotifyMatchScore(s('紅蓮華', 'LiSA', 239000), s('紅蓮華', 'LiSA', 240000)), greaterThan(0.9));
    });

    test('the best result is taken, not the first', () async {
      final pl = await SpotifyService(client: _api(), tokenProvider: () async => 'tok', search: _search)
          .getPlaylistWithTracks('p2', 'Gym', '');
      expect(pl.tracks.map((t) => t.id), ['yt_g1', 'yt_g2']);
    });
  });

  group('public link (no account)', () {
    SpotifyService service() =>
        SpotifyService(client: _publicApi(), tokenProvider: () async => throw 'no account', search: _search);

    test('parses the embed page: name, cover, songs, both artists', () async {
      final r = await service().getPublicPlaylistWithTracks('pubsmall');
      expect(r.playlist.name, 'Public Mix');
      expect(r.playlist.imageUrl, 'https://i.scdn.co/pub.jpg');
      expect(r.playlist.tracks.map((t) => t.id), ['yt_a1', 'yt_e1']);
      expect(r.playlist.tracks.first.artistName, 'Artist, Guest');
      expect(r.playlist.tracks[1].isExplicit, isTrue);
      expect(r.total, 2);
    });

    test('past 100 songs: the full list from spclient, the rest from track pages, in order', () async {
      final reading = <(int, int)>[];
      final r = await service().getPublicPlaylistWithTracks('publarge', onReading: (a, b) => reading.add((a, b)));
      expect(r.playlist.tracks, hasLength(102));
      expect(r.playlist.tracks[100].trackName, 'Song x1');
      expect(r.playlist.tracks[101].trackName, 'Song x2');
      expect(r.playlist.tracks[101].albumArtUrl, 'https://i.scdn.co/x2.jpg');
      expect(reading.last, (102, 102));
      expect(r.total, 102);
    });

    test('a private or missing playlist says so', () async {
      expect(() => service().getPublicPlaylistWithTracks('gone12345678'),
          throwsA(isA<SpotifyPublicException>().having((e) => e.message, 'message', contains('private'))));
    });

    test('pure parsers tolerate junk', () {
      expect(parseEmbedPlaylist('<html>no data</html>', 'x'), isNull);
      expect(parseEmbedTrack('<script id="__NEXT_DATA__" type="application/json">{bad</script>'), isNull);
      expect(parseSpclientPlaylist('[]').ids, isEmpty);
    });
  });

  group('screen', () {
    late MusicProvider p;

    setUpAll(() async {
      UserPlaylistDetailScreen.defaultUsePalette = false;
      SharedPreferences.setMockInitialValues({});
      final ready = Completer<void>();
      final original = debugPrint;
      debugPrint = (msg, {wrapWidth}) {
        if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) ready.complete();
      };
      p = MusicProvider();
      await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      debugPrint = original;
    });

    setUp(() {
      for (final pl in List.of(p.userPlaylists)) {
        p.deletePlaylistWithUndo(pl.id);
      }
    });

    Future<void> pump(WidgetTester tester,
        {bool configured = true, Size size = const Size(412, 1600), double scale = 1, SpotifyService? service}) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<MusicProvider>.value(value: p),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp(
          theme: GlassTheme.build(AccentColors.peach),
          builder: (c, child) =>
              MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: PlaylistImportScreen(
            configured: configured,
            service: service ?? SpotifyService(client: _api(), tokenProvider: () async => 'tok', search: _search),
          ),
        ),
      ));
      await tester.pump();
    }

    Future<void> realWait(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    testWidgets('Spotify only: no YouTube or Amazon routes', (tester) async {
      await pump(tester);
      expect(find.text('Import from Spotify'), findsWidgets);
      expect(find.textContaining('YouTube Music'), findsWidgets, reason: 'only as where songs are matched');
      expect(find.text('YouTube'), findsNothing);
      expect(find.textContaining('Amazon'), findsNothing);
    });

    testWidgets('without credentials it says so up front', (tester) async {
      await pump(tester, configured: false);
      expect(find.textContaining('isn\'t available in this build'), findsOneWidget);
      expect(find.text('Connect Spotify'), findsNothing);
      expect(find.byType(TextField), findsOneWidget, reason: 'a link still works');
    });

    testWidgets('without credentials a pasted public link imports', (tester) async {
      await pump(tester,
          configured: false,
          service: SpotifyService(client: _publicApi(), tokenProvider: () async => throw 'no account', search: _search));
      await tester.enterText(find.byType(TextField), 'https://open.spotify.com/playlist/pubsmall12345?si=x');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Import'));
      await realWait(tester);
      await realWait(tester);
      expect(p.playlistById('pubsmall12345')?.name, 'Public Mix');
      expect(p.playlistById('pubsmall12345')!.tracks, hasLength(2));
      expect(find.text('All 2 songs matched'), findsOneWidget);
    });

    testWidgets('connect, pick two, import: both saved with an honest summary', (tester) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Connect Spotify'));
      await realWait(tester);
      expect(find.text('Chill'), findsOneWidget);
      expect(find.text('Third'), findsOneWidget, reason: 'second page read');

      await tester.tap(find.text('Chill'));
      await tester.pump();
      await tester.tap(find.text('Gym'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // the import bar fades in
      await tester.tap(find.bySemanticsLabel('Import 2 playlists'));
      await realWait(tester);
      await realWait(tester);

      expect(p.playlistById('p1')!.tracks, hasLength(3));
      expect(p.playlistById('p2')!.tracks, hasLength(2));
      expect(find.text('2 of 3 matched · 1 will be looked up when played'), findsOneWidget);
      expect(find.text('All 2 songs matched'), findsOneWidget);
    });

    testWidgets('a pasted link imports; a bad link says why', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'https://open.spotify.com/album/xyz1234567890');
      await tester.tap(find.bySemanticsLabel('Import'));
      await tester.pump();
      expect(find.text('That doesn\'t look like a Spotify playlist link.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'https://open.spotify.com/playlist/linkedabcdefghij?si=1');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Import'));
      await realWait(tester);
      await realWait(tester);
      expect(p.playlistById('linkedabcdefghij')?.name, 'Linked');
      expect(p.playlistById('linkedabcdefghij')!.tracks, hasLength(1));
      expect(find.text('1 song matched'), findsOneWidget);
    });

    testWidgets('an already imported playlist is marked and re-import updates it', (tester) async {
      await tester.runAsync(() async {
        final s = SpotifyService(client: _api(), tokenProvider: () async => 'tok', search: _search);
        await p.importPlaylist(await s.getPlaylistWithTracks('p2', 'Gym', ''));
      });
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Connect Spotify'));
      await realWait(tester);
      expect(find.textContaining('Imported · importing again updates it'), findsOneWidget);
    });

    testWidgets('no layout errors at 360 dp, text x1.3', (tester) async {
      await pump(tester, size: const Size(360, 800), scale: 1.3);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Connect Spotify'));
      await realWait(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
