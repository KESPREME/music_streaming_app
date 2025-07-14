import 'dart:convert';
import 'dart:io'; // For SocketException
import 'package:flutter/services.dart'; // For PlatformException
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/api_service.dart';

class SpotifyService {
  // Replace with your Spotify Developer credentials
  static const String _clientId = 'b0d754792f364e2fa6b7731b460a75a4';
  static const String _clientSecret = 'e1290c6890f74502a21ea5e187995c69';
  static const String _redirectUri = 'musicapp://callback'; // Simplified URI scheme

  // Spotify API endpoints
  static const String _authEndpoint = 'https://accounts.spotify.com/authorize';
  static const String _tokenEndpoint = 'https://accounts.spotify.com/api/token';
  static const String _apiBaseUrl = 'https://api.spotify.com/v1';

  String? _accessToken;
  final ApiService _apiService;

  SpotifyService(this._apiService);

  Future<String> _authenticate() async {
    if (_accessToken != null) return _accessToken!;

    // Define OAuth scopes needed
    final scopes = [
      'playlist-read-private',
      'playlist-read-collaborative',
      'user-library-read',
    ];

    // Build authorization URL
    final authUrl = Uri.parse('$_authEndpoint'
        '?client_id=$_clientId'
        '&response_type=code'
        '&redirect_uri=$_redirectUri'
        '&scope=${scopes.join('%20')}');

    try {
      // Launch the authorization flow
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: 'musicapp', // Just the scheme part
      );

      // Extract the authorization code
      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) throw Exception('Authorization code not found');

      // Exchange code for access token
      final basicAuth = base64Encode(utf8.encode('$_clientId:$_clientSecret'));
      final response = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {
          'Authorization': 'Basic $basicAuth',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': _redirectUri,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _accessToken = data['access_token'];
        return _accessToken!;
      } else {
        throw Exception('Failed to get access token: ${response.body}');
      }
    } on PlatformException catch (e) {
      // This can happen if the user cancels the web auth flow.
      print('Spotify Auth Error (Platform): ${e.message}');
      throw Exception('Authentication cancelled or failed.');
    } on SocketException catch (e) {
      print('Spotify Auth Error (Network): $e');
      throw Exception('Network error during authentication. Please check your connection.');
    } catch (e) {
      print('Authentication error: $e');
      throw Exception('Failed to authenticate with Spotify: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getUserPlaylists() async {
    try {
      final token = await _authenticate();

      final response = await http.get(
        Uri.parse('$_apiBaseUrl/me/playlists?limit=50'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['items']);
      } else {
        throw Exception('Failed to fetch playlists: ${response.body}');
      }
    } catch (e) {
      print('Error fetching playlists: $e');
      throw Exception('Failed to fetch playlists: $e');
    }
  }

  Future<Playlist> getPlaylistWithTracks(String playlistId, String playlistName, String imageUrl) async {
    try {
      final token = await _authenticate();

      final response = await http.get(
        Uri.parse('$_apiBaseUrl/playlists/$playlistId/tracks'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;

        final tracks = items.where((item) => item['track'] != null).map((item) {
          final track = item['track'];
          final artists = track['artists'] as List;
          final artistName = artists.isNotEmpty ? artists[0]['name'] : 'Unknown Artist';

          return Track(
            id: track['id'],
            trackName: track['name'],
            artistName: artistName,
            albumName: track['album']['name'],
            previewUrl: track['preview_url'] ?? '',
            albumArtUrl: track['album']['images'].isNotEmpty
                ? track['album']['images'][0]['url']
                : '',
            source: 'spotify', // Mark as Spotify source
          );
        }).toList();

        // Convert Spotify tracks to YouTube tracks
        List<Track> youtubeTracks = [];
        for (var track in tracks) {
          try {
            // Search for the track on YouTube
            final searchQuery = "${track.trackName} ${track.artistName} official audio";
            final searchResults = await _apiService.fetchTracksByQuery(searchQuery);

            if (searchResults.isNotEmpty) {
              // Use the first result but keep the original track name and artist
              final youtubeTrack = Track(
                id: searchResults[0].id,
                trackName: track.trackName,
                artistName: track.artistName,
                albumName: track.albumName,
                previewUrl: searchResults[0].previewUrl,
                albumArtUrl: track.albumArtUrl, // Keep Spotify album art
                source: 'youtube',
              );
              youtubeTracks.add(youtubeTrack);
            } else {
              // If no YouTube results, just add the original track
              youtubeTracks.add(track);
            }
          } catch (e) {
            print('Error converting track to YouTube: $e');
            // Just add the original track if conversion fails
            youtubeTracks.add(track);
          }
        }

        return Playlist(
          id: playlistId,
          name: playlistName,
          imageUrl: imageUrl,
          tracks: youtubeTracks, // Use the converted tracks
        );
      } else {
        throw Exception('Failed to fetch playlist tracks: ${response.body}');
      }
    } catch (e) {
      print('Error fetching playlist tracks: $e');
      throw Exception('Failed to fetch playlist tracks: $e');
    }
  }

  // Helper method to search for a track on YouTube
  Future<Track?> findYouTubeTrack(Track spotifyTrack) async {
    try {
      final searchQuery = "${spotifyTrack.trackName} ${spotifyTrack.artistName} official audio";
      final searchResults = await _apiService.fetchTracksByQuery(searchQuery);

      if (searchResults.isNotEmpty) {
        return Track(
          id: searchResults[0].id,
          trackName: spotifyTrack.trackName,
          artistName: spotifyTrack.artistName,
          albumName: spotifyTrack.albumName,
          previewUrl: searchResults[0].previewUrl,
          albumArtUrl: spotifyTrack.albumArtUrl,
          source: 'youtube',
        );
      }
      return null;
    } catch (e) {
      print('Error finding YouTube track: $e');
      return null;
    }
  }
}
