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

  final http.Client? _client;
  final Future<String> Function()? _tokenOverride;
  final Future<List<Track>> Function(String query)? _searchOverride;

  SpotifyService({
    http.Client? client,
    Future<String> Function()? tokenProvider,
    Future<List<Track>> Function(String query)? search,
  })  : _client = client,
        _tokenOverride = tokenProvider,
        _searchOverride = search;

  /// Whether this build carries Spotify credentials. Without them nothing can
  /// connect, and the import screen says so up front.
  static bool get isConfigured => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  /// Signed in to Spotify in this session.
  bool get isConnected => _accessToken != null;

  Future<http.Response> _get(Uri uri, String token) =>
      (_client?.get ?? http.get)(uri, headers: {'Authorization': 'Bearer $token'});

  Future<String> _token() => _tokenOverride?.call() ?? _authenticate();

  Future<List<Track>> _search(String q) =>
      _searchOverride?.call(q) ?? _innerTubeService.searchSongs(q, limit: 3);
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

  /// Every playlist the listener owns or follows (Spotify pages them 50 at a
  /// time; all pages are read).
  Future<List<Map<String, dynamic>>> getUserPlaylists() async {
    try {
      final token = await _token();
      final out = <Map<String, dynamic>>[];
      Uri? next = Uri.parse('$_apiBaseUrl/me/playlists?limit=50');
      var pages = 0;
      while (next != null && pages < 20) {
        pages++;
        final response = await _get(next, token);
        if (response.statusCode != 200) {
          throw Exception('Failed to fetch playlists: ${response.statusCode}');
        }
        final data = json.decode(response.body) as Map<String, dynamic>;
        for (final item in (data['items'] as List? ?? const [])) {
          if (item is Map<String, dynamic> && item['id'] is String) out.add(item);
        }
        final n = data['next'];
        next = n is String && n.isNotEmpty ? Uri.parse(n) : null;
      }
      return out;
    } catch (e) {
      debugPrint('Error fetching playlists: $e');
      throw Exception('Failed to fetch playlists: $e');
    }
  }

  /// A Spotify playlist as a playlist here: every page of its songs (Spotify
  /// returns 100 at a time; this used to stop at the first page), each matched
  /// to YouTube Music.
  ///
  /// [onProgress] reports songs matched so far out of the total. [isCancelled]
  /// is checked between songs; a cancelled import throws [ImportCancelled] and
  /// saves nothing. A song with no match is kept as a Spotify song: playback
  /// already looks those up by name when they are played.
  Future<Playlist> getPlaylistWithTracks(
    String playlistId,
    String playlistName,
    String imageUrl, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final token = await _token();
    final source = <Track>[];
    Uri? next = Uri.parse('$_apiBaseUrl/playlists/$playlistId/tracks?limit=100');
    var pages = 0;
    while (next != null && pages < 100) {
      pages++;
      final response = await _get(next, token);
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch playlist tracks: ${response.statusCode}');
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      for (final item in (data['items'] as List? ?? const [])) {
        final track = item is Map ? item['track'] : null;
        if (track is! Map || track['id'] is! String) continue; // local files, removed songs
        final artists = (track['artists'] as List?) ?? const [];
        final album = track['album'] as Map?;
        final images = (album?['images'] as List?) ?? const [];
        source.add(Track(
          id: track['id'] as String,
          trackName: (track['name'] as String?) ?? '',
          artistName: artists.isNotEmpty ? (artists[0]['name'] as String? ?? 'Unknown Artist') : 'Unknown Artist',
          albumName: (album?['name'] as String?) ?? '',
          previewUrl: (track['preview_url'] as String?) ?? '',
          albumArtUrl: images.isNotEmpty ? (images[0]['url'] as String? ?? '') : '',
          durationMs: track['duration_ms'] is int ? track['duration_ms'] as int : null,
          isExplicit: track['explicit'] == true,
          source: 'spotify',
        ));
      }
      final n = data['next'];
      next = n is String && n.isNotEmpty ? Uri.parse(n) : null;
    }

    final total = source.length;
    onProgress?.call(0, total);
    final tracks = <Track>[];
    for (var i = 0; i < source.length; i++) {
      if (isCancelled?.call() ?? false) throw const ImportCancelled();
      final s = source[i];
      try {
        final results = await _search('${s.trackName} ${s.artistName}');
        if (results.isNotEmpty) {
          tracks.add(Track(
            id: results[0].id,
            trackName: s.trackName,
            artistName: s.artistName,
            albumName: s.albumName,
            previewUrl: results[0].previewUrl,
            albumArtUrl: s.albumArtUrl,
            durationMs: s.durationMs,
            isExplicit: s.isExplicit,
            source: 'youtube',
          ));
        } else {
          tracks.add(s);
        }
      } catch (e) {
        debugPrint('Error converting track to YouTube: $e');
        tracks.add(s);
      }
      onProgress?.call(i + 1, total);
    }

    return Playlist(
      id: playlistId,
      name: playlistName,
      imageUrl: imageUrl,
      tracks: tracks,
    );
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
       final token = await _token();
       final response = await _get(
          Uri.parse('$_apiBaseUrl/playlists/$playlistId?fields=id,name,images,tracks.total'), token);

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

/// Thrown when an import is cancelled between songs.
class ImportCancelled implements Exception {
  const ImportCancelled();
}

/// The playlist id in a Spotify playlist link, or null.
/// Accepts `open.spotify.com/playlist/ID`, `/intl-xx/playlist/ID`, a `?si=` suffix, and `spotify:playlist:ID`.
String? spotifyPlaylistIdFrom(String input) {
  final s = input.trim();
  final uri = RegExp(r'^spotify:playlist:([A-Za-z0-9]{10,})$').firstMatch(s);
  if (uri != null) return uri.group(1);
  final m = RegExp(r'spotify\.com/(?:[a-z-]+/)?playlist/([A-Za-z0-9]{10,})').firstMatch(s);
  return m?.group(1);
}
