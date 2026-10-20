import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/providers/music_provider.dart';
import 'package:music_streaming_app/services/home/home_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_streaming_app/services/home/ytm_home_source.dart';
import 'package:music_streaming_app/services/innertube/innertube_service.dart';

Map<String, dynamic> _song(String id, String title) => {
      'musicTwoRowItemRenderer': {
        'title': {
          'runs': [
            {'text': title}
          ]
        },
        'subtitle': {
          'runs': [
            {'text': 'Some Artist'}
          ]
        },
        'navigationEndpoint': {
          'watchEndpoint': {'videoId': id}
        },
        'thumbnailRenderer': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://lh3.googleusercontent.com/$id=w544-h544'}
              ]
            }
          }
        },
      }
    };

Map<String, dynamic> _shelf(String title, List<String> ids, {String? strapline}) => {
      'musicCarouselShelfRenderer': {
        'header': {
          'musicCarouselShelfBasicHeaderRenderer': {
            'title': {
              'runs': [
                {'text': title}
              ]
            },
            if (strapline != null)
              'strapline': {
                'runs': [
                  {'text': strapline}
                ]
              },
          }
        },
        'contents': [for (final id in ids) _song(id, 'Song $id')],
      }
    };

Map<String, dynamic> _json(Object o) => jsonDecode(jsonEncode(o)) as Map<String, dynamic>;

void main() {
  final source = YouTubeMusicHomeSource(InnerTubeService.instance);

  test('first page: strapline becomes the section subtitle; token recorded', () async {
    final feed = await source.parseResponse(_json({
      'contents': {
        'singleColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      _shelf('Tame Impala', ['aaaaaaaaaa1', 'aaaaaaaaaa2'], strapline: 'Similar to'),
                      _shelf('Quick picks', ['bbbbbbbbbb1', 'bbbbbbbbbb2']),
                    ],
                    'continuations': [
                      {
                        'nextContinuationData': {'continuation': 'PAGE2'}
                      }
                    ],
                  }
                }
              }
            }
          ]
        }
      }
    }));
    expect(feed, isNotNull);
    expect(feed!.sections.first.title, 'Tame Impala');
    expect(feed.sections.first.sourceSubtitle, 'Similar to');
    expect(feed.sections[1].sourceSubtitle, isNull);
    expect(feed.continuationToken, 'PAGE2');
  });

  test('classic continuation page: shelves and the next token', () async {
    final page = await source.parseContinuation(_json({
      'continuationContents': {
        'sectionListContinuation': {
          'contents': [
            _shelf('Covers and remixes', ['ccccccccccc', 'ddddddddddd']),
            _shelf('From the community', ['eeeeeeeeeee', 'fffffffffff'],
                strapline: 'Playlists'),
          ],
          'continuations': [
            {
              'nextContinuationData': {'continuation': 'PAGE3'}
            }
          ],
        }
      }
    }));
    expect(page, isNotNull);
    expect(page!.sections.map((s) => s.title), ['Covers and remixes', 'From the community']);
    expect(page.sections[1].sourceSubtitle, 'Playlists');
    expect(page.continuationToken, 'PAGE3');
  });

  test('append-action continuation page (newer shape)', () async {
    final page = await source.parseContinuation(_json({
      'onResponseReceivedActions': [
        {
          'appendContinuationItemsAction': {
            'continuationItems': [
              _shelf('Indie', ['ggggggggggg', 'hhhhhhhhhhh']),
              {
                'continuationItemRenderer': {
                  'continuationEndpoint': {
                    'continuationCommand': {'token': 'PAGE4'}
                  }
                }
              },
            ]
          }
        }
      ]
    }));
    expect(page, isNotNull);
    expect(page!.sections.single.title, 'Indie');
    expect(page.continuationToken, 'PAGE4');
  });

  test('an unknown or empty page is null, never a crash', () async {
    expect(await source.parseContinuation({}), isNull);
    expect(
      await source.parseContinuation(_json({
        'continuationContents': {
          'sectionListContinuation': {'contents': []}
        }
      })),
      isNull,
    );
  });

  group('MusicProvider.loadMoreHome', () {
    late MusicProvider p;

    HomeItem item(String id) => HomeItem(
          id: id,
          videoId: id,
          title: 'Song $id',
          subtitle: 'Artist',
          artworkUrl: 'https://x/$id.jpg',
          contentType: HomeContentType.song,
        );
    HomeSection section(String title, List<String> ids) => HomeSection(
          id: '${title.toLowerCase()}:song',
          title: title,
          items: [for (final i in ids) item(i)],
          presentation: HomePresentation.artworkRail,
        );
    HomeFeed feed(List<HomeSection> s, String? token) => HomeFeed(
          sections: s,
          fetchedAt: DateTime(2026),
          source: 'ytm_home',
          continuationToken: token,
        );

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final ready = Completer<void>();
      final original = debugPrint;
      debugPrint = (msg, {wrapWidth}) {
        if (msg != null && msg.contains('Initialization complete') && !ready.isCompleted) {
          ready.complete();
        }
      };
      p = MusicProvider();
      await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      debugPrint = original;
    });

    test('appends new shelves, keeps the next token, marks them as paged', () async {
      p.debugPublishHomeFeed(feed([section('Quick picks', ['q1', 'q2'])], 'T2'));
      expect(p.canLoadMoreHome, isTrue);
      final asked = <String>[];
      p.debugFetchMoreHome = (t) async {
        asked.add(t);
        return feed([
          section('Covers and remixes', ['c1', 'c2']),
          section('Quick picks', ['z1', 'z2']), // same title: first wins
        ], 'T3');
      };
      await p.loadMoreHome();
      expect(asked, ['T2']);
      expect(p.homeFeed!.sections.map((s) => s.title), ['Quick picks', 'Covers and remixes']);
      expect(p.homeFeed!.continuationToken, 'T3');
      expect(p.homePagedSectionIds, {'covers and remixes:song'});
      expect(p.canLoadMoreHome, isTrue);
      expect(p.isLoadingMoreHome, isFalse);
    });

    test('a page that adds nothing stops paging for this feed', () async {
      p.debugPublishHomeFeed(feed([section('Listen again', ['l1', 'l2'])], 'T2'));
      var calls = 0;
      p.debugFetchMoreHome = (t) async {
        calls++;
        return feed([section('Listen again', ['l3', 'l4'])], 'T3');
      };
      await p.loadMoreHome();
      expect(p.canLoadMoreHome, isFalse);
      await p.loadMoreHome();
      expect(calls, 1);
      expect(p.homeFeed!.sections, hasLength(1));
    });

    test('a failed page stops; a new feed starts over', () async {
      p.debugPublishHomeFeed(feed([section('Mixed for you', ['m1', 'm2'])], 'T2'));
      p.debugFetchMoreHome = (t) async => throw Exception('offline');
      await p.loadMoreHome();
      expect(p.canLoadMoreHome, isFalse);
      expect(p.homeFeed!.sections, hasLength(1));

      p.debugPublishHomeFeed(feed([section('Daily discover', ['d1', 'd2'])], 'T9'));
      expect(p.canLoadMoreHome, isTrue);
      expect(p.homePagedSectionIds, isEmpty);
    });

    test('a page for a feed that was replaced mid-flight is dropped', () async {
      p.debugPublishHomeFeed(feed([section('Trending', ['t1', 't2'])], 'T2'));
      final gate = Completer<void>();
      p.debugFetchMoreHome = (t) async {
        await gate.future;
        return feed([section('Indie', ['i1', 'i2'])], null);
      };
      final pending = p.loadMoreHome();
      expect(p.isLoadingMoreHome, isTrue);
      p.debugPublishHomeFeed(feed([section('New releases', ['n1', 'n2'])], 'T5'));
      gate.complete();
      await pending;
      expect(p.homeFeed!.sections.map((s) => s.title), ['New releases']);
      expect(p.isLoadingMoreHome, isFalse);
    });
  });
}