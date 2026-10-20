import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_streaming_app/services/update/update_http.dart';
import 'package:music_streaming_app/services/update/update_models.dart';
import 'package:music_streaming_app/services/update/update_repository.dart';

/// UPDATES: asking GitHub. The repository turns a release into one
/// [ReleaseInfo] for THIS device, prefers `update.json`, falls back to the
/// plain release, and reports every failure as a value.

const _repo = 'KESPREME/music_streaming_app';
const _api = 'https://api.github.com/repos/$_repo/releases';
final _sha = 'a1b2c3d4' * 8;
final _sha2 = '0f1e2d3c' * 8;

String _download(String tag, String file) =>
    'https://github.com/$_repo/releases/download/${Uri.encodeComponent(tag)}/$file';

http.Response _json(Object body, {int status = 200, Map<String, String> headers = const {}}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8', ...headers},
    );

Map<String, dynamic> _asset(
  String tag,
  String name, {
  int size = 62914560,
  String? digest,
  String state = 'uploaded',
  String? url,
}) =>
    {
      'name': name,
      'browser_download_url': url ?? _download(tag, name),
      'size': size,
      'state': state,
      if (digest != null) 'digest': digest,
    };

/// A GitHub REST release with an APK (and whatever [extra] assets).
Map<String, dynamic> _gh({
  String tag = 'v1.1.0+142',
  String apk = 'MineMusic-1.1.0-b142.apk',
  bool prerelease = false,
  bool draft = false,
  String body = '',
  String? name,
  List<Map<String, dynamic>> extra = const [],
  bool withApk = true,
  String? digest,
}) =>
    {
      'tag_name': tag,
      'name': name ?? tag,
      'body': body,
      'published_at': '2026-10-20T12:00:00Z',
      'html_url': 'https://github.com/$_repo/releases/tag/${Uri.encodeComponent(tag)}',
      'prerelease': prerelease,
      'draft': draft,
      'assets': [
        if (withApk) _asset(tag, apk, digest: digest),
        ...extra,
      ],
    };

Map<String, dynamic> _manifestAsset(String name, String abi, {String? sha, String? url}) => {
      'name': name,
      'abi': abi,
      'url': url ?? _download('v1.1.0+142', name),
      'size': 62914560,
      if (sha != null) 'sha256': sha,
    };

Map<String, dynamic> _manifest({
  String version = '1.1.0',
  int build = 142,
  List<Map<String, dynamic>>? assets,
  Map<String, dynamic> extra = const {},
}) =>
    {
      'schema': 1,
      'app': 'mine-music',
      'version': version,
      'build': build,
      'tag': 'v$version+$build',
      'channel': 'stable',
      'publishedAt': '2026-10-20T12:00:00Z',
      'minSdk': 24,
      'title': 'Glass that behaves, and an equalizer',
      'summary': 'optional one line',
      'highlights': ['short bullet', 'short bullet 2'],
      'sections': [
        {'title': 'New', 'icon': 'sparkle', 'items': ['Equalizer', 'Sleep timer']},
        {'title': 'Improved', 'items': ['Search']},
        {'title': 'Fixed', 'items': ['Seek bar']},
      ],
      'notes': '## Details\nFull **markdown** body.',
      'images': {
        'banner': _download('v$version+$build', 'banner.png'),
        'gallery': [
          {'url': _download('v$version+$build', 'screenshot-1.jpg'), 'caption': 'Equalizer'},
        ],
      },
      'assets': assets ?? [_manifestAsset('MineMusic-$version-b$build.apk', 'universal', sha: _sha)],
      'releaseUrl': 'https://github.com/$_repo/releases/tag/v$version%2B$build',
      ...extra,
    };

/// A scripted network: routes by full URL, a request log, and one switch to
/// make everything throw.
class _Net {
  final List<http.Request> log = [];
  final Map<String, http.Response Function(http.Request)> routes = {};
  Object? failWith;
  Duration? stall;

  late final http.Client client = MockClient((req) async {
    log.add(req);
    if (stall != null) await Future<void>.delayed(stall!);
    final err = failWith;
    if (err != null) throw err;
    final handler = routes[req.url.toString()];
    return handler == null ? http.Response('not found', 404) : handler(req);
  });

  void on(String url, http.Response Function(http.Request) handler) => routes[url] = handler;
  void respond(String url, http.Response res) => routes[url] = (_) => res;

  List<String> get urls => [for (final r in log) r.url.toString()];
  String header(int i, String name) => log[i].headers[name] ?? log[i].headers[name.toLowerCase()] ?? '';
}

UpdateRepository _repoFor(_Net net, {DateTime Function()? now, Duration? timeout}) =>
    UpdateRepository(
      client: net.client,
      now: now,
      timeout: timeout ?? const Duration(seconds: 5),
    );

const _arm64 = ['arm64-v8a', 'armeabi-v7a'];

void main() {
  group('fetchLatest - stable, with update.json', () {
    late _Net net;
    late UpdateRepository repo;
    final tag = 'v1.1.0+142';

    setUp(() {
      net = _Net();
      repo = _repoFor(net);
      net.respond(
        '$_api/latest',
        _json(
          _gh(extra: [
            _asset(tag, 'update.json', size: 900),
            _asset(tag, 'banner.png', size: 100),
          ]),
          headers: {'ETag': '"abc123"'},
        ),
      );
      net.respond(_download(tag, 'update.json'), _json(_manifest()));
    });

    test('reads the manifest: version, notes, the right APK and its checksum', () async {
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64);
      final fetched = r as Fetched;
      expect(fetched.etag, '"abc123"');
      final rel = fetched.release!;
      expect(rel.version, '1.1.0');
      expect(rel.build, 142);
      expect(rel.tag, 'v1.1.0+142');
      expect(rel.id, '1.1.0+142');
      expect(rel.channel, UpdateChannel.stable);
      expect(rel.prerelease, isFalse);
      expect(rel.minSdk, 24);
      expect(rel.publishedAt, DateTime.utc(2026, 10, 20, 12));
      expect(rel.releaseUrl, 'https://github.com/$_repo/releases/tag/v1.1.0%2B142');
      expect(rel.notes.title, 'Glass that behaves, and an equalizer');
      expect(rel.notes.summary, 'optional one line');
      expect(rel.notes.sections.map((s) => s.title), ['New', 'Improved', 'Fixed']);
      expect(rel.notes.bannerUrl, _download(tag, 'banner.png'));
      expect(rel.notes.gallery.single.caption, 'Equalizer');
      expect(rel.asset!.name, 'MineMusic-1.1.0-b142.apk');
      expect(rel.asset!.abi, 'universal');
      expect(rel.asset!.sha256, _sha);
      expect(rel.asset!.size, 62914560);
    });

    test('sends the GitHub headers, no If-None-Match on the first call, and fetches the manifest once', () async {
      await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64);
      expect(net.urls, ['$_api/latest', _download(tag, 'update.json')]);
      expect(net.header(0, 'Accept'), 'application/vnd.github+json');
      expect(net.header(0, 'X-GitHub-Api-Version'), '2022-11-28');
      expect(net.header(0, 'User-Agent'), 'MineMusic-Updater');
      expect(net.log.first.headers.keys.map((k) => k.toLowerCase()), isNot(contains('if-none-match')));
    });

    test('the result round-trips through the cache JSON', () async {
      final fetched = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      final rel = fetched.release!;
      expect(ReleaseInfo.fromJson(jsonDecode(jsonEncode(rel.toJson())) as Map<String, dynamic>), rel);
    });

    test('a manifest with an unknown schema and unknown fields still parses', () async {
      net.respond(
        _download(tag, 'update.json'),
        _json(_manifest(extra: {
          'schema': 7,
          'futureField': {'a': [1, 2, 3]},
          'sections': [
            {'title': 'New', 'items': ['x'], 'weird': true},
          ],
        })),
      );
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release!.version, '1.1.0');
      expect(r.release!.notes.sections.single.items, ['x']);
    });

    test('a manifest that omits everything optional still gives a usable release', () async {
      net.respond(
        _download(tag, 'update.json'),
        _json({
          'schema': 1,
          'version': '1.1.0',
          'build': 142,
          'assets': [_manifestAsset('MineMusic-1.1.0-b142.apk', 'universal')],
        }),
      );
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      final rel = r.release!;
      expect(rel.notes.isEmpty, isTrue);
      expect(rel.minSdk, isNull);
      expect(rel.tag, 'v1.1.0+142'); // from the release
      expect(rel.publishedAt, DateTime.utc(2026, 10, 20, 12)); // from the release
      expect(rel.releaseUrl, startsWith('https://github.com/'));
    });

    test('a manifest asset with no checksum takes it from the GitHub digest', () async {
      net.respond(
        '$_api/latest',
        _json(_gh(extra: [_asset(tag, 'update.json')], digest: 'sha256:${_sha2.toUpperCase()}')),
      );
      net.respond(
        _download(tag, 'update.json'),
        _json(_manifest(assets: [_manifestAsset('MineMusic-1.1.0-b142.apk', 'universal')])),
      );
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release!.asset!.sha256, _sha2);
    });

    test('a manifest asset with no checksum falls back to the .sha256 sibling', () async {
      final apk = 'MineMusic-1.1.0-b142.apk';
      net.respond(
        '$_api/latest',
        _json(_gh(extra: [_asset(tag, 'update.json'), _asset(tag, '$apk.sha256', size: 90)])),
      );
      net.respond(
        _download(tag, 'update.json'),
        _json(_manifest(assets: [_manifestAsset(apk, 'universal')])),
      );
      net.respond(_download(tag, '$apk.sha256'), http.Response('$_sha2  $apk\n', 200));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release!.asset!.sha256, _sha2);
    });

    // A manifest that cannot be used must never lose us the release.
    final unusable = <String, http.Response>{
      'HTTP 500': http.Response('boom', 500),
      'HTTP 404': http.Response('gone', 404),
      'not JSON': http.Response('<html>', 200),
      'JSON but not an object': _json([1, 2, 3]),
      'another app': _json(_manifest(extra: {'app': 'some-other-app'})),
      'no readable version': _json({'schema': 1, 'build': 142, 'version': 'junk', 'assets': <Object>[]}),
    };
    for (final e in unusable.entries) {
      test('falls back to the release body when update.json is unusable: ${e.key}', () async {
        net.respond(
          '$_api/latest',
          _json(_gh(
            body: '# From body\n\n## New\n- from the body',
            extra: [_asset(tag, 'update.json')],
          )),
        );
        net.respond(_download(tag, 'update.json'), e.value);
        final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
        expect(r.release!.notes.title, 'From body');
        expect(r.release!.version, '1.1.0');
        expect(r.release!.asset!.name, 'MineMusic-1.1.0-b142.apk');
      });
    }

    test('a manifest with no installable APK borrows the one from the release', () async {
      net.respond(
        _download(tag, 'update.json'),
        _json(_manifest(assets: [])),
      );
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release!.notes.title, 'Glass that behaves, and an equalizer'); // manifest notes
      expect(r.release!.asset!.name, 'MineMusic-1.1.0-b142.apk'); // release APK
    });
  });

  group('fetchLatest - stable, plain GitHub release', () {
    late _Net net;
    late UpdateRepository repo;
    const tag = 'v1.1.0+142';
    const apk = 'MineMusic-1.1.0-b142.apk';

    const body = '''
![banner](https://github.com/x/y/releases/download/v1/banner.png)

# Glass that behaves

A calmer player.

## \u2728 New
- Equalizer
- Sleep timer

### \u{1F41B} Fixed
- Seek bar
''';

    setUp(() {
      net = _Net();
      repo = _repoFor(net);
    });

    test('parses version, build, notes and the checksum from the .sha256 sibling', () async {
      net.respond(
        '$_api/latest',
        _json(_gh(body: body, extra: [_asset(tag, '$apk.sha256', size: 90)]), headers: {'etag': 'W/"w1"'}),
      );
      net.respond(_download(tag, '$apk.sha256'), http.Response('${_sha.toUpperCase()}  $apk\n', 200));

      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.etag, 'W/"w1"');
      final rel = r.release!;
      expect(rel.version, '1.1.0');
      expect(rel.build, 142);
      expect(rel.asset!.name, apk);
      expect(rel.asset!.sha256, _sha); // lower-cased
      expect(rel.asset!.abi, 'universal');
      expect(rel.notes.title, 'Glass that behaves');
      expect(rel.notes.summary, 'A calmer player.');
      expect(rel.notes.sections.map((s) => s.title), ['New', 'Fixed']);
      expect(rel.notes.bannerUrl, 'https://github.com/x/y/releases/download/v1/banner.png');
      expect(rel.releaseUrl, 'https://github.com/$_repo/releases/tag/v1.1.0%2B142');
      expect(net.urls, ['$_api/latest', _download(tag, '$apk.sha256')]);
    });

    test('uses the GitHub digest and makes no extra request', () async {
      net.respond('$_api/latest', _json(_gh(digest: 'sha256:$_sha')));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release!.asset!.sha256, _sha);
      expect(net.log, hasLength(1));
    });

    test('a missing or unreadable checksum leaves it empty rather than failing', () async {
      net.respond('$_api/latest', _json(_gh(extra: [_asset(tag, '$apk.sha256')])));
      net.respond(_download(tag, '$apk.sha256'), http.Response('not a hash', 200));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release!.asset!.sha256, '');
      expect(r.release!.asset!.hasChecksum, isFalse);
    });

    test('a checksum download that errors leaves it empty', () async {
      net.respond('$_api/latest', _json(_gh(extra: [_asset(tag, '$apk.sha256')])));
      net.on(_download(tag, '$apk.sha256'), (_) => throw const SocketException('x'));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release!.asset!.sha256, '');
    });

    test('no release has ever been published (404 on /latest) is not an error', () async {
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64);
      expect(r, isA<Fetched>());
      expect((r as Fetched).release, isNull);
      expect(r.etag, isNull);
    });

    test('a release with no APK has nothing to offer, but keeps its ETag', () async {
      net.respond('$_api/latest', _json(_gh(withApk: false, extra: [_asset(tag, 'banner.png')]), headers: {'etag': '"e"'}));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release, isNull);
      expect(r.etag, '"e"');
    });

    test('an APK that is still uploading is ignored', () async {
      net.respond('$_api/latest', _json(_gh(withApk: false, extra: [_asset(tag, apk, state: 'starter')])));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release, isNull);
    });

    test('a draft or non-object body yields nothing', () async {
      net.respond('$_api/latest', _json(_gh(draft: true)));
      expect(((await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64)) as Fetched).release, isNull);
      net.respond('$_api/latest', _json(<Object>[]));
      expect(((await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64)) as Fetched).release, isNull);
      net.respond('$_api/latest', _json('a string'));
      expect(((await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64)) as Fetched).release, isNull);
    });

    test('a tag that is not a version yields nothing', () async {
      net.respond('$_api/latest', _json(_gh(tag: 'nightly')));
      expect(((await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64)) as Fetched).release, isNull);
    });

    test('a UTF-8 body is decoded as UTF-8 even when the response names no charset', () async {
      final payload = _gh(body: '## \u2728 Caf\u00E9 \u{1F680}\n- cr\u00E8me br\u00FBl\u00E9e');
      net.respond('$_api/latest', http.Response.bytes(utf8.encode(jsonEncode(payload)), 200));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release!.notes.sections.single.title, 'Caf\u00E9');
      expect(r.release!.notes.sections.single.items.single, 'cr\u00E8me br\u00FBl\u00E9e');
    });

    test('the release name is the title only when it says more than the version', () async {
      const table = {
        'Glass that behaves': 'Glass that behaves',
        'v1.1.0': null,
        'Mine Music 1.1.0': null,
        'Release v1.1.0+142': null,
        tag: null,
      };
      for (final e in table.entries) {
        net.respond('$_api/latest', _json(_gh(name: e.key)));
        final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
        expect(r.release!.notes.title, e.value, reason: e.key);
      }
    });
  });

  group('conditional requests and failures', () {
    late _Net net;
    late UpdateRepository repo;

    setUp(() {
      net = _Net();
      repo = _repoFor(net, now: () => DateTime.utc(2026, 1, 1, 12));
    });

    test('304 means NotModified, and the ETag is sent as If-None-Match', () async {
      net.on('$_api/latest', (req) {
        return req.headers['If-None-Match'] == '"abc123"' || req.headers['if-none-match'] == '"abc123"'
            ? http.Response('', 304)
            : _json(_gh());
      });
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64, etag: '"abc123"');
      expect(r, isA<NotModified>());
      expect(net.log, hasLength(1));
    });

    test('an empty ETag is not sent', () async {
      net.respond('$_api/latest', _json(_gh()));
      await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64, etag: '');
      expect(net.log.first.headers.keys.map((k) => k.toLowerCase()), isNot(contains('if-none-match')));
    });

    test('403 with no requests left is RateLimited until the reset time', () async {
      final reset = DateTime.utc(2026, 1, 1, 13).millisecondsSinceEpoch ~/ 1000;
      net.respond(
        '$_api/latest',
        http.Response('rate limited', 403, headers: {
          'X-RateLimit-Remaining': '0',
          'X-RateLimit-Reset': '$reset',
        }),
      );
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64);
      expect(r, isA<RateLimited>());
      expect((r as RateLimited).retryAt, DateTime.utc(2026, 1, 1, 13));
    });

    test('429 with Retry-After waits that long from now', () async {
      net.respond('$_api/latest', http.Response('slow down', 429, headers: {'retry-after': '120'}));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as RateLimited;
      expect(r.retryAt, DateTime.utc(2026, 1, 1, 12, 2));
    });

    test('429 with no hints is still RateLimited, with no time', () async {
      net.respond('$_api/latest', http.Response('slow down', 429));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as RateLimited;
      expect(r.retryAt, isNull);
    });

    test('a plain 403 (not rate limiting) is a failure', () async {
      net.respond('$_api/latest', http.Response('forbidden', 403, headers: {'x-ratelimit-remaining': '42'}));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64);
      expect(r, isA<Failed>());
    });

    final serverErrors = [500, 502, 503, 401, 410];
    for (final code in serverErrors) {
      test('HTTP $code is a Failed with a sentence', () async {
        net.respond('$_api/latest', http.Response('x', code));
        final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Failed;
        expect(r.message, kUnreachableMessage);
        expect(r.offline, isFalse);
      });
    }

    final offline = <String, Object>{
      'SocketException': const SocketException('Network is unreachable'),
      'ClientException wrapping a SocketException':
          http.ClientException('SocketException: Failed host lookup: api.github.com'),
      'ClientException "no address"': http.ClientException('No address associated with hostname'),
    };
    for (final e in offline.entries) {
      test('${e.key} means offline', () async {
        net.failWith = e.value;
        final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Failed;
        expect(r.offline, isTrue);
        expect(r.message, 'You appear to be offline.');
      });
    }

    final notOffline = <String, Object>{
      'TimeoutException': TimeoutException('slow'),
      'HandshakeException': const HandshakeException('bad cert'),
      'a ClientException about something else': http.ClientException('Connection closed before full header was received'),
      'a StateError': StateError('bug'),
    };
    for (final e in notOffline.entries) {
      test('${e.key} is a failure but not "offline"', () async {
        net.failWith = e.value;
        final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Failed;
        expect(r.offline, isFalse);
        expect(r.message, 'GitHub could not be reached. Try again in a moment.');
      });
    }

    test('a hung connection times out into a Failed', () async {
      net.stall = const Duration(milliseconds: 400);
      final slow = _repoFor(net, timeout: const Duration(milliseconds: 60));
      final r = await slow.fetchLatest(channel: UpdateChannel.stable, abis: _arm64);
      expect(r, isA<Failed>());
    });

    test('a 200 whose body is not JSON is a Failed, never a throw', () async {
      net.respond('$_api/latest', http.Response('<html>captive portal</html>', 200));
      expect(await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64), isA<Failed>());
    });

    test('a half-sent JSON body is a Failed', () async {
      net.respond('$_api/latest', http.Response('{"tag_name": "v1', 200));
      expect(await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64), isA<Failed>());
    });
  });

  group('fetchLatest - beta channel', () {
    late _Net net;
    late UpdateRepository repo;

    setUp(() {
      net = _Net();
      repo = _repoFor(net);
    });

    test('asks for the list and takes the first non-draft, prerelease included', () async {
      net.respond(
        '$_api?per_page=10',
        _json([
          _gh(tag: 'v1.3.0+160', apk: 'MineMusic-1.3.0-b160.apk', draft: true),
          _gh(tag: 'v1.2.0-beta.1+150', apk: 'MineMusic-1.2.0-beta.1-b150.apk', prerelease: true),
          _gh(),
        ]),
      );
      final r = await repo.fetchLatest(channel: UpdateChannel.beta, abis: _arm64) as Fetched;
      expect(net.log.single.url.queryParameters, {'per_page': '10'});
      final rel = r.release!;
      expect(rel.version, '1.2.0-beta.1');
      expect(rel.build, 150);
      expect(rel.channel, UpdateChannel.beta);
      expect(rel.prerelease, isTrue);
      expect(rel.asset!.name, 'MineMusic-1.2.0-beta.1-b150.apk');
    });

    test('when the newest release is a stable one, that is the beta answer too', () async {
      net.respond('$_api?per_page=10', _json([_gh(), _gh(tag: 'v1.0.0+100', apk: 'MineMusic-1.0.0-b100.apk')]));
      final r = await repo.fetchLatest(channel: UpdateChannel.beta, abis: _arm64) as Fetched;
      expect(r.release!.build, 142);
      expect(r.release!.channel, UpdateChannel.stable);
    });

    test('an empty list and a list of only drafts have nothing to offer', () async {
      net.respond('$_api?per_page=10', _json(<Object>[]));
      expect(((await repo.fetchLatest(channel: UpdateChannel.beta, abis: _arm64)) as Fetched).release, isNull);
      net.respond('$_api?per_page=10', _json([_gh(draft: true), _gh(draft: true)]));
      expect(((await repo.fetchLatest(channel: UpdateChannel.beta, abis: _arm64)) as Fetched).release, isNull);
    });

    test('a 404 on the list is a failure (the repo itself is missing), not "no releases"', () async {
      final r = await repo.fetchLatest(channel: UpdateChannel.beta, abis: _arm64);
      expect(r, isA<Failed>());
    });

    test('stable never picks up a prerelease, even if the endpoint returned a list', () async {
      net.respond('$_api/latest', _json([_gh(tag: 'v2.0.0-beta.1+300', prerelease: true, apk: 'MineMusic-2.0.0-beta.1-b300.apk'), _gh()]));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release!.build, 142);
    });
  });

  group('ABI selection', () {
    late _Net net;
    late UpdateRepository repo;
    const tag = 'v1.1.0+142';

    ReleaseAsset? chosen(Object? result) => ((result as Fetched).release)?.asset;

    setUp(() {
      net = _Net();
      repo = _repoFor(net);
      net.respond('$_api/latest', _json(_gh(extra: [_asset(tag, 'update.json')], withApk: false)));
    });

    void manifestAssets(List<Map<String, dynamic>> assets) =>
        net.respond(_download(tag, 'update.json'), _json(_manifest(assets: assets)));

    final all = [
      _manifestAsset('universal.apk', 'universal'),
      _manifestAsset('arm64.apk', 'arm64-v8a'),
      _manifestAsset('armv7.apk', 'armeabi-v7a'),
      _manifestAsset('x64.apk', 'x86_64'),
    ];

    // device ABIs (best first) -> chosen file
    final table = <(List<String>, String)>[
      (['arm64-v8a', 'armeabi-v7a', 'armeabi'], 'arm64.apk'),
      (['armeabi-v7a', 'arm64-v8a'], 'armv7.apk'), // the device's own order wins
      (['x86_64', 'x86'], 'x64.apk'),
      (['x86'], 'universal.apk'), // no x86 build: fall back to universal
      (<String>[], 'universal.apk'),
      (['arm64'], 'arm64.apk'), // alias spelling
      (['riscv64', 'arm64-v8a'], 'arm64.apk'), // skips an ABI nothing was built for
    ];
    for (final (abis, file) in table) {
      test('$abis -> $file', () async {
        manifestAssets(all);
        final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: abis);
        expect(chosen(r)!.name, file);
      });
    }

    test('without a universal build, an unmatched device gets nothing', () async {
      manifestAssets([_manifestAsset('arm64.apk', 'arm64-v8a')]);
      expect(chosen(await repo.fetchLatest(channel: UpdateChannel.stable, abis: ['x86_64'])), isNull);
      expect(chosen(await repo.fetchLatest(channel: UpdateChannel.stable, abis: ['arm64-v8a']))!.name, 'arm64.apk');
    });

    test('an asset with no abi field takes it from its file name', () async {
      manifestAssets([
        {'name': 'MineMusic-1.1.0-arm64-v8a-b142.apk', 'url': _download(tag, 'a.apk')},
        {'name': 'MineMusic-1.1.0-b142.apk', 'url': _download(tag, 'u.apk')},
      ]);
      expect(chosen(await repo.fetchLatest(channel: UpdateChannel.stable, abis: ['arm64-v8a']))!.abi, 'arm64-v8a');
      expect(chosen(await repo.fetchLatest(channel: UpdateChannel.stable, abis: ['x86']))!.abi, 'universal');
    });

    test('plain-release APKs are matched by name too', () async {
      net.respond(
        '$_api/latest',
        _json(_gh(withApk: false, extra: [
          _asset(tag, 'MineMusic-1.1.0-b142-universal.apk'),
          _asset(tag, 'MineMusic-1.1.0-arm64-v8a-b142.apk'),
        ])),
      );
      expect(chosen(await repo.fetchLatest(channel: UpdateChannel.stable, abis: ['arm64-v8a']))!.name,
          'MineMusic-1.1.0-arm64-v8a-b142.apk');
      expect(chosen(await repo.fetchLatest(channel: UpdateChannel.stable, abis: ['x86']))!.name,
          'MineMusic-1.1.0-b142-universal.apk');
    });

    test('only .apk files are ever chosen', () async {
      manifestAssets([
        _manifestAsset('MineMusic.zip', 'universal'),
        _manifestAsset('MineMusic.apk.sha256', 'universal'),
      ]);
      expect(chosen(await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64)), isNull);
    });
  });

  group('https only', () {
    late _Net net;
    late UpdateRepository repo;
    const tag = 'v1.1.0+142';

    setUp(() {
      net = _Net();
      repo = _repoFor(net);
    });

    test('a manifest APK served over http is rejected; an https sibling is still chosen', () async {
      net.respond('$_api/latest', _json(_gh(withApk: false, extra: [_asset(tag, 'update.json')])));
      net.respond(
        _download(tag, 'update.json'),
        _json(_manifest(assets: [
          _manifestAsset('insecure.apk', 'universal', url: 'http://evil.example/insecure.apk'),
          _manifestAsset('arm64.apk', 'arm64-v8a'),
        ])),
      );
      final none = await repo.fetchLatest(channel: UpdateChannel.stable, abis: ['x86']) as Fetched;
      expect(none.release, isNull);
      final arm = await repo.fetchLatest(channel: UpdateChannel.stable, abis: ['arm64-v8a']) as Fetched;
      expect(arm.release!.asset!.name, 'arm64.apk');
    });

    test('other schemes are rejected too', () async {
      net.respond('$_api/latest', _json(_gh(withApk: false, extra: [_asset(tag, 'update.json')])));
      for (final bad in ['ftp://x/a.apk', 'file:///sdcard/a.apk', 'javascript:alert(1)', '//x/a.apk', 'a.apk', '']) {
        net.respond(
          _download(tag, 'update.json'),
          _json(_manifest(assets: [_manifestAsset('a.apk', 'universal', url: bad)])),
        );
        final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
        expect(r.release, isNull, reason: bad);
      }
    });

    test('a plain-release APK served over http is rejected', () async {
      net.respond(
        '$_api/latest',
        _json(_gh(withApk: false, extra: [_asset(tag, 'a.apk', url: 'http://github.com/a.apk')])),
      );
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release, isNull);
    });

    test('an update.json served over http is never fetched', () async {
      net.respond(
        '$_api/latest',
        _json(_gh(extra: [_asset(tag, 'update.json', url: 'http://evil.example/update.json')], body: '# Body title')),
      );
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(net.urls, ['$_api/latest']);
      expect(r.release!.notes.title, 'Body title');
    });

    test('images over http never reach the notes', () async {
      net.respond('$_api/latest', _json(_gh(body: '![a](http://e.com/a.png)\n![b](https://e.com/b.png)\n- x')));
      final r = await repo.fetchLatest(channel: UpdateChannel.stable, abis: _arm64) as Fetched;
      expect(r.release!.notes.bannerUrl, 'https://e.com/b.png');
      expect(r.release!.notes.gallery, isEmpty);
    });
  });

  group('fetchByTag', () {
    late _Net net;
    late UpdateRepository repo;

    setUp(() {
      net = _Net();
      repo = _repoFor(net);
    });

    test('tries the usual spellings in order, percent-encoding the +', () async {
      net.respond(
        '$_api/tags/1.1.0%2B142',
        _json(_gh(tag: '1.1.0+142', withApk: false, body: '# Old notes\n\n## Fixed\n- a')),
      );
      final r = await repo.fetchByTag('v1.1.0+142', _arm64);
      expect(net.urls, ['$_api/tags/v1.1.0%2B142', '$_api/tags/1.1.0%2B142']);
      expect(r, isNotNull);
      expect(r!.notes.title, 'Old notes');
      expect(r.asset, isNull); // notes-only: no APK is fine here
      expect(r.version, '1.1.0');
      expect(r.build, 142);
    });

    test('returns the APK when the release has one', () async {
      net.respond('$_api/tags/v1.1.0%2B142', _json(_gh()));
      final r = await repo.fetchByTag('v1.1.0+142', _arm64);
      expect(r!.asset!.name, 'MineMusic-1.1.0-b142.apk');
      expect(net.log, hasLength(1));
    });

    test('prefers update.json here too', () async {
      net.respond('$_api/tags/v1.1.0%2B142', _json(_gh(extra: [_asset('v1.1.0+142', 'update.json')])));
      net.respond(_download('v1.1.0+142', 'update.json'), _json(_manifest()));
      final r = await repo.fetchByTag('v1.1.0+142', _arm64);
      expect(r!.notes.title, 'Glass that behaves, and an equalizer');
    });

    test('null when no spelling exists, after trying every one', () async {
      expect(await repo.fetchByTag('v1.1.0+142', _arm64), isNull);
      expect(net.log.length, tagVariants('v1.1.0+142').length);
    });

    test('network errors and server errors give null without throwing, and stop early', () async {
      net.failWith = const SocketException('down');
      expect(await repo.fetchByTag('v1.1.0+142', _arm64), isNull);
      expect(net.log, hasLength(1));

      final net2 = _Net()..respond('$_api/tags/v1.1.0%2B142', http.Response('boom', 500));
      expect(await _repoFor(net2).fetchByTag('v1.1.0+142', _arm64), isNull);
      expect(net2.log, hasLength(1));
    });

    test('garbage input does not throw', () async {
      for (final t in ['', '   ', 'not a version', '\u0000', 'a/b/../c', 'x' * 500]) {
        await expectLater(repo.fetchByTag(t, _arm64), completion(isNull), reason: t);
      }
    });
  });

  group('pure helpers', () {
    test('tagVariants', () {
      expect(tagVariants('v1.1.0+142'), [
        'v1.1.0+142',
        '1.1.0+142',
        'v1.1.0-b142',
        '1.1.0-b142',
        'v1.1.0',
        '1.1.0',
      ]);
      expect(tagVariants('1.1.0'), ['1.1.0', 'v1.1.0']);
      expect(tagVariants('v1.2.0-beta.1+150').first, 'v1.2.0-beta.1+150');
      expect(tagVariants('v1.2.0-beta.1+150'), contains('1.2.0-beta.1+150'));
      expect(tagVariants('garbage'), ['garbage']);
      expect(tagVariants(''), isEmpty);
      expect(tagVariants('v1.1.0+142').toSet().length, tagVariants('v1.1.0+142').length);
    });

    test('normalizeAbi and inferAbi', () {
      const norm = {
        'arm64-v8a': 'arm64-v8a',
        'ARM64': 'arm64-v8a',
        'aarch64': 'arm64-v8a',
        'armeabi-v7a': 'armeabi-v7a',
        'armv7': 'armeabi-v7a',
        'arm': 'armeabi-v7a',
        'x86_64': 'x86_64',
        'x64': 'x86_64',
        'x86': 'x86',
        'i686': 'x86',
        'universal': 'universal',
        'fat': 'universal',
        'mips': 'mips',
      };
      norm.forEach((raw, want) => expect(normalizeAbi(raw), want, reason: raw));

      const names = {
        'MineMusic-1.1.0-b142.apk': 'universal',
        'MineMusic-1.1.0-universal-b142.apk': 'universal',
        'MineMusic-1.1.0-arm64-v8a-b142.apk': 'arm64-v8a',
        'app-armeabi-v7a-release.apk': 'armeabi-v7a',
        'app-x86_64-release.apk': 'x86_64',
        'app-x86-release.apk': 'x86',
        'x86.apk': 'x86',
      };
      names.forEach((name, want) => expect(inferAbi(name), want, reason: name));
    });

    // tag, apk name, expected version, expected build, expected channel
    final tags = <(String, String, String?, int, UpdateChannel)>[
      ('v1.1.0+142', 'MineMusic-1.1.0-b142.apk', '1.1.0', 142, UpdateChannel.stable),
      ('1.1.0', 'MineMusic-1.1.0-b142.apk', '1.1.0', 142, UpdateChannel.stable), // build from the file name
      ('v1.2.0-beta.1+150', 'MineMusic-1.2.0-beta.1-b150.apk', '1.2.0-beta.1', 150, UpdateChannel.beta),
      ('v1.1.0-b142', 'MineMusic-1.1.0-b142.apk', '1.1.0', 142, UpdateChannel.stable),
      ('v1.1.0', 'MineMusic.apk', '1.1.0', 0, UpdateChannel.stable),
      ('v2', 'MineMusic-2-b9.apk', '2.0.0', 9, UpdateChannel.stable),
      ('nightly', 'MineMusic.apk', null, 0, UpdateChannel.stable),
    ];
    for (final (tag, apk, version, build, channel) in tags) {
      test('releaseFromGithub tag "$tag"', () {
        final rel = releaseFromGithub(_gh(tag: tag, apk: apk), abis: _arm64);
        if (version == null) {
          expect(rel, isNull);
          return;
        }
        expect(rel!.version, version);
        expect(rel.build, build);
        expect(rel.channel, channel);
        expect(rel.tag, tag);
      });
    }

    test('releaseFromGithub: an empty or junk object is null, never a throw', () {
      for (final j in <Map<String, dynamic>>[
        {},
        {'tag_name': 5},
        {'tag_name': '', 'assets': 'x'},
        {'tag_name': 'v1.0.0', 'assets': [null, 1, 'x', {}]},
      ]) {
        expect(() => releaseFromGithub(j, abis: _arm64), returnsNormally, reason: '$j');
      }
      expect(releaseFromGithub({}, abis: _arm64), isNull);
    });

    test('pickAsset only considers https APKs', () {
      const a = ReleaseAsset(name: 'a.apk', url: 'https://e.com/a.apk');
      const http1 = ReleaseAsset(name: 'b.apk', url: 'http://e.com/b.apk');
      const zip = ReleaseAsset(name: 'c.zip', url: 'https://e.com/c.zip');
      expect(pickAsset([http1, zip, a], const []), a);
      expect(pickAsset([http1, zip], const []), isNull);
      expect(pickAsset(const [], ['arm64-v8a']), isNull);
    });

    test('close() leaves a client it was given open', () async {
      final spy = _CloseSpy();
      UpdateRepository(client: spy).close();
      expect(spy.closed, isFalse);
      expect(() => UpdateRepository().close(), returnsNormally);
    });
  });
}

class _CloseSpy extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}
