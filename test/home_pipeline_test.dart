import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/home/home_composer.dart';
import 'package:music_streaming_app/services/home/home_models.dart';
import 'package:music_streaming_app/services/home/ytm_home_source.dart';

HomeItem _song(String id, String title, String artist) => HomeItem(
      id: id,
      videoId: id,
      title: title,
      subtitle: artist,
      artworkUrl: 'https://example.com/$id.jpg',
      contentType: HomeContentType.song,
    );

HomeSection _shelf(String title, List<HomeItem> items) => HomeSection(
      id: 'id_$title',
      title: title,
      items: items,
      presentation: HomePresentation.artworkRail,
    );

HomeFeed _feed(String source, List<HomeSection> sections) => HomeFeed(
      sections: sections,
      fetchedAt: DateTime.now(),
      source: source,
    );

void main() {
  group('HomeComposer', () {
    test('validates: rejects items missing identity/title/artwork', () {
      final composer = const HomeComposer();
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          _shelf('Mixed', [
            _song('a1', 'Valid', 'Artist A'),
            _song('', 'No id', 'Artist A'), // rejected: no identity
            HomeItem(
              id: 'a2',
              title: '',
              subtitle: '',
              artworkUrl: 'https://example.com/a2.jpg',
              contentType: HomeContentType.song,
            ), // rejected: no title
            _song('a3', 'No artwork', 'Artist A').copyWithNoArtwork(),
            _song('a4', 'Also valid', 'Artist B'),
          ]),
        ]),
        fallback: null,
      );

      final items = feed!.sections.first.items;
      expect(items.map((i) => i.title), ['Valid', 'Also valid']);
    });

    test('cross-section dedupe keeps first appearance only', () {
      final composer = const HomeComposer();
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          _shelf('Shelf A', [
            _song('x1', 'Same Track', 'Artist A'),
            _song('x2', 'Other Track', 'Artist B'),
          ]),
          _shelf('Shelf B', [
            _song('x1', 'Same Track', 'Artist A'), // duplicate → rejected
          ]),
        ]),
        fallback: null,
      );

      // Shelf B dropped to 0 items after dedupe → collapses below the
      // 2-item floor; only Shelf A survives.
      expect(feed!.sections.length, 1);
      expect(feed.sections.single.title, 'Shelf A');
      expect(feed.sections.single.items.map((i) => i.id), ['x1', 'x2']);
    });

    test('artist diversity cap within a section', () {
      final composer = const HomeComposer(maxPerArtist: 2);
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          _shelf('Repetition', [
            _song('s1', 'One', 'Same Artist'),
            _song('s2', 'Two', 'Same Artist'),
            _song('s3', 'Three', 'Same Artist'), // capped
            _song('s4', 'Four', 'Other Artist'),
          ]),
        ]),
        fallback: null,
      );

      expect(feed!.sections.first.items.map((i) => i.title),
          ['One', 'Two', 'Four']);
    });

    test('source order preserved, never shuffled', () {
      final composer = const HomeComposer();
      final titles = List.generate(6, (i) => 'Track $i');
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          _shelf(
            'Order',
            List.generate(6, (i) => _song('o$i', titles[i], 'Artist $i')),
          ),
        ]),
        fallback: null,
      );

      expect(feed!.sections.first.items.map((i) => i.title).toList(), titles);
    });

    test('bad primary → fallback used wholesale (no merge)', () {
      final composer = const HomeComposer();
      final fallbackFeed = _feed('fallback', [
        _shelf('Trending', [
          _song('t1', 'Chart hit', 'Chart Artist'),
          _song('t3', 'Chart second', 'Other Chart Artist'),
        ]),
        _shelf('New releases', [
          _song('t2', 'Fresh drop', 'New Artist'),
          _song('t4', 'Fresh second', 'Another New Artist'),
        ]),
      ]);
      final feed =
          composer.compose(primary: fallbackFeed, fallback: fallbackFeed);
      expect(feed!.source, 'fallback');
      expect(feed.sections.map((s) => s.title), ['Trending', 'New releases']);
    });

    test('null inputs → null feed (UI falls back to legacy sections)', () {
      final composer = const HomeComposer();
      expect(composer.compose(primary: null, fallback: null), isNull);
    });
  });

  group('HomeRepository quality gate', () {
    test('feed with <2 sections fails the gate', () {
      final weak = _feed('ytm_home', [
        _shelf('Only one', [_song('s1', 'A', 'B'), _song('s2', 'C', 'D')]),
      ]);
      expect(HomeRepository.feedPassesQualityGate(weak), isFalse);
    });

    test('feed with <4 items total fails the gate', () {
      final weak = _feed('ytm_home', [
        _shelf('A', [_song('s1', 'A', 'B'), _song('s2', 'C', 'D')]),
        _shelf('B', [_song('s3', 'E', 'F')]),
      ]);
      expect(HomeRepository.feedPassesQualityGate(weak), isFalse);
    });

    test('healthy feed passes the gate', () {
      final healthy = _feed('ytm_home', [
        _shelf('A', [
          _song('s1', 'A', 'B'),
          _song('s2', 'C', 'D'),
          _song('s3', 'E', 'F'),
        ]),
        _shelf('B', [
          _song('s4', 'G', 'H'),
          _song('s5', 'I', 'J'),
        ]),
      ]);
      expect(HomeRepository.feedPassesQualityGate(healthy), isTrue);
    });

    test('section with empty title fails the gate', () {
      final bad = _feed('ytm_home', [
        _shelf('', [_song('s1', 'A', 'B'), _song('s2', 'C', 'D')]),
        _shelf('B', [_song('s3', 'E', 'F'), _song('s4', 'G', 'H')]),
      ]);
      expect(HomeRepository.feedPassesQualityGate(bad), isFalse);
    });
  });

  group('HomeFeed cache roundtrip', () {
    test('toJson → fromJson preserves sections, items, types', () {
      final feed = _feed('ytm_home', [
        _shelf('Listen again', [
          _song('BddP6PYotfs', 'Kesariya', 'Arijit Singh'),
          HomeItem(
            id: 'MPREb_album1',
            browseId: 'MPREb_album1',
            title: 'Some Album',
            subtitle: 'Album • Artist',
            artworkUrl: 'https://example.com/al.jpg',
            contentType: HomeContentType.album,
          ),
        ]),
        _shelf('Artists', [
          HomeItem(
            id: 'UCartist1',
            browseId: 'UCartist1',
            title: 'Artist',
            subtitle: 'Artist',
            artworkUrl: 'https://example.com/ar.jpg',
            contentType: HomeContentType.artist,
          ),
        ]),
      ]);

      final json = feed.toJson();
      final restored = HomeFeed.fromJson(json);

      expect(restored, isNotNull);
      expect(restored!.source, 'ytm_home');
      expect(restored.sections.length, 2);
      expect(restored.sections[0].title, 'Listen again');
      expect(restored.sections[0].items.first.id, 'BddP6PYotfs');
      expect(
          restored.sections[0].items.last.contentType, HomeContentType.album);
      expect(
          restored.sections[1].items.first.contentType, HomeContentType.artist);
    });

    test('wrong schema version invalidates cache', () {
      final feed = _feed('ytm_home', [
        _shelf('A', [_song('s1', 'A', 'B'), _song('s2', 'C', 'D')]),
      ]);
      final json = feed.toJson();
      json['schema'] = 1; // stale v1 snapshot from the old parser
      expect(HomeFeed.fromJson(json), isNull);
    });

    test('corrupt JSON cannot produce a feed', () {
      expect(HomeFeed.fromJson(null), isNull);
      expect(
          HomeFeed.fromJson({'schema': 2, 'sections': 'not-a-list'}), isNull);
    });
  });
}

extension _NoArt on HomeItem {
  HomeItem copyWithNoArtwork() => HomeItem(
        id: id,
        videoId: videoId,
        browseId: browseId,
        title: title,
        subtitle: subtitle,
        artworkUrl: '',
        contentType: contentType,
      );
}
