import 'package:shared_preferences/shared_preferences.dart';

/// Persistent "Recently Searched" history.
///
/// SharedPreferences-backed (matches ThemeProvider pattern), capped,
/// deduped with move-to-front. UI reads [entries] after [load]; mutations
/// persist immediately and update [entries] in place.
class SearchHistoryStore {
  static const String _key = 'recent_searches';
  static const int maxEntries = 10;

  final List<String> _entries = [];
  List<String> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_key) ?? const [];
      _entries
        ..clear()
        ..addAll(saved.take(maxEntries));
    } catch (_) {
      // Corrupt storage → start clean rather than crash the search tab.
    }
  }

  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _entries
      ..remove(trimmed)
      ..insert(0, trimmed);
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    await _persist();
  }

  Future<void> remove(String query) async {
    _entries.remove(query);
    await _persist();
  }

  Future<void> clear() async {
    _entries.clear();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, _entries);
    } catch (_) {
      // Persist failure is non-fatal — in-memory history still works.
    }
  }
}
