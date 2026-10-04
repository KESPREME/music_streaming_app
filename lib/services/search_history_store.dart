import 'package:shared_preferences/shared_preferences.dart';

import '../models/search_history_entry.dart';

/// Persistent "Recent searches".
///
/// Holds *entries* rather than query strings, so a row can carry the artwork
/// and identity of something the user actually played and can be tapped to play
/// it again, instead of only echoing the words they typed. A typed query is
/// still a first-class entry - it is just one with no artwork, and tapping it
/// re-runs the search.
///
/// Stored as a JSON string rather than a string list, because an entry is a
/// struct and a query can contain any character.
///
/// On disk under a *new* key. The previous release stored a `StringList` under
/// [legacyKey]; reusing that key for a string would be a type conflict in
/// SharedPreferences, so the old list is read once, converted, and left alone.
class SearchHistoryStore {
  static const String _key = 'recent_search_entries';
  static const String legacyKey = 'recent_searches';
  static const int maxEntries = 10;

  final List<SearchHistoryEntry> _entries = [];
  List<SearchHistoryEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        _entries
          ..clear()
          ..addAll(SearchHistoryEntry.decodeList(raw).take(maxEntries));
        return;
      }

      // First run after the upgrade: bring the old query strings across as
      // query entries so nobody loses the history they had.
      final migrated = _migrateLegacy(prefs);
      _entries
        ..clear()
        ..addAll(migrated.take(maxEntries));
      if (migrated.isNotEmpty) await _persist();
    } catch (_) {
      // Corrupt storage -> start clean rather than crash the search tab.
    }
  }

  List<SearchHistoryEntry> _migrateLegacy(SharedPreferences prefs) {
    try {
      return (prefs.getStringList(legacyKey) ?? const <String>[])
          .where((q) => q.trim().isNotEmpty)
          .map(SearchHistoryEntry.query)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Records [entry], or moves an existing row with the same id back to the top.
  Future<void> add(SearchHistoryEntry entry) async {
    if (entry.id.trim().isEmpty) return;
    _entries
      ..removeWhere((e) => e.id.toLowerCase() == entry.id.toLowerCase())
      ..insert(0, entry);
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    await _persist();
  }

  /// Records a typed query, unless a track with the same id is already there.
  ///
  /// Not simply "always insert": searching a term whose name is also a track
  /// title should not push the artwork row the user played off the list in
  /// favour of a bare text row for the same thing.
  Future<void> addQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    // Compared against the track's *title*, not its id: a track row's id is its
    // video id, which will never equal the words the user typed. Comparing ids
    // here silently never matches, and the bare text row lands next to the
    // artwork row for the same song.
    final clash = _entries.any(
      (e) =>
          e.kind == SearchHistoryKind.track &&
          e.title.toLowerCase() == trimmed.toLowerCase(),
    );
    if (clash) return;
    await add(SearchHistoryEntry.query(trimmed));
  }

  Future<void> addTrack({
    required String id,
    required String title,
    required String artist,
    required String artworkUrl,
  }) {
    if (id.trim().isEmpty) return Future<void>.value();
    return add(SearchHistoryEntry.track(
      id: id,
      title: title,
      artist: artist,
      artworkUrl: artworkUrl,
    ));
  }

  Future<void> remove(String id) async {
    _entries.removeWhere((e) => e.id.toLowerCase() == id.toLowerCase());
    await _persist();
  }

  Future<void> clear() async {
    _entries.clear();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, SearchHistoryEntry.encodeList(_entries));
    } catch (_) {
      // Persist failure is non-fatal - in-memory history still works.
    }
  }
}
