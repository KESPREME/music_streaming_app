import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/release/src/commit_notes.dart';
import '../tool/release/src/manifest.dart';
import '../tool/release/src/version_plan.dart';

void main() {
  group('planVersion', () {
    test('a branch push: pubspec name, build from the run number plus the offset',
        () {
      final p = planVersion(
          pubspecVersion: '1.0.4+1', ref: 'refs/heads/master', runNumber: 42);
      expect(p.name, '1.0.4');
      expect(p.build, 142);
      expect(p.tag, 'v1.0.4+142');
      expect(p.fileId, '1.0.4-b142');
      expect(p.prerelease, isFalse);
      expect(p.channel, 'stable');
    });

    test('the build always goes up with the run number', () {
      int build(int run) => planVersion(
              pubspecVersion: '1.0.4+1', ref: 'refs/heads/main', runNumber: run)
          .build;
      expect(build(43), greaterThan(build(42)));
    });

    test('installs in the wild have versionCode 1, so the first build must beat it',
        () {
      expect(
          planVersion(pubspecVersion: '1.0.4+1', ref: 'refs/heads/master', runNumber: 0)
              .build,
          greaterThan(1));
    });

    test('a pubspec build number is a floor, never a ceiling', () {
      expect(
          planVersion(pubspecVersion: '1.0.4+900', ref: 'refs/heads/master', runNumber: 3)
              .build,
          900);
    });

    test('a pushed tag decides the name; +build pins the build', () {
      final p = planVersion(
          pubspecVersion: '1.0.4+1', ref: 'refs/tags/v2.0.0', runNumber: 7);
      expect(p.name, '2.0.0');
      expect(p.build, 107);
      final q = planVersion(
          pubspecVersion: '1.0.4+1', ref: 'refs/tags/v2.0.0+555', runNumber: 7);
      expect(q.build, 555);
    });

    test('a pre-release name or the flag selects the beta channel', () {
      final a = planVersion(
          pubspecVersion: '1.0.4+1', ref: 'refs/tags/v2.0.0-beta.1', runNumber: 1);
      expect(a.prerelease, isTrue);
      expect(a.channel, 'beta');
      final b = planVersion(
          pubspecVersion: '1.0.4+1',
          ref: 'refs/heads/master',
          runNumber: 1,
          forcePrerelease: true);
      expect(b.prerelease, isTrue);
    });

    test('garbage is refused rather than shipped', () {
      expect(
          () => planVersion(pubspecVersion: 'x', ref: 'refs/heads/master', runNumber: 1),
          throwsFormatException);
      expect(
          () => planVersion(
              pubspecVersion: '1.0.0+1', ref: 'refs/tags/release-1', runNumber: 1),
          throwsFormatException);
      expect(
          () => planVersion(pubspecVersion: '1.0.0+1', ref: 'refs/heads/m', runNumber: -1),
          throwsArgumentError);
    });

    test('reads the real pubspec', () {
      final v = readPubspecVersion(File('pubspec.yaml').readAsStringSync());
      expect(v, isNotNull);
      expect(RegExp(r'^\d+\.\d+\.\d+').hasMatch(v!), isTrue);
    });
  });

  group('commit subjects', () {
    test('parse type, scope, breaking and body', () {
      final c = parseCommit('feat(eq)!: bigger bands')!;
      expect(c.type, 'feat');
      expect(c.scope, 'eq');
      expect(c.breaking, isTrue);
      expect(c.subject, 'bigger bands');
      expect(parseCommit('just words'), isNull);
    });

    test('the repo\'s own long commits become short, plain bullets', () {
      final s = sectionsFromCommits([
        'feat(equalizer): a real equalizer - native audio effects on both decks, device-true bands, 23 presets with curve thumbnails, an interactive response graph, pre-amp + clipping protection, loudness, bass, spatial width, hold-to-compare, saved presets and per-output profiles',
        'feat(session): the app remembers where you were - song, queue, position, shuffle, tab and Library view survive a restart; back sends the app to the background instead of ending it; cached Home shows before the network',
        'fix(glass): pure black draws the bottom chrome as dark frosted glass instead of the refraction shader; Glass rendering becomes a setting (Auto / Refraction / Frosted)',
        'docs: pill physics - the one touch language, its rules and what is proven',
        'chore: tidy',
        'Merge branch x',
      ]);
      final titles = s.map((e) => e.title).toList();
      expect(titles, ['New', 'Fixed']);

      final fresh = s.first.items;
      expect(fresh.length, 4,
          reason: 'the equalizer + the three ; clauses of the session commit');
      expect(fresh.first, 'A real equalizer');
      expect(fresh[1], 'The app remembers where you were',
          reason: 'detail after " - " is cut');
      expect(fresh.every((l) => l.length <= maxItemLength), isTrue);
      expect(fresh, contains('Back sends the app to the background instead of ending it'));
      expect(fresh, contains('Cached Home shows before the network'));

      final fixed = s.last.items;
      expect(fixed.length, 2);
      expect(fixed.last, startsWith('Glass rendering becomes a setting'));
    });

    test('invisible work is left out; sections come in a fixed order', () {
      final s = sectionsFromCommits([
        'fix: a crash',
        'feat: a feature',
        'perf: faster start',
        'ci: workflow',
        'test: more',
        'docs: words',
        'build: gradle',
      ]);
      expect(s.map((e) => e.title), ['New', 'Improved', 'Fixed']);
      expect(s.map((e) => e.icon), ['sparkle', 'improved', 'fix']);
    });

    test('a breaking chore is still reported', () {
      final s = sectionsFromCommits(['chore!: drop Android 6']);
      expect(s.single.items.single, 'Drop Android 6');
    });

    test('non-conventional subjects are bucketed by their first word', () {
      final s = sectionsFromCommits(['Fix the thing', 'Add a button', 'Tweak colours']);
      expect(s.firstWhere((e) => e.title == 'Fixed').items, ['Fix the thing']);
      expect(s.firstWhere((e) => e.title == 'New').items, ['Add a button']);
      expect(s.firstWhere((e) => e.title == 'Improved').items, ['Tweak colours']);
    });

    test('duplicates collapse and a section is capped', () {
      final dup = sectionsFromCommits(['fix: same', 'fix(x): Same.']);
      expect(dup.single.items.length, 1);
      final many = sectionsFromCommits([for (var i = 0; i < 40; i++) 'feat: item $i']);
      expect(many.single.items.length, maxItemsPerSection);
    });

    test('[skip release] commits are not mentioned', () {
      expect(sectionsFromCommits(['feat: x [skip release]']), isEmpty);
    });

    test('tidy: capital, no full stop, no backticks, never overlong', () {
      expect(tidy('  fix   the   thing. '), 'Fix the thing');
      expect(tidy('use `Foo` now'), 'Use Foo now');
      final long = tidy('word ' * 80);
      expect(long.length, lessThanOrEqualTo(maxItemLength));
      expect(long, endsWith('\u2026'));
      expect(tidy(''), '');
    });
  });

  group('curated notes', () {
    const md = '''
# Glass that behaves

A calmer, cleaner bottom bar and a real equalizer.

## ✨ New
- Equalizer with presets
- Software update screen

## 🛠 Improved
* Faster cold start

### 🐞 Fixed
1. Pure black no longer tears
''';

    test('title, summary, sections and icons are read', () {
      final r = sectionsFromMarkdown(md);
      expect(r.title, 'Glass that behaves');
      expect(r.summary, startsWith('A calmer'));
      expect(r.sections.map((s) => s.title), ['New', 'Improved', 'Fixed']);
      expect(r.sections.map((s) => s.icon), ['sparkle', 'improved', 'fix']);
      expect(r.sections.first.items, ['Equalizer with presets', 'Software update screen']);
    });

    test('empty and odd input does not throw', () {
      expect(sectionsFromMarkdown('').sections, isEmpty);
      expect(sectionsFromMarkdown('\r\n\r\n- bullet with no heading').sections, isEmpty);
    });
  });

  group('release body', () {
    final sections = [
      const NoteSection('New', 'sparkle', ['Equalizer']),
      const NoteSection('Fixed', 'fix', ['Pure black tearing']),
    ];

    test('banner first, then a title, sections, screenshots and the checksum', () {
      final body = renderReleaseBody(
        appName: 'Mine Music',
        version: '1.1.0',
        sections: sections,
        bannerUrl: 'https://x/banner.png',
        gallery: const [GalleryImage('https://x/a.jpg', 'Equalizer')],
        compareUrl: 'https://x/compare',
        sha256: 'ab' * 32,
      );
      final lines = body.split('\n');
      expect(lines.first, '![Mine Music 1.1.0](https://x/banner.png)');
      expect(body, contains('# Mine Music 1.1.0'));
      expect(body, contains('## \u2728 New'));
      expect(body, contains('- Equalizer'));
      expect(body, contains('## \ud83d\udc1e Fixed'));
      expect(body, contains('![Equalizer](https://x/a.jpg)'));
      expect(body, contains('SHA-256: `${'ab' * 32}`'));
      expect(body.indexOf('banner.png'), lessThan(body.indexOf('# Mine Music')));
      expect(body.indexOf('## \u2728 New'), lessThan(body.indexOf('## Screenshots')));
    });

    test('a release with no notes still says something true', () {
      final body = renderReleaseBody(
          appName: 'Mine Music', version: '1.1.0', sections: const []);
      expect(body, contains('Maintenance release'));
    });
  });

  group('update.json', () {
    ManifestInput input({String sha = ''}) => ManifestInput(
          repo: 'KESPREME/music_streaming_app',
          name: '1.1.0',
          build: 142,
          tag: 'v1.1.0+142',
          channel: 'stable',
          publishedAt: DateTime.utc(2026, 10, 20, 12),
          apkName: 'MineMusic-1.1.0-b142.apk',
          apkSize: 62914560,
          apkSha256: sha.isEmpty ? 'a1' * 32 : sha,
          sections: const [
            NoteSection('New', 'sparkle', ['One', 'Two']),
            NoteSection('Fixed', 'fix', ['Three', 'Four']),
          ],
          notesMarkdown: '# Notes',
          title: 'Mine Music 1.1.0',
          bannerName: 'MineMusic-1.1.0-b142-banner.png',
          gallery: const [('MineMusic-1.1.0-b142-eq.jpg', 'Eq')],
        );

    test('carries everything the app reads, with URL-safe asset links', () {
      final m = jsonDecode(encodeManifest(buildManifest(input()))) as Map<String, dynamic>;
      expect(m['schema'], 1);
      expect(m['version'], '1.1.0');
      expect(m['build'], 142);
      expect(m['tag'], 'v1.1.0+142');
      expect(m['channel'], 'stable');
      expect(m['publishedAt'], '2026-10-20T12:00:00.000Z');
      expect(m['highlights'], ['One', 'Two', 'Three']);
      expect((m['sections'] as List).length, 2);

      final asset = (m['assets'] as List).single as Map<String, dynamic>;
      expect(asset['abi'], 'universal');
      expect(asset['size'], 62914560);
      expect(asset['sha256'], 'a1' * 32);
      expect(asset['url'],
          'https://github.com/KESPREME/music_streaming_app/releases/download/v1.1.0%2B142/MineMusic-1.1.0-b142.apk');

      final images = m['images'] as Map<String, dynamic>;
      expect((images['banner'] as String), contains('%2B142'));
      expect(((images['gallery'] as List).single as Map)['caption'], 'Eq');
      expect(m['releaseUrl'],
          'https://github.com/KESPREME/music_streaming_app/releases/tag/v1.1.0%2B142');
    });

    test('refuses a checksum that is not 64 lowercase hex', () {
      expect(() => buildManifest(input(sha: 'XYZ')), throwsArgumentError);
      expect(() => buildManifest(input(sha: 'A1' * 32)), throwsArgumentError);
    });

    test('captions come from file names', () {
      expect(captionFromFileName('screenshot-1.jpg'), 'Screenshot');
      expect(captionFromFileName('screenshot-2-equalizer.png'), 'Equalizer');
      expect(captionFromFileName('home_screen.jpg'), 'Home screen');
    });
  });

  group('end to end: dart run tool/release/prepare.dart', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('release_tools'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('plan prints GITHUB_OUTPUT lines', () async {
      final r = await Process.run('dart', [
        'run', 'tool/release/prepare.dart', 'plan',
        '--ref', 'refs/heads/master', '--run-number', '9',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final out = (r.stdout as String).trim().split(RegExp(r'\r?\n'));
      expect(out.any((l) => l.startsWith('name=')), isTrue);
      expect(out, contains('build=109'));
      expect(out.any((l) => RegExp(r'^tag=v\d+\.\d+\.\d+\+109$').hasMatch(l)), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('notes builds the apk name, checksum, manifest, body and images', () async {
      final apk = File('${tmp.path}/app-release.apk')
        ..writeAsBytesSync(List<int>.generate(4096, (i) => i % 251));
      final images = Directory('${tmp.path}/images')..createSync();
      File('${images.path}/banner.png').writeAsBytesSync([1, 2, 3]);
      File('${images.path}/screenshot-1-equalizer.jpg').writeAsBytesSync([4, 5]);
      File('${images.path}/captions.json')
          .writeAsStringSync(jsonEncode({'screenshot-1-equalizer.jpg': 'The new equalizer'}));
      final out = Directory('${tmp.path}/out');

      final r = await Process.run('dart', [
        'run', 'tool/release/prepare.dart', 'notes',
        '--repo', 'KESPREME/music_streaming_app',
        '--name', '9.9.9', '--build', '777', '--tag', 'v9.9.9+777',
        '--apk', apk.path, '--out', out.path, '--images', images.path,
        '--from', 'HEAD~3', '--to', 'HEAD',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');

      expect(File('${out.path}/MineMusic-9.9.9-b777.apk').existsSync(), isTrue);
      final sha = File('${out.path}/MineMusic-9.9.9-b777.apk.sha256').readAsStringSync();
      expect(RegExp(r'^[0-9a-f]{64}  MineMusic-9\.9\.9-b777\.apk\n$').hasMatch(sha), isTrue);

      final m = jsonDecode(File('${out.path}/update.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(m['build'], 777);
      final asset = (m['assets'] as List).single as Map<String, dynamic>;
      expect(asset['size'], 4096);
      expect(sha.startsWith(asset['sha256'] as String), isTrue,
          reason: 'the manifest and the .sha256 file agree');
      final gallery = (m['images'] as Map)['gallery'] as List;
      expect((gallery.single as Map)['caption'], 'The new equalizer');

      final body = File('${out.path}/notes.md').readAsStringSync();
      expect(body, startsWith('![Mine Music 9.9.9]('));
      expect(body, contains('![The new equalizer]('));
      expect(File('${out.path}/MineMusic-9.9.9-b777-banner.png').existsSync(), isTrue);
      expect(File('${out.path}/MineMusic-9.9.9-b777-screenshot-1-equalizer.jpg').existsSync(), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('notes fails loudly when the APK is missing', () async {
      final r = await Process.run('dart', [
        'run', 'tool/release/prepare.dart', 'notes',
        '--repo', 'o/r', '--name', '1.0.0', '--build', '1', '--tag', 'v1.0.0+1',
        '--apk', '${tmp.path}/nope.apk', '--out', '${tmp.path}/out',
      ]);
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('APK not found'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
