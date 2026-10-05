import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/presentation/home/home_playback.dart';
import 'package:music_streaming_app/services/home/home_convergence.dart';
import 'package:music_streaming_app/services/home/home_models.dart';
import 'package:music_streaming_app/services/home/ytm_home_source.dart'
    show HomeLoadTrace;

HomeItem _song(String id, String title, String artist) => HomeItem(
      id: id,
      videoId: id,
      title: title,
      subtitle: artist,
      artworkUrl: 'https://example.com/$id.jpg',
      contentType: HomeContentType.song,
    );

HomeSection _shelf(String title, List<HomeItem> items, {String? provenance}) =>
    HomeSection(
      id: 'id_$title',
      title: title,
      items: items,
      presentation: HomePresentation.artworkRail,
      provenance: provenance,
    );

HomeFeed _feed(String source, List<HomeSection> sections) => HomeFeed(
      sections: sections,
      fetchedAt: DateTime.now(),
      source: source,
    );

Map<String, SectionMemoryEntry> _memoryFrom(HomeFeed feed) => {
      for (final s in feed.sections)
        SectionIdentity.forSection(s): SectionMemoryEntry(
          section: s,
          identity: SectionIdentity.forSection(s),
          cachedAt: DateTime.now(),
        ),
    };

void main() {
  group('SectionIdentity (spec #4)', () {
    test('history titles all resolve to the same "recent" slug', () {
      // Load-bearing: this slug is what decides a feed shelf gets the
      // rows/cards toggle. If a reordering of the `contains` checks in
      // semanticSlug ever lets one of these fall through, the toggle silently
      // disappears from a shelf the user can plainly see it on.
      for (final title in const [
        'Listen again',
        'Recents',
        'Jump back in',
        'Recently played',
        'LISTEN AGAIN', // case must not matter
      ]) {
        expect(
          SectionIdentity.semanticSlug(_shelf(title, [_song('a1', 'T', 'X')])),
          'recent',
          reason: '"$title" should be classified as history',
        );
      }
    });

    test('non-history titles are NOT classified as recent', () {
      // The flip side: too loose a match would hand the toggle to every shelf
      // on the page, which is noise rather than a feature.
      for (final title in const [
        'New releases',
        'Charts & Trending',
        'Your playlists',
        'Moods & genres',
      ]) {
        expect(
          SectionIdentity.semanticSlug(_shelf(title, [_song('a1', 'T', 'X')])),
          isNot('recent'),
          reason: '"$title" is not a history shelf',
        );
      }
    });

    test('index-independent: same title → same identity across requests', () {
      final requestA = _shelf('New releases', [
        _song('a1', 'Old', 'X'),
        _song('a2', 'Old2', 'Y'),
      ]);
      final requestB = _shelf('New releases', [
        _song('b1', 'New', 'X'),
        _song('b2', 'New2', 'Y'),
      ]);
      expect(SectionIdentity.forSection(requestA),
          SectionIdentity.forSection(requestB));
    });

    test('index-safe: different titles → different identities', () {
      final newReleases = _shelf('New releases', [
        _song('a1', 'Old', 'X'),
        _song('a2', 'Old2', 'Y'),
      ]);
      final trending = _shelf('Trending', [
        _song('a1', 'Old', 'X'),
        _song('a2', 'Old2', 'Y'),
      ]);
      expect(SectionIdentity.forSection(newReleases),
          isNot(SectionIdentity.forSection(trending)));
    });

    test('provenance-qualified: enrichment Trending ≠ native Trending', () {
      final native = _shelf('Trending', [
        _song('a1', 'Old', 'X'),
        _song('a2', 'Old2', 'Y'),
      ]);
      final chart = _shelf(
          'Trending',
          [
            _song('a1', 'Old', 'X'),
            _song('a2', 'Old2', 'Y'),
          ],
          provenance: 'chart');
      expect(SectionIdentity.forSection(native),
          isNot(SectionIdentity.forSection(chart)));
    });
  });

  group('Section memory convergence (spec #9/#12)', () {
    test('A B C D + fresh A C D → A\' B(prev) C\' D\'', () {
      final previousFeed = _feed('ytm_home', [
        _shelf('A', [_song('a1', 'A1', 'X'), _song('a2', 'A2', 'X')]),
        _shelf('B', [_song('b1', 'B1', 'X'), _song('b2', 'B2', 'X')]),
        _shelf('C', [_song('c1', 'C1', 'X'), _song('c2', 'C2', 'X')]),
        _shelf('D', [_song('d1', 'D1', 'X'), _song('d2', 'D2', 'X')]),
      ]);
      final memory = _memoryFrom(previousFeed);
      final previousOrder =
          previousFeed.sections.map(SectionIdentity.forSection).toList();

      final fresh = _feed('ytm_home', [
        _shelf('A', [_song('a1n', 'A1-new', 'X'), _song('a2n', 'A2-new', 'X')]),
        _shelf('C', [_song('c1n', 'C1-new', 'X'), _song('c2n', 'C2-new', 'X')]),
        _shelf('D', [_song('d1n', 'D1-new', 'X'), _song('d2n', 'D2-new', 'X')]),
      ]);

      final converged = const HomeConvergence().convergeWithOrder(
        fresh: fresh,
        memory: memory,
        previousOrder: previousOrder,
      );

      final titles = converged.sections.map((s) => s.title).toList();
      // B retained at position 2 (spec #10 positional stability).
      expect(titles, ['A', 'B', 'C', 'D']);
      // Fresh content inside retained-position sections (spec #11).
      expect(
        converged.sections.firstWhere((s) => s.title == 'A').items.first.title,
        'A1-new',
      );
    });

    test('same identity fresh content replaces items — no duplicate shelf', () {
      final memory = _memoryFrom(_feed('ytm_home', [
        _shelf('New Releases', [
          _song('old1', 'A', 'X'),
          _song('old2', 'B', 'X'),
          _song('old3', 'C', 'X'),
        ]),
      ]));

      final fresh = _feed('ytm_home', [
        _shelf('New Releases', [
          _song('new1', 'D', 'X'),
          _song('new2', 'E', 'X'),
          _song('new3', 'F', 'X'),
        ]),
      ]);

      final converged = const HomeConvergence().converge(
        fresh: fresh,
        memory: memory,
      );

      expect(converged!.sections.length, 1);
      expect(
          converged.sections.first.items.map((i) => i.title), ['D', 'E', 'F']);
    });

    test('expired remembered section is REMOVED, not retained', () {
      final stale = _feed('ytm_home', [
        _shelf('Trending', [
          _song('t1', 'Old chart', 'X'),
          _song('t2', 'Old chart2', 'X'),
        ]),
      ]);
      // Age the entry beyond the trending TTL (3h).
      final memory = {
        for (final s in stale.sections)
          SectionIdentity.forSection(s): SectionMemoryEntry(
            section: s,
            identity: SectionIdentity.forSection(s),
            cachedAt: DateTime.now().subtract(const Duration(hours: 4)),
          ),
      };

      final fresh = _feed('ytm_home', [
        _shelf('Other', [_song('o1', 'X', 'Y'), _song('o2', 'Z', 'Y')]),
      ]);

      final converged = const HomeConvergence().converge(
        fresh: fresh,
        memory: memory,
      );
      expect(converged!.sections.map((s) => s.title), ['Other']);
    });

    test('malformed remembered section is REMOVED', () {
      final broken = _feed('ytm_home', [
        _shelf('Broken', []),
      ]);
      final memory = {
        for (final s in broken.sections)
          SectionIdentity.forSection(s): SectionMemoryEntry(
            section: s,
            identity: SectionIdentity.forSection(s),
            cachedAt: DateTime.now(),
          ),
      };

      final fresh = _feed('ytm_home', [
        _shelf('Good', [_song('g1', 'X', 'Y'), _song('g2', 'Z', 'Y')]),
      ]);

      final converged = const HomeConvergence().converge(
        fresh: fresh,
        memory: memory,
      );
      expect(converged!.sections.map((s) => s.title), ['Good']);
    });

    test('ratchet sequence 8→6→3→2 never collapses below memory', () {
      var feed = _feed('ytm_home', [
        for (var s = 0; s < 8; s++)
          _shelf(
            'Shelf $s',
            List.generate(6, (i) => _song('s$s-$i', 'T$s-$i', 'A$i')),
          ),
      ]);
      var memory = _memoryFrom(feed);
      const convergence = HomeConvergence();

      // Refresh 1: 6 sections (2 omitted)
      var fresh = _feed('ytm_home', [
        for (var s = 0; s < 6; s++)
          _shelf(
            'Shelf $s',
            List.generate(6, (i) => _song('s$s-$i', 'T$s-$i', 'A$i')),
          ),
      ]);
      feed = convergence.converge(fresh: fresh, memory: memory)!;
      expect(feed.sections.length, 8);
      memory = _memoryFrom(feed);

      // Refresh 2: 3 sections (5 omitted)
      fresh = _feed('ytm_home', [
        for (var s = 0; s < 3; s++)
          _shelf(
            'Shelf $s',
            List.generate(6, (i) => _song('s$s-$i', 'T$s-$i', 'A$i')),
          ),
      ]);
      feed = convergence.converge(fresh: fresh, memory: memory)!;
      expect(feed.sections.length, 8);

      // Refresh 3: 2 sections (6 omitted)
      fresh = _feed('ytm_home', [
        _shelf(
          'Shelf 0',
          List.generate(6, (i) => _song('s0-$i', 'T0-$i', 'A0')),
        ),
        _shelf(
          'Shelf 1',
          List.generate(6, (i) => _song('s1-$i', 'T1-$i', 'A1')),
        ),
      ]);
      feed = convergence.converge(fresh: fresh, memory: memory)!;
      // All 8 categories survive the upstream thinning.
      expect(feed.sections.length, 8);
    });
  });

  group('HomePlaybackController routing (spec #29/#30)', () {
    test('song with videoId → playSong', () {
      final item = _song('abc12345678', 'Song', 'Artist');
      expect(HomePlaybackController.actionFor(item), HomePlayAction.playSong);
    });

    test('video with videoId → playVideo', () {
      final item = HomeItem(
        id: 'abc12345678',
        videoId: 'abc12345678',
        title: 'Video',
        subtitle: 'Channel',
        artworkUrl: 'https://example.com/v.jpg',
        contentType: HomeContentType.video,
      );
      expect(HomePlaybackController.actionFor(item), HomePlayAction.playVideo);
    });

    test('playlist with browseId → navigateCollection', () {
      final item = HomeItem(
        id: 'VLPLabc',
        browseId: 'VLPLabc',
        title: 'Playlist',
        subtitle: 'Curator',
        artworkUrl: 'https://example.com/p.jpg',
        contentType: HomeContentType.playlist,
      );
      expect(HomePlaybackController.actionFor(item),
          HomePlayAction.navigateCollection);
    });

    test('album with browseId → navigateCollection', () {
      final item = HomeItem(
        id: 'MPREb_abc',
        browseId: 'MPREb_abc',
        title: 'Album',
        subtitle: 'Album • Artist',
        artworkUrl: 'https://example.com/a.jpg',
        contentType: HomeContentType.album,
      );
      expect(HomePlaybackController.actionFor(item),
          HomePlayAction.navigateCollection);
    });

    test('song WITHOUT videoId → none (no fake play affordance)', () {
      final item = HomeItem(
        id: 'abc12345678',
        browseId: null,
        videoId: null,
        title: 'Broken song',
        subtitle: 'Artist',
        artworkUrl: 'https://example.com/b.jpg',
        contentType: HomeContentType.song,
      );
      expect(HomePlaybackController.actionFor(item), HomePlayAction.none);
    });

    test('unknown type with videoId → playVideo (safe fallback)', () {
      final item = HomeItem(
        id: 'abc12345678',
        videoId: 'abc12345678',
        title: 'Unknown thing',
        subtitle: 'Sub',
        artworkUrl: 'https://example.com/u.jpg',
        contentType: HomeContentType.unknown,
      );
      expect(HomePlaybackController.actionFor(item), HomePlayAction.playVideo);
    });

    test('unknown type without videoId → none', () {
      final item = HomeItem(
        id: 'VLPLabc',
        browseId: 'VLPLabc',
        title: 'Unknown collection',
        subtitle: 'Sub',
        artworkUrl: 'https://example.com/u2.jpg',
        contentType: HomeContentType.unknown,
      );
      expect(HomePlaybackController.actionFor(item), HomePlayAction.none);
    });

    test('LIVE-RUN REGRESSION: MPREb album mislabeled as song → navigate', () {
      // The runtime log showed playTrack receiving MPREb ids from the
      // enriched New-releases shelf ("Skipping non-playable track: Good
      // Times (ID: MPREb_5tEt5EeS7tZ)"). The fallback builder now
      // classifies by id prefix; this test pins the contract.
      final albumAsSong = HomeItem(
        id: 'MPREb_5tEt5EeS7tZ',
        videoId: null,
        browseId: 'MPREb_5tEt5EeS7tZ',
        title: 'Good Times',
        subtitle: 'Album • Artist',
        artworkUrl: 'https://example.com/g.jpg',
        contentType: HomeContentType.album,
      );
      expect(HomePlaybackController.actionFor(albumAsSong),
          HomePlayAction.navigateCollection);
      expect(HomePlaybackController.isPlayableSongItem(albumAsSong), isFalse);
    });

    test('isPlayableSongItem rejects non-11-char and prefix ids', () {
      expect(
        HomePlaybackController.isPlayableSongItem(HomeItem(
          id: 'MPREb_abc',
          videoId: 'MPREb_abc',
          title: 'X',
          subtitle: '',
          artworkUrl: 'https://example.com/x.jpg',
          contentType: HomeContentType.song,
        )),
        isFalse,
      );
      expect(
        HomePlaybackController.isPlayableSongItem(HomeItem(
          id: 'short',
          videoId: 'short',
          title: 'X',
          subtitle: '',
          artworkUrl: 'https://example.com/x.jpg',
          contentType: HomeContentType.song,
        )),
        isFalse,
      );
      expect(
        HomePlaybackController.isPlayableSongItem(HomeItem(
          id: 'abc12345678',
          videoId: 'abc12345678',
          title: 'X',
          subtitle: '',
          artworkUrl: 'https://example.com/x.jpg',
          contentType: HomeContentType.song,
        )),
        isTrue,
      );
    });
  });
}
