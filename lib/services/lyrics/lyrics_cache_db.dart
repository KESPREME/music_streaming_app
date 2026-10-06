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

/// SQLite-based persistent lyrics cache
class LyricsCacheDb {
  static const String _dbName = 'lyrics_cache.db';
  static const String _tableName = 'lyrics';
  static const int _dbVersion = 2;
  
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
        version: _dbVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_tableName (
              key TEXT PRIMARY KEY,
              lyrics TEXT NOT NULL,
              is_synced INTEGER NOT NULL,
              provider TEXT NOT NULL,
              cached_at INTEGER NOT NULL
            )
          ''');

          // Index for faster lookups
          await db.execute('CREATE INDEX idx_key ON $_tableName(key)');

          if (kDebugMode) debugPrint('LyricsCacheDb: Database created');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // v2 added word/syllable timings. Existing rows are left alone and
          // simply carry NULL timings, which reads back as "no word timings" -
          // the same thing they had before. Recreating them would mean refetching
          // every cached song to get back data we already discarded once.
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE $_tableName ADD COLUMN timings TEXT',
            );
            if (kDebugMode) debugPrint('LyricsCacheDb: added timings column');
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


