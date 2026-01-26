// lib/services/lyrics/lrclib_provider.dart
// LrcLib API integration - free lyrics database


import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// LrcLib API provider for synced lyrics
/// API Documentation: https://lrclib.net/docs
class LrcLibProvider {
  static const String _baseUrl = 'https://lrclib.net';
  static const String _userAgent = 'MusicStreamingApp/1.0.0 (https://github.com/example)';
  
  final http.Client _httpClient = http.Client();
  
  /// Get synced lyrics for a track
  /// Returns LRC formatted lyrics or null if not found
  Future<String?> getLyrics({
    required String title,
    required String artist,
    int? durationSeconds,
    String? album,
  }) async {
    try {
      // First try exact match with duration
      if (durationSeconds != null) {
        final exactResult = await _getExactMatch(
          title: title,
          artist: artist,
          duration: durationSeconds,
          album: album,
        );
        if (exactResult != null) return exactResult;
      }
      
      // Fall back to search
      return await _searchLyrics(
        title: title,
        artist: artist,
        duration: durationSeconds,
      );
      
    } catch (e) {
      if (kDebugMode) {
        print('LrcLibProvider: Error getting lyrics: $e');
      }
      return null;
    }
  }
  
  /// Get all possible lyrics options for a track
  Future<List<LrcLibResult>> getAllLyrics({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    try {
      final results = await _search(title: title, artist: artist);
      
      // Sort by relevance (duration match if provided)
      if (durationSeconds != null) {
        results.sort((a, b) {
          final diffA = (a.duration - durationSeconds).abs();
          final diffB = (b.duration - durationSeconds).abs();
          return diffA.compareTo(diffB);
        });
      }
      
      return results;
      
    } catch (e) {
      if (kDebugMode) {
        print('LrcLibProvider: Error getting all lyrics: $e');
      }
      return [];
    }
  }
  
  /// Try to get exact match using the /api/get endpoint
  Future<String?> _getExactMatch({
    required String title,
    required String artist,
    required int duration,
    String? album,
  }) async {
    try {
      final params = {
        'track_name': title,
        'artist_name': artist,
        'duration': duration.toString(),
      };
      if (album != null && album.isNotEmpty) {
        params['album_name'] = album;
      }
      
      final uri = Uri.parse('$_baseUrl/api/get').replace(queryParameters: params);
      
      final response = await _httpClient.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Prefer synced lyrics
        final syncedLyrics = data['syncedLyrics'] as String?;
        if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
          return syncedLyrics;
        }
        // Fall back to plain lyrics
        return data['plainLyrics'] as String?;
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('LrcLibProvider: Exact match failed: $e');
      }
      return null;
    }
  }
  
  /// Search for lyrics using the /api/search endpoint
  Future<String?> _searchLyrics({
    required String title,
    required String artist,
    int? duration,
  }) async {
    final results = await _search(title: title, artist: artist);
    
    if (results.isEmpty) return null;
    
    // Find best match
    LrcLibResult? bestMatch;
    
    if (duration != null) {
      // Find closest duration match
      int bestDiff = 999999;
      for (final result in results) {
        final diff = (result.duration - duration).abs();
        if (diff < bestDiff && result.syncedLyrics != null) {
          bestDiff = diff;
          bestMatch = result;
        }
      }
      
      // Also try string similarity for title matching
      if (bestMatch == null) {
        for (final result in results) {
          if (_stringSimilarity(result.trackName, title) > 0.8 &&
              result.syncedLyrics != null) {
            bestMatch = result;
            break;
          }
        }
      }
    }
    
    // Fall back to first result with synced lyrics
    bestMatch ??= results.firstWhere(
      (r) => r.syncedLyrics != null && r.syncedLyrics!.isNotEmpty,
      orElse: () => results.first,
    );
    
    return bestMatch.syncedLyrics ?? bestMatch.plainLyrics;
  }
  
  /// Search the LrcLib API
  Future<List<LrcLibResult>> _search({
    required String title,
    String? artist,
  }) async {
    try {
      final params = <String, String>{
        'track_name': title,
      };
      if (artist != null && artist.isNotEmpty) {
        params['artist_name'] = artist;
      }
      
      final uri = Uri.parse('$_baseUrl/api/search').replace(queryParameters: params);
      
      if (kDebugMode) {
        print('LrcLibProvider: Searching: $uri');
      }
      
      final response = await _httpClient.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
      );
      
      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('LrcLibProvider: Search failed: ${response.statusCode}');
        }
        return [];
      }
      
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => LrcLibResult.fromJson(item)).toList();
      
    } catch (e) {
      if (kDebugMode) {
        print('LrcLibProvider: Search error: $e');
      }
      return [];
    }
  }
  
  /// Calculate string similarity (Levenshtein-based)
  double _stringSimilarity(String s1, String s2) {
    final a = s1.toLowerCase().trim();
    final b = s2.toLowerCase().trim();
    
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    
    final distance = _levenshteinDistance(a, b);
    final maxLength = a.length > b.length ? a.length : b.length;
    
    return 1.0 - (distance / maxLength);
  }
  
  /// Calculate Levenshtein distance
  int _levenshteinDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;
    
    List<int> v0 = List.generate(s2.length + 1, (i) => i);
    List<int> v1 = List.filled(s2.length + 1, 0);
    
    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      
      for (int j = 0; j < s2.length; j++) {
        final cost = s1[i] == s2[j] ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
      }
      
      final temp = v0;
      v0 = v1;
      v1 = temp;
    }
    
    return v0[s2.length];
  }
  
  void dispose() {
    _httpClient.close();
  }
}

/// Result from LrcLib API
class LrcLibResult {
  final int id;
  final String trackName;
  final String artistName;
  final String? albumName;
  final int duration;
  final String? syncedLyrics;
  final String? plainLyrics;
  
  const LrcLibResult({
    required this.id,
    required this.trackName,
    required this.artistName,
    this.albumName,
    required this.duration,
    this.syncedLyrics,
    this.plainLyrics,
  });
  
  factory LrcLibResult.fromJson(Map<String, dynamic> json) {
    return LrcLibResult(
      id: json['id'] ?? 0,
      trackName: json['trackName'] ?? json['name'] ?? '',
      artistName: json['artistName'] ?? '',
      albumName: json['albumName'],
      duration: json['duration'] ?? 0,
      syncedLyrics: json['syncedLyrics'],
      plainLyrics: json['plainLyrics'],
    );
  }
}
