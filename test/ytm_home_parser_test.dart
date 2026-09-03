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

    test('no-identity rejected; no-artwork retained as PARTIAL (tolerance)',
        () async {
      final source = _source();
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
              // No id at all — rejected (identity is non-negotiable).
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
              // No artwork — RETAINED as PARTIAL (spec #8: shelf failure
              // must not destroy the section; artwork renders as
              // placeholder).
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

      final degenerate =
          feed.sections.singleWhere((s) => s.title == 'Degenerate shelf');
      // 2 of 3 survive: no-identity rejected, no-artwork retained PARTIAL.
      expect(degenerate.items.length, 2);
      expect(
        degenerate.items.map((i) => i.title).toSet(),
        {'No artwork', 'Valid one'},
      );
      final partial =
          degenerate.items.singleWhere((i) => i.title == 'No artwork');
      expect(partial.supportLevel, SupportLevel.partiallySupported);
      expect(partial.artworkUrl, isEmpty);
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

  group('forensic accounting + hero', () {
    test('accounting invariants hold on mixed fixture', () async {
      final source = YouTubeMusicHomeSource(InnerTubeService.instance);
      await source.parseResponse(_homeResponseFixture());
      final report = source.lastReport!;

      expect(report.discoveredShelves, 3); // 2 carousels + 1 podcast shelf
      expect(report.parsedShelves, 2);
      expect(report.unsupportedShelves, 1);
      expect(report.invariantsHold, isTrue);
    });

    test('unsupported renderer is reported, not silently dropped', () async {
      final source = YouTubeMusicHomeSource(InnerTubeService.instance);
      await source.parseResponse(_homeResponseFixture());
      final report = source.lastReport!;

      final unsupported = report.shelves
          .where((s) => s.status == ShelfStatus.unsupportedRenderer)
          .toList();
      expect(unsupported.length, 1);
      expect(unsupported.first.renderer, 'musicPodcastShelfRenderer');
    });

    test('musicShelfRenderer is discovered and parsed', () async {
      final source = YouTubeMusicHomeSource(InnerTubeService.instance);
      final fixture = _homeResponseFixture(extraSections: [
        {
          'musicShelfRenderer': {
            'title': {
              'runs': [
                {'text': 'Trending community playlists'}
              ]
            },
            'contents': [
              for (var i = 0; i < 3; i++)
                {
                  'musicResponsiveListItemRenderer': {
                    'playlistItemData': {'videoId': 'shelfVID$i'},
                    'flexColumns': [
                      {
                        'musicResponsiveListItemFlexColumnRenderer': {
                          'text': {
                            'runs': [
                              {'text': 'Playlist item $i'}
                            ]
                          }
                        }
                      },
                      {
                        'musicResponsiveListItemFlexColumnRenderer': {
                          'text': {
                            'runs': [
                              {'text': 'Curator $i'}
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
                                  'https://lh3.googleusercontent.com/ms$i=w544-h544'
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
      final shelf = feed.sections
          .singleWhere((s) => s.title == 'Trending community playlists');
      expect(shelf.renderer, 'musicShelfRenderer');
      expect(shelf.items.length, 3);
      expect(shelf.sourcePath, isNotNull);
    });

    test('hero candidate = first playable song shelf item', () async {
      final source = YouTubeMusicHomeSource(InnerTubeService.instance);
      final feed = (await source.parseResponse(_homeResponseFixture()))!;
      expect(feed.heroCandidate, isNotNull);
      expect(feed.heroCandidate!.id, 'BddP6PYotfs');
    });

    test('subtitle segments for duration/views are not artists (live bug)',
        () async {
      Map<String, dynamic> twoRow(
              String title, String videoId, List<String> subRuns) =>
          {
            'musicTwoRowItemRenderer': {
              'title': {
                'runs': [
                  {'text': title}
                ]
              },
              'subtitle': {
                'runs': [
                  for (final r in subRuns) {'text': r}
                ]
              },
              'navigationEndpoint': {
                'watchEndpoint': {'videoId': videoId}
              },
              'thumbnailRenderer': {
                'musicThumbnailRenderer': {
                  'thumbnail': {
                    'thumbnails': [
                      {'url': 'https://lh3.googleusercontent.com/q=w544-h544'}
                    ]
                  }
                }
              }
            }
          };
      final source = _source();
      final feed = (await source.parseResponse(_homeResponseFixture(
        extraSections: [
          {
            'musicCarouselShelfRenderer': {
              'header': {
                'musicCarouselShelfBasicHeaderRenderer': {
                  'title': {
                    'runs': [
                      {'text': 'Noisy subtitles'}
                    ]
                  }
                }
              },
              'contents': [
                twoRow('Loser', 'GQgLDk9sq00',
                    ['Tame Impala', ' • ', 'Deadbeat', ' • ', '3:44']),
                twoRow('Veridis Quo', 'qe8Q7mjxji1',
                    ['Daft Punk', ' • ', '106M plays']),
              ],
            }
          },
        ],
      )))!;
      final shelf =
          feed.sections.singleWhere((s) => s.title == 'Noisy subtitles');
      expect(shelf.items[0].artists, ['Tame Impala', 'Deadbeat']);
      expect(shelf.items[1].artists, ['Daft Punk']);
    });
  });
}
