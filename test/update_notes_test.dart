import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/services/update/release_notes.dart';
import 'package:music_streaming_app/services/update/update_models.dart';

/// UPDATES: release notes. A GitHub body (or an update.json) becomes a title,
/// one summary line, three highlights, sections with icons, a banner and a
/// gallery - and ANY string, however broken, parses without throwing.

const _bannerUrl = 'https://github.com/KESPREME/music_streaming_app/releases/download/v1.1.0%2B142/banner.png';
const _shotUrl = 'https://github.com/KESPREME/music_streaming_app/releases/download/v1.1.0%2B142/screenshot-1.jpg';

/// BitChord-style: banner, H1, intro, emoji section headings, mixed bullets,
/// a trailing screenshot.
const _bitchord = '''
![banner]($_bannerUrl)

# Glass that behaves, and an equalizer

A calmer player, a ten-band equalizer, and a lot of small fixes.

## \u2728 New
- **Equalizer** with ten bands and presets
- Sleep timer in the player menu
* Lyrics share card

### \u{1F527} Improved
1. Mini player animates `smoother`
2. Search remembers [recent queries](https://example.com/q)

### \u{1F41B} Fixed
- Seek bar jumping on long tracks
- Crash when the queue is empty

![Equalizer]($_shotUrl)
''';

void main() {
  group('parseReleaseBody - BitChord-style body', () {
    final n = parseReleaseBody(_bitchord);

    test('the first image before any heading is the banner', () {
      expect(n.bannerUrl, _bannerUrl);
    });

    test('a leading H1 is the title and is not repeated in the body', () {
      expect(n.title, 'Glass that behaves, and an equalizer');
      expect(n.notesMarkdown, isNot(contains('# Glass')));
    });

    test('the first paragraph is the summary', () {
      expect(n.summary, 'A calmer player, a ten-band equalizer, and a lot of small fixes.');
    });

    test('headings become sections with the emoji stripped and an icon', () {
      expect(n.sections.map((s) => s.title), ['New', 'Improved', 'Fixed']);
      expect(n.sections.map((s) => s.icon), ['sparkle', 'improved', 'fix']);
    });

    test('bullets of every flavour become items, original text intact', () {
      expect(n.sections[0].items, [
        '**Equalizer** with ten bands and presets',
        'Sleep timer in the player menu',
        'Lyrics share card',
      ]);
      expect(n.sections[1].items, [
        'Mini player animates `smoother`',
        'Search remembers [recent queries](https://example.com/q)',
      ]);
      expect(n.sections[2].items, hasLength(2));
    });

    test('highlights are the first three items with markdown stripped', () {
      expect(n.highlights, [
        'Equalizer with ten bands and presets',
        'Sleep timer in the player menu',
        'Lyrics share card',
      ]);
    });

    test('every other image is gallery, alt text is the caption, and none remain in the body', () {
      expect(n.gallery, [const ReleaseGalleryImage(url: _shotUrl, caption: 'Equalizer')]);
      expect(n.notesMarkdown, isNot(contains('![')));
      expect(n.notesMarkdown, contains('## \u2728 New'));
    });
  });

  group('parseReleaseBody - images', () {
    test('an image after a heading is gallery, not banner', () {
      final n = parseReleaseBody('## New\n![late](https://e.com/a.png)\n- one');
      expect(n.bannerUrl, isNull);
      expect(n.gallery.single.url, 'https://e.com/a.png');
      expect(n.gallery.single.caption, 'late');
    });

    test('a banner may follow the H1 title', () {
      final n = parseReleaseBody('# Title\n![b](https://e.com/b.png)\n\n## New\n- x');
      expect(n.title, 'Title');
      expect(n.bannerUrl, 'https://e.com/b.png');
    });

    test('HTML <img> is recognised, either quote style, and layout tags are dropped', () {
      final n = parseReleaseBody('''
<p align="center">
  <img src="https://e.com/a.png" alt="Home screen" width="300">
</p>

## What's new
- Faster startup

## Performance
- Lower memory use
<img alt='Graph' src='https://e.com/b.png'>
''');
      expect(n.bannerUrl, 'https://e.com/a.png');
      expect(n.gallery, [const ReleaseGalleryImage(url: 'https://e.com/b.png', caption: 'Graph')]);
      expect(n.notesMarkdown, isNot(contains('<img')));
      expect(n.notesMarkdown, isNot(contains('<p')));
      expect(n.sections.map((s) => s.title), ["What's new", 'Performance']);
      expect(n.sections.map((s) => s.icon), ['sparkle', 'perf']);
    });

    test('an image wrapped in a link keeps the image and drops the link', () {
      final n = parseReleaseBody('[![badge](https://e.com/i.png)](https://e.com/page)\n## New\n- a');
      expect(n.bannerUrl, 'https://e.com/i.png');
      expect(n.notesMarkdown, isNot(contains('e.com/page')));
    });

    test('an image with a title and angle brackets still parses', () {
      final n = parseReleaseBody('![x](<https://e.com/a.png> "Title")\n![y](https://e.com/y.png "t")');
      expect(n.bannerUrl, 'https://e.com/a.png');
      expect(n.gallery.single.url, 'https://e.com/y.png');
    });

    test('non-https and relative images are removed from the text and never offered', () {
      final n = parseReleaseBody('![a](http://e.com/a.png)\n![b](screenshot.png)\n![c](https://e.com/c.png)\n- x');
      expect(n.bannerUrl, 'https://e.com/c.png');
      expect(n.gallery, isEmpty);
      expect(n.notesMarkdown, isNot(contains('![')));
    });

    test('the same image twice appears once', () {
      final n = parseReleaseBody('![a](https://e.com/a.png)\n![a](https://e.com/a.png)\n![b](https://e.com/b.png)');
      expect(n.bannerUrl, 'https://e.com/a.png');
      expect(n.gallery.map((g) => g.url), ['https://e.com/b.png']);
    });

    test('an image mid-sentence is pulled out and the sentence stays', () {
      final n = parseReleaseBody('See ![x](https://e.com/x.png) for details\n- a');
      expect(n.notesMarkdown, contains('See'));
      expect(n.notesMarkdown, contains('for details'));
      expect(n.notesMarkdown, isNot(contains('![')));
    });

    test('images inside a code fence are left alone', () {
      final n = parseReleaseBody('```\n![x](https://e.com/x.png)\n# not a heading\n- not a bullet\n```\n- real');
      expect(n.bannerUrl, isNull);
      expect(n.gallery, isEmpty);
      expect(n.sections.single.items, ['real']);
      expect(n.notesMarkdown, contains('![x](https://e.com/x.png)'));
    });
  });

  group('parseReleaseBody - structure', () {
    test('CRLF and a GitHub auto-generated body', () {
      final n = parseReleaseBody(
        "## What's Changed\r\n"
        '* Fix crash on startup by @dev in https://github.com/x/y/pull/12\r\n'
        '* Add [equalizer](https://x.y) by @dev in #13\r\n'
        '\r\n'
        '## New Contributors\r\n'
        '* @newbie made their first contribution in #14\r\n'
        '\r\n'
        '**Full Changelog**: https://github.com/x/y/compare/v1.0.0...v1.1.0\r\n',
      );
      expect(n.notesMarkdown, isNot(contains('\r')));
      expect(n.sections.map((s) => s.title), ["What's Changed", 'New Contributors']);
      expect(n.sections[0].items.first, 'Fix crash on startup by @dev in https://github.com/x/y/pull/12');
      expect(n.highlights, [
        'Fix crash on startup by @dev in https://github.com/x/y/pull/12',
        'Add equalizer by @dev in #13',
        '@newbie made their first contribution in #14',
      ]);
      // "Full Changelog" is not a summary.
      expect(n.summary, isNull);
      expect(n.title, isNull);
    });

    test('bullets with no heading land in an implicit "Changes" section', () {
      final n = parseReleaseBody('Quick fix release.\n\n- Fixed crash\n- Fixed login');
      expect(n.summary, 'Quick fix release.');
      expect(n.sections.single.title, 'Changes');
      expect(n.sections.single.icon, 'improved'); // "Changes" reads as improved
      expect(n.sections.single.items, ['Fixed crash', 'Fixed login']);
    });

    test('a wrapped bullet continues the item; checkboxes lose their box', () {
      final n = parseReleaseBody('## New\n- A very long item that\n  wraps onto a second line\n- [x] Done thing\n- [ ] Open thing');
      expect(n.sections.single.items, [
        'A very long item that wraps onto a second line',
        'Done thing',
        'Open thing',
      ]);
    });

    test('nested bullets are kept as their own items', () {
      final n = parseReleaseBody('## New\n- Parent\n  - Child one\n  - Child two');
      expect(n.sections.single.items, ['Parent', 'Child one', 'Child two']);
    });

    test('headings with closing hashes, emphasis, trailing colons and emoji', () {
      final n = parseReleaseBody('## **Fixed** ##\n- a\n\n### \u{1F41B} Bug fixes:\n- b\n\n## New \u2728\n- c\n\n## \u{1F389}\n- d');
      expect(n.sections.map((s) => s.title), ['Fixed', 'Bug fixes', 'New', 'Other']);
      expect(n.sections.map((s) => s.icon), ['fix', 'fix', 'sparkle', 'sparkle']);
    });

    test('a heading with no bullets under it is not a section but stays in the text', () {
      final n = parseReleaseBody('## Notes\nJust prose here.\n\n## New\n- a');
      expect(n.sections.map((s) => s.title), ['New']);
      expect(n.notesMarkdown, contains('## Notes'));
      expect(n.summary, 'Just prose here.');
    });

    test('a second H1 is a section, not a second title', () {
      final n = parseReleaseBody('# One\n# Two\n- a');
      expect(n.title, 'One');
      expect(n.sections.single.title, 'Two');
    });

    test('summary is the first paragraph only, truncated to 160 characters', () {
      final long = 'word ' * 100;
      final n = parseReleaseBody('$long\n\nSecond paragraph.\n\n- a');
      expect(n.summary!.length, lessThanOrEqualTo(160));
      expect(n.summary, endsWith('\u2026'));
      expect(n.summary, startsWith('word word'));
    });

    test('a multi-line paragraph joins into one summary line, markdown stripped', () {
      final n = parseReleaseBody('A **bold** move with\n[a link](https://e.com) and `code`.\n\n- a');
      expect(n.summary, 'A bold move with a link and code.');
    });

    test('summary skips quotes, tables, bare URLs and Full Changelog', () {
      final n = parseReleaseBody('> quote\n\n| a | b |\n\nhttps://example.com/x\n\n**Full Changelog**: https://x\n\nReal one.\n');
      expect(n.summary, 'Real one.');
    });

    test('highlights stop at three even across sections', () {
      final n = parseReleaseBody('## New\n- a\n- b\n## Fixed\n- c\n- d\n- e');
      expect(n.highlights, ['a', 'b', 'c']);
    });

    test('horizontal rules and blank-line runs are tidied', () {
      final n = parseReleaseBody('## New\n- a\n\n\n\n\n---\n\n\n\nText');
      expect(n.notesMarkdown, isNot(contains('\n\n\n')));
      expect(n.notesMarkdown, contains('---'));
    });

    test('empty and whitespace-only bodies are empty notes', () {
      expect(parseReleaseBody(''), ReleaseNotes.empty);
      expect(parseReleaseBody('   \n\r\n\t\n').isEmpty, isTrue);
    });
  });

  group('parseReleaseBody - totality', () {
    final hostile = <String, String>{
      'control characters': '\u0000\u0001\u0002## New\u0003\n- a\u0004',
      'lone high surrogate': 'bad ${String.fromCharCode(0xD83D)} text\n- ${String.fromCharCode(0xD83D)}',
      'lone low surrogate': '\u{FFFF}${String.fromCharCode(0xDE00)}',
      'only CRs': '\r\r\r\r',
      'bare hash': '#',
      'hash space': '# ',
      'open image': '![](',
      'open image 2': '![x](',
      'open html': '<img',
      'open html 2': '<img src="https://e.com/a.png"',
      'empty bullet': '- ',
      'empty bullets': '-\n*\n+\n1.\n',
      'unterminated fence': '```\n- a\n## b',
      'nested brackets': '[[[[]]]](((())))![![![![',
      'emphasis soup': '*' * 500 + '_' * 500 + '`' * 500,
      'null bytes': '\u0000' * 1000,
      'tabs': '\t\t\t- a\n\t## b',
    };
    for (final e in hostile.entries) {
      test('survives ${e.key}', () {
        final n = parseReleaseBody(e.value);
        expect(n.highlights.length, lessThanOrEqualTo(3));
        expect((n.summary ?? '').length, lessThanOrEqualTo(160));
        // Whatever comes out must be safe to hand to the text engine.
        expect(_hasLoneSurrogate(n.notesMarkdown), isFalse);
        expect(_hasLoneSurrogate(n.summary ?? ''), isFalse);
      });
    }

    test('a huge body (5000 bullets, 20 headings) parses quickly and is bounded', () {
      final b = StringBuffer();
      for (var s = 0; s < 20; s++) {
        b.writeln('## Section $s');
        for (var i = 0; i < 250; i++) {
          b.writeln('- item $s.$i with **some** `markdown`');
        }
      }
      final sw = Stopwatch()..start();
      final n = parseReleaseBody(b.toString());
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      // The body is cut at 120,000 characters, so not every section survives.
      expect(n.sections.length, inInclusiveRange(5, 20));
      expect(n.sections.first.items.length, 200); // capped per section
      expect(n.highlights, hasLength(3));
    });

    test('a 300 KB body is cut, not crashed on', () {
      final n = parseReleaseBody('word ' * 60000);
      expect(n.notesMarkdown.length, lessThanOrEqualTo(120000));
    });

    test('pathological syntax cannot hang the parser', () {
      // One enormous line is skipped by the inline pass; 60 lines of ~2,000
      // characters are the worst case for the image/emphasis regexes (each
      // unclosed opener used to rescan the whole line - 4 s for this input).
      String rep(String unit) => unit * (1990 ~/ unit.length);
      final cases = <String, String>{
        'one huge line': '![' * 100000,
        'unclosed images': List.filled(60, rep('![')).join('\n'),
        'unclosed html': List.filled(60, rep('<img ')).join('\n'),
        'linked images': List.filled(60, rep('[![')).join('\n'),
        'brackets': List.filled(60, rep('[')).join('\n'),
        'image openers': List.filled(60, rep('![](')).join('\n'),
        'backticks': List.filled(60, rep('`a')).join('\n'),
        'stars': List.filled(60, rep('*a')).join('\n'),
        'underscores': List.filled(60, rep('_a')).join('\n'),
        'tags': List.filled(60, rep('<a ')).join('\n'),
        'bullets': List.filled(60, rep('- ')).join('\n'),
        'hashes': List.filled(60, rep('#')).join('\n'),
        'spaces': List.filled(60, '${' ' * 1980}x').join('\n'),
        'twenty images': List.filled(60, rep('![a](https://e.com/a.png)')).join('\n'),
      };
      for (final e in cases.entries) {
        final sw = Stopwatch()..start();
        parseReleaseBody(e.value);
        expect(sw.elapsed, lessThan(const Duration(seconds: 2)), reason: e.key);
      }
    });

    test('random markdown soup never throws', () {
      final rnd = Random(42);
      final atoms = [
        '# ', '## ', '### ', '- ', '* ', '1. ', '> ', '```', '~~~', '![', '](', ')', '[', ']',
        '<img src="', '">', 'https://e.com/a.png', 'http://e.com', '**', '_', '`', '\n', '\n\n',
        '\r\n', '\t', '  ', 'word', 'New', 'Fixed', '\u2728', '\u{1F41B}', '\u0000', 'x' * 50,
      ];
      for (var i = 0; i < 400; i++) {
        final s = List.generate(rnd.nextInt(60), (_) => atoms[rnd.nextInt(atoms.length)]).join();
        final n = parseReleaseBody(s);
        expect(n.highlights.length, lessThanOrEqualTo(3), reason: s);
        expect((n.summary ?? '').length, lessThanOrEqualTo(160), reason: s);
        expect(n.notesMarkdown, isNot(contains('\r')), reason: s);
        for (final sec in n.sections) {
          expect(sec.items, isNotEmpty, reason: s);
          expect(sec.title, isNotEmpty, reason: s);
          expect(kNoteIconKeys, contains(sec.icon), reason: s);
        }
      }
    });
  });

  group('helpers', () {
    test('iconForHeading prefers the words, then the emoji, then other', () {
      const table = {
        'New': 'sparkle',
        "What's new": 'sparkle',
        '\u2728 Features': 'sparkle',
        'Improvements': 'improved',
        'Changed': 'improved',
        'Fixed': 'fix',
        'Bug fixes': 'fix',
        'Performance': 'perf',
        'Faster everything': 'perf',
        'UI polish': 'design',
        'Design': 'design',
        '\u{1F680} Performance': 'perf', // words beat the rocket
        '\u{1F41B}': 'fix',
        '\u26A1': 'perf',
        '\u{1F3A8}': 'design',
        'Misc': 'other',
        '': 'other',
      };
      table.forEach((heading, icon) {
        expect(iconForHeading(heading), icon, reason: heading);
      });
    });

    test('normalizeIconKey maps synonyms and rejects the unknown', () {
      expect(normalizeIconKey('sparkle'), 'sparkle');
      expect(normalizeIconKey(' NEW '), 'sparkle');
      expect(normalizeIconKey('bug'), 'fix');
      expect(normalizeIconKey('bolt'), 'perf');
      expect(normalizeIconKey('rocket'), isNull);
      expect(normalizeIconKey(null), isNull);
    });

    test('cleanSectionTitle', () {
      const table = {
        '\u2728 New': 'New',
        '\u{1F41B}\uFE0F Fixed:': 'Fixed',
        '**Improved**': 'Improved',
        'New \u2728': 'New',
        '\u{1F389}': 'Other',
        '   ': 'Other',
        '\u00DCnic\u00F6de': '\u00DCnic\u00F6de',
        '2024 recap': '2024 recap',
      };
      table.forEach((raw, clean) {
        expect(cleanSectionTitle(raw), clean, reason: raw);
      });
    });

    test('plainFromMarkdown', () {
      const table = {
        '**bold** and __also__': 'bold and also',
        '*em* and _em_': 'em and em',
        'snake_case_name stays': 'snake_case_name stays',
        '`code` here': 'code here',
        '[text](https://e.com) link': 'text link',
        '![alt](https://e.com/i.png) pic': 'pic',
        '~~gone~~ stays': 'gone stays',
        '<b>tag</b> text': 'tag text',
        '<https://e.com/x>': 'https://e.com/x',
        '  lots   of   space  ': 'lots of space',
        '': '',
      };
      table.forEach((md, plain) {
        expect(plainFromMarkdown(md), plain, reason: md);
      });
    });
  });

  group('ReleaseNotes.fromManifest', () {
    final manifest = <String, dynamic>{
      'title': 'Glass that behaves, and an equalizer',
      'summary': 'optional one line',
      'highlights': ['short bullet', 'short bullet 2'],
      'sections': [
        {'title': 'New', 'icon': 'sparkle', 'items': ['a', 'b']},
        {'title': 'Improved', 'items': ['c']},
        {'title': 'Fixed', 'icon': 'bug', 'items': ['d']},
        {'title': 'Empty', 'items': []},
        'not a map',
      ],
      'notes': '## Details\nSome **markdown** with ![inline](https://e.com/inline.png) image.\n\n- bullet',
      'images': {
        'banner': 'https://e.com/banner.png',
        'gallery': [
          {'url': 'https://e.com/s1.jpg', 'caption': 'Equalizer'},
          {'url': 'https://e.com/s2.jpg'},
          {'url': 'http://e.com/insecure.jpg'},
          'https://e.com/s3.jpg',
        ],
      },
      'somethingNew': {'ignored': true},
    };

    test('reads every declared field', () {
      final n = ReleaseNotes.fromManifest(manifest);
      expect(n.title, 'Glass that behaves, and an equalizer');
      expect(n.summary, 'optional one line');
      expect(n.highlights, ['short bullet', 'short bullet 2']);
      expect(n.sections.map((s) => s.title), ['New', 'Improved', 'Fixed']);
      expect(n.sections.map((s) => s.icon), ['sparkle', 'improved', 'fix']);
      expect(n.bannerUrl, 'https://e.com/banner.png');
    });

    test('gallery keeps order, skips insecure, and adds images found in the notes', () {
      final n = ReleaseNotes.fromManifest(manifest);
      expect(n.gallery.map((g) => g.url), [
        'https://e.com/s1.jpg',
        'https://e.com/s2.jpg',
        'https://e.com/s3.jpg',
        'https://e.com/inline.png',
      ]);
      expect(n.gallery.first.caption, 'Equalizer');
      expect(n.notesMarkdown, isNot(contains('![')));
      expect(n.notesMarkdown, contains('Some **markdown**'));
    });

    test('absent keys are derived from the markdown notes', () {
      final n = ReleaseNotes.fromManifest({'notes': _bitchord});
      expect(n.title, 'Glass that behaves, and an equalizer');
      expect(n.sections.map((s) => s.title), ['New', 'Improved', 'Fixed']);
      expect(n.highlights, hasLength(3));
      expect(n.bannerUrl, _bannerUrl);
    });

    test('a key that is present is authoritative, even when empty', () {
      final n = ReleaseNotes.fromManifest({
        'notes': _bitchord,
        'highlights': <String>[],
        'sections': <Object>[],
        'title': null,
      });
      expect(n.highlights, isEmpty);
      expect(n.sections, isEmpty);
      expect(n.title, isNull);
    });

    test('highlights are derived from declared sections when not declared', () {
      final n = ReleaseNotes.fromManifest({
        'sections': [
          {'title': 'New', 'items': ['**one**', 'two', 'three', 'four']},
        ],
      });
      expect(n.highlights, ['one', 'two', 'three']);
    });

    test('wrong types and junk do not throw', () {
      final junk = <Map<String, dynamic>>[
        {},
        {'title': 5, 'summary': [], 'highlights': {'a': 1}, 'sections': 'nope', 'notes': 7, 'images': 'x'},
        {'sections': [null, 1, [], {'items': 'x'}], 'images': {'gallery': 'x', 'banner': 4}},
        {'notes': '\u0000' * 100},
      ];
      for (final m in junk) {
        expect(() => ReleaseNotes.fromManifest(m), returnsNormally, reason: '$m');
      }
    });

    test('an over-long summary is cut to 160', () {
      final n = ReleaseNotes.fromManifest({'summary': 'x' * 500});
      expect(n.summary!.length, 160);
    });
  });

  group('JSON round trip (the cache)', () {
    test('ReleaseNotes survives toJson/fromJson exactly', () {
      for (final body in [_bitchord, '', '- a\n- b', '## New\n![x](https://e.com/x.png)\n- a']) {
        final n = parseReleaseBody(body);
        expect(ReleaseNotes.fromJson(n.toJson()), n, reason: body);
      }
    });

    test('ReleaseInfo survives a JSON text round trip', () {
      final info = ReleaseInfo(
        version: '1.2.0-beta.1',
        build: 150,
        tag: 'v1.2.0-beta.1+150',
        channel: UpdateChannel.beta,
        publishedAt: DateTime.utc(2026, 10, 20, 12),
        minSdk: 24,
        notes: parseReleaseBody(_bitchord),
        asset: ReleaseAsset(
          name: 'MineMusic-1.2.0-beta.1-b150.apk',
          url: 'https://e.com/a.apk',
          abi: 'arm64-v8a',
          size: 62914560,
          sha256: 'a' * 64,
        ),
        releaseUrl: 'https://github.com/KESPREME/music_streaming_app/releases/tag/v1.2.0-beta.1%2B150',
        prerelease: true,
      );
      final back = ReleaseInfo.fromJson(_viaText(info.toJson()));
      expect(back, info);
      expect(back.id, '1.2.0-beta.1+150');
      expect(back.hashCode, info.hashCode);
    });

    test('a minimal ReleaseInfo round-trips with null fields staying null', () {
      const info = ReleaseInfo(version: '1.0.0', build: 1, tag: 'v1.0.0+1');
      final back = ReleaseInfo.fromJson(_viaText(info.toJson()));
      expect(back, info);
      expect(back.asset, isNull);
      expect(back.publishedAt, isNull);
      expect(back.minSdk, isNull);
      expect(back.notes.isEmpty, isTrue);
    });

    test('fromJson without version/build is a FormatException; with junk elsewhere it still reads', () {
      expect(() => ReleaseInfo.fromJson({'version': '1.0.0'}), throwsFormatException);
      expect(() => ReleaseInfo.fromJson({'build': 3}), throwsFormatException);
      final r = ReleaseInfo.fromJson({
        'version': '1.0.0',
        'build': '7', // a string where a number belongs
        'asset': {'url': 'http://insecure/a.apk', 'name': 'a.apk'},
        'publishedAt': 'yesterday',
        'channel': 42,
        'releaseUrl': 'ftp://x',
      });
      expect(r.build, 7);
      expect(r.asset, isNull);
      expect(r.publishedAt, isNull);
      expect(r.releaseUrl, '');
      expect(r.tag, 'v1.0.0+7');
    });

    test('ReleaseAsset.tryParse needs an https url and clamps absurd sizes', () {
      expect(ReleaseAsset.tryParse({'name': 'a.apk', 'url': 'http://e.com/a.apk'}), isNull);
      expect(ReleaseAsset.tryParse('x'), isNull);
      final a = ReleaseAsset.tryParse({'url': 'https://e.com/dir/b.apk', 'size': -5, 'sha256': 'NOPE'})!;
      expect(a.name, 'b.apk');
      expect(a.size, 0);
      expect(a.sha256, '');
      expect(a.abi, 'universal');
      final b = ReleaseAsset.tryParse({'url': 'https://e.com/b.apk', 'sha256': 'SHA256:${'AB' * 32}'})!;
      expect(b.sha256, 'ab' * 32);
    });
  });
}

Map<String, dynamic> _viaText(Map<String, dynamic> json) {
  // Through real JSON text, as SharedPreferences would store it.
  return jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
}

bool _hasLoneSurrogate(String s) {
  for (var i = 0; i < s.length; i++) {
    final u = s.codeUnitAt(i);
    if (u >= 0xD800 && u <= 0xDBFF) {
      if (i + 1 >= s.length) return true;
      final next = s.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return true;
      i++;
    } else if (u >= 0xDC00 && u <= 0xDFFF) {
      return true;
    }
  }
  return false;
}
