import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/bitchord_page_models.dart';
import 'package:music_streaming_app/presentation/explore/explore_feed_card.dart' show exploreBackdropUrl;
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/screens/artist_detail_screen.dart';
import 'package:music_streaming_app/utils/image_quality_utils.dart';
import 'package:music_streaming_app/widgets/fallback_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// COVERS THAT ALWAYS LOAD.
///
/// An artist opened from Now Playing arrives with only a NAME and no picture, and
/// every failure on the way (the lookup, the browse, the image host) ended in a flat
/// colour. Video thumbnails were rewritten into links that do not exist. These pin
/// the rules and the chain.

void main() {
  group('ImageQualityUtils', () {
    test('a signed video thumbnail is left exactly as the source signed it', () {
      const signed = 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg?sqp=-oaym&rs=AMzJL3';
      expect(ImageQualityUtils.getHighResArtwork(signed), signed,
          reason: 'editing the path under a signature gets the request refused');
    });

    test('an unsigned one is upgraded - and the original is kept as the fallback', () {
      const plain = 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg';
      expect(ImageQualityUtils.getHighResArtwork(plain), 'https://i.ytimg.com/vi/abcdefghijk/maxresdefault.jpg');
      expect(ImageQualityUtils.candidates(plain), [
        'https://i.ytimg.com/vi/abcdefghijk/maxresdefault.jpg',
        plain,
      ]);
    });

    test('a link with nothing to upgrade has one candidate; empty has none', () {
      expect(ImageQualityUtils.candidates('https://example.com/a.jpg'), ['https://example.com/a.jpg']);
      expect(ImageQualityUtils.candidates(''), isEmpty);
      expect(ImageQualityUtils.candidates(null), isEmpty);
      expect(ImageQualityUtils.candidates('   '), isEmpty);
    });

    test('a protocol-relative link becomes https', () {
      expect(ImageQualityUtils.getHighResArtwork('//lh3.googleusercontent.com/abc=w60-h60'),
          startsWith('https://lh3.googleusercontent.com/abc=w1200'));
      expect(ImageQualityUtils.candidates('//example.com/a.jpg'), ['https://example.com/a.jpg']);
    });

    test('Google user content still goes up to 1200', () {
      expect(ImageQualityUtils.getHighResArtwork('https://lh3.googleusercontent.com/abc=w60-h60-l90-rj'),
          'https://lh3.googleusercontent.com/abc=w1200-h1200-l90-rj');
    });
  });

  group('Explore backdrop links', () {
    test('every size name goes to mqdefault, once', () {
      for (final name in ['default', 'mqdefault', 'hqdefault', 'sddefault', 'maxresdefault']) {
        expect(exploreBackdropUrl('https://i.ytimg.com/vi/abcdefghijk/$name.jpg'),
            'https://i.ytimg.com/vi/abcdefghijk/mqdefault.jpg',
            reason: name);
      }
    });

    test('the old rule produced mqmqdefault.jpg; no name is ever doubled', () {
      final out = exploreBackdropUrl('https://i.ytimg.com/vi/abcdefghijk/sddefault.jpg');
      expect(out, isNot(contains('mqmq')));
      expect(out, isNot(contains('sdmq')));
    });

    test('a signed link is left alone', () {
      const signed = 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg?sqp=x&rs=y';
      expect(exploreBackdropUrl(signed), signed);
    });
  });

  group('FallbackNetworkImage', () {
    /// A loader that fails the links in [bad] and "loads" the rest as a labelled box.
    Widget host(List<String> urls, Set<String> bad) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              height: 100,
              child: FallbackNetworkImage(
                urls: urls,
                placeholder: const Text('PLACEHOLDER'),
                debugLoader: (context, url, onError) {
                  if (bad.contains(url)) {
                    // What an image's error builder does: report, show the placeholder.
                    WidgetsBinding.instance.addPostFrameCallback((_) => onError());
                    return const Text('PLACEHOLDER');
                  }
                  return Text('LOADED $url');
                },
              ),
            ),
          ),
        );

    testWidgets('a failed first link falls through to the second', (tester) async {
      await tester.pumpWidget(host(['https://img.test/a.jpg', 'https://img.test/b.jpg'], {'https://img.test/a.jpg'}));
      await tester.pump();
      await tester.pump();
      expect(find.text('LOADED https://img.test/b.jpg'), findsOneWidget, reason: 'it tried the next link');
    });

    testWidgets('a good first link is the only one used', (tester) async {
      await tester.pumpWidget(host(['https://img.test/a.jpg', 'https://img.test/b.jpg'], {}));
      await tester.pump();
      expect(find.text('LOADED https://img.test/a.jpg'), findsOneWidget);
      expect(find.textContaining('b.jpg'), findsNothing);
    });

    testWidgets('with every link bad it settles on the placeholder (and stops trying)', (tester) async {
      await tester.pumpWidget(host(
        ['https://img.test/a.jpg', 'https://img.test/b.jpg'],
        {'https://img.test/a.jpg', 'https://img.test/b.jpg'},
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(find.text('PLACEHOLDER'), findsOneWidget);
      expect(find.textContaining('LOADED'), findsNothing);
    });

    testWidgets('a different picture starts again from its best link', (tester) async {
      await tester.pumpWidget(host(['https://img.test/a.jpg', 'https://img.test/b.jpg'], {'https://img.test/a.jpg'}));
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(host(['https://img.test/c.jpg', 'https://img.test/d.jpg'], {}));
      await tester.pump();
      expect(find.text('LOADED https://img.test/c.jpg'), findsOneWidget);
    });

    testWidgets('no links at all is the placeholder, not a crash', (tester) async {
      await tester.pumpWidget(host(const [], {}));
      expect(find.text('PLACEHOLDER'), findsOneWidget);
    });

    testWidgets('empty and duplicate entries are ignored', (tester) async {
      await tester.pumpWidget(host(['', 'https://img.test/a.jpg', '  '], {}));
      expect(find.text('LOADED https://img.test/a.jpg'), findsOneWidget);
    });
  });
  group('the artist page', () {
    late MusicProvider p;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // The image cache asks the platform for a folder; a test has no platform.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path,
      );
      SharedPreferences.setMockInitialValues({});
      final ready = Completer<void>();
      final original = debugPrint;
      debugPrint = (msg, {wrapWidth}) {
        if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) ready.complete();
      };
      p = _NoNetworkProvider();
      await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      debugPrint = original;
    });

    Future<void> pumpArtist(WidgetTester tester, {String? fallback}) async {
      // The test binding answers every image request with a 400, which Flutter
      // reports as an error. That IS the situation under test (a picture that will
      // not load); only that report is let through.
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.library == 'image resource service') return;
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);
      tester.view.physicalSize = const Size(1200, 2700);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<MusicProvider>.value(
        value: p,
        child: MaterialApp(
          home: ArtistDetailScreen(
            artistId: 'artist_Tame Impala',
            artistName: 'Tame Impala',
            searchByName: true,
            fallbackImage: fallback,
          ),
        ),
      ));
      // The lookup fails (no network in tests); let the page settle on that.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// The page's palette lookup has a timeout of its own: let it run out.
    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
    }

    testWidgets('when the lookup fails, the hero is the song\'s cover, not a blank box', (tester) async {
      await pumpArtist(tester, fallback: 'https://img.test/song-cover.jpg');
      final photo = tester.widget<FallbackNetworkImage>(find.byType(FallbackNetworkImage).first);
      expect(photo.urls, contains('https://img.test/song-cover.jpg'));
      await drain(tester);
    });

    testWidgets('with no fallback it is the plain colour, as before', (tester) async {
      await pumpArtist(tester);
      expect(find.byType(FallbackNetworkImage), findsNothing);
      await drain(tester);
    });
  });
}

/// The real provider, with the two lookups the artist page makes answered as a dead
/// connection would answer them.
class _NoNetworkProvider extends MusicProvider {
  @override
  Future<ArtistDetailData> fetchArtistPageData(String browseId) async =>
      throw Exception('offline');
}
