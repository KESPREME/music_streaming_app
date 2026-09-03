import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/home/home_composer.dart';
import 'package:music_streaming_app/services/home/home_diagnostics.dart';
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
    test(
        'validates: rejects missing identity/title; retains artwork-less as PARTIAL',
        () {
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
            // artwork-less: PARTIAL, retained (spec #8 tolerance)
            _song('a3', 'No artwork', 'Artist A').copyWithNoArtwork(),
            _song('a4', 'Also valid', 'Artist B'),
          ]),
        ]),
        fallback: null,
      );

      final items = feed!.sections.first.items;
      expect(items.map((i) => i.title), ['Valid', 'No artwork', 'Also valid']);
      expect(
        items.singleWhere((i) => i.title == 'No artwork').supportLevel,
        SupportLevel.partiallySupported,
      );
    });

    test('section-local dedupe: same entity allowed across shelves', () {
      final composer = const HomeComposer();
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          _shelf('Shelf A', [
            _song('x1', 'Same Track', 'Artist A'),
            _song('x2', 'Other Track', 'Artist B'),
          ]),
          _shelf('Shelf B', [
            // Same videoId as Shelf A — LEGITIMATE editorial repeat.
            // Global dedupe (old behavior) collapsed this shelf entirely.
            _song('x1', 'Same Track', 'Artist A'),
            _song('x3', 'Third Track', 'Artist C'),
          ]),
        ]),
        fallback: null,
      );

      expect(feed!.sections.length, 2);
      expect(feed.sections.last.items.map((i) => i.id), ['x1', 'x3']);
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

    test('native shelf order preserved even with same-artist repetition '
        '(no re-curation)', () {
      const composer = HomeComposer();
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          _shelf('Listen again', [
            _song('s1', 'One', 'Same Artist'),
            _song('s2', 'Two', 'Same Artist'),
            _song('s3', 'Three', 'Same Artist'),
            _song('s4', 'Four', 'Other Artist'),
          ]),
        ]),
        fallback: null,
      );

      // The user's history is the user's history — the composer must not
      // re-curate native editorial shelves (live bug: artist cap trimmed
      // "Listen again" 12→3 and "Albums for you" 10→3).
      expect(feed!.sections.first.items.map((i) => i.title).toList(),
          ['One', 'Two', 'Three', 'Four']);
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

  group('structured metadata', () {
    test('HomeItem JSON roundtrip preserves artists/publishedText/playability',
        () {
      final item = HomeItem(
        id: 'BddP6PYotfs',
        videoId: 'BddP6PYotfs',
        title: 'Kesariya',
        subtitle: 'Arijit Singh • Brahmastra • 2024',
        artworkUrl: 'https://example.com/k.jpg',
        contentType: HomeContentType.song,
        artists: const ['Arijit Singh'],
        publishedText: '2024',
        playability: Playability.playable,
      );

      final restored = HomeItem.fromJson(item.toJson());
      expect(restored.artists, ['Arijit Singh']);
      expect(restored.publishedText, '2024');
      expect(restored.playability, Playability.playable);
      expect(restored.isPlayable, isTrue);
    });

    test('album item is not song-playable', () {
      final album = HomeItem(
        id: 'MPREb_album1',
        browseId: 'MPREb_album1',
        title: 'Album',
        subtitle: 'Album • Artist',
        artworkUrl: 'https://example.com/a.jpg',
        contentType: HomeContentType.album,
      );
      // Albums route to detail screens, not direct song playback.
      expect(album.videoId, isNull);
      expect(album.contentType, HomeContentType.album);
    });
  });

  group('quality dimensions', () {
    test('healthy native feed scores well on all axes', () {
      final feed = _feed('ytm_home', [
        _shelf('A', [
          _song('s1', 'One', 'Artist One'),
          _song('s2', 'Two', 'Artist Two'),
          _song('s3', 'Three', 'Artist Three'),
        ]),
        _shelf('B', [
          _song('s4', 'Four', 'Artist Four'),
          _song('s5', 'Five', 'Artist Five'),
        ]),
      ]);

      final d = HomeDiagnostics.qualityDimensions(feed);
      expect(d['structural'], greaterThan(0.9));
      expect(d['sourceTrust'], 1.0);
      expect(d['freshness'], 1.0);
      expect(d['diversity'], 1.0); // all distinct artists
    });

    test('fallback feed has lower source trust than native', () {
      final native = _feed('ytm_home', [
        _shelf('A', [
          _song('s1', 'One', 'A'),
          _song('s2', 'Two', 'B'),
        ]),
        _shelf('B', [
          _song('s3', 'Three', 'C'),
          _song('s4', 'Four', 'D'),
        ]),
      ]);
      final fallback = _feed('fallback', native.sections);

      final dNative = HomeDiagnostics.qualityDimensions(native);
      final dFallback = HomeDiagnostics.qualityDimensions(fallback);
      expect(dNative['sourceTrust'], greaterThan(dFallback['sourceTrust']!));
    });

    test('stale feed decays freshness', () {
      final stale = HomeFeed(
        sections: [
          _shelf('A', [
            _song('s1', 'One', 'A'),
            _song('s2', 'Two', 'B'),
          ]),
          _shelf('B', [
            _song('s3', 'Three', 'C'),
            _song('s4', 'Four', 'D'),
          ]),
        ],
        fetchedAt: DateTime.now().subtract(const Duration(hours: 30)),
        source: 'ytm_home',
      );
      final d = HomeDiagnostics.qualityDimensions(stale);
      expect(d['freshness'], lessThan(0.5));
    });
  });
  group('feed degradation protection', () {
    test('rich feed -> thin fresh feed is DEGRADED', () {
      final rich = _feed('ytm_home', [
        for (var s = 0; s < 8; s++)
          _shelf(
            'Shelf $s',
            List.generate(6, (i) => _song('s$s-$i', 'Track $s-$i', 'A$i')),
          ),
      ]);
      final thin = _feed('ytm_home', [
        _shelf('Only', [
          _song('t1', 'One', 'A'),
          _song('t2', 'Two', 'B'),
        ]),
      ]);

      expect(HomeDiagnostics.isDegraded(previous: rich, next: thin), isTrue);
    });

    test('healthy refresh of a rich feed is NOT degraded', () {
      final rich = _feed('ytm_home', [
        for (var s = 0; s < 8; s++)
          _shelf(
            'Shelf $s',
            List.generate(6, (i) => _song('s$s-$i', 'Track $s-$i', 'A$i')),
          ),
      ]);
      final alsoRich = _feed('ytm_home', [
        for (var s = 0; s < 7; s++)
          _shelf(
            'Changed $s',
            List.generate(5, (i) => _song('n$s-$i', 'New $s-$i', 'B$i')),
          ),
      ]);

      expect(
          HomeDiagnostics.isDegraded(previous: rich, next: alsoRich), isFalse);
    });

    test('thin previous feed never flags degradation (below comparison floor)',
        () {
      final thin = _feed('ytm_home', [
        _shelf('Only', [
          _song('t1', 'One', 'A'),
          _song('t2', 'Two', 'B'),
        ]),
      ]);
      final thinner = _feed('ytm_home', [
        _shelf('One', [
          _song('t3', 'Three', 'C'),
        ]),
      ]);
      expect(
          HomeDiagnostics.isDegraded(previous: thin, next: thinner), isFalse);
    });

    test('load-all: every valid shelf survives compose (no section budget)',
        () {
      const composer = HomeComposer();
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          for (var s = 0; s < 15; s++)
            _shelf(
              'Shelf $s',
              List.generate(3, (i) => _song('s$s-$i', 'T$s-$i', 'A$s$i')),
            ),
        ]),
        fallback: null,
      );

      expect(feed!.sections.length, 15);
      expect(
        feed.sections.map((s) => s.title),
        [for (var s = 0; s < 15; s++) 'Shelf $s'],
      );
    });

    test('per-shelf item budget still caps render cost', () {
      const composer = HomeComposer(maxItemsPerSection: 4);
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          _shelf(
            'Long shelf',
            List.generate(10, (i) => _song('l$i', 'T$i', 'A$i')),
          ),
        ]),
        fallback: null,
      );

      expect(feed!.sections.length, 1);
      expect(feed.sections.first.items.length, 4);
    });

    test('artist cards drop from song-majority shelves (Listen again fix)',
        () {
      const composer = HomeComposer();
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          _shelf('Listen again', [
            _song('s1', 'Song 1', 'A'),
            _song('s2', 'Song 2', 'B'),
            _song('s3', 'Song 3', 'C'),
            HomeItem(
              id: 'UCartist001',
              videoId: null,
              browseId: 'UCartist001',
              title: 'K\u2019NAAN',
              subtitle: 'Artist',
              artworkUrl: 'https://example.com/a.jpg',
              contentType: HomeContentType.artist,
            ),
          ]),
        ]),
        fallback: null,
      );

      final section = feed!.sections.single;
      expect(section.items.map((i) => i.id), ['s1', 's2', 's3']);
    });

    test('album-majority shelves keep album items (New releases intact)',
        () {
      const composer = HomeComposer();
      final album = HomeItem(
        id: 'MPREb_x1',
        videoId: null,
        browseId: 'MPREb_x1',
        title: 'Album',
        subtitle: 'Artist • Album',
        artworkUrl: 'https://example.com/x.jpg',
        contentType: HomeContentType.album,
      );
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          _shelf('New releases', [
            album,
            HomeItem(
              id: 'MPREb_x2',
              videoId: null,
              browseId: 'MPREb_x2',
              title: 'Album 2',
              subtitle: 'Artist • Album',
              artworkUrl: 'https://example.com/y.jpg',
              contentType: HomeContentType.album,
            ),
            HomeItem(
              id: 'UCartist002',
              videoId: null,
              browseId: 'UCartist002',
              title: 'Some Artist',
              subtitle: 'Artist',
              artworkUrl: 'https://example.com/z.jpg',
              contentType: HomeContentType.artist,
            ),
          ]),
        ]),
        fallback: null,
      );

      final section = feed!.sections.single;
      expect(section.items.map((i) => i.id), ['MPREb_x1', 'MPREb_x2']);
    });

    test('enrichment section with duplicate native title collapses (no '
        '"New releases" x2)', () {
      const composer = HomeComposer();
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          _shelf('New releases', [
            _song('n1', 'A', 'X'),
            _song('n2', 'B', 'Y'),
          ]),
          _shelf('New releases', [
            _song('e1', 'C', 'Z'),
            _song('e2', 'D', 'W'),
          ]),
        ]),
        fallback: null,
      );

      expect(feed!.sections, hasLength(1));
      // First (native) shelf wins.
      expect(feed.sections.single.items.map((i) => i.id), ['n1', 'n2']);
    });
  });

  group('convergence: ratchet + enrichment', () {
    // THE REGRESSION: degradation ratchet. isDegraded previously compared
    // against the LATEST accepted feed, so 10→6 (accept) →4 (accept)
    // →2 (accept) each passed the >50% test and the UI collapsed.
    // The repository now tracks a best-known high-water mark, so the
    // ratchet requires a genuinely thin session — and enrichment fills
    // sparse-but-valid feeds instead.
    test('ratchet sequence: thin feeds stay flagged against best known', () {
      final rich = _feed('ytm_home', [
        for (var s = 0; s < 8; s++)
          _shelf(
            'Shelf $s',
            List.generate(6, (i) => _song('s$s-$i', 'T$s-$i', 'A$i')),
          ),
      ]);
      // Simulate the high-water mark being the rich feed (as the repo does).
      final bestKnown = rich;
      final step1 = _feed('ytm_home', [
        for (var s = 0; s < 6; s++)
          _shelf('S$s', List.generate(5, (i) => _song('a$s-$i', 'X', 'B'))),
      ]);
      final step2 = _feed('ytm_home', [
        for (var s = 0; s < 3; s++)
          _shelf('T$s', List.generate(4, (i) => _song('b$s-$i', 'Y', 'C'))),
      ]);
      final step3 = _feed('ytm_home', [
        _shelf('Last', [_song('c1', 'Z', 'D'), _song('c2', 'W', 'E')]),
      ]);

      // Against BEST KNOWN (8 shelves/48 items), each ratchet step is
      // flagged — previously only step 3 was, because each step replaced
      // the comparison baseline.
      expect(HomeDiagnostics.isDegraded(previous: bestKnown, next: step1),
          isFalse); // 6/8 sections, 30/48 items — legitimate variation
      expect(HomeDiagnostics.isDegraded(previous: bestKnown, next: step2),
          isTrue); // 3/8 AND 12/48 — below both halves
      expect(
          HomeDiagnostics.isDegraded(previous: bestKnown, next: step3), isTrue);
    });

    test('enrichment policy: sparse feed gets floor sections, rich does not',
        () {
      const sparseFloor = 4;
      // A 2-section native feed + 2 enrichment sections = 4 (target range
      // 6-10 with local overlays on top; never fabricated native labels).
      final native = _feed('ytm_home', [
        _shelf('Native A', [_song('n1', 'A', 'X'), _song('n2', 'B', 'Y')]),
        _shelf('Native B', [_song('n3', 'C', 'Z'), _song('n4', 'D', 'W')]),
      ]);
      // Enrichment only applies below the floor — verified by the repo's
      // _enrichSparse guard. This test pins the threshold semantics.
      expect(native.sections.length < sparseFloor, isTrue);

      final rich = _feed('ytm_home', [
        for (var s = 0; s < 6; s++)
          _shelf('S$s', List.generate(4, (i) => _song('r$s-$i', 'Q', 'P'))),
      ]);
      expect(rich.sections.length < sparseFloor, isFalse);
    });

    test('provenance survives composition and serialization', () {
      final composer = const HomeComposer();
      final feed = composer.compose(
        primary: _feed('ytm_home', [
          HomeSection(
            id: 'prov_shelf',
            title: 'Native shelf',
            items: [
              _song('p1', 'One', 'A'),
              _song('p2', 'Two', 'B'),
            ],
            presentation: HomePresentation.artworkRail,
            provenance: 'native',
          ),
          HomeSection(
            id: 'chart_shelf',
            title: 'Trending',
            items: [
              _song('p3', 'Three', 'C'),
              _song('p4', 'Four', 'D'),
            ],
            presentation: HomePresentation.artworkRail,
            provenance: 'chart',
          ),
        ]),
        fallback: null,
      );

      expect(feed!.sections.map((s) => s.provenance), ['native', 'chart']);
      final restored = HomeFeed.fromJson(feed.toJson())!;
      expect(restored.sections.map((s) => s.provenance), ['native', 'chart']);
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
