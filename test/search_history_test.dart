import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_streaming_app/services/search_history_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts empty', () async {
    final store = SearchHistoryStore();
    await store.load();
    expect(store.entries, isEmpty);
  });

  test('add inserts at front and dedupes (move-to-front)', () async {
    final store = SearchHistoryStore();
    await store.load();
    await store.add('tame impala');
    await store.add('jo0ji');
    await store.add('tame impala');

    expect(store.entries, ['tame impala', 'jo0ji'],
        reason: 're-searched term moves to front, no duplicates');
  });

  test('add persists across load', () async {
    final store = SearchHistoryStore();
    await store.load();
    await store.add('bang bang');

    final fresh = SearchHistoryStore();
    await fresh.load();
    expect(fresh.entries, ['bang bang']);
  });

  test('caps at maxEntries (10)', () async {
    final store = SearchHistoryStore();
    await store.load();
    for (var i = 0; i < 15; i++) {
      await store.add('query-$i');
    }
    expect(store.entries.length, 10);
    expect(store.entries.first, 'query-14');
    expect(store.entries.last, 'query-5');
  });

  test('remove deletes one entry', () async {
    final store = SearchHistoryStore();
    await store.load();
    await store.add('a');
    await store.add('b');
    await store.remove('a');
    expect(store.entries, ['b']);
  });

  test('clear empties and persists', () async {
    final store = SearchHistoryStore();
    await store.load();
    await store.add('x');
    await store.clear();

    final fresh = SearchHistoryStore();
    await fresh.load();
    expect(fresh.entries, isEmpty);
  });

  test('blank queries are ignored', () async {
    final store = SearchHistoryStore();
    await store.load();
    await store.add('   ');
    expect(store.entries, isEmpty);
  });
}
