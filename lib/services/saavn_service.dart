// lib/services/saavn_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/track.dart';

/// Service for interacting with the JioSaavn API (saavn.sumit.co)
/// This is a robust implementation using the official API documentation
class SaavnService {
  static const String _baseUrl = 'https://saavn.sumit.co/api';
  static const Duration _timeout = Duration(seconds: 15);
  
  /// Preprocess search query - DISABLED
  /// JioSaavn has limited international content, pass queries as-is
  String _preprocessQuery(String query) {
    return query.trim();
  }
  
  /// Search for songs with pagination support
  /// Returns up to [limit] songs. For comprehensive results, use limit=100 or higher
  Future<List<Track>> searchSongs(String query, {int page = 0, int limit = 100}) async {
    try {
      if (query.trim().isEmpty) {
        return [];
      }
      
      // Preprocess query to handle API limitations
      final processedQuery = _preprocessQuery(query);
      
      if (processedQuery.isEmpty) {
        if (kDebugMode) {
          print('SaavnService: Query became empty after preprocessing: "$query"');
        }
        return [];
      }
      
      final url = Uri.parse('$_baseUrl/search/songs')
          .replace(queryParameters: {
        'query': processedQuery,
        'page': page.toString(),
        'limit': limit.toString(),
      });
      
      if (kDebugMode) {
        if (processedQuery != query.trim()) {
          print('SaavnService: Preprocessed query: "$query" → "$processedQuery"');
        }
        print('SaavnService: Searching songs: "$processedQuery" (page: $page, limit: $limit)');
      }
      
      final response = await http.get(url).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] != true) {
          throw Exception('API returned success: false');
        }
        
        final int total = data['data']?['total'] ?? 0;
        final List<dynamic> results = data['data']?['results'] ?? [];
        final tracks = results.map((item) => _parseTrackFromSong(item)).toList();
        
        if (kDebugMode) {
          print('SaavnService: Found ${tracks.length} songs (total available: $total)');
        }
        
        return tracks;
      } else if (response.statusCode == 400) {
        // Bad request - try alternative search strategies
        if (kDebugMode) {
          print('SaavnService: Got 400 error, trying fallback search');
        }
        
        // Try removing more words or using original query
        if (processedQuery != query.trim()) {
          // Already preprocessed, try with original
          return await _searchWithFallback(query.trim(), page, limit);
        }
        
        throw Exception('HTTP 400: Bad Request - Query may contain unsupported characters');
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Error searching songs: $e');
      }
      rethrow;
    }
  }
  
  /// Fallback search with alternative strategies
  Future<List<Track>> _searchWithFallback(String query, int page, int limit) async {
    try {
      // Strategy 1: Try with just the last word (often the artist/song name)
      final words = query.split(' ');
      if (words.length > 1) {
        final lastWord = words.last;
        if (kDebugMode) {
          print('SaavnService: Fallback - trying last word: "$lastWord"');
        }
        
        final url = Uri.parse('$_baseUrl/search/songs')
            .replace(queryParameters: {
          'query': lastWord,
          'page': page.toString(),
          'limit': limit.toString(),
        });
        
        final response = await http.get(url).timeout(_timeout);
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            final List<dynamic> results = data['data']?['results'] ?? [];
            return results.map((item) => _parseTrackFromSong(item)).toList();
          }
        }
      }
      
      // Strategy 2: Try with first word
      if (words.isNotEmpty) {
        final firstWord = words.first;
        if (kDebugMode) {
          print('SaavnService: Fallback - trying first word: "$firstWord"');
        }
        
        final url = Uri.parse('$_baseUrl/search/songs')
            .replace(queryParameters: {
          'query': firstWord,
          'page': page.toString(),
          'limit': limit.toString(),
        });
        
        final response = await http.get(url).timeout(_timeout);
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            final List<dynamic> results = data['data']?['results'] ?? [];
            return results.map((item) => _parseTrackFromSong(item)).toList();
          }
        }
      }
      
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Fallback search also failed: $e');
      }
      return [];
    }
  }
  
  /// Search for songs and return ALL available results (up to 250)
  /// Use this for comprehensive searches when you need maximum coverage
  Future<List<Track>> searchSongsAll(String query) async {
    try {
      if (query.trim().isEmpty) {
        return [];
      }
      
      if (kDebugMode) {
        print('SaavnService: Performing comprehensive search for: "$query"');
      }
      
      // First, get the first batch to know total count
      final firstBatch = await searchSongs(query, page: 0, limit: 100);
      
      if (firstBatch.length < 100) {
        // If we got less than 100, we have all results
        return firstBatch;
      }
      
      // Get second batch if needed
      final secondBatch = await searchSongs(query, page: 1, limit: 100);
      
      // Combine results
      final allTracks = [...firstBatch, ...secondBatch];
      
      if (kDebugMode) {
        print('SaavnService: Comprehensive search returned ${allTracks.length} total songs');
      }
      
      return allTracks;
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Error in comprehensive search: $e');
      }
      // Return whatever we got so far
      return [];
    }
  }
  
  /// Get song details by ID
  Future<Track?> getSongById(String songId) async {
    try {
      final url = Uri.parse('$_baseUrl/songs/$songId');
      
      if (kDebugMode) {
        print('SaavnService: Getting song by ID: $songId');
      }
      
      final response = await http.get(url).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] != true) {
          throw Exception('API returned success: false');
        }
        
        final List<dynamic> songs = data['data'] ?? [];
        if (songs.isEmpty) {
          return null;
        }
        
        return _parseTrackFromSong(songs.first);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Error getting song by ID: $e');
      }
      return null;
    }
  }
  
  /// Get audio stream URL for a song
  Future<String> getAudioStreamUrl(String songId) async {
    try {
      final track = await getSongById(songId);
      
      if (track == null) {
        throw Exception('Song not found: $songId');
      }
      
      // The downloadUrl array contains different quality options
      // We already parsed the best quality URL in _parseTrackFromSong
      if (track.previewUrl.isEmpty) {
        throw Exception('No audio stream URL available');
      }
      
      if (kDebugMode) {
        print('SaavnService: Got audio stream URL for: $songId');
      }
      
      return track.previewUrl;
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Error getting audio stream URL: $e');
      }
      rethrow;
    }
  }
  
  /// Get trending/popular tracks
  Future<List<Track>> getTrendingTracks({int limit = 20}) async {
    try {
      // Use a curated playlist for trending tracks
      // Playlist ID 110858205 is a popular trending playlist
      final url = Uri.parse('$_baseUrl/playlists')
          .replace(queryParameters: {
        'id': '110858205',
        'limit': limit.toString(),
      });
      
      if (kDebugMode) {
        print('SaavnService: Getting trending tracks (limit: $limit)');
      }
      
      final response = await http.get(url).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] != true) {
          throw Exception('API returned success: false');
        }
        
        final List<dynamic> songs = data['data']?['songs'] ?? [];
        final tracks = songs
            .take(limit)
            .map((item) => _parseTrackFromSong(item))
            .toList();
        
        if (kDebugMode) {
          print('SaavnService: Found ${tracks.length} trending tracks');
        }
        
        return tracks;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Error getting trending tracks: $e');
      }
      rethrow;
    }
  }
  
  /// Get popular tracks (alias for search with popular query)
  Future<List<Track>> getPopularTracks({int limit = 20}) async {
    try {
      // Search for popular Bollywood and English hits
      final tracks = await searchSongs('top hits 2025', limit: limit);
      return tracks;
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Error getting popular tracks: $e');
      }
      // Fallback to trending if search fails
      return getTrendingTracks(limit: limit);
    }
  }
  
  /// Get song suggestions based on a song ID
  Future<List<Track>> getSongSuggestions(String songId, {int limit = 10}) async {
    try {
      final url = Uri.parse('$_baseUrl/songs/$songId/suggestions')
          .replace(queryParameters: {
        'limit': limit.toString(),
      });
      
      if (kDebugMode) {
        print('SaavnService: Getting suggestions for song: $songId');
      }
      
      final response = await http.get(url).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] != true) {
          throw Exception('API returned success: false');
        }
        
        final List<dynamic> songs = data['data'] ?? [];
        final tracks = songs.map((item) => _parseTrackFromSong(item)).toList();
        
        if (kDebugMode) {
          print('SaavnService: Found ${tracks.length} suggestions');
        }
        
        return tracks;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Error getting suggestions: $e');
      }
      return [];
    }
  }
  
  /// Parse a Track object from song JSON data
  Track _parseTrackFromSong(Map<String, dynamic> item) {
    // Extract highest quality image
    String imageUrl = '';
    final images = item['image'] as List<dynamic>?;
    if (images != null && images.isNotEmpty) {
      // Get the highest quality image (usually the last one)
      imageUrl = images.last['url'] ?? '';
    }
    
    // Extract highest quality audio URL
    String audioUrl = '';
    final downloadUrls = item['downloadUrl'] as List<dynamic>?;
    if (downloadUrls != null && downloadUrls.isNotEmpty) {
      // Sort by quality: 320kbps > 160kbps > 96kbps > 48kbps > 12kbps
      final qualityOrder = ['320kbps', '160kbps', '96kbps', '48kbps', '12kbps'];
      downloadUrls.sort((a, b) {
        final qualityA = a['quality'] ?? '';
        final qualityB = b['quality'] ?? '';
        final indexA = qualityOrder.indexOf(qualityA);
        final indexB = qualityOrder.indexOf(qualityB);
        return indexA.compareTo(indexB);
      });
      audioUrl = downloadUrls.first['url'] ?? '';
    }
    
    // Parse duration
    int durationSeconds = 0;
    if (item['duration'] is int) {
      durationSeconds = item['duration'];
    } else if (item['duration'] is String) {
      durationSeconds = int.tryParse(item['duration']) ?? 0;
    }
    
    // Extract artist names
    String artistName = 'Unknown Artist';
    final artists = item['artists'];
    if (artists is Map && artists['primary'] is List) {
      final primaryArtists = artists['primary'] as List<dynamic>;
      if (primaryArtists.isNotEmpty) {
        artistName = primaryArtists
            .map((a) => a['name'] ?? '')
            .where((n) => n.isNotEmpty)
            .join(', ');
      }
    }
    
    // Extract album name
    String albumName = 'Unknown Album';
    final album = item['album'];
    if (album is Map && album['name'] != null) {
      albumName = album['name'];
    }
    
    return Track(
      id: item['id'] ?? '',
      trackName: item['name'] ?? 'Unknown',
      artistName: artistName,
      albumName: albumName,
      previewUrl: audioUrl,
      albumArtUrl: imageUrl,
      source: 'saavn',
      duration: Duration(seconds: durationSeconds),
    );
  }
  
  /// Search for albums
  Future<List<Map<String, dynamic>>> searchAlbums(String query, {int page = 0, int limit = 10}) async {
    try {
      final url = Uri.parse('$_baseUrl/search/albums')
          .replace(queryParameters: {
        'query': query,
        'page': page.toString(),
        'limit': limit.toString(),
      });
      
      final response = await http.get(url).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] != true) {
          throw Exception('API returned success: false');
        }
        
        return List<Map<String, dynamic>>.from(data['data']?['results'] ?? []);
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Error searching albums: $e');
      }
      return [];
    }
  }
  
  /// Search for artists
  Future<List<Map<String, dynamic>>> searchArtists(String query, {int page = 0, int limit = 10}) async {
    try {
      // Preprocess query
      final processedQuery = _preprocessQuery(query);
      if (processedQuery.isEmpty) return [];
      
      final url = Uri.parse('$_baseUrl/search/artists')
          .replace(queryParameters: {
        'query': processedQuery,
        'page': page.toString(),
        'limit': limit.toString(),
      });
      
      if (kDebugMode) {
        print('SaavnService: Searching artists: "$processedQuery"');
      }
      
      final response = await http.get(url).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] != true) {
          throw Exception('API returned success: false');
        }
        
        final results = List<Map<String, dynamic>>.from(data['data']?['results'] ?? []);
        
        if (kDebugMode) {
          print('SaavnService: Found ${results.length} artists');
        }
        
        return results;
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Error searching artists: $e');
      }
      return [];
    }
  }
  
  /// Get songs by a specific artist
  /// This searches for the artist and returns their top songs
  Future<List<Track>> getArtistSongs(String artistName, {int limit = 100}) async {
    try {
      if (artistName.trim().isEmpty) return [];
      
      if (kDebugMode) {
        print('SaavnService: Getting songs for artist: "$artistName"');
      }
      
      // Strategy 1: Search for artist name directly to get their songs
      final artistSongs = await searchSongs(artistName, limit: limit);
      
      if (artistSongs.isNotEmpty) {
        // Filter to only include songs where the artist name matches
        final filteredSongs = artistSongs.where((track) {
          return track.artistName.toLowerCase().contains(artistName.toLowerCase());
        }).toList();
        
        if (filteredSongs.isNotEmpty) {
          if (kDebugMode) {
            print('SaavnService: Found ${filteredSongs.length} songs for artist');
          }
          return filteredSongs;
        }
      }
      
      // Strategy 2: Try searching with "artist name songs"
      final songsQuery = await searchSongs('$artistName songs', limit: limit);
      if (songsQuery.isNotEmpty) {
        return songsQuery;
      }
      
      // Strategy 3: Try searching with "artist name top hits"
      final hitsQuery = await searchSongs('$artistName top hits', limit: limit);
      return hitsQuery;
      
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Error getting artist songs: $e');
      }
      return [];
    }
  }
  
  /// Search for playlists
  Future<List<Map<String, dynamic>>> searchPlaylists(String query, {int page = 0, int limit = 10}) async {
    try {
      final url = Uri.parse('$_baseUrl/search/playlists')
          .replace(queryParameters: {
        'query': query,
        'page': page.toString(),
        'limit': limit.toString(),
      });
      
      final response = await http.get(url).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] != true) {
          throw Exception('API returned success: false');
        }
        
        return List<Map<String, dynamic>>.from(data['data']?['results'] ?? []);
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('SaavnService: Error searching playlists: $e');
      }
      return [];
    }
  }
}
