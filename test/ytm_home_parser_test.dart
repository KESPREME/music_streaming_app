import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/home/home_models.dart';
import 'package:music_streaming_app/services/home/ytm_home_source.dart';
import 'package:music_streaming_app/services/innertube/innertube_service.dart';

// _parse is private; tests go through the public parseResponse entry.
YouTubeMusicHomeSource _source() =>
    YouTubeMusicHomeSource(InnerTubeService.instance);

/// Parser fixtures. Structures mirror the real YTM Home response shapes
/// (singleColumnBrowseResultsRenderer → tabs → sectionListRenderer →
/// musicCarouselShelfRenderer → musicTwoRowItemRenderer /
/// musicResponsiveListItemRenderer). If YouTube changes schema, these
/// tests must be updated BEFORE the UI silently degrades.
Map<String, dynamic> _homeResponseFixture({
  List<Map<String, dynamic>>? extraSections,
}) {
  return jsonDecode(jsonEncode({
    'contents': {
      'singleColumnBrowseResultsRenderer': {
        'tabs': [
          {
            'tabRenderer': {
              'content': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'musicCarouselShelfRenderer': {
                        'header': {
                          'musicCarouselShelfBasicHeaderRenderer': {
                            'title': {
                              'runs': [
                                {'text': 'Listen again'}
                              ]
                            }
                          }
                        },
                        'contents': [
                          {
                            'musicTwoRowItemRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Kesariya'}
                                ]
                              },
                              'subtitle': {
                                'runs': [
                                  {'text': 'Arijit Singh'},
                                  {'text': ' • '},
                                  {'text': 'Brahmastra'}
                                ]
                              },
                              'navigationEndpoint': {
                                'watchEndpoint': {'videoId': 'BddP6PYotfs'}
                              },
                              'thumbnailRenderer': {
                                'musicThumbnailRenderer': {
                                  'thumbnail': {
                                    'thumbnails': [
                                      {
                                        'url':
                                            'https://lh3.googleusercontent.com/x=w120-h120'
                                      },
                                      {
                                        'url':
                                            'https://lh3.googleusercontent.com/x=w544-h544'
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          },
                          {
                            'musicTwoRowItemRenderer': {
                              'title': {
                                'runs': [
                                  {'text': 'Tum Se Hi'}
                                ]
                              },
                              'subtitle': {
                                'runs': [
                                  {'text': 'Mohit Chauhan'}
                                ]
                              },
                              'navigationEndpoint': {
                                'watchEndpoint': {'videoId': 'abcDEF12345'}
                              },
                              'thumbnailRenderer': {
                                'musicThumbnailRenderer': {
                                  'thumbnail': {
                                    'thumbnails': [
                                      {
                                        'url':
                                            'https://lh3.googleusercontent.com/y=w544-h544'
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          },
                        ],
                      }
                    },
                    {
                      'musicCarouselShelfRenderer': {
                        'header': {
                          'musicCarouselShelfBasicHeaderRenderer': {
                            'title': {
                              'runs': [
                                {'text': 'Forgotten favourites'}
                              ]
                            }
                          }
                        },
                        'contents': [
                          {
                            'musicResponsiveListItemRenderer': {
                              'playlistItemData': {'videoId': 'xyz789abcde'},
                              'flexColumns': [
                                {
                                  'musicResponsiveListItemFlexColumnRenderer': {
                                    'text': {
                                      'runs': [
                                        {'text': 'Raabta'}
                                      ]
                                    }
                                  }
                                },
                                {
                                  'musicResponsiveListItemFlexColumnRenderer': {
                                    'text': {
                                      'runs': [
                                        {'text': 'Arijit Singh'},
                                        {'text': ' • '},
                                        {'text': 'Agent Vinod'}
                                      ]
                                    }
                                  }
                                }
                              ],
                              'thumbnail': {
                                'musicThumbnailRenderer': {
                                  'thumbnail': {
                                    'thumbnails': [
                                      {
                                        'url':
                                            'https://lh3.googleusercontent.com/z=w544-h544'
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          },
                          {
                            'musicResponsiveListItemRenderer': {
                              // Album item: navigation browse id only.
                              'navigationEndpoint': {
                                'browseEndpoint': {'browseId': 'MPREb_abc123'}
                              },
                              'flexColumns': [
                                {
                                  'musicResponsiveListItemFlexColumnRenderer': {
                                    'text': {
                                      'runs': [
                                        {'text': 'Aashiqui 2'}
                                      ]
                                    }
                                  }
                                },
                                {
                                  'musicResponsiveListItemFlexColumnRenderer': {
                                    'text': {
                                      'runs': [
                                        {'text': 'Album'},
                                        {'text': ' • '},
                                        {'text': 'Various Artists'}
                                      ]
                                    }
                                  }
                                }
                              ],
                              'thumbnail': {
                                'musicThumbnailRenderer': {
                                  'thumbnail': {
                                    'thumbnails': [
                                      {
                                        'url':
                                            'https://lh3.googleusercontent.com/al=w544-h544'
                                      }
                                    ]
                                  }
                                }
                              }
                            }
                          },
                        ],
                      }
                    },
                    // Unsupported renderer — must be skipped, not crash.
                    {
                      'musicPodcastShelfRenderer': {'contents': []}
                    },
                    ...?extraSections,
                  ],
                }
              }
            }
          }
        ]
      }
    }
  }));
}

void main() {
  group('YouTubeMusicHomeSource parser', () {
    test('parses shelves with real titles preserved, in source order',
        () async {
      final source = YouTubeMusicHomeSource(InnerTubeService.instance);
      final feed = await source.parseResponse(_homeResponseFixture());

      expect(feed, isNotNull);
      expect(feed!.source, 'ytm_home');
      expect(feed.sections.length, 2);
      expect(feed.sections[0].title, 'Listen again');
      expect(feed.sections[1].title, 'Forgotten favourites');
    });

    test('item identity comes from videoId/browseId, not title', () async {
      final source = YouTubeMusicHomeSource(InnerTubeService.instance);
      final feed = (await source.parseResponse(_homeResponseFixture()))!;

      final first = feed.sections[0].items.first;
      expect(first.id, 'BddP6PYotfs');
      expect(first.videoId, 'BddP6PYotfs');
      expect(first.contentType, HomeContentType.song);
      expect(first.title, 'Kesariya');
      expect(first.artworkUrl, contains('w544-h544')); // resolution policy
      expect(first.artworkUrl, isNot(contains('w120-h120')));
    });

    test('responsive album item: browse id identity, album type', () async {
      final source = YouTubeMusicHomeSource(InnerTubeService.instance);
      final feed = (await source.parseResponse(_homeResponseFixture()))!;

      final album = feed.sections[1].items.last;
      expect(album.id, 'MPREb_abc123');
      expect(album.contentType, HomeContentType.album);
      expect(album.videoId, isNull);
      expect(album.browseId, 'MPREb_abc123');
    });

    test('unsupported renderer is skipped without crashing', () async {
      final source = YouTubeMusicHomeSource(InnerTubeService.instance);
      final feed = await source.parseResponse(_homeResponseFixture());
      expect(feed, isNotNull);
      expect(feed!.sections.length, 2);
    });

    test('items without identity or artwork are rejected', () async {
      final source = YouTubeMusicHomeSource(InnerTubeService.instance);
      final fixture = _homeResponseFixture(extraSections: [
        {
          'musicCarouselShelfRenderer': {
            'header': {
              'musicCarouselShelfBasicHeaderRenderer': {
                'title': {
                  'runs': [
                    {'text': 'Degenerate shelf'}
                  ]
                }
              }
            },
            'contents': [
              // No id at all.
              {
                'musicTwoRowItemRenderer': {
                  'title': {
                    'runs': [
                      {'text': 'No identity'}
                    ]
                  },
                  'thumbnailRenderer': {
                    'musicThumbnailRenderer': {
                      'thumbnail': {
                        'thumbnails': [
                          {
                            'url':
                                'https://lh3.googleusercontent.com/q=w544-h544'
                          }
                        ]
                      }
                    }
                  }
                }
              },
              // No artwork.
              {
                'musicTwoRowItemRenderer': {
                  'title': {
                    'runs': [
                      {'text': 'No artwork'}
                    ]
                  },
                  'navigationEndpoint': {
                    'watchEndpoint': {'videoId': 'noArtwork123'}
                  }
                }
              },
              // Valid.
              {
                'musicTwoRowItemRenderer': {
                  'title': {
                    'runs': [
                      {'text': 'Valid one'}
                    ]
                  },
                  'navigationEndpoint': {
                    'watchEndpoint': {'videoId': 'validItem001'}
                  },
                  'thumbnailRenderer': {
                    'musicThumbnailRenderer': {
                      'thumbnail': {
                        'thumbnails': [
                          {
                            'url':
                                'https://lh3.googleusercontent.com/v=w544-h544'
                          }
                        ]
                      }
                    }
                  }
                }
              },
            ],
          }
        },
      ]);
      final feed = (await source.parseResponse(fixture))!;

      // Degenerate shelf collapsed entirely: only 1 of 3 items survived
      // (no-identity + no-artwork rejected), below the 2-item section floor.
      expect(
        feed.sections.where((s) => s.title == 'Degenerate shelf'),
        isEmpty,
      );
      expect(
        feed.sections.any((s) => s.items.any((i) => i.title == 'Valid one')),
        isFalse,
      );
    });

    test('empty/missing response structure returns null (not crash)', () async {
      final source = YouTubeMusicHomeSource(InnerTubeService.instance);
      expect(await source.parseResponse({}), isNull);
      expect(await source.parseResponse({'contents': {}}), isNull);
    });

    test('artist shelf via browse id gets artistRail presentation', () async {
      final source = YouTubeMusicHomeSource(InnerTubeService.instance);
      final fixture = _homeResponseFixture(extraSections: [
        {
          'musicCarouselShelfRenderer': {
            'header': {
              'musicCarouselShelfBasicHeaderRenderer': {
                'title': {
                  'runs': [
                    {'text': 'Artists you may like'}
                  ]
                }
              }
            },
            'contents': [
              for (var i = 0; i < 3; i++)
                {
                  'musicTwoRowItemRenderer': {
                    'title': {
                      'runs': [
                        {'text': 'Artist $i'}
                      ]
                    },
                    'subtitle': {
                      'runs': [
                        {'text': 'Artist'}
                      ]
                    },
                    'navigationEndpoint': {
                      'browseEndpoint': {'browseId': 'UCartist$i'}
                    },
                    'thumbnailRenderer': {
                      'musicThumbnailRenderer': {
                        'thumbnail': {
                          'thumbnails': [
                            {
                              'url':
                                  'https://lh3.googleusercontent.com/a$i=w544-h544'
                            }
                          ]
                        }
                      }
                    }
                  }
                },
            ],
          }
        },
      ]);
      final feed = (await source.parseResponse(fixture))!;
      final artists =
          feed.sections.singleWhere((s) => s.title == 'Artists you may like');
      expect(artists.presentation, HomePresentation.artistRail);
      expect(artists.dominantType, HomeContentType.artist);
      expect(artists.items.every((i) => i.videoId == null), isTrue);
    });
  });
}
