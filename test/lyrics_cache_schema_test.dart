import 'package:flutter_test/flutter_test.dart';

import 'package:music_streaming_app/core/navigation/shell_back.dart';
import 'package:music_streaming_app/services/lyrics/lyrics_cache_db.dart';

/// A database that understands just the statements the schema code issues.
class _FakeDb implements LyricsSchemaDb {
  _FakeDb({Set<String> columns = const {}, this.rows = 0})
      : columns = {...columns};

  final Set<String> columns;
  int rows;
  final List<String> executed = [];

  @override
  Future<void> execute(String sql) async {
    executed.add(sql);
    if (sql.contains('CREATE TABLE')) {
      for (final c in ['key', 'lyrics', 'is_synced', 'provider', 'cached_at', 'timings']) {
        if (sql.contains(c)) columns.add(c);
      }
    } else if (sql.contains('ADD COLUMN timings')) {
      columns.add('timings');
    } else if (sql.startsWith('DELETE FROM')) {
      rows = 0;
    }
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql) async =>
      [for (final c in columns) {'name': c}];

  int get alters => executed.where((s) => s.contains('ALTER TABLE')).length;
}

void main() {
  group('lyrics cache schema', () {
    test('a FRESH database has the timings column', () async {
      // The bug: the column was added only in onUpgrade, so a database created
      // at version 2 never had it, every put threw, and nothing was ever cached.
      final db = _FakeDb();
      await LyricsCacheSchema.create(db);
      expect(db.columns, contains('timings'));
    });

    test('a fresh-v2 database (no column) is healed on upgrade', () async {
      final db = _FakeDb(columns: {'key', 'lyrics', 'is_synced', 'provider', 'cached_at'}, rows: 5);
      await LyricsCacheSchema.upgrade(db, 2, LyricsCacheSchema.version);
      expect(db.columns, contains('timings'));
      expect(db.alters, 1);
    });

    test('an upgraded-v1 database is healed too', () async {
      final db = _FakeDb(columns: {'key', 'lyrics', 'is_synced', 'provider', 'cached_at'}, rows: 5);
      await LyricsCacheSchema.upgrade(db, 1, LyricsCacheSchema.version);
      expect(db.columns, contains('timings'));
    });

    test('the column is asked about, not assumed: no second ALTER', () async {
      final db = _FakeDb(columns: {'key', 'timings'}, rows: 3);
      await LyricsCacheSchema.upgrade(db, 2, LyricsCacheSchema.version);
      expect(db.alters, 0);
    });

    test('rows written before version 3 are dropped', () async {
      final db = _FakeDb(columns: {'timings'}, rows: 40);
      await LyricsCacheSchema.upgrade(db, 2, 3);
      expect(db.rows, 0);
    });

    test('later upgrades keep what is there', () async {
      final db = _FakeDb(columns: {'timings'}, rows: 40);
      await LyricsCacheSchema.upgrade(db, 3, 4);
      expect(db.rows, 40);
    });

    test('the version is 3', () => expect(LyricsCacheSchema.version, 3));
  });

  group('shell back', () {
    ShellBackAction resolve({
      bool panel = false,
      bool playerCanPop = false,
      bool detail = false,
      bool search = false,
      int tab = 0,
    }) =>
        resolveShellBack(
          isPanelOpen: panel,
          playerCanPop: playerCanPop,
          detailCanPop: detail,
          searchMode: search,
          tabIndex: tab,
        );

    test('a sheet on the player\'s navigator is closed BEFORE the player',
        () {
      // The bug: back collapsed the player under a sheet still on screen.
      expect(resolve(panel: true, playerCanPop: true),
          ShellBackAction.popPlayerRoute);
    });

    test('with nothing above it, back brings the player down', () {
      expect(resolve(panel: true), ShellBackAction.collapsePlayer);
    });

    test('with the player closed the order is detail, search, home, exit', () {
      expect(resolve(detail: true, search: true, tab: 2), ShellBackAction.popDetail);
      expect(resolve(search: true, tab: 2), ShellBackAction.exitSearch);
      expect(resolve(tab: 2), ShellBackAction.goHome);
      expect(resolve(), ShellBackAction.none);
    });

    test('a player route does not matter once the player is closed', () {
      expect(resolve(playerCanPop: true), ShellBackAction.none);
    });
  });
}
