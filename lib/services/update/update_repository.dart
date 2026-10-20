// lib/services/update/update_repository.dart
//
// Asks GitHub what the newest release is, and turns the answer into one
// [ReleaseInfo] for THIS device.
//
// Source of truth, in order:
//   1. `update.json` attached to the release (CI writes it; it already carries
//      title, sections, images and per-ABI APKs with checksums).
//   2. The plain GitHub release (`tag_name`, markdown `body`, `assets[]`),
//      for releases cut by hand or by an older workflow.
//
// Failure is a value, never an exception. [fetchLatest] returns a sealed
// [FetchResult]: a release (or "no releases"), "unchanged" (HTTP 304), "slow
// down until T" (rate limited), or a sentence for a person. A broken network,
// a malformed manifest, a 500 - none of them can escape into the app.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'release_notes.dart';
import 'update_http.dart';
import 'update_json.dart';
import 'update_models.dart';
import 'version_compare.dart';

/// Where releases live unless a test says otherwise.
const String kDefaultUpdateRepo = 'KESPREME/music_streaming_app';

const String _apiHost = 'api.github.com';

/// The name CI gives the manifest asset.
const String kManifestAssetName = 'update.json';

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

/// What [UpdateRepository.fetchLatest] found out.
sealed class FetchResult {
  const FetchResult();
}

/// A fresh answer. [release] is null when there is nothing installable to
/// offer (no releases yet, or the newest one has no APK for this device).
final class Fetched extends FetchResult {
  const Fetched(this.release, this.etag);
  final ReleaseInfo? release;

  /// Send back as `If-None-Match` next time.
  final String? etag;
}

/// HTTP 304: what we cached is still the newest.
final class NotModified extends FetchResult {
  const NotModified();
}

/// GitHub asked us to stop. [retryAt] is when it will talk to us again, if it
/// said.
final class RateLimited extends FetchResult {
  const RateLimited(this.retryAt);
  final DateTime? retryAt;
}

/// Nothing usable came back. [message] is a sentence for a person;
/// [offline] says it was the device's connection rather than GitHub.
final class Failed extends FetchResult {
  const Failed(this.message, {this.offline = false});
  final String message;
  final bool offline;
}

// ---------------------------------------------------------------------------
// ABI helpers (pure)
// ---------------------------------------------------------------------------

/// Canonical ABI name: `arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`, `universal`.
String normalizeAbi(String raw) {
  final s = raw.trim().toLowerCase();
  return switch (s) {
    'arm64-v8a' || 'arm64' || 'aarch64' => 'arm64-v8a',
    'armeabi-v7a' || 'armv7' || 'armv7a' || 'armeabi' || 'arm' => 'armeabi-v7a',
    'x86_64' || 'x64' || 'amd64' => 'x86_64',
    'x86' || 'i686' || 'i386' => 'x86',
    'universal' || 'all' || 'fat' => 'universal',
    _ => s,
  };
}

final RegExp _x86Token = RegExp(r'(?:^|[-_.])x86(?:[-_.]|$)');

/// The ABI an APK file name advertises; an unlabelled name is `universal`.
String inferAbi(String assetName) {
  final n = assetName.toLowerCase();
  if (n.contains('arm64')) return 'arm64-v8a';
  if (n.contains('armeabi-v7a') || n.contains('armv7')) return 'armeabi-v7a';
  if (n.contains('x86_64') || n.contains('x86-64')) return 'x86_64';
  if (_x86Token.hasMatch(n)) return 'x86';
  return 'universal';
}

bool _isApk(ReleaseAsset a) => a.name.toLowerCase().endsWith('.apk');

/// The APK for a device whose ABIs, best first, are [abis]: the asset built
/// for the first ABI that has one, else the `universal` build, else null.
/// Non-https and non-APK assets are never chosen.
ReleaseAsset? pickAsset(Iterable<ReleaseAsset> assets, List<String> abis) {
  final apks = [
    for (final a in assets)
      if (_isApk(a) && asHttpsUrl(a.url) != null) a,
  ];
  if (apks.isEmpty) return null;
  for (final abi in abis) {
    final want = normalizeAbi(abi);
    for (final a in apks) {
      if (normalizeAbi(a.abi) == want) return a;
    }
  }
  for (final a in apks) {
    if (normalizeAbi(a.abi) == 'universal') return a;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Parsing (pure)
// ---------------------------------------------------------------------------

/// Tags worth trying for a version, most likely first, no duplicates.
List<String> tagVariants(String tag) {
  final t = tag.trim();
  final out = <String>{if (t.isNotEmpty) t};
  final v = AppVersion.parse(t);
  if (!v.isZero) {
    final name = v.name;
    final b = v.build;
    if (b > 0) {
      out
        ..add('v$name+$b')
        ..add('$name+$b')
        ..add('v$name-b$b')
        ..add('$name-b$b');
    }
    out
      ..add('v$name')
      ..add(name);
  }
  return out.toList();
}

Iterable<Map<String, dynamic>> _restAssets(Map<String, dynamic>? release) sync* {
  for (final raw in asList(release?['assets'])) {
    final m = asMap(raw);
    if (m == null) continue;
    final state = asTrimmed(m['state']);
    if (state != null && state != 'uploaded') continue; // still uploading
    yield m;
  }
}

ReleaseAsset? _restAsset(Map<String, dynamic> m) {
  final url = asHttpsUrl(m['browser_download_url']);
  final name = asTrimmed(m['name']);
  if (url == null || name == null) return null;
  return ReleaseAsset(
    name: name,
    url: url,
    abi: inferAbi(name),
    size: (asInt(m['size']) ?? 0).clamp(0, 1 << 40),
    sha256: normalizeSha256(m['digest']) ?? '',
  );
}

/// The `.sha256` sibling of [apkName] in a GitHub release, if it was uploaded.
String? siblingShaUrl(Map<String, dynamic>? release, String apkName) {
  final want = '$apkName.sha256'.toLowerCase();
  for (final m in _restAssets(release)) {
    if ((asTrimmed(m['name']) ?? '').toLowerCase() == want) {
      return asHttpsUrl(m['browser_download_url']);
    }
  }
  return null;
}

final RegExp _assetBuild = RegExp(r'-b(\d+)\.apk$', caseSensitive: false);

/// The `digest` GitHub computed for the asset called [name], if any.
String? _digestFor(Map<String, dynamic>? release, String name) {
  for (final r in _restAssets(release)) {
    if (asTrimmed(r['name']) == name) return normalizeSha256(r['digest']);
  }
  return null;
}

/// A release from its `update.json`. Null when the manifest is not ours
/// (`app` names something else) or has no readable version.
///
/// [release] (the GitHub REST object) only fills what the manifest left out:
/// prerelease flag, publish date, page URL, a checksum via `digest`, and notes
/// when the manifest carries none.
ReleaseInfo? releaseFromManifest(
  Map<String, dynamic> m, {
  required List<String> abis,
  Map<String, dynamic>? release,
}) {
  final app = asTrimmed(m['app']);
  if (app != null && app != 'mine-music') return null;

  final tagText = asTrimmed(m['tag']) ?? asTrimmed(release?['tag_name']);
  final versionText = asTrimmed(m['version']) ?? tagText;
  if (versionText == null) return null;
  final v = AppVersion.parse(versionText);
  if (v.isZero) return null;

  var build = asInt(m['build']) ?? v.build;
  if (build <= 0 && tagText != null) build = AppVersion.parse(tagText).build;
  if (build < 0) build = 0;

  final assets = <ReleaseAsset>[];
  for (final raw in asList(m['assets'])) {
    final a = ReleaseAsset.tryParse(raw);
    if (a == null) continue;
    final given = asTrimmed(asMap(raw)?['abi']);
    assets.add(given == null
        ? ReleaseAsset(
            name: a.name,
            url: a.url,
            abi: inferAbi(a.name),
            size: a.size,
            sha256: a.sha256,
          )
        : a);
  }
  var asset = pickAsset(assets, abis);
  if (asset != null && asset.sha256.isEmpty) {
    final sha = _digestFor(release, asset.name);
    if (sha != null) asset = asset.copyWith(sha256: sha);
  }

  final prerelease = asBool(release?['prerelease']) ??
      (UpdateChannel.parse(m['channel']) == UpdateChannel.beta || v.isPreRelease);
  final channel = m['channel'] == null
      ? (prerelease ? UpdateChannel.beta : UpdateChannel.stable)
      : UpdateChannel.parse(m['channel']);

  var notes = ReleaseNotes.fromManifest(m);
  final body = asTrimmed(release?['body']);
  if (notes.notesMarkdown.isEmpty && notes.sections.isEmpty && body != null) {
    final fromBody = parseReleaseBody(body);
    notes = ReleaseNotes(
      title: notes.title ?? fromBody.title,
      summary: notes.summary ?? fromBody.summary,
      highlights: notes.highlights.isNotEmpty ? notes.highlights : fromBody.highlights,
      sections: fromBody.sections,
      notesMarkdown: fromBody.notesMarkdown,
      bannerUrl: notes.bannerUrl ?? fromBody.bannerUrl,
      gallery: notes.gallery.isNotEmpty ? notes.gallery : fromBody.gallery,
    );
  }

  return ReleaseInfo(
    version: v.name,
    build: build,
    tag: tagText ?? ReleaseInfo.tagFor(v.name, build),
    channel: channel,
    publishedAt: asDate(m['publishedAt']) ?? asDate(release?['published_at']),
    minSdk: asInt(m['minSdk']),
    notes: notes,
    asset: asset,
    releaseUrl: asHttpsUrl(m['releaseUrl']) ?? asHttpsUrl(release?['html_url']) ?? '',
    prerelease: prerelease,
  );
}

final RegExp _versionish = RegExp(r'v?\d+(?:\.\d+)*(?:[-+][0-9A-Za-z.]+)?');
final RegExp _brandish = RegExp(r'mine\s*music|release|version|build', caseSensitive: false);

/// A GitHub release `name` is only worth showing as a title when it says more
/// than the version ("v1.1.0", "Mine Music 1.1.0").
bool _nameIsUseful(String name, String tag) {
  if (name == tag) return false;
  final letters = name
      .replaceAll(_versionish, '')
      .replaceAll(_brandish, '')
      .replaceAll(RegExp(r'[^A-Za-z]'), '');
  return letters.length >= 3;
}

/// A release from the plain GitHub REST object. Null when the tag is not a
/// readable version. The APK's checksum is taken from `digest` when present;
/// the repository fills it from a `.sha256` sibling otherwise.
ReleaseInfo? releaseFromGithub(
  Map<String, dynamic> json, {
  required List<String> abis,
}) {
  final tag = asTrimmed(json['tag_name']);
  if (tag == null) return null;
  final v = AppVersion.parse(tag);
  if (v.isZero) return null;

  final assets = [
    for (final m in _restAssets(json))
      if (_restAsset(m) case final a?) a,
  ];
  final asset = pickAsset(assets, abis);

  var build = v.build;
  if (build <= 0) {
    for (final a in [if (asset != null) asset, ...assets.where(_isApk)]) {
      final m = _assetBuild.firstMatch(a.name);
      if (m != null) {
        build = int.tryParse(m.group(1)!) ?? 0;
        break;
      }
    }
  }

  var notes = parseReleaseBody(asTrimmed(json['body']) ?? '');
  final name = asTrimmed(json['name']);
  if (notes.title == null && name != null && _nameIsUseful(name, tag)) {
    notes = ReleaseNotes(
      title: name,
      summary: notes.summary,
      highlights: notes.highlights,
      sections: notes.sections,
      notesMarkdown: notes.notesMarkdown,
      bannerUrl: notes.bannerUrl,
      gallery: notes.gallery,
    );
  }

  final prerelease = json['prerelease'] == true || v.isPreRelease;
  return ReleaseInfo(
    version: v.name,
    build: build,
    tag: tag,
    channel: prerelease ? UpdateChannel.beta : UpdateChannel.stable,
    publishedAt: asDate(json['published_at']),
    notes: notes,
    asset: asset,
    releaseUrl: asHttpsUrl(json['html_url']) ?? '',
    prerelease: prerelease,
  );
}

// ---------------------------------------------------------------------------
// The repository
// ---------------------------------------------------------------------------

class UpdateRepository {
  UpdateRepository({
    http.Client? client,
    this.repo = kDefaultUpdateRepo,
    this.timeout = const Duration(seconds: 12),
    DateTime Function()? now,
  })  : _client = client,
        _ownsClient = client == null,
        _now = now ?? DateTime.now;

  /// `owner/name`.
  final String repo;

  /// Per request (the manifest and checksum downloads each get their own).
  final Duration timeout;

  http.Client? _client;
  final bool _ownsClient;
  final DateTime Function() _now;

  http.Client get _http => _client ??= http.Client();

  /// Closes the HTTP client only if this repository created it.
  void close() {
    if (_ownsClient) {
      _client?.close();
      _client = null;
    }
  }

  static const Map<String, String> _apiHeaders = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': kUpdateUserAgent,
  };

  /// The newest release for [channel], as it applies to a device with [abis].
  ///
  /// Stable asks `/releases/latest` (GitHub already skips drafts and
  /// prereleases there); beta takes the first non-draft of the newest ten.
  /// Pass the [etag] from the previous [Fetched] to get [NotModified] when
  /// nothing changed - conditional requests that return 304 do not count
  /// against the rate limit.
  Future<FetchResult> fetchLatest({
    required UpdateChannel channel,
    required List<String> abis,
    String? etag,
  }) async {
    try {
      final stable = channel == UpdateChannel.stable;
      final uri = stable
          ? Uri.https(_apiHost, '/repos/$repo/releases/latest')
          : Uri.https(_apiHost, '/repos/$repo/releases', const {'per_page': '10'});
      final res = await _get(uri, headers: {
        ..._apiHeaders,
        if (etag != null && etag.isNotEmpty) 'If-None-Match': etag,
      });

      if (res.statusCode == 304) return const NotModified();
      // No release has ever been published: a normal state, not an error.
      if (res.statusCode == 404 && stable) return const Fetched(null, null);
      final blocked = _failureFor(res);
      if (blocked != null) return blocked;

      final decoded = jsonDecode(_text(res));
      final json = _pickRelease(decoded, stable: stable);
      final responseEtag = _header(res.headers, 'etag');
      if (json == null) return Fetched(null, responseEtag);

      final info = await _build(json, abis);
      // A release without an APK for this phone (or one still uploading)
      // cannot be installed, so there is nothing to offer yet.
      if (info == null || info.asset == null) return Fetched(null, responseEtag);
      return Fetched(info, responseEtag);
    } catch (e) {
      logUpdate('fetchLatest failed: $e');
      return _failureFromError(e);
    }
  }

  /// The release for [tag] - used for the "what's new" of the running version.
  /// Tries the usual spellings of the tag (`v1.1.0+142`, `1.1.0+142`,
  /// `v1.1.0-b142`, `v1.1.0`, ...). Returns a notes-only [ReleaseInfo]
  /// (`asset == null`) when the release has no APK for [abis]. Null when no
  /// variant exists or the network fails. Never throws.
  Future<ReleaseInfo?> fetchByTag(String tag, List<String> abis) async {
    for (final variant in tagVariants(tag)) {
      try {
        final uri = Uri.parse(
          'https://$_apiHost/repos/$repo/releases/tags/${Uri.encodeComponent(variant)}',
        );
        final res = await _get(uri, headers: _apiHeaders);
        if (res.statusCode == 404) continue;
        if (res.statusCode < 200 || res.statusCode >= 300) return null;
        final json = asMap(jsonDecode(_text(res)));
        if (json == null) return null;
        return await _build(json, abis);
      } catch (e) {
        logUpdate('fetchByTag($variant) failed: $e');
        return null;
      }
    }
    return null;
  }

  // -- building -------------------------------------------------------------

  Future<ReleaseInfo?> _build(Map<String, dynamic> json, List<String> abis) async {
    ReleaseInfo? info;

    final manifestUrl = _manifestUrl(json);
    if (manifestUrl != null) {
      final manifest = await _fetchManifest(manifestUrl);
      if (manifest != null) {
        info = releaseFromManifest(manifest, abis: abis, release: json);
        // A manifest that lists no APK for this phone may still sit next to a
        // REST release that has one.
        if (info != null && info.asset == null) {
          final restAsset = releaseFromGithub(json, abis: abis)?.asset;
          if (restAsset != null) info = info.copyWith(asset: restAsset);
        }
      }
    }
    info ??= releaseFromGithub(json, abis: abis);
    if (info == null) return null;

    final asset = info.asset;
    if (asset != null && asset.sha256.isEmpty) {
      final sha = await _fetchSiblingSha(json, asset.name);
      if (sha != null) info = info.copyWith(asset: asset.copyWith(sha256: sha));
    }
    if (info.releaseUrl.isEmpty) {
      info = info.copyWith(
        releaseUrl: 'https://github.com/$repo/releases/tag/${Uri.encodeComponent(info.tag)}',
      );
    }
    return info;
  }

  String? _manifestUrl(Map<String, dynamic> json) {
    for (final m in _restAssets(json)) {
      if ((asTrimmed(m['name']) ?? '').toLowerCase() == kManifestAssetName) {
        return asHttpsUrl(m['browser_download_url']);
      }
    }
    return null;
  }

  /// `update.json`, or null for any reason it cannot be used.
  Future<Map<String, dynamic>?> _fetchManifest(String url) async {
    try {
      final res = await _get(Uri.parse(url), headers: const {
        'Accept': 'application/json',
        'User-Agent': kUpdateUserAgent,
      });
      if (res.statusCode != 200) return null;
      return asMap(jsonDecode(_text(res)));
    } catch (e) {
      logUpdate('manifest unreadable, using the release body: $e');
      return null;
    }
  }

  /// The hash from `<apk>.sha256` (`<64 hex>  <filename>`), or null.
  Future<String?> _fetchSiblingSha(Map<String, dynamic> json, String apkName) async {
    final url = siblingShaUrl(json, apkName);
    if (url == null) return null;
    try {
      final res = await _get(Uri.parse(url), headers: const {
        'Accept': 'text/plain, application/octet-stream',
        'User-Agent': kUpdateUserAgent,
      });
      if (res.statusCode != 200) return null;
      return firstSha256In(_text(res));
    } catch (e) {
      logUpdate('checksum file unreadable: $e');
      return null;
    }
  }

  // -- http -----------------------------------------------------------------

  Future<http.Response> _get(Uri uri, {required Map<String, String> headers}) =>
      _http.get(uri, headers: headers).timeout(timeout);

  /// Bodies are decoded as UTF-8 here, not by `http`, which falls back to
  /// Latin-1 when a response carries no charset.
  static String _text(http.Response res) =>
      utf8.decode(res.bodyBytes, allowMalformed: true);

  static String? _header(Map<String, String> headers, String name) {
    final want = name.toLowerCase();
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == want) return e.value;
    }
    return null;
  }

  Map<String, dynamic>? _pickRelease(Object? decoded, {required bool stable}) {
    if (decoded is List) {
      for (final e in decoded) {
        final m = asMap(e);
        if (m == null || m['draft'] == true) continue;
        if (stable && m['prerelease'] == true) continue;
        return m;
      }
      return null;
    }
    final m = asMap(decoded);
    if (m == null || m['draft'] == true) return null;
    return m;
  }

  FetchResult? _failureFor(http.Response res) {
    final code = res.statusCode;
    if (code >= 200 && code < 300) return null;
    if (code == 403 || code == 429) {
      final remaining = _header(res.headers, 'x-ratelimit-remaining');
      final retryAfter = _header(res.headers, 'retry-after');
      if (code == 429 || remaining == '0' || retryAfter != null) {
        return RateLimited(_retryAt(res.headers));
      }
    }
    return const Failed(kUnreachableMessage);
  }

  DateTime? _retryAt(Map<String, String> headers) {
    final after = int.tryParse(_header(headers, 'retry-after') ?? '');
    if (after != null) {
      return _now().add(Duration(seconds: after.clamp(0, 86400)));
    }
    final reset = int.tryParse(_header(headers, 'x-ratelimit-reset') ?? '');
    if (reset != null) {
      return DateTime.fromMillisecondsSinceEpoch(reset * 1000, isUtc: true);
    }
    return null;
  }

  FetchResult _failureFromError(Object e) => looksOffline(e)
      ? const Failed(kOfflineMessage, offline: true)
      : const Failed(kUnreachableMessage);
}
