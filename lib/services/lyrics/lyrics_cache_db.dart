// lib/services/lyrics/lyrics_cache_db.dart
// Persistent SQLite cache for lyrics with 7-day TTL

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Cached lyrics entry for database storage
class LyricsCacheEntry {
  final String key;
  final String lyrics;
  final bool isSynced;
  final String provider;
  final DateTime cachedAt;

  /// Word and syllable timings, JSON-encoded, or null when the source gave
  /// none.
  ///
  /// Stored beside the line text rather than inside it. Word timings used to be
  /// flattened away when a track was cached, so a word-synced song came back
  /// line-synced after a restart and the progressive wipe had nothing to draw
  /// from until the track had been fetched again. Keeping them means the first
  /// play of the day already has them.
  final String? timings;

  LyricsCacheEntry({
    required this.key,
    required this.lyrics,
    required this.isSynced,
    required this.provider,
    required this.cachedAt,
    this.timings,
  });

  Map<String, dynamic> toMap() => {
    'key': key,
    'lyrics': lyrics,
    'is_synced': isSynced ? 1 : 0,
    'provider': provider,
    'cached_at': cachedAt.millisecondsSinceEpoch,
    'timings': timings,
  };

  factory LyricsCacheEntry.fromMap(Map<String, dynamic> map) => LyricsCacheEntry(
    key: map['key'] as String,
    lyrics: map['lyrics'] as String,
    isSynced: (map['is_synced'] as int) == 1,
    provider: map['provider'] as String,
    cachedAt: DateTime.fromMillisecondsSinceEpoch(map['cached_at'] as int),
    // Absent on rows written before the column existed, and null on rows for a
    // source with no word timings. Both mean "no timings", not a failure.
    timings: map['timings'] as String?,
  );
  
  /// Check if entry is expired (7 days)
  bool get isExpired => DateTime.now().difference(cachedAt) > const Duration(days: 7);
}

/// The two things the schema code needs from a database.
///
/// A seam so the create/upgrade rules can be tested without a SQLite engine
/// (the project has no FFI SQLite for tests). [DatabaseExecutor] is adapted to
/// it by [LyricsCacheSchema.over].
abstract class LyricsSchemaDb {
  Future<void> execute(String sql);
  Future<List<Map<String, Object?>>> rawQuery(String sql);
}

class _SqfliteSchemaDb implements LyricsSchemaDb {
  const _SqfliteSchemaDb(this._db);

  final DatabaseExecutor _db;

  @override
  Future<void> execute(String sql) => _db.execute(sql);

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql) => _db.rawQuery(sql);
}

/// How the lyrics table is created and brought up to date.
///
/// WHY THIS IS ITS OWN CLASS
///
/// Version 2 added the `timings` column ONLY in `onUpgrade`. A database created
/// fresh at version 2 - every install since - never ran the upgrade, so the
/// table had no such column, every `put` threw "no column named timings", the
/// error was caught and logged in debug only, and NOTHING was ever cached on a
/// fresh install. Create and upgrade now come from one definition, and the
/// upgrade asks the database what it has rather than trusting the version
/// number, so both a fresh-v2 and an upgraded-v1 database heal.
class LyricsCacheSchema {
  const LyricsCacheSchema._();

  static const String table = 'lyrics';

  /// 3: rows written before this are dropped.
  ///
  /// They came from providers that mostly could not answer, so a cached
  /// line-synced result would hide a word-synced one that now can be found; and
  /// their word timings, where they had any, were guesses from the old vowel
  /// counter. A cache is disposable. Refetching is cheaper than showing a
  /// stale guess for a week.
  static const int version = 3;

  static LyricsSchemaDb over(DatabaseExecutor db) => _SqfliteSchemaDb(db);

  static Future<void> create(LyricsSchemaDb db) async {
    await db.execute('''
      CREATE TABLE $table (
        key TEXT PRIMARY KEY,
        lyrics TEXT NOT NULL,
        is_synced INTEGER NOT NULL,
        provider TEXT NOT NULL,
        cached_at INTEGER NOT NULL,
        timings TEXT
      )
    ''');
    // Index for faster lookups
    await db.execute('CREATE INDEX idx_key ON $table(key)');
  }

  static Future<void> upgrade(
    LyricsSchemaDb db,
    int oldVersion,
    int newVersion,
  ) async {
    // Whatever the version says, make sure the column exists.
    if (!await _hasColumn(db, 'timings')) {
      await db.execute('ALTER TABLE $table ADD COLUMN timings TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('DELETE FROM $table');
    }
  }

  static Future<bool> _hasColumn(LyricsSchemaDb db, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }
}

/// SQLite-based persistent lyrics cache
class LyricsCacheDb {
  static const String _dbName = 'lyrics_cache.db';
  static const String _tableName = LyricsCacheSchema.table;
  
  Database? _database;
  bool _isInitialized = false;
  
  /// Initialize the database
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _dbName);
      
      _database = await openDatabase(
        path,
        version: LyricsCacheSchema.version,
        onCreate: (db, version) async {
          await LyricsCacheSchema.create(LyricsCacheSchema.over(db));
          if (kDebugMode) debugPrint('LyricsCacheDb: Database created');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await LyricsCacheSchema.upgrade(
            LyricsCacheSchema.over(db),
            oldVersion,
            newVersion,
          );
          if (kDebugMode) {
            debugPrint('LyricsCacheDb: upgraded $oldVersion -> $newVersion');
          }
        },
      );
      
      _isInitialized = true;
      if (kDebugMode) debugPrint('LyricsCacheDb: Initialized');
      
      // Cleanup expired entries on startup
      await _cleanupExpired();
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsCacheDb: Init error: $e');
    }
  }
  
  /// Get cached lyrics by key
  Future<LyricsCacheEntry?> get(String key) async {
    if (!_isInitialized || _database == null) return null;
    
    try {
      final results = await _database!.query(
        _tableName,
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      
      if (results.isEmpty) return null;
      
      final entry = LyricsCacheEntry.fromMap(results.first);
      
      // Check expiration
      if (entry.isExpired) {
        await delete(key);
        return null;
      }
      
      return entry;
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsCacheDb: Get error: $e');
      return null;
    }
  }
  
  /// Store lyrics in cache.
  ///
  /// [timings] carries the word/syllable payload for this track, or null when
  /// the source had none. Losing it here is what made a word-synced song come
  /// back line-synced after a restart.
  Future<void> put(
    String key,
    String lyrics,
    bool isSynced,
    String provider, {
    String? timings,
  }) async {
    if (!_isInitialized || _database == null) return;

    try {
      final entry = LyricsCacheEntry(
        key: key,
        lyrics: lyrics,
        isSynced: isSynced,
        provider: provider,
        cachedAt: DateTime.now(),
        timings: timings,
      );
      
      await _database!.insert(
        _tableName,
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      if (kDebugMode) debugPrint('LyricsCacheDb: Cached lyrics for "$key"');
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsCacheDb: Put error: $e');
    }
  }
  
  /// Delete a cached entry
  Future<void> delete(String key) async {
    if (!_isInitialized || _database == null) return;
    
    try {
      await _database!.delete(
        _tableName,
        where: 'key = ?',
        whereArgs: [key],
      );
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsCacheDb: Delete error: $e');
    }
  }
  
  /// Cleanup expired entries
  Future<void> _cleanupExpired() async {
    if (!_isInitialized || _database == null) return;
    
    try {
      final expirationThreshold = DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch;
      
      final deleted = await _database!.delete(
        _tableName,
        where: 'cached_at < ?',
        whereArgs: [expirationThreshold],
      );
      
      if (kDebugMode && deleted > 0) {
        debugPrint('LyricsCacheDb: Cleaned up $deleted expired entries');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsCacheDb: Cleanup error: $e');
    }
  }
  
  /// Clear all cached lyrics
  Future<void> clear() async {
    if (!_isInitialized || _database == null) return;
    
    try {
      await _database!.delete(_tableName);
      if (kDebugMode) debugPrint('LyricsCacheDb: Cache cleared');
    } catch (e) {
      if (kDebugMode) debugPrint('LyricsCacheDb: Clear error: $e');
    }
  }
  
  /// Close the database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _isInitialized = false;
    }
  }
}
