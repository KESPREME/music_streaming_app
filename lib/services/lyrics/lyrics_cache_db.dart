// lib/services/lyrics/lyrics_cache_db.dart
// Persistent SQLite cache for lyrics with 7-day TTL

import 'dart:convert';
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
  
  LyricsCacheEntry({
    required this.key,
    required this.lyrics,
    required this.isSynced,
    required this.provider,
    required this.cachedAt,
  });
  
  Map<String, dynamic> toMap() => {
    'key': key,
    'lyrics': lyrics,
    'is_synced': isSynced ? 1 : 0,
    'provider': provider,
    'cached_at': cachedAt.millisecondsSinceEpoch,
  };
  
  factory LyricsCacheEntry.fromMap(Map<String, dynamic> map) => LyricsCacheEntry(
    key: map['key'] as String,
    lyrics: map['lyrics'] as String,
    isSynced: (map['is_synced'] as int) == 1,
    provider: map['provider'] as String,
    cachedAt: DateTime.fromMillisecondsSinceEpoch(map['cached_at'] as int),
  );
  
  /// Check if entry is expired (7 days)
  bool get isExpired => DateTime.now().difference(cachedAt) > const Duration(days: 7);
}

/// SQLite-based persistent lyrics cache
class LyricsCacheDb {
  static const String _dbName = 'lyrics_cache.db';
  static const String _tableName = 'lyrics';
  static const int _dbVersion = 1;
  
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
          
          if (kDebugMode) print('LyricsCacheDb: Database created');
        },
      );
      
      _isInitialized = true;
      if (kDebugMode) print('LyricsCacheDb: Initialized');
      
      // Cleanup expired entries on startup
      await _cleanupExpired();
    } catch (e) {
      if (kDebugMode) print('LyricsCacheDb: Init error: $e');
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
      if (kDebugMode) print('LyricsCacheDb: Get error: $e');
      return null;
    }
  }
  
  /// Store lyrics in cache
  Future<void> put(String key, String lyrics, bool isSynced, String provider) async {
    if (!_isInitialized || _database == null) return;
    
    try {
      final entry = LyricsCacheEntry(
        key: key,
        lyrics: lyrics,
        isSynced: isSynced,
        provider: provider,
        cachedAt: DateTime.now(),
      );
      
      await _database!.insert(
        _tableName,
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      if (kDebugMode) print('LyricsCacheDb: Cached lyrics for "$key"');
    } catch (e) {
      if (kDebugMode) print('LyricsCacheDb: Put error: $e');
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
      if (kDebugMode) print('LyricsCacheDb: Delete error: $e');
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
        print('LyricsCacheDb: Cleaned up $deleted expired entries');
      }
    } catch (e) {
      if (kDebugMode) print('LyricsCacheDb: Cleanup error: $e');
    }
  }
  
  /// Clear all cached lyrics
  Future<void> clear() async {
    if (!_isInitialized || _database == null) return;
    
    try {
      await _database!.delete(_tableName);
      if (kDebugMode) print('LyricsCacheDb: Cache cleared');
    } catch (e) {
      if (kDebugMode) print('LyricsCacheDb: Clear error: $e');
    }
  }
  
  /// Get cache statistics
  Future<Map<String, dynamic>> getStats() async {
    if (!_isInitialized || _database == null) {
      return {'count': 0, 'initialized': false};
    }
    
    try {
      final result = await _database!.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
      return {
        'count': result.first['count'] ?? 0,
        'initialized': true,
      };
    } catch (e) {
      return {'count': 0, 'initialized': true, 'error': e.toString()};
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
