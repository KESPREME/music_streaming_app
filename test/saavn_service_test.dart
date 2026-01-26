// Test file for SaavnService
// Run this to verify the API integration works correctly

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/saavn_service.dart';

void main() {
  late SaavnService saavnService;

  setUp(() {
    saavnService = SaavnService();
  });

  group('SaavnService Tests', () {
    test('Search songs returns results', () async {
      final results = await saavnService.searchSongs('Believer', limit: 5);
      
      expect(results, isNotEmpty);
      expect(results.length, lessThanOrEqualTo(5));
      expect(results.first.trackName, isNotEmpty);
      expect(results.first.id, isNotEmpty);
      expect(results.first.source, equals('saavn'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Get song by ID returns track', () async {
      // First search for a song to get a valid ID
      final searchResults = await saavnService.searchSongs('Believer', limit: 1);
      expect(searchResults, isNotEmpty);
      
      final songId = searchResults.first.id;
      final track = await saavnService.getSongById(songId);
      
      expect(track, isNotNull);
      expect(track!.id, equals(songId));
      expect(track.previewUrl, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Get audio stream URL returns valid URL', () async {
      // First search for a song
      final searchResults = await saavnService.searchSongs('Believer', limit: 1);
      expect(searchResults, isNotEmpty);
      
      final songId = searchResults.first.id;
      final streamUrl = await saavnService.getAudioStreamUrl(songId);
      
      expect(streamUrl, isNotEmpty);
      expect(streamUrl, startsWith('http'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Get trending tracks returns results', () async {
      final trending = await saavnService.getTrendingTracks(limit: 10);
      
      expect(trending, isNotEmpty);
      expect(trending.length, lessThanOrEqualTo(10));
      expect(trending.first.source, equals('saavn'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Get popular tracks returns results', () async {
      final popular = await saavnService.getPopularTracks(limit: 10);
      
      expect(popular, isNotEmpty);
      expect(popular.length, lessThanOrEqualTo(10));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Get song suggestions returns results', () async {
      // First search for a song
      final searchResults = await saavnService.searchSongs('Believer', limit: 1);
      expect(searchResults, isNotEmpty);
      
      final songId = searchResults.first.id;
      final suggestions = await saavnService.getSongSuggestions(songId, limit: 5);
      
      expect(suggestions, isNotEmpty);
      expect(suggestions.length, lessThanOrEqualTo(5));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Search albums returns results', () async {
      final albums = await saavnService.searchAlbums('Evolve', limit: 5);
      
      expect(albums, isNotEmpty);
      expect(albums.length, lessThanOrEqualTo(5));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Search artists returns results', () async {
      final artists = await saavnService.searchArtists('Imagine Dragons', limit: 5);
      
      expect(artists, isNotEmpty);
      expect(artists.length, lessThanOrEqualTo(5));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Search playlists returns results', () async {
      final playlists = await saavnService.searchPlaylists('Indie', limit: 5);
      
      expect(playlists, isNotEmpty);
      expect(playlists.length, lessThanOrEqualTo(5));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Track has proper metadata', () async {
      final results = await saavnService.searchSongs('Believer', limit: 1);
      expect(results, isNotEmpty);
      
      final track = results.first;
      
      expect(track.id, isNotEmpty);
      expect(track.trackName, isNotEmpty);
      expect(track.artistName, isNotEmpty);
      expect(track.albumName, isNotEmpty);
      expect(track.albumArtUrl, isNotEmpty);
      expect(track.previewUrl, isNotEmpty);
      expect(track.source, equals('saavn'));
      expect(track.duration?.inSeconds ?? 0, greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Handles invalid song ID gracefully', () async {
      final track = await saavnService.getSongById('invalid_id_12345');
      expect(track, isNull);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Pagination works correctly', () async {
      final page0 = await saavnService.searchSongs('Bollywood', page: 0, limit: 5);
      final page1 = await saavnService.searchSongs('Bollywood', page: 1, limit: 5);
      
      expect(page0, isNotEmpty);
      expect(page1, isNotEmpty);
      
      // Results should be different
      expect(page0.first.id, isNot(equals(page1.first.id)));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
