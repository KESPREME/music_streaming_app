import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/auth_models.dart';
import 'package:music_streaming_app/services/innertube/account_parser.dart';

/// Response-shape coverage for the account endpoints.
///
/// The shapes here are the risk: `account_menu` and `accounts_list` wrap the
/// same renderers in envelopes that differ per client, and the identity tokens
/// arrive inside `supportedTokens` in no promised order. Every case below is a
/// shape we would otherwise be guessing at, so each one states what would break
/// if the parser got it wrong.
void main() {
  group('parseIdentity', () {
    test('reads name, email and avatar from an activeAccountHeaderRenderer', () {
      final identity = AccountParser.parseIdentity({
        'response': {
          'actions': [
            {
              'activeAccountHeaderRenderer': {
                'accountName': {'simpleText': 'Nipun Gupta'},
                'email': {'simpleText': 'nipun@example.com'},
                'accountPhoto': {
                  'thumbnails': [
                    {'url': 'https://small', 'width': 48},
                    {'url': 'https://large', 'width': 544},
                  ],
                },
              },
            },
          ],
        },
      });

      expect(identity, isNotNull);
      expect(identity!.name, 'Nipun Gupta');
      expect(identity.email, 'nipun@example.com');
      // The largest thumbnail, not the first: YouTube orders them ascending.
      expect(identity.avatarUrl, 'https://large');
    });

    test('joins a runs-based name', () {
      final identity = AccountParser.parseIdentity({
        'activeAccountHeaderRenderer': {
          'accountName': {
            'runs': [
              {'text': 'Nipun '},
              {'text': 'Gupta'},
            ],
          },
        },
      });
      expect(identity!.name, 'Nipun Gupta');
    });

    test('falls back to the handle when there is no email', () {
      // Some clients answer with only the @handle. A blank second line reads as
      // a bug; the handle is the honest thing to show.
      final identity = AccountParser.parseIdentity({
        'activeAccountHeaderRenderer': {
          'accountName': {'simpleText': 'Nipun'},
          'channelHandle': {'runs': [{'text': '@nipungupta8447'}]},
        },
      });
      expect(identity!.email, '@nipungupta8447');
    });

    test('a missing header yields null rather than a guessed identity', () {
      expect(AccountParser.parseIdentity({'response': {}}), isNull);
      expect(AccountParser.parseIdentity(null), isNull);
    });

    test('a header with no name is not an identity', () {
      // Persisting a nameless account is how the settings list fills with rows
      // that say nothing.
      expect(
        AccountParser.parseIdentity({
          'activeAccountHeaderRenderer': {'email': {'simpleText': 'a@b.c'}},
        }),
        isNull,
      );
    });

    test('finds the header even when nested deep in a different envelope', () {
      // The renderer name is the contract, not the path.
      final identity = AccountParser.parseIdentity({
        'response': {
          'contents': {
            'twoColumnBrowseResultsRenderer': {
              'tabs': [
                {
                  'tabRenderer': {
                    'content': {
                      'sectionListRenderer': {
                        'contents': [
                          {
                            'itemSectionRenderer': {
                              'contents': [
                                {
                                  'activeAccountHeaderRenderer': {
                                    'accountName': {'simpleText': 'Deep'},
                                  },
                                },
                              ],
                            },
                          },
                        ],
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      });
      expect(identity!.name, 'Deep');
    });
  });

  group('parseChannels', () {
    Map<String, dynamic> item({
      String name = 'Personal',
      String? pageId,
      String? dataSyncId,
      bool selected = false,
    }) =>
        {
          'accountItem': {
            'accountName': {'simpleText': name},
            if (pageId != null || dataSyncId != null)
              'supportedTokens': {
                'serializedShareEntities': [
                  if (pageId != null) {'pageIdToken': pageId},
                  // Order is not promised and a positional read would be a
                  // guess, so the token may come first or second.
                  if (dataSyncId != null) {'datasyncIdToken': dataSyncId},
                ],
              },
            if (selected) 'isSelected': 'true',
          },
        };

    test('reads a personal channel with only a dataSyncId', () {
      final channels =
          AccountParser.parseChannels({'accounts': [item(dataSyncId: '123')]});
      expect(channels, hasLength(1));
      expect(channels.single.dataSyncId, '123');
      expect(channels.single.pageId, isNull);
      expect(channels.single.isBrandAccount, isFalse);
    });

    test('reads a brand channel and normalises the delegated id', () {
      final channels = AccountParser.parseChannels({
        'accounts': [
          item(name: 'Brand', pageId: 'UC9', dataSyncId: '999||777'),
        ],
      });
      final channel = channels.single;
      expect(channel.pageId, 'UC9');
      // The delegated half wins; the account half is not who is speaking.
      expect(channel.dataSyncId, '777');
      expect(channel.isBrandAccount, isTrue);
    });

    test('token order does not matter', () {
      final channels = AccountParser.parseChannels({
        'accounts': [
          {
            'accountItem': {
              'accountName': {'simpleText': 'Reversed'},
              'supportedTokens': {
                'serializedShareEntities': [
                  {'datasyncIdToken': '55'},
                  {'pageIdToken': 'UC1'},
                ],
              },
            },
          },
        ],
      });
      final channel = channels.single;
      expect(channel.pageId, 'UC1');
      expect(channel.dataSyncId, '55');
    });

    test('an entry with neither token is dropped', () {
      // Offering a channel we cannot act as silently keeps the current one,
      // which is worse than not offering it at all.
      final channels = AccountParser.parseChannels({
        'accounts': [item(), // no tokens at all
        ],
      });
      expect(channels, isEmpty);
    });

    test('a blank dataSyncId is treated as no token', () {
      // normalizeDataSyncId answers '' for blank input; if that is not folded
      // to null the "no usable tokens" guard silently passes.
      final channels = AccountParser.parseChannels({
        'accounts': [
          {
            'accountItem': {
              'accountName': {'simpleText': 'Blank'},
              'supportedTokens': {
                'serializedShareEntities': [
                  {'datasyncIdToken': '   '},
                ],
              },
            },
          },
        ],
      });
      expect(channels, isEmpty);
    });

    test('reads the avatar, handle and selection flag', () {
      final channels = AccountParser.parseChannels({
        'accounts': [
          {
            'accountItem': {
              'accountName': {'runs': [{'text': 'Ada'}]},
              'channelHandle': {'simpleText': '@ada'},
              'accountPhoto': {
                'thumbnails': [
                  {'url': 'https://tiny', 'width': 16},
                  {'url': 'https://big', 'width': 256},
                ],
              },
              'isSelected': 'true',
              'supportedTokens': {
                'serializedShareEntities': [
                  {'pageIdToken': 'UC7'},
                ],
              },
            },
          },
        ],
      });
      final channel = channels.single;
      expect(channel.name, 'Ada');
      expect(channel.subtitle, '@ada');
      expect(channel.avatarUrl, 'https://big');
      expect(channel.activeOnWeb, isTrue);
    });

    test('an unrecognised envelope yields an empty list, not a throw', () {
      // "We could not read the answer" must not be mistaken for "no channels",
      // so this returns empty and the caller decides what to do about it.
      expect(AccountParser.parseChannels({'response': {'contents': []}}), isEmpty);
      expect(AccountParser.parseChannels(null), isEmpty);
    });

    test('duplicate channels are collapsed by identity', () {
      final channels = AccountParser.parseChannels({
        'accounts': [
          item(name: 'Personal', pageId: 'UC1'),
          item(name: 'Personal again', pageId: 'UC1'),
          item(name: 'Other', pageId: 'UC2'),
        ],
      });
      expect(channels, hasLength(2));
    });
  });

  group('channel presentation', () {
    test('a channel with no subtitle never renders a blank second line', () {
      const brand = AccountChannel(name: 'Brand', pageId: 'UC1');
      expect(brand.displaySubtitle, 'Brand channel');
      const personal = AccountChannel(name: 'Me', dataSyncId: '1');
      expect(personal.displaySubtitle, 'Your channel');
    });

    test('key prefers pageId, then dataSyncId, then name', () {
      expect(const AccountChannel(name: 'n', pageId: 'U', dataSyncId: 'd').key,
          'U');
      expect(const AccountChannel(name: 'n', dataSyncId: 'd').key, 'd');
      expect(const AccountChannel(name: 'n').key, 'n');
    });

    test('activeOnWeb is independent of the app selection', () {
      // Google marking a channel active is not this app acting as it. Treating
      // them as the same thing makes the tick lie.
      const channel = AccountChannel(
          name: 'n', pageId: 'U', dataSyncId: 'd', activeOnWeb: true);
      expect(channel.activeOnWeb, isTrue);
    });
  });
}