import 'package:sqflite/sqflite.dart';

/// Persistence for the search-followup graph (spec #7/#53): local-only.
class SearchFollowupStore {
  static const _table = 'search_followups_v1';

  Future<Database> _db() async {
    return openDatabase('search_followups_v1.db',
        version: 1, onCreate: (db, v) => db.execute('''
          CREATE TABLE $_table(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            query_normalized TEXT NOT NULL,
            track_id TEXT NOT NULL,
            artist_name TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )'''));
  }

  Future<void> saveTransition(
      String queryNormalized, String trackId, String artistName) async {
    final db = await _db();
    await db.insert(_table, {
      'query_normalized': queryNormalized,
      'track_id': trackId,
      'artist_name': artistName,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<SearchTransition>> loadTransitions() async {
    try {
      final db = await _db();
      final rows =
          await db.query(_table, orderBy: 'created_at DESC', limit: 500);
      return rows
          .map((r) => SearchTransition(
                queryNormalized: r['query_normalized'] as String,
                trackId: r['track_id'] as String,
                artistName: r['artist_name'] as String,
                createdAt:
                    DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

class SearchTransition {
  const SearchTransition({
    required this.queryNormalized,
    required this.trackId,
    required this.artistName,
    required this.createdAt,
  });

  final String queryNormalized;
  final String trackId;
  final String artistName;
  final DateTime createdAt;
}
