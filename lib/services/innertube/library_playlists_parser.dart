// lib/services/innertube/library_playlists_parser.dart
//
// The signed-in listener's YouTube Music playlists, from the "Library >
// Playlists" browse (FEmusic_liked_playlists).
//
// Pure: response JSON in, playlists out. It walks the whole response for
// `musicTwoRowItemRenderer`s rather than one fixed path, because YouTube moves
// the grid between `gridRenderer` and `musicShelfRenderer`/`itemSectionRenderer`
// across clients and experiments. What makes an item a playlist is its browse
// id (`VL…`), not where it sits.
//
// Skipped: the "New playlist" tile (no browse id) and "Episodes for later"
// (VLSE, podcasts). Kept: "Liked Music" (VLLM) - it is your YouTube likes.

class YouTubeLibraryPlaylist {
  const YouTubeLibraryPlaylist({
    required this.browseId,
    required this.title,
    required this.subtitle,
    required this.thumbnailUrl,
    this.songCount,
  });

  /// `VL…`, ready for the playlist page.
  final String browseId;
  final String title;

  /// "Playlist • 32 songs", "Auto playlist", as YouTube wrote it.
  final String subtitle;
  final String thumbnailUrl;

  /// Parsed from the subtitle when it says so ("32 songs", "1 song").
  final int? songCount;

  /// The playlist id without the `VL` prefix.
  String get playlistId => browseId.startsWith('VL') ? browseId.substring(2) : browseId;

  bool get isLikedMusic => browseId == 'VLLM';
}

String _runs(Object? text) {
  if (text is! Map) return '';
  final simple = text['simpleText'];
  if (simple is String) return simple;
  final runs = text['runs'];
  if (runs is! List) return '';
  return runs.map((r) => r is Map ? (r['text'] ?? '') : '').join();
}

String _bestThumb(Map r) {
  Object? node = r['thumbnailRenderer'];
  if (node is Map) node = node['musicThumbnailRenderer'] ?? node['croppedSquareThumbnailRenderer'];
  if (node is Map) node = node['thumbnail'];
  if (node is! Map) return '';
  final list = node['thumbnails'];
  if (list is! List || list.isEmpty) return '';
  // Largest by width; YouTube orders small to large but not always.
  Map? best;
  var bestW = -1;
  for (final t in list) {
    if (t is! Map || t['url'] is! String) continue;
    final w = t['width'] is int ? t['width'] as int : 0;
    if (w > bestW) {
      bestW = w;
      best = t;
    }
  }
  var url = (best?['url'] as String?) ?? '';
  if (url.startsWith('//')) url = 'https:$url';
  return url;
}

int? songCountFrom(String subtitle) {
  final m = RegExp(r'([\d,.]+)\s+(songs?|tracks?|videos?)', caseSensitive: false).firstMatch(subtitle);
  if (m == null) return null;
  return int.tryParse(m.group(1)!.replaceAll(RegExp(r'[,.]'), ''));
}

List<YouTubeLibraryPlaylist> parseLibraryPlaylists(Object? json) {
  final out = <YouTubeLibraryPlaylist>[];
  final seen = <String>{};

  void visit(Object? node) {
    if (node is Map) {
      final r = node['musicTwoRowItemRenderer'];
      if (r is Map) {
        final nav = r['navigationEndpoint'];
        final browse = nav is Map ? nav['browseEndpoint'] : null;
        final id = browse is Map ? browse['browseId'] : null;
        if (id is String && id.startsWith('VL') && id != 'VLSE' && seen.add(id)) {
          final subtitle = _runs(r['subtitle']);
          final title = _runs(r['title']).trim();
          if (title.isNotEmpty) {
            out.add(YouTubeLibraryPlaylist(
              browseId: id,
              title: title,
              subtitle: subtitle,
              thumbnailUrl: _bestThumb(r),
              songCount: songCountFrom(subtitle),
            ));
          }
        }
        return; // a two-row item has no playlists nested inside it
      }
      for (final v in node.values) {
        visit(v);
      }
    } else if (node is List) {
      for (final v in node) {
        visit(v);
      }
    }
  }

  visit(json);
  return out;
}
