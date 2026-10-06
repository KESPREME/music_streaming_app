// lib/services/lyrics/lrc_red_provider.dart
// lrc.red - Apple Music syllable timings addressed by recording.
//
// This provider leads the default order. It serves the same Apple catalogue as
// BiniLyrics and PaxSenix with the same syllable resolution, but is asked
// first because it is the one host whose availability does not depend on a
// volunteer mirror being up: when the mirror BiniLyrics normally reads from is
// down, lrc.red usually still has the document.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/lyrics_entry.dart';
import 'apple_lyrics_common.dart';

/// One row of lrc.red's search answer.
class _LrcRedHit {
  _LrcRedHit({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationSec,
    required this.instrumental,
  });

  final int id;
  final String title;
  final String artist;
  final double durationSec;
  final bool instrumental;
}

class LrcRedProvider extends AppleLyricsSource {
  static const String _base = 'https://lrc.red/';
  static const String _searchUrl = '${_base}search.json';
  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client = http.Client();

  /// Syllable-synced lyrics for [query], or null when this host has none.
  ///
  /// Line-synced results are not returned. This source exists for its syllable
  /// timings, and a plain line-synced answer from here is no better than the
  /// cheaper providers already in the list - letting it answer would take the
  /// "prioritize word sync" setting out of the caller's hands.
  Future<List<LyricsEntry>?> getLyrics(AppleLyricsQuery query) async {
    final hits = await _search(query);
    if (hits.isEmpty) return null;

    // Duration is the tie-breaker that matters. Two candidates with the same
    // name are different recordings - a live cut, an edit - and their timings
    // are not interchangeable.
    final sorted = List<_LrcRedHit>.of(hits)
      ..sort((a, b) {
        final da = (a.durationSec - (query.durationSeconds ?? a.durationSec)).abs();
        final db = (b.durationSec - (query.durationSeconds ?? b.durationSec)).abs();
        return da.compareTo(db);
      });

    for (final hit in sorted) {
      if (!AppleLyricsSource.titlesMatch(hit.title, query.title)) continue;
      if (!AppleLyricsSource.durationMatches(
        hit.durationSec.round(),
        query.durationSeconds,
      )) {
        continue;
      }
      if (hit.instrumental) continue;

      final entries = await fetchTtml('${_base}s/${hit.id}.ttml');
      if (entries != null && entries.isNotEmpty) return entries;
    }
    return null;
  }

  Future<List<_LrcRedHit>> _search(AppleLyricsQuery query) async {
    try {
      // Free-text: this host has no lookup by ISRC. That is precisely why it
      // is worth having alongside BiniLyrics, which does.
      final uri = Uri.parse(_searchUrl).replace(queryParameters: {
        'q': '${query.title} ${query.artist}',
      });

      final response = await _client.get(uri, headers: const {
        'User-Agent': 'MusicStreamingApp/1.0.0 (lyrics)',
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];

      final hits = <_LrcRedHit>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final id = item['id'];
        final title = item['trackName'] ?? item['title'];
        final artist = item['artistName'] ?? item['artist'];
        final duration = item['duration'];
        if (id is! num || title is! String) continue;
        hits.add(_LrcRedHit(
          id: id.toInt(),
          title: title,
          artist: artist is String ? artist : '',
          durationSec: duration is num ? duration.toDouble() : 0,
          instrumental: item['instrumental'] == true,
        ));
      }
      if (kDebugMode) {
        debugPrint('LrcRedProvider: search returned ${hits.length} hits');
      }
      return hits;
    } catch (e) {
      if (kDebugMode) debugPrint('LrcRedProvider: search failed: $e');
      return const [];
    }
  }
}