import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';
import 'package:music_streaming_app/presentation/home/home_shelf_plan.dart';
import 'package:music_streaming_app/services/home/home_composer.dart';
import 'package:music_streaming_app/services/home/home_convergence.dart';
import 'package:music_streaming_app/services/home/home_models.dart';

/// ONE SHELF PER JOB.
///
/// Home drew the app's own "Quick picks" and "Jump back in" AND every shelf the
/// feed sent - including YouTube Music's own "Quick picks" and "Listen again".
/// Nothing compared them, so for any account whose response carried those
/// shelves the same job was done twice. These pin the rule that fixes that, and
/// the three neighbouring bugs that let a duplicate in by another door (title
/// comparison, convergence with a stale remembered shelf).

// ── fixtures ──────────────────────────────────────────────────────────────
//
// YouTube video ids are exactly eleven characters; the planner relies on that
// to tell a streamable play from a local file or a collection id.
String vid(int n) => 'vid${n.toString().padLeft(8, '0')}'; // 3 + 8 = 11

HomeItem item(String id, [String? title]) => HomeItem(
      id: id,
      videoId: id,
      title: title ?? 'Song $id',
      subtitle: 'Artist',
      artworkUrl: 'https://example.com/$id.jpg',
      contentType: HomeContentType.song,
    );

HomeSection shelf(String title, List<String> ids, {String? id}) => HomeSection(
      id: id ?? 'id_$title',
      title: title,
      items: [for (final i in ids) item(i)],
      presentation: HomePresentation.artworkRail,
    );

Track track(String id, {String source = 'youtube', String? title}) => Track(
      id: id,
      trackName: title ?? 'Track $id',
      artistName: 'Me',
      albumName: 'Album',
      previewUrl: '',
      source: source,
    );

HomeShelfPlan plan({
  List<HomeSection> feed = const [],
  HomeSection? hero,
  Set<String> heroIds = const {},
  List<Track> recents = const [],
  List<Track> quick = const [],
  bool Function(HomeSection)? renders,
}) =>
    planHomeShelves(
      feed: feed,
      hero: hero,
      heroTrackIds: heroIds,
      recents: recents,
      quickPicks: quick,
      renders: renders ?? (_) => true,
    );

void main() {
  group('roles', () {
    test('Quick picks and every history title are recognised', () {
      expect(shelfRoleOf(shelf('Quick picks', [vid(1), vid(2)])),
          HomeShelfRole.quickPicks);
      expect(shelfRoleOf(shelf('QUICK PICKS', [vid(1), vid(2)])),
          HomeShelfRole.quickPicks);
      // Server-side decoration after the name is still the same shelf.
      expect(shelfRoleOf(shelf('Quick picks:', [vid(1), vid(2)])),
          HomeShelfRole.quickPicks);
      for (final t in const [
        'Listen again',
        'Recents',
        'Jump back in',
        'Recently played'
      ]) {
        expect(shelfRoleOf(shelf(t, [vid(1), vid(2)])), HomeShelfRole.history,
            reason: t);
      }
    });

    test('other shelves have no role', () {
      for (final t in const ['New releases', 'Trending', 'Your playlists']) {
        expect(shelfRoleOf(shelf(t, [vid(1), vid(2)])), isNull, reason: t);
      }
    });

    test('a streamable track is a real video id, not a file or a collection', () {
      expect(isStreamableTrack(track(vid(1))), isTrue);
      expect(isStreamableTrack(track(vid(1), source: 'local')), isFalse);
      expect(isStreamableTrack(track('short')), isFalse);
      expect(isStreamableTrack(track('MPREb_abcde')), isFalse); // 11 chars, album
      expect(isStreamableTrack(track('OLAK5uy_abc')), isFalse); // 11 chars, album
    });
  });

  group('Quick picks: one shelf', () {
    test('the feed sent one - it stays in its place, the app\'s own is gone', () {
      final feed = [
        shelf('New releases', [vid(1), vid(2)]),
        shelf('Quick picks', [vid(3), vid(4), vid(5)]),
        shelf('Trending', [vid(6), vid(7)]),
      ];
      final p = plan(feed: feed, quick: [track(vid(8)), track(vid(9))]);
      expect(p.localQuickPicks, isEmpty);
      expect(p.quickPicksSection, isNotNull);
      expect(p.feedSections.map((s) => s.title),
          ['New releases', 'Quick picks', 'Trending'],
          reason: 'native order is truth');
    });

    test('the feed sent none - the app fills the job, as before', () {
      final p = plan(
        feed: [shelf('New releases', [vid(1), vid(2)])],
        quick: [track(vid(8)), track(vid(9))],
      );
      expect(p.localQuickPicks.map((t) => t.id), [vid(8), vid(9)]);
      expect(p.quickPicksSection, isNull);
    });

    test('two feed shelves both claiming Quick picks: the first stays', () {
      final p = plan(feed: [
        shelf('Quick picks', [vid(1), vid(2)], id: 'first'),
        shelf('Quick picks:', [vid(3), vid(4)], id: 'second'),
      ]);
      expect(p.feedSections.map((s) => s.id), ['first']);
    });

    test('a native shelf that draws nothing does not suppress the app\'s', () {
      final native = shelf('Quick picks', [vid(1), vid(2)]);
      final p = plan(
        feed: [native],
        quick: [track(vid(8)), track(vid(9))],
        renders: (s) => !identical(s, native),
      );
      expect(p.quickPicksSection, isNull);
      expect(p.localQuickPicks, hasLength(2),
          reason: 'a collapsed shelf does not do the job');
    });
  });

  group('Listen again / Jump back in: one shelf', () {
    test('the feed sent one - the app\'s plays join its front, no second shelf', () {
      final p = plan(
        feed: [shelf('Listen again', [vid(1), vid(2), vid(3)])],
        recents: [track(vid(7)), track(vid(8))],
      );
      expect(p.feedSections, hasLength(1));
      final ids = p.feedSections.single.items.map((i) => i.videoId).toList();
      expect(ids, [vid(7), vid(8), vid(1), vid(2), vid(3)]);
      expect(p.localHistory, isEmpty, reason: 'no separate Jump back in');
    });

    test('a track in both lists appears once, at the front', () {
      final p = plan(
        feed: [shelf('Listen again', [vid(1), vid(2), vid(3)])],
        recents: [track(vid(2)), track(vid(9))],
      );
      final ids =
          p.feedSections.single.items.map((i) => i.videoId).toList();
      expect(ids, [vid(2), vid(9), vid(1), vid(3)]);
      expect(ids.toSet().length, ids.length);
    });

    test('lead and total are capped; native items fill what is left', () {
      final recents = [for (var i = 100; i < 120; i++) track(vid(i))];
      final native = [for (var i = 1; i <= 12; i++) vid(i)];
      final p = plan(
        feed: [shelf('Listen again', native)],
        recents: recents,
      );
      final ids = p.feedSections.single.items.map((i) => i.videoId).toList();
      expect(ids, hasLength(kHistoryShelfCap));
      expect(ids.take(kHistoryLocalLead),
          [for (var i = 100; i < 100 + kHistoryLocalLead; i++) vid(i)]);
      expect(ids.skip(kHistoryLocalLead).first, vid(1));
    });

    test('local files never bring Jump back in back', () {
      final local = track('/storage/song.mp3', source: 'local');
      final p = plan(
        feed: [shelf('Listen again', [vid(1), vid(2)])],
        recents: [local, track(vid(7))],
      );
      expect(p.localHistory, isEmpty, reason: 'hidden, local plays or not');
      expect(p.feedSections.single.items.first.videoId, vid(7),
          reason: 'the streamable play is still folded into Listen again');
    });

    test('only local plays and no history shelf: still no Jump back in', () {
      final p = plan(
        feed: [shelf('New releases', [vid(1), vid(2)])],
        recents: [track('/a.mp3', source: 'local'), track('/b.mp3', source: 'local')],
      );
      expect(p.localHistory, isEmpty);
    });

    test('the feed sent none - Jump back in keeps the streamable plays only', () {
      final streamed = track(vid(7));
      final p = plan(
        feed: [shelf('New releases', [vid(1), vid(2)])],
        recents: [streamed, track('x', source: 'local')],
      );
      expect(p.localHistory, [streamed]);
      expect(p.historySection, isNull);
    });

    test('"Listen again" and "Recents" in one feed: the first stays', () {
      final p = plan(feed: [
        shelf('Listen again', [vid(1), vid(2)], id: 'first'),
        shelf('Recents', [vid(3), vid(4)], id: 'second'),
      ]);
      expect(p.feedSections.map((s) => s.id), ['first']);
    });

    test('merging does not mutate the feed\'s own shelf', () {
      final native = shelf('Listen again', [vid(1), vid(2)]);
      plan(feed: [native], recents: [track(vid(7))]);
      expect(native.items.map((i) => i.videoId), [vid(1), vid(2)]);
    });
  });

  group('hero carousel', () {
    test('a hero that IS the Quick picks shelf does the job', () {
      final hero = shelf('Quick picks', [vid(1), vid(2)], id: 'hero');
      final p = plan(
        feed: [hero, shelf('Trending', [vid(3), vid(4)])],
        hero: hero,
        quick: [track(vid(8)), track(vid(9))],
      );
      expect(p.localQuickPicks, isEmpty);
      expect(p.feedSections.map((s) => s.title), ['Trending'],
          reason: 'the hero is not drawn twice');
    });

    test('a hero that IS the history shelf: no Jump back in beside it', () {
      final hero = shelf('Listen again', [vid(1), vid(2)], id: 'hero');
      final p = plan(
        feed: [hero],
        hero: hero,
        recents: [track(vid(7))],
      );
      expect(p.localHistory, isEmpty);
    });

    test('tracks the hero shows are not repeated as Quick picks', () {
      final quick = [for (var i = 1; i <= 6; i++) track(vid(i))];
      final p = plan(quick: quick, heroIds: {vid(1), vid(2)});
      expect(p.localQuickPicks.map((t) => t.id),
          [vid(3), vid(4), vid(5), vid(6)]);
    });

    test('with no overlap, the shelf is exactly as it was', () {
      final quick = [track(vid(1))];
      final p = plan(quick: quick, heroIds: {vid(50)});
      expect(p.localQuickPicks, quick, reason: 'a single pick is still a shelf');
    });

    test('overlap that leaves a rail of one or two is dropped, not shown thin', () {
      final quick = [for (var i = 1; i <= 5; i++) track(vid(i))];
      final p = plan(quick: quick, heroIds: {vid(1), vid(2), vid(3)});
      expect(p.localQuickPicks, isEmpty);
    });

    test('hero fully covering the picks leaves no shelf', () {
      final quick = [track(vid(1)), track(vid(2))];
      final p = plan(quick: quick, heroIds: {vid(1), vid(2)});
      expect(p.localQuickPicks, isEmpty);
    });
  });

  group('the page the user described', () {
    test('Quick picks + Listen again in the feed, plus local picks and plays: '
        'exactly one of each', () {
      final p = plan(
        feed: [
          shelf('Listen again', [vid(1), vid(2), vid(3)]),
          shelf('Quick picks', [vid(4), vid(5), vid(6)]),
          shelf('New releases', [vid(10), vid(11)]),
        ],
        recents: [track(vid(7)), track(vid(8))],
        quick: [track(vid(20)), track(vid(21)), track(vid(22))],
      );
      final titles = p.feedSections.map((s) => s.title).toList();
      expect(titles.where((t) => t == 'Quick picks'), hasLength(1));
      expect(titles.where((t) => t == 'Listen again'), hasLength(1));
      expect(p.localQuickPicks, isEmpty);
      expect(p.localHistory, isEmpty);
      expect(titles, ['Listen again', 'Quick picks', 'New releases']);
    });
  });

  group('title identity (what a person calls the same name)', () {
    test('case, NBSP, zero-width, curly quotes and trailing punctuation fold', () {
      String n(String s) => SectionIdentity.normalizedTitle(s);
      expect(n('Listen again'), n('LISTEN AGAIN'));
      expect(n('Listen again'), n('Listen\u00A0again'));
      expect(n('Listen again'), n('Listen\u200B again'));
      expect(n('Listen again'), n('  Listen   again  '));
      expect(n("What's new"), n('What\u2019s new'));
      expect(n('Quick picks'), n('Quick picks:'));
      expect(n('Quick picks'), n('Quick picks\u2026'));
    });

    test('non-Latin titles are kept distinct, not all reduced to nothing', () {
      String n(String s) => SectionIdentity.normalizedTitle(s);
      expect(n('おすすめ'), isNotEmpty);
      expect(n('おすすめ'), isNot(n('新着')));
      expect(n('جديد'), isNot(n('مختارات')));
    });

    test('the composer collapses titles that differ only in invisible ways', () {
      final feed = HomeFeed(
        sections: [
          shelf('Listen again', [vid(1), vid(2)], id: 'a'),
          shelf('Listen\u00A0again', [vid(3), vid(4)], id: 'b'),
          shelf('LISTEN AGAIN.', [vid(5), vid(6)], id: 'c'),
          shelf('New releases', [vid(7), vid(8)], id: 'd'),
        ],
        fetchedAt: DateTime.now(),
        source: 'ytm_home',
      );
      final out = const HomeComposer().compose(primary: feed, fallback: null)!;
      expect(out.sections.map((s) => s.id), ['a', 'd']);
    });

    test('the composer does NOT collapse distinct non-Latin shelves', () {
      final feed = HomeFeed(
        sections: [
          shelf('おすすめ', [vid(1), vid(2)], id: 'a'),
          shelf('新着', [vid(3), vid(4)], id: 'b'),
        ],
        fetchedAt: DateTime.now(),
        source: 'ytm_home',
      );
      final out = const HomeComposer().compose(primary: feed, fallback: null)!;
      expect(out.sections.map((s) => s.id), ['a', 'b']);
    });
  });

  group('convergence: a stale remembered shelf never beats the fresh one', () {
    test('same name, different dominant type (so a different identity)', () {
      // Last response: Quick picks was mostly songs. This one: mostly videos.
      // Identity folds the dominant type, so the remembered shelf looked
      // "omitted" and came back - at its OLD, earlier position, ahead of the
      // fresh shelf - and the title collapse kept the STALE one.
      final stale = shelf('Quick picks', [vid(1), vid(2)], id: 'stale');
      final fresh = HomeSection(
        id: 'fresh',
        title: 'Quick picks',
        items: [
          for (final i in [vid(3), vid(4)])
            HomeItem(
              id: i,
              videoId: i,
              title: 'V $i',
              subtitle: 'A',
              artworkUrl: 'u',
              contentType: HomeContentType.video,
            ),
        ],
        presentation: HomePresentation.videoRail,
      );
      expect(SectionIdentity.forSection(stale),
          isNot(SectionIdentity.forSection(fresh)),
          reason: 'the premise: the identities really differ');

      final memory = {
        SectionIdentity.forSection(stale): SectionMemoryEntry(
          section: stale,
          identity: SectionIdentity.forSection(stale),
          cachedAt: DateTime.now(),
        ),
      };
      final out = const HomeConvergence().convergeWithOrder(
        fresh: HomeFeed(
          sections: [shelf('Trending', [vid(9), vid(8)]), fresh],
          fetchedAt: DateTime.now(),
          source: 'ytm_home',
        ),
        memory: memory,
        previousOrder: [SectionIdentity.forSection(stale)],
      );
      final quick = out.sections.where((s) => s.title == 'Quick picks').toList();
      expect(quick, hasLength(1));
      expect(quick.single.id, 'fresh');
    });

    test('a shelf the response really omitted is still remembered', () {
      final stale = shelf('Moods', [vid(1), vid(2)], id: 'stale');
      final memory = {
        SectionIdentity.forSection(stale): SectionMemoryEntry(
          section: stale,
          identity: SectionIdentity.forSection(stale),
          cachedAt: DateTime.now(),
        ),
      };
      final out = const HomeConvergence().convergeWithOrder(
        fresh: HomeFeed(
          sections: [shelf('Trending', [vid(9), vid(8)])],
          fetchedAt: DateTime.now(),
          source: 'ytm_home',
        ),
        memory: memory,
        previousOrder: [SectionIdentity.forSection(stale)],
      );
      expect(out.sections.map((s) => s.title), contains('Moods'));
    });
  });
}
