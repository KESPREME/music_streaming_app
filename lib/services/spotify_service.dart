import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io'; // For SocketException
import 'package:flutter/services.dart'; // For PlatformException
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import 'innertube/innertube_service.dart';

class SpotifyService {
  // Credentials are injected at build time via --dart-define:
  // flutter build apk --dart-define=SPOTIFY_CLIENT_ID=xxx --dart-define=SPOTIFY_CLIENT_SECRET=yyy
  // Rotate any previously committed credentials on the Spotify developer dashboard.
  static const String _clientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
  static const String _clientSecret =
      String.fromEnvironment('SPOTIFY_CLIENT_SECRET');
  static const String _redirectUri = 'musicapp://callback'; // Simplified URI scheme

  // Spotify API endpoints
  static const String _authEndpoint = 'https://accounts.spotify.com/authorize';
  static const String _tokenEndpoint = 'https://accounts.spotify.com/api/token';
  static const String _apiBaseUrl = 'https://api.spotify.com/v1';

  String? _accessToken;
  final InnerTubeService _innerTubeService = InnerTubeService();

  SpotifyService();

  Future<String> _authenticate() async {
    if (_accessToken != null) return _accessToken!;

    if (_clientId.isEmpty || _clientSecret.isEmpty) {
      throw Exception(
        'Spotify credentials missing. Build with --dart-define=SPOTIFY_CLIENT_ID=... '
        '--dart-define=SPOTIFY_CLIENT_SECRET=...',
      );
    }

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
      debugPrint('Spotify Auth Error (Platform): ${e.message}');
      throw Exception('Authentication cancelled or failed.');
    } on SocketException catch (e) {
      debugPrint('Spotify Auth Error (Network): $e');
      throw Exception('Network error during authentication. Please check your connection.');
    } catch (e) {
      debugPrint('Authentication error: $e');
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
      debugPrint('Error fetching playlists: $e');
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

        // Convert Spotify tracks to YouTube tracks using InnerTube
        List<Track> youtubeTracks = [];
        for (var track in tracks) {
          try {
            // Search for the track on YouTube Music using InnerTube
            final searchQuery = "${track.trackName} ${track.artistName}";
            final searchResults = await _innerTubeService.searchSongs(searchQuery, limit: 3);

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
            debugPrint('Error converting track to YouTube: $e');
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
      debugPrint('Error fetching playlist tracks: $e');
      throw Exception('Failed to fetch playlist tracks: $e');
    }
  }

  // Helper method to search for a track on YouTube
  Future<Track?> findYouTubeTrack(Track spotifyTrack) async {
    try {
      final searchQuery = "${spotifyTrack.trackName} ${spotifyTrack.artistName}";
      final searchResults = await _innerTubeService.searchSongs(searchQuery, limit: 3);

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
      debugPrint('Error finding YouTube track: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> getPlaylistMetadata(String playlistId) async {
    try {
       final token = await _authenticate();
       final response = await http.get(
        Uri.parse('$_apiBaseUrl/playlists/$playlistId?fields=id,name,images'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'id': data['id'],
          'name': data['name'],
          'images': data['images'] ?? [],
        };
      } else {
        throw Exception('Failed to fetch playlist metadata: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch playlist metadata: $e');
    }
  }
}



