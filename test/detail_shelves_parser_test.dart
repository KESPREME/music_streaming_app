import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/innertube/detail_shelves_parser.dart';

Map<String, dynamic> _card(String title, String browseId, {String subtitle = '', String thumb = 'https://x/y.jpg'}) => {
      'musicTwoRowItemRenderer': {
        'title': {
          'runs': [
            {'text': title}
          ]
        },
        'subtitle': {
          'runs': [
            for (final part in subtitle.split('•')) {'text': part.trim()},
          ]
        },
        'navigationEndpoint': {
          'browseEndpoint': {'browseId': browseId}
        },
        'thumbnailRenderer': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': thumb}
              ]
            }
          }
        },
      }
    };

Map<String, dynamic> _shelf(String title, List<Map<String, dynamic>> cards) => {
      'musicCarouselShelfRenderer': {
        'header': {
          'musicCarouselShelfBasicHeaderRenderer': {
            'title': {
              'runs': [
                {'text': title}
              ]
            }
          }
        },
        'contents': cards,
      }
    };

dynamic _page(List<Map<String, dynamic>> shelves) => jsonDecode(jsonEncode({
      'contents': {
        'twoColumnBrowseResultsRenderer': {
          'secondaryContents': {
            'sectionListRenderer': {'contents': shelves}
          }
        }
      }
    }));

void main() {
  test('items are typed by what they point at, not by the shelf title', () {
    final shelves = parseDetailShelves(_page([
      _shelf('You might also like', [
        _card('Some Album', 'MPREb_aaa', subtitle: 'Album • Someone • 2019'),
        _card('Some Single', 'MPREb_bbb', subtitle: 'Single • Someone • 2023'),
        _card('Some EP', 'MPREb_ccc', subtitle: 'EP • Someone'),
        _card('A Mix', 'VLPLxyz', subtitle: 'Playlist • YouTube Music'),
        _card('Someone Else', 'UCabc', subtitle: '1.2M subscribers'),
      ]),
    ]));
    expect(shelves, hasLength(1));
    // The artist page would call all of these "artist" because of the title.
    expect(shelves.single.items.map((i) => i.type), ['album', 'single', 'single', 'playlist', 'artist']);
    expect(shelves.single.items.first.subtitle, 'Album Someone 2019');
  });

  test('detailShelfItemType', () {
    expect(detailShelfItemType('UCx', ''), 'artist');
    expect(detailShelfItemType('RDCLAKx', ''), 'playlist');
    expect(detailShelfItemType('MPREb_x', 'Single • 2020'), 'single');
    expect(detailShelfItemType('MPREb_x', 'Album'), 'album');
    expect(detailShelfItemType('OLAK5uy', ''), 'album');
  });

  test('the album being shown is not offered again, by id or by title', () {
    final shelves = parseDetailShelves(
      _page([
        _shelf('Other versions', [
          _card('Dawn FM', 'MPREb_self', subtitle: 'Album'),
          _card('Dawn FM (Alternate World)', 'MPREb_alt', subtitle: 'Album'),
          _card('Dawn FM', 'MPREb_dup', subtitle: 'Album'),
          _card('After Hours', 'MPREb_other', subtitle: 'Album'),
        ]),
      ]),
      selfBrowseId: 'MPREb_self',
      selfTitle: 'Dawn FM',
    );
    expect(shelves.single.items.map((i) => i.title), ['Dawn FM (Alternate World)', 'After Hours']);
  });

  test('an artist with the album\'s name is kept (it is not the album)', () {
    final shelves = parseDetailShelves(
      _page([
        _shelf('Fans might also like', [
          _card('Drake', 'UCdrake'),
          _card('Others', 'UCother'),
        ]),
      ]),
      selfTitle: 'Drake',
    );
    expect(shelves.single.items.map((i) => i.title), ['Drake', 'Others']);
  });

  test('video shelves, thin shelves, nameless items and repeated titles are dropped', () {
    final shelves = parseDetailShelves(_page([
      _shelf('Music videos', [_card('A', 'MPREb_1'), _card('B', 'MPREb_2')]),
      _shelf('Just one', [_card('A', 'MPREb_1')]),
      _shelf('More by Artist', [
        _card('One', 'MPREb_1'),
        _card('', 'MPREb_x'),
        _card('NoDest', ''),
        _card('Two', 'MPREb_2'),
      ]),
      _shelf('More by Artist', [_card('Dup1', 'MPREb_8'), _card('Dup2', 'MPREb_9')]),
    ]));
    expect(shelves.map((s) => s.title), ['More by Artist']);
    expect(shelves.single.items.map((i) => i.title), ['One', 'Two']);
  });

  test('capped: shelves and items per shelf', () {
    final many = [
      for (var s = 0; s < 8; s++) _shelf('Shelf $s', [for (var i = 0; i < 30; i++) _card('Item $i', 'MPREb_${s}_$i')]),
    ];
    final shelves = parseDetailShelves(_page(many));
    expect(shelves, hasLength(kAlbumShelfCap));
    expect(shelves.first.items, hasLength(kAlbumShelfItemCap));
  });

  test('the google image is asked for at card size', () {
    final shelves = parseDetailShelves(_page([
      _shelf('X', [
        _card('A', 'MPREb_1', thumb: 'https://lh3.googleusercontent.com/abc=w60-h60-l90'),
        _card('B', 'MPREb_2'),
      ]),
    ]));
    expect(shelves.single.items.first.imageUrl, contains('=w500-h500'));
  });

  test('a response with no carousels, or junk, is empty and never throws', () {
    expect(parseDetailShelves(_page([])), isEmpty);
    expect(parseDetailShelves(null), isEmpty);
    expect(parseDetailShelves('nope'), isEmpty);
    expect(parseDetailShelves({'musicCarouselShelfRenderer': 7}), isEmpty);
  });
}
