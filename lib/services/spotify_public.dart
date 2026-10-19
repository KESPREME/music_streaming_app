// lib/services/spotify_public.dart
//
// A public Spotify playlist, read from a pasted link with no account and no
// developer credentials. Plan: docs/PLAN-motion-perf-downloads.md (P1).
//
// These are the endpoints Spotify's own embed player uses (probed 2026-10):
//
//   * open.spotify.com/embed/playlist/{id}
//       HTML with a `__NEXT_DATA__` JSON blob: name, cover, the first 100
//       songs (title, artists, duration, explicit, uri) and an anonymous
//       access token.
//   * spclient.wg.spotify.com/playlist/v2/playlist/{id}?from=0&length=N
//       with that token and `Accept: application/json`: every song's uri, for
//       playlists longer than the embed shows.
//   * open.spotify.com/embed/track/{id}
//       one song, for the ones past the first 100.
//
// They are not a contracted API and can change. Everything here degrades to
// an exception the import screen turns into "Spotify didn't answer"; nothing
// is half-saved.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class SpotifyPublicTrack {
  const SpotifyPublicTrack({
    required this.id,
    required this.title,
    required this.artists,
    this.durationMs,
    this.explicit = false,
    this.imageUrl = '',
  });

  final String id;
  final String title;
  final List<String> artists;
  final int? durationMs;
  final bool explicit;
  final String imageUrl;
}

class SpotifyPublicPlaylist {
  const SpotifyPublicPlaylist({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.tracks,
    this.total,
    this.token,
  });

  final String id;
  final String name;
  final String imageUrl;
  final List<SpotifyPublicTrack> tracks;

  /// How many songs the playlist has, when Spotify said (the embed alone
  /// stops at 100).
  final int? total;

  /// The embed page's anonymous token, for the full song list.
  final String? token;

  /// Fewer songs than the playlist has (the full list could not be read).
  bool get partial => total != null && tracks.length < total!;
}

final RegExp _nextData =
    RegExp(r'<script id="__NEXT_DATA__" type="application/json">(.+?)</script>', dotAll: true);

Map<String, dynamic>? _pageState(String html) {
  final m = _nextData.firstMatch(html);
  if (m == null) return null;
  try {
    final json = jsonDecode(m.group(1)!);
    final state = (json is Map ? json['props'] : null)?['pageProps']?['state'];
    return state is Map<String, dynamic> ? state : null;
  } catch (_) {
    return null;
  }
}

String? _idFromUri(Object? uri) {
  if (uri is! String) return null;
  final parts = uri.split(':');
  return parts.length == 3 && parts[1] == 'track' && parts[2].isNotEmpty ? parts[2] : null;
}

/// "Olivia Rodrigo,\u00a0Chappell Roan" -> both names.
List<String> _splitArtists(String s) =>
    s.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty).toList();

String _firstImage(Object? sources) {
  if (sources is! List) return '';
  for (final s in sources) {
    if (s is Map && s['url'] is String && (s['url'] as String).isNotEmpty) return s['url'] as String;
  }
  return '';
}

/// The playlist on an embed page, or null if the page is not one.
SpotifyPublicPlaylist? parseEmbedPlaylist(String html, String id) {
  final state = _pageState(html);
  final entity = state?['data']?['entity'];
  if (entity is! Map || entity['type'] != 'playlist') return null;
  final tracks = <SpotifyPublicTrack>[];
  for (final t in (entity['trackList'] as List? ?? const [])) {
    if (t is! Map) continue;
    final tid = _idFromUri(t['uri']);
    final title = (t['title'] as String?)?.trim() ?? '';
    if (tid == null || title.isEmpty) continue; // episodes, removed songs
    tracks.add(SpotifyPublicTrack(
      id: tid,
      title: title,
      artists: _splitArtists((t['subtitle'] as String?) ?? ''),
      durationMs: t['duration'] is int ? t['duration'] as int : null,
      explicit: t['isExplicit'] == true,
    ));
  }
  final token = state?['settings']?['session']?['accessToken'];
  return SpotifyPublicPlaylist(
    id: id,
    name: ((entity['name'] ?? entity['title']) as String?)?.trim() ?? 'Spotify playlist',
    imageUrl: _firstImage((entity['coverArt'] as Map?)?['sources']),
    tracks: tracks,
    token: token is String && token.isNotEmpty ? token : null,
  );
}

/// One song on a track embed page, or null.
SpotifyPublicTrack? parseEmbedTrack(String html) {
  final entity = _pageState(html)?['data']?['entity'];
  if (entity is! Map || entity['type'] != 'track') return null;
  final id = (entity['id'] as String?) ?? _idFromUri(entity['uri']);
  final title = ((entity['name'] ?? entity['title']) as String?)?.trim() ?? '';
  if (id == null || title.isEmpty) return null;
  final artists = <String>[
    for (final a in (entity['artists'] as List? ?? const []))
      if (a is Map && a['name'] is String) (a['name'] as String).trim(),
  ];
  return SpotifyPublicTrack(
    id: id,
    title: title,
    artists: artists,
    durationMs: entity['duration'] is int ? entity['duration'] as int : null,
    explicit: entity['isExplicit'] == true,
    imageUrl: _firstImage(entity['visualIdentity']?['image']),
  );
}

/// Every song id in a spclient playlist answer, in order, and the total.
({List<String> ids, int? total}) parseSpclientPlaylist(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map) return (ids: const [], total: null);
    final ids = <String>[
      for (final item in (json['contents']?['items'] as List? ?? const []))
        if (item is Map && _idFromUri(item['uri']) != null) _idFromUri(item['uri'])!,
    ];
    return (ids: ids, total: json['length'] is int ? json['length'] as int : null);
  } catch (_) {
    return (ids: const [], total: null);
  }
}

class SpotifyPublicPlaylists {
  SpotifyPublicPlaylists({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const _ua =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36';
  static const _timeout = Duration(seconds: 15);
  static const int _trackConcurrency = 6;

  Future<http.Response> _get(Uri uri, [Map<String, String>? headers]) =>
      (_client?.get ?? http.get)(uri, headers: {'User-Agent': _ua, ...?headers}).timeout(_timeout);

  /// The playlist [id], every song of it when Spotify lets us read them.
  ///
  /// [onSongs] reports songs read so far out of the total while the songs past
  /// the first 100 are fetched. [isCancelled] stops between songs.
  Future<SpotifyPublicPlaylist> fetch(
    String id, {
    void Function(int read, int total)? onSongs,
    bool Function()? isCancelled,
  }) async {
    final page = await _get(Uri.parse('https://open.spotify.com/embed/playlist/$id'));
    if (page.statusCode == 404) throw const SpotifyPublicException('That playlist is private or no longer exists.');
    if (page.statusCode != 200) throw SpotifyPublicException('Spotify answered ${page.statusCode}.');
    final first = parseEmbedPlaylist(page.body, id);
    if (first == null) throw const SpotifyPublicException('That link isn\'t a public playlist.');

    // The embed stops at 100. Below that it is the whole playlist.
    if (first.tracks.length < 100 || first.token == null) {
      return SpotifyPublicPlaylist(
          id: id, name: first.name, imageUrl: first.imageUrl, tracks: first.tracks, total: first.tracks.length);
    }

    ({List<String> ids, int? total}) all = (ids: const [], total: null);
    try {
      final r = await _get(
        Uri.parse('https://spclient.wg.spotify.com/playlist/v2/playlist/$id?from=0&length=10000'),
        {'Authorization': 'Bearer ${first.token}', 'Accept': 'application/json'},
      );
      if (r.statusCode == 200) all = parseSpclientPlaylist(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (all.ids.length <= first.tracks.length) {
      // Could not read past the first 100: say so rather than pretend.
      return SpotifyPublicPlaylist(
          id: id, name: first.name, imageUrl: first.imageUrl, tracks: first.tracks, total: all.total);
    }

    final known = {for (final t in first.tracks) t.id: t};
    final missing = [for (final i in all.ids) if (!known.containsKey(i)) i];
    var read = known.length;
    onSongs?.call(read, all.ids.length);
    var next = 0;
    Future<void> worker() async {
      while (next < missing.length) {
        if (isCancelled?.call() ?? false) return;
        final tid = missing[next++];
        try {
          final r = await _get(Uri.parse('https://open.spotify.com/embed/track/$tid'));
          final t = r.statusCode == 200 ? parseEmbedTrack(r.body) : null;
          if (t != null) known[tid] = t;
        } catch (_) {}
        read++;
        onSongs?.call(read, all.ids.length);
      }
    }

    await Future.wait([for (var i = 0; i < _trackConcurrency; i++) worker()]);
    return SpotifyPublicPlaylist(
      id: id,
      name: first.name,
      imageUrl: first.imageUrl,
      tracks: [for (final i in all.ids) if (known[i] != null) known[i]!],
      total: all.total ?? all.ids.length,
    );
  }
}

class SpotifyPublicException implements Exception {
  const SpotifyPublicException(this.message);
  final String message;
  @override
  String toString() => message;
}
