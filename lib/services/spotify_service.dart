import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io'; // For SocketException
import 'package:flutter/services.dart'; // For PlatformException
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import 'innertube/innertube_service.dart';
import 'spotify_public.dart';

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
  final SpotifyPublicPlaylists _public;

  SpotifyService({
    http.Client? client,
    Future<String> Function()? tokenProvider,
    Future<List<Track>> Function(String query)? search,
    SpotifyPublicPlaylists? public,
  })  : _client = client,
        _tokenOverride = tokenProvider,
        _searchOverride = search,
        _public = public ?? SpotifyPublicPlaylists(client: client);

  /// Whether this build carries Spotify credentials. Without them nothing can
  /// connect, and the import screen says so up front.
  static bool get isConfigured => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  /// Signed in to Spotify in this session.
  bool get isConnected => _accessToken != null;

  Future<http.Response> _get(Uri uri, String token) =>
      (_client?.get ?? http.get)(uri, headers: {'Authorization': 'Bearer $token'});

  Future<String> _token() => _tokenOverride?.call() ?? _authenticate();

  Future<List<Track>> _search(String q) =>
      _searchOverride?.call(q) ?? _innerTubeService.searchSongs(q, limit: 5);
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
    final tracks = await _matchAll(source, onProgress: onProgress, isCancelled: isCancelled);
    assert(tracks.length == total);

    return Playlist(
      id: playlistId,
      name: playlistName,
      imageUrl: imageUrl,
      tracks: tracks,
    );
  }

  /// A public playlist from a pasted link: no Spotify account and no build
  /// credentials needed (see spotify_public.dart). [onReading] reports songs
  /// read past the embed's first 100; [onProgress] then reports matching.
  Future<({Playlist playlist, int? total})> getPublicPlaylistWithTracks(
    String playlistId, {
    void Function(String name)? onName,
    void Function(int read, int total)? onReading,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final pub = await _public.fetch(playlistId, onSongs: onReading, isCancelled: isCancelled);
    if (isCancelled?.call() ?? false) throw const ImportCancelled();
    onName?.call(pub.name);
    final source = [
      for (final t in pub.tracks)
        Track(
          id: t.id,
          trackName: t.title,
          artistName: t.artists.isEmpty ? 'Unknown Artist' : t.artists.join(', '),
          albumName: '',
          previewUrl: '',
          albumArtUrl: t.imageUrl,
          durationMs: t.durationMs,
          isExplicit: t.explicit,
          source: 'spotify',
        ),
    ];
    final tracks = await _matchAll(source, onProgress: onProgress, isCancelled: isCancelled);
    return (
      playlist: Playlist(id: playlistId, name: pub.name, imageUrl: pub.imageUrl, tracks: tracks),
      total: pub.total,
    );
  }

  static const int _matchConcurrency = 6;

  /// Every song of [source] matched to YouTube Music, in order, a few at a
  /// time. A song with no good match is kept as it is (playback looks those up
  /// by name). Cancelling stops starting new songs and throws [ImportCancelled].
  Future<List<Track>> _matchAll(
    List<Track> source, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = source.length;
    onProgress?.call(0, total);
    final out = List<Track?>.filled(total, null);
    var next = 0;
    var done = 0;
    var cancelled = false;

    Future<void> worker() async {
      while (true) {
        if (cancelled || (isCancelled?.call() ?? false)) {
          cancelled = true;
          return;
        }
        if (next >= total) return;
        final i = next++;
        out[i] = await _matchOne(source[i]);
        done++;
        onProgress?.call(done, total);
      }
    }

    await Future.wait([for (var w = 0; w < _matchConcurrency; w++) worker()]);
    if (cancelled) throw const ImportCancelled();
    return [for (var i = 0; i < total; i++) out[i] ?? source[i]];
  }

  Future<Track> _matchOne(Track s) async {
    try {
      final lead = s.artistName.split(',').first.trim();
      final results = await _search('${s.trackName} $lead');
      Track? best;
      var bestScore = 0.0;
      for (final c in results) {
        final score = spotifyMatchScore(s, c);
        if (score > bestScore) {
          best = c;
          bestScore = score;
        }
      }
      if (best == null || bestScore < kSpotifyMatchThreshold) return s;
      return Track(
        id: best.id,
        trackName: s.trackName,
        artistName: s.artistName,
        albumName: s.albumName.isNotEmpty ? s.albumName : best.albumName,
        previewUrl: best.previewUrl,
        albumArtUrl: s.albumArtUrl.isNotEmpty ? s.albumArtUrl : best.albumArtUrl,
        durationMs: s.durationMs ?? best.durationMs,
        isExplicit: s.isExplicit,
        source: 'youtube',
      );
    } catch (e) {
      debugPrint('Error converting track to YouTube: $e');
      return s;
    }
  }
  // Helper method to search for a track on YouTube
  Future<Track?> findYouTubeTrack(Track spotifyTrack) async {
    try {
      // The best scored result first; the old first-result rule only when
      // nothing scores, so a song that used to play still plays.
      final matched = await _matchOne(spotifyTrack);
      if (matched.source == 'youtube') return matched;
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

/// Below this a search result is not taken as the song (kept unmatched).
const double kSpotifyMatchThreshold = 0.45;

final RegExp _bracketed = RegExp(r'[\(\[][^\)\]]*[\)\]]');
final RegExp _versionTail = RegExp(
    r'\s+-\s+.*\b(remaster(ed)?|live|version|edit|mix|mono|stereo|from|feat\.?)\b.*$',
    caseSensitive: false);
final RegExp _nonWord = RegExp(r"[^\p{L}\p{N}\s]", unicode: true);

String _normTitle(String s) => s
    .toLowerCase()
    .replaceAll(_bracketed, ' ')
    .replaceAll(_versionTail, ' ')
    .replaceAll(_nonWord, ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _normName(String s) =>
    s.toLowerCase().replaceAll(_nonWord, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// How well the search result [c] stands for the Spotify song [s]: about 1 for
/// the same song, low for a different one, negative when the lengths say it
/// cannot be the same recording.
///
/// Title (brackets, "- Remastered" tails and punctuation ignored) weighs most,
/// then a credited artist, then length. The old rule took the first result
/// whatever it was, which is how covers and karaoke versions got imported.
double spotifyMatchScore(Track s, Track c) {
  final a = _normTitle(s.trackName), b = _normTitle(c.trackName);
  double title;
  if (a.isEmpty || b.isEmpty) {
    title = 0;
  } else if (a == b) {
    title = 1;
  } else if (a.contains(b) || b.contains(a)) {
    title = 0.85;
  } else {
    final ta = a.split(' ').toSet(), tb = b.split(' ').toSet();
    title = 2 * ta.intersection(tb).length / (ta.length + tb.length);
  }

  final candArtist = _normName(c.artistName);
  final names = s.artistName.split(RegExp(r',|&')).map(_normName).where((n) => n.isNotEmpty);
  double artist = 0;
  for (final n in names) {
    if (candArtist.contains(n) || (candArtist.isNotEmpty && n.contains(candArtist))) {
      artist = 1;
      break;
    }
    final words = n.split(' ').where((w) => w.length > 2);
    if (words.any(candArtist.contains)) artist = 0.5;
  }

  double length = 0.5; // unknown on either side
  final sd = s.durationMs, cd = c.durationMs;
  if (sd != null && cd != null && sd > 0 && cd > 0) {
    final diff = (sd - cd).abs() / 1000;
    if (diff > 25) return -1;
    length = diff <= 3
        ? 1
        : diff <= 8
            ? 0.7
            : diff <= 15
                ? 0.35
                : 0.1;
  }
  return 0.5 * title + 0.3 * artist + 0.2 * length;
}
