import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/update/update_models.dart';
import 'package:music_streaming_app/services/update/update_repository.dart';

/// THE CONTRACT BETWEEN CI AND THE APP.
///
/// The release workflow writes `update.json`, the app reads it. Each side has its
/// own tests, but a mismatch between them - a renamed field, a changed URL shape -
/// would pass both and still ship an app that cannot see its own updates. This
/// runs the real tool, serves its real output as a GitHub release, and asks the
/// real client what it understood.
/// GitHub serves UTF-8 JSON; the notes carry emoji headings.
http.Response _json(String body, {String? etag}) => http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        if (etag != null) 'etag': etag,
      },
    );

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pipeline'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('what the release tool publishes is exactly what the app understands',
      () async {
    final apk = File('${tmp.path}/app-release.apk')
      ..writeAsBytesSync(List<int>.generate(8192, (i) => (i * 7) % 253));
    final arm = File('${tmp.path}/app-arm64.apk')
      ..writeAsBytesSync(List<int>.generate(3000, (i) => (i * 11) % 251));
    final images = Directory('${tmp.path}/images')..createSync();
    File('${images.path}/banner.png').writeAsBytesSync([9, 9, 9]);
    File('${images.path}/equalizer.jpg').writeAsBytesSync([1]);
    File('${images.path}/glass.jpg').writeAsBytesSync([2]);
    File('${images.path}/captions.json')
        .writeAsStringSync(jsonEncode({'glass.jpg': 'Frosted glass on pure black'}));
    final out = '${tmp.path}/out';
    const repo = 'KESPREME/music_streaming_app';

    final run = await Process.run('dart', [
      'run', 'tool/release/prepare.dart', 'notes',
      '--repo', repo, '--name', '1.1.0', '--build', '142', '--tag', 'v1.1.0+142',
      '--apk', apk.path, '--apk-arm64', arm.path, '--out', out, '--images', images.path,
      '--from', 'HEAD~6', '--to', 'HEAD', '--min-sdk', '24',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');

    final manifest = File('$out/update.json').readAsStringSync();
    final universalAsset = (jsonDecode(manifest)['assets'] as List)
        .firstWhere((a) => a['abi'] == 'universal') as Map;
    final sha = universalAsset['sha256'] as String;

    // GitHub's REST answer for that release: the assets CI uploaded, and the body.
    final apkName = 'MineMusic-1.1.0-b142.apk';
    String url(String f) =>
        'https://github.com/$repo/releases/download/v1.1.0%2B142/$f';
    final release = {
      'tag_name': 'v1.1.0+142',
      'name': 'Mine Music 1.1.0',
      'body': File('$out/notes.md').readAsStringSync(),
      'draft': false,
      'prerelease': false,
      'published_at': '2026-10-20T12:00:00Z',
      'html_url': 'https://github.com/$repo/releases/tag/v1.1.0%2B142',
      'assets': [
        for (final f in ['update.json', apkName, '$apkName.sha256'])
          {
            'name': f,
            'browser_download_url': url(f),
            'size': File('$out/$f').lengthSync(),
            'state': 'uploaded',
          },
      ],
    };

    final client = MockClient((req) async {
      if (req.url.path.endsWith('/releases/latest')) {
        return _json(jsonEncode(release), etag: 'W/"x"');
      }
      if (req.url.path.endsWith('/update.json')) {
        return _json(manifest);
      }
      return http.Response('not found', 404);
    });

    final repoClient = UpdateRepository(client: client, repo: repo);
    final result = await repoClient
        .fetchLatest(channel: UpdateChannel.stable, abis: const ['arm64-v8a', 'armeabi-v7a']);

    // A phone that cannot run arm64 gets the universal APK.
    final oldPhone = await repoClient
        .fetchLatest(channel: UpdateChannel.stable, abis: const ['x86']);
    expect((oldPhone as Fetched).release!.asset!.name, apkName);
    expect(oldPhone.release!.asset!.size, 8192);

    expect(result, isA<Fetched>(), reason: result is Failed ? result.message : '$result');
    final r = (result as Fetched).release!;
    expect(r.version, '1.1.0');
    expect(r.build, 142);
    expect(r.tag, 'v1.1.0+142');
    expect(r.prerelease, isFalse);
    expect(r.minSdk, 24);

    // An arm64 phone is offered the small APK, with its own size and checksum.
    final asset = r.asset!;
    expect(asset.abi, 'arm64-v8a');
    expect(asset.name, 'MineMusic-1.1.0-b142-arm64-v8a.apk');
    expect(asset.size, 3000);
    expect(asset.url, url('MineMusic-1.1.0-b142-arm64-v8a.apk'));
    expect(asset.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(asset.sha256, isNot(sha), reason: 'not the universal APK\'s checksum');
    final armSha = File('$out/MineMusic-1.1.0-b142-arm64-v8a.apk.sha256').readAsStringSync();
    expect(armSha.startsWith(asset.sha256), isTrue);

    expect(r.notes.bannerUrl, url('MineMusic-1.1.0-b142-banner.png'));
    expect(r.notes.gallery.length, 2);
    expect(r.notes.gallery.map((g) => g.caption),
        containsAll(['Frosted glass on pure black']));
    expect(r.notes.gallery.every((g) => g.url.startsWith('https://')), isTrue);
    expect(r.releaseUrl, contains('v1.1.0%2B142'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('with no update.json, the app still reads the release body and sibling checksum',
      () async {
    final apk = File('${tmp.path}/app-release.apk')
      ..writeAsBytesSync(List<int>.generate(2048, (i) => i % 200));
    final out = '${tmp.path}/out';
    const repo = 'KESPREME/music_streaming_app';
    final run = await Process.run('dart', [
      'run', 'tool/release/prepare.dart', 'notes',
      '--repo', repo, '--name', '1.2.0', '--build', '150', '--tag', 'v1.2.0+150',
      '--apk', apk.path, '--out', out, '--images', '${tmp.path}/none',
      '--from', 'HEAD~4', '--to', 'HEAD',
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');

    final apkName = 'MineMusic-1.2.0-b150.apk';
    final shaFile = File('$out/$apkName.sha256').readAsStringSync();
    String url(String f) =>
        'https://github.com/$repo/releases/download/v1.2.0%2B150/$f';
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/releases/latest')) {
        return _json(
          jsonEncode({
            'tag_name': 'v1.2.0+150',
            'body': File('$out/notes.md').readAsStringSync(),
            'draft': false,
            'prerelease': false,
            'published_at': '2026-10-21T08:00:00Z',
            'html_url': 'https://github.com/$repo/releases/tag/v1.2.0%2B150',
            'assets': [
              {
                'name': apkName,
                'browser_download_url': url(apkName),
                'size': 2048,
                'state': 'uploaded'
              },
              {
                'name': '$apkName.sha256',
                'browser_download_url': url('$apkName.sha256'),
                'size': shaFile.length,
                'state': 'uploaded'
              },
            ],
          }),
        );
      }
      if (req.url.path.endsWith('.sha256')) return http.Response(shaFile, 200);
      return http.Response('nope', 404);
    });

    final result = await UpdateRepository(client: client, repo: repo)
        .fetchLatest(channel: UpdateChannel.stable, abis: const ['arm64-v8a']);
    final r = (result as Fetched).release!;
    expect(r.version, '1.2.0');
    expect(r.build, 150);
    expect(r.asset!.sha256, shaFile.substring(0, 64));
    expect(r.notes.title ?? r.notes.sections.map((s) => s.title).join(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
