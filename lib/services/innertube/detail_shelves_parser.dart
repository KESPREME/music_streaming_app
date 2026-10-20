// lib/services/innertube/detail_shelves_parser.dart
//
// The carousels under an album's track list ("More by the artist", "You might
// also like", "Other versions") as detail-page shelves.
//
// Pure and separate from InnerTubeService so it can be tested on JSON. Items
// are typed by what they POINT AT (the browse id), not by the shelf title: the
// artist page guesses from the title ("...like..." -> artist), which would turn
// an album page's "You might also like" into a row of artists.

import '../../models/bitchord_page_models.dart';

const int kAlbumShelfItemCap = 14;
const int kAlbumShelfCap = 4;

/// 'artist', 'album', 'single' or 'playlist' for an item that points at
/// [browseId], with [subtitle] ("Single . 2023") breaking album ties.
String detailShelfItemType(String browseId, String subtitle) {
  if (browseId.startsWith('UC')) return 'artist';
  if (browseId.startsWith('VL') || browseId.startsWith('PL') || browseId.startsWith('RDCLAK')) {
    return 'playlist';
  }
  final s = subtitle.trim().toLowerCase();
  if (s.startsWith('single') || s.startsWith('ep')) return 'single';
  return 'album';
}

String _runsText(dynamic node) {
  final runs = node is Map ? node['runs'] : null;
  if (runs is! List) return '';
  return runs.map((r) => r is Map ? (r['text']?.toString() ?? '') : '').join('').trim();
}

void _collect(dynamic node, String key, List<Map<String, dynamic>> out, int depth) {
  if (depth > 14) return;
  if (node is Map) {
    node.forEach((k, v) {
      if (k == key && v is Map<String, dynamic>) {
        out.add(v);
      } else {
        _collect(v, key, out, depth + 1);
      }
    });
  } else if (node is List) {
    for (final v in node) {
      _collect(v, key, out, depth + 1);
    }
  }
}

/// Carousels of [data] as shelves, newest page order. Drops video shelves,
/// items with no destination, the album being shown ([selfBrowseId] /
/// [selfTitle]) and repeated titles.
List<DetailShelf> parseDetailShelves(
  dynamic data, {
  String? selfBrowseId,
  String? selfTitle,
}) {
  final carousels = <Map<String, dynamic>>[];
  _collect(data, 'musicCarouselShelfRenderer', carousels, 0);

  final shelves = <DetailShelf>[];
  final seenTitles = <String>{};
  final self = (selfTitle ?? '').trim().toLowerCase();
  for (final carousel in carousels) {
    if (shelves.length >= kAlbumShelfCap) break;
    final header = carousel['header'];
    final headerRenderer = header is Map ? header['musicCarouselShelfBasicHeaderRenderer'] : null;
    final title = headerRenderer is Map ? _runsText(headerRenderer['title']) : '';
    if (title.isEmpty || RegExp(r'\bvideos?\b', caseSensitive: false).hasMatch(title)) continue;
    if (!seenTitles.add(title.toLowerCase())) continue;

    final contents = carousel['contents'];
    if (contents is! List) continue;
    final items = <DetailShelfItem>[];
    for (final c in contents) {
      final r = c is Map ? c['musicTwoRowItemRenderer'] : null;
      if (r is! Map) continue;
      final nav = r['navigationEndpoint'];
      final browse = nav is Map ? nav['browseEndpoint'] : null;
      final browseId = browse is Map ? (browse['browseId']?.toString() ?? '') : '';
      if (browseId.isEmpty) continue;
      if (selfBrowseId != null && browseId == selfBrowseId) continue;

      final itemTitle = _runsText(r['title']);
      if (itemTitle.isEmpty) continue;
      if (self.isNotEmpty && itemTitle.toLowerCase() == self && !browseId.startsWith('UC')) continue;

      final subRuns = r['subtitle'] is Map ? (r['subtitle'] as Map)['runs'] : null;
      final subtitle = subRuns is List
          ? subRuns
              .map((x) => x is Map ? (x['text']?.toString() ?? '') : '')
              .where((s) => s.trim().isNotEmpty)
              .join(' ')
              .trim()
          : '';

      var image = '';
      final thumbRenderer = r['thumbnailRenderer'];
      final mt = thumbRenderer is Map ? thumbRenderer['musicThumbnailRenderer'] : null;
      final thumbs = mt is Map && mt['thumbnail'] is Map ? (mt['thumbnail'] as Map)['thumbnails'] : null;
      if (thumbs is List && thumbs.isNotEmpty && thumbs.last is Map) {
        image = (thumbs.last as Map)['url']?.toString() ?? '';
        if (image.contains('lh3.googleusercontent.com')) {
          image = image.replaceAll(RegExp(r'=w\d+-h\d+'), '=w500-h500');
        }
      }

      items.add(DetailShelfItem(
        title: itemTitle,
        subtitle: subtitle,
        browseId: browseId,
        imageUrl: image,
        type: detailShelfItemType(browseId, subtitle),
      ));
      if (items.length >= kAlbumShelfItemCap) break;
    }
    if (items.length >= 2) shelves.add(DetailShelf(title: title, items: items));
  }
  return shelves;
}
