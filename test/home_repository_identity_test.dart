import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/home/home_models.dart';
import 'package:music_streaming_app/services/home/ytm_home_source.dart';
import 'package:music_streaming_app/services/innertube/innertube_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WHOSE HOME IS THIS?
///
/// Two ways one account's shelves reached another's Home:
///   * the section memory (which pins which shelves exist, and where) lived under
///     one global key, and `clearHomeCache` did not delete it; and
///   * `refresh()` handed back the fetch already in flight even when that fetch
///     had been started for the PREVIOUS account.
/// Both put a stale "Quick picks" / "Listen again" in the new account's feed,
/// where they surfaced as duplicates of its own. These pin the scoping.

HomeItem _song(String id) => HomeItem(
      id: id,
      videoId: id,
      title: 'Song $id',
      subtitle: 'Artist',
      artworkUrl: 'https://example.com/$id.jpg',
      contentType: HomeContentType.song,
    );

HomeSection _shelf(String title, String prefix) => HomeSection(
      id: 'id_$title',
      title: title,
      items: [_song('${prefix}1'), _song('${prefix}2'), _song('${prefix}3')],
      presentation: HomePresentation.artworkRail,
    );

/// Five shelves: at or above the "sparse" floor, so no enrichment (network) runs.
HomeFeed _feed(String prefix) => HomeFeed(
      sections: [
        _shelf('Quick picks', prefix),
        _shelf('Listen again', prefix),
        _shelf('New releases', prefix),
        _shelf('Trending', prefix),
        _shelf('Your playlists', prefix),
      ],
      fetchedAt: DateTime.now(),
      source: 'ytm_home',
    );

/// A primary source whose fetches the test completes by hand.
class _ScriptedSource extends YouTubeMusicHomeSource {
  _ScriptedSource() : super(InnerTubeService.instance);

  final List<Completer<HomeFeed?>> calls = [];

  @override
  bool get hasVisitorData => true;

  @override
  Future<HomeFeed?> fetch({int perShelfLimit = 12}) {
    final c = Completer<HomeFeed?>();
    calls.add(c);
    return c.future;
  }
}

class _NoFallback extends FallbackHomeSource {
  _NoFallback() : super(InnerTubeService.instance);

  @override
  Future<HomeFeed?> fetch() async => null;
}

HomeRepository _repo([_ScriptedSource? primary]) => HomeRepository(
      primary: primary ?? _ScriptedSource(),
      fallback: _NoFallback(),
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HomeRepository.debugIdentity = null;
  });
  tearDown(() => HomeRepository.debugIdentity = null);

  group('section memory is scoped to the signed-in account', () {
    test('the storage key differs per identity', () {
      expect(HomeRepository.memoryKeyFor('anon'),
          isNot(HomeRepository.memoryKeyFor('user_a')));
      expect(HomeRepository.memoryKeyFor('user_a'),
          isNot(HomeRepository.memoryKeyFor('user_b')));
    });

    test('shelves remembered for A are not restored for B, and are for A again',
        () async {
      HomeRepository.debugIdentity = 'user_a';
      final a = _repo();
      await a.rememberForTest(_feed('a'));
      expect(a.memoryForTest, isNotEmpty);

      HomeRepository.debugIdentity = 'user_b';
      final b = _repo();
      await b.loadMemoryForTest();
      expect(b.memoryForTest, isEmpty,
          reason: 'B must not inherit A\'s Quick picks / Listen again');

      HomeRepository.debugIdentity = 'user_a';
      final a2 = _repo();
      await a2.loadMemoryForTest();
      expect(a2.memoryForTest.length, a.memoryForTest.length,
          reason: 'A\'s own memory still survives a restart');
    });

    test('the old unscoped v1 key is deleted, never trusted', () async {
      SharedPreferences.setMockInitialValues({
        'home_section_memory_v1': '{"schema":1,"entries":[]}',
      });
      HomeRepository.debugIdentity = 'user_a';
      await _repo().loadMemoryForTest();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('home_section_memory_v1'), isFalse);
    });

    test('clearHomeCache removes the memory of every identity and the snapshots, '
        'and nothing else', () async {
      SharedPreferences.setMockInitialValues({'unrelated_setting': 'keep'});
      HomeRepository.debugIdentity = 'user_a';
      await _repo().rememberForTest(_feed('a'));
      HomeRepository.debugIdentity = 'user_b';
      final b = _repo();
      await b.rememberForTest(_feed('b'));

      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getKeys().where((k) => k.startsWith('home_section_memory')),
          hasLength(2),
          reason: 'premise: one memory per identity');

      await b.clearHomeCache();

      expect(prefs.getKeys().where((k) => k.startsWith('home_section_memory')),
          isEmpty);
      expect(prefs.getString('unrelated_setting'), 'keep');
      expect(b.memoryForTest, isEmpty);
    });
  });

  group('refresh never hands one account\'s fetch to another', () {
    test('two refreshes for the same account share one request', () async {
      HomeRepository.debugIdentity = 'user_a';
      final source = _ScriptedSource();
      final repo = _repo(source);
      final r1 = repo.refresh();
      final r2 = repo.refresh();
      expect(source.calls, hasLength(1), reason: 'coalesced');
      source.calls.single.complete(_feed('a'));
      expect(await r1, same(await r2));
    });

    test('a refresh after the account changed starts its own request', () async {
      HomeRepository.debugIdentity = 'user_a';
      final source = _ScriptedSource();
      final repo = _repo(source);
      unawaited(repo.refresh());
      HomeRepository.debugIdentity = 'user_b';
      unawaited(repo.refresh());
      expect(source.calls, hasLength(2),
          reason: 'B must not wait on, or receive, A\'s request');
    });

    test('A\'s late response is discarded: not shown, not remembered', () async {
      HomeRepository.debugIdentity = 'user_a';
      final source = _ScriptedSource();
      final repo = _repo(source);
      final forA = repo.refresh();

      HomeRepository.debugIdentity = 'user_b';
      final forB = repo.refresh();

      // A's response arrives while B is signed in.
      source.calls[0].complete(_feed('a'));
      final aResult = await forA;
      await _settle();
      expect(aResult, isNull, reason: 'nothing of A is published');
      expect(repo.current, isNull);
      expect(repo.memoryForTest, isEmpty,
          reason: 'A\'s shelves must not enter B\'s memory');

      // B's own response is accepted normally.
      source.calls[1].complete(_feed('b'));
      final bResult = await forB;
      await _settle();
      expect(bResult, isNotNull);
      expect(bResult!.sections.first.items.first.id, 'b1');
      expect(repo.memoryForTest.values.map((e) => e.section.items.first.id),
          everyElement(startsWith('b')));
    });

    test('a superseded request finishing late does not clear its successor',
        () async {
      HomeRepository.debugIdentity = 'user_a';
      final source = _ScriptedSource();
      final repo = _repo(source);
      final forA = repo.refresh();
      HomeRepository.debugIdentity = 'user_b';
      final forB = repo.refresh();

      source.calls[0].complete(_feed('a'));
      await forA;
      await _settle();

      // B's request is still in flight: a third caller joins it rather than
      // starting a duplicate.
      final joined = repo.refresh();
      expect(source.calls, hasLength(2),
          reason: 'A finishing must not make B look idle');

      source.calls[1].complete(_feed('b'));
      expect(await joined, same(await forB));
    });
  });
}
