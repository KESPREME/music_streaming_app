import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/models/search_history_entry.dart';
import 'package:music_streaming_app/services/search_history_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  List<String> titlesOf(SearchHistoryStore store) =>
      store.entries.map((e) => e.title).toList();

  List<String> idsOf(SearchHistoryStore store) =>
      store.entries.map((e) => e.id).toList();

  test('starts empty', () async {
    final store = SearchHistoryStore();
    await store.load();
    expect(store.entries, isEmpty);
  });

  test('addQuery inserts at front and dedupes (move-to-front)', () async {
    final store = SearchHistoryStore();
    await store.load();
    await store.addQuery('tame impala');
    await store.addQuery('jo0ji');
    await store.addQuery('tame impala');

    expect(titlesOf(store), ['tame impala', 'jo0ji'],
        reason: 're-searched term moves to front, no duplicates');
  });

  test('addQuery persists across load', () async {
    final store = SearchHistoryStore();
    await store.load();
    await store.addQuery('bang bang');

    final fresh = SearchHistoryStore();
    await fresh.load();
    expect(titlesOf(fresh), ['bang bang']);
  });

  test('caps at maxEntries (10)', () async {
    final store = SearchHistoryStore();
    await store.load();
    for (var i = 0; i < 15; i++) {
      await store.addQuery('query-$i');
    }
    expect(store.entries.length, 10);
    expect(store.entries.first.title, 'query-14');
    expect(store.entries.last.title, 'query-5');
  });

  test('remove deletes one entry', () async {
    final store = SearchHistoryStore();
    await store.load();
    await store.addQuery('a');
    await store.addQuery('b');
    await store.remove('a');
    expect(titlesOf(store), ['b']);
  });

  test('clear empties and persists', () async {
    final store = SearchHistoryStore();
    await store.load();
    await store.addQuery('x');
    await store.clear();

    final fresh = SearchHistoryStore();
    await fresh.load();
    expect(fresh.entries, isEmpty);
  });

  test('blank queries are ignored', () async {
    final store = SearchHistoryStore();
    await store.load();
    await store.addQuery('   ');
    expect(store.entries, isEmpty);
  });

  group('track entries', () {
    test('carry artwork, artist and a track kind', () async {
      final store = SearchHistoryStore();
      await store.load();
      await store.addTrack(
        id: 'abc123',
        title: 'My Old Ways',
        artist: 'Tame Impala',
        artworkUrl: 'https://example.test/cover.jpg',
      );

      final entry = store.entries.single;
      expect(entry.kind, SearchHistoryKind.track);
      expect(entry.title, 'My Old Ways');
      expect(entry.subtitle, 'Tame Impala');
      expect(entry.artworkUrl, 'https://example.test/cover.jpg');
      expect(entry.hasArtwork, isTrue);
    });

    test('re-record moves the track to the front without duplicating',
        () async {
      final store = SearchHistoryStore();
      await store.load();
      await store.addTrack(id: 'a', title: 'A', artist: 'X', artworkUrl: '');
      await store.addTrack(id: 'b', title: 'B', artist: 'Y', artworkUrl: '');
      await store.addTrack(id: 'a', title: 'A', artist: 'X', artworkUrl: '');

      expect(idsOf(store), ['a', 'b']);
    });

    test('a query with the same text does not displace the track row',
        () async {
      // Searching a term that is also a track title must not push the artwork
      // row the user actually played off the list in favour of a bare text row.
      final store = SearchHistoryStore();
      await store.load();
      await store.addTrack(
        id: 'vid1',
        title: 'Starboy',
        artist: 'The Weeknd',
        artworkUrl: 'https://example.test/s.jpg',
      );
      await store.addQuery('Starboy');

      expect(store.entries.length, 1);
      expect(store.entries.single.kind, SearchHistoryKind.track);
    });

    test('query entries report no artwork', () async {
      final store = SearchHistoryStore();
      await store.load();
      await store.addQuery('hello');
      expect(store.entries.single.kind, SearchHistoryKind.query);
      expect(store.entries.single.hasArtwork, isFalse);
    });

    test('dedupe is case-insensitive', () async {
      final store = SearchHistoryStore();
      await store.load();
      await store.addQuery('Tame Impala');
      await store.addQuery('tame impala');
      expect(store.entries.length, 1);
    });
  });

  group('upgrade from the legacy string list', () {
    setUp(() {
      // The previous release stored a StringList under this key.
      SharedPreferences.setMockInitialValues({
        'recent_searches': <String>['older ways', 'kanye'],
      });
    });

    test('legacy queries are carried over as query entries', () async {
      final store = SearchHistoryStore();
      await store.load();

      expect(titlesOf(store), ['older ways', 'kanye']);
      expect(store.entries.every((e) => e.kind == SearchHistoryKind.query),
          isTrue);
    });

    test('the migration is persisted, so it only runs once', () async {
      final store = SearchHistoryStore();
      await store.load();

      final fresh = SearchHistoryStore();
      await fresh.load();
      expect(titlesOf(fresh), ['older ways', 'kanye']);
    });

    test('new writes land under the new key and do not touch the legacy one',
        () async {
      final store = SearchHistoryStore();
      await store.load();
      await store.addQuery('newest');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('recent_search_entries'), isNotNull);
      // Untouched, so a downgrade would still find it.
      expect(prefs.getStringList('recent_searches'), ['older ways', 'kanye']);
    });
  });

  group('serialisation', () {
    test('round-trips every field', () {
      final entry = SearchHistoryEntry.track(
        id: 'abc',
        title: 'Title',
        artist: 'Artist',
        artworkUrl: 'https://example.test/a.jpg',
      );
      final decoded = SearchHistoryEntry.decodeList(
        SearchHistoryEntry.encodeList([entry]),
      );

      expect(decoded, hasLength(1));
      expect(decoded.single.id, 'abc');
      expect(decoded.single.title, 'Title');
      expect(decoded.single.subtitle, 'Artist');
      expect(decoded.single.artworkUrl, 'https://example.test/a.jpg');
      expect(decoded.single.kind, SearchHistoryKind.track);
    });

    test('a record with no id is dropped rather than throwing', () {
      expect(SearchHistoryEntry.fromJson({'title': 'no id'}), isNull);
    });

    test('an unknown kind degrades to a query', () {
      final decoded = SearchHistoryEntry.decodeList(
        '[{"id":"x","title":"t","kind":"SOMETHING_NEW"}]',
      );
      expect(decoded.single.kind, SearchHistoryKind.query);
    });

    test('malformed json yields an empty list, not an exception', () {
      expect(SearchHistoryEntry.decodeList('{not json'), isEmpty);
    });
  });
}
