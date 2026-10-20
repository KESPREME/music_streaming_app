// lib/services/update/update_models.dart
//
// The vocabulary of the in-app updater: what a release is, what its notes say,
// which APK is ours, and where the updater currently stands.
//
// All of it is immutable and JSON-round-trippable, because a [ReleaseInfo] is
// cached in SharedPreferences so the "what's new" sheet and the pending-update
// card still work offline. The JSON a [ReleaseInfo] writes is deliberately the
// same shape as the `update.json` CI publishes (plus a single chosen `asset`),
// so one parser reads both.

import 'package:flutter/foundation.dart';

import 'release_notes.dart' show releaseNotesFromManifest;
import 'update_json.dart';

/// Where the updater is. The UI switches on this and nothing else.
enum UpdateStatus {
  /// Nothing known yet (no check has finished).
  idle,

  /// Asking GitHub for the newest release.
  checking,

  /// The newest release is not newer than what is installed.
  upToDate,

  /// A newer release exists; nothing downloaded yet.
  available,

  /// Streaming the APK (`progress`, `bytesPerSecond`, `etaSeconds` are live).
  downloading,

  /// Hashing the finished download.
  verifying,

  /// A verified APK is on disk and can be installed.
  ready,

  /// The system installer was handed the file.
  installing,

  /// "Install unknown apps" is off; the user must allow it, then install again.
  needsPermission,

  /// Something went wrong; see `error` and `failedDuring`.
  failed,
}

/// Which stream of releases to follow.
enum UpdateChannel {
  /// Only releases GitHub marks as non-prerelease (`/releases/latest`).
  stable,

  /// The newest release of any kind, prereleases included.
  beta;

  /// Parses a stored or published channel name. Anything that is not clearly a
  /// pre-release channel is [stable] - the safe default.
  static UpdateChannel parse(Object? raw) {
    final s = raw is String ? raw.trim().toLowerCase() : '';
    return switch (s) {
      'beta' || 'prerelease' || 'pre-release' || 'alpha' || 'nightly' || 'rc' => beta,
      _ => stable,
    };
  }
}

/// One downloadable file of a release.
@immutable
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    this.abi = 'universal',
    this.size = 0,
    this.sha256 = '',
  });

  /// File name, e.g. `MineMusic-1.1.0-b142.apk`. Also the on-disk name.
  final String name;

  /// `universal`, `arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`.
  final String abi;

  /// Always `https://` - the repository drops anything else.
  final String url;

  /// Bytes, or 0 when unknown.
  final int size;

  /// Lower-case 64-hex SHA-256, or empty when the release carries none.
  final String sha256;

  bool get hasChecksum => sha256.isNotEmpty;

  ReleaseAsset copyWith({String? sha256, int? size}) => ReleaseAsset(
        name: name,
        url: url,
        abi: abi,
        size: size ?? this.size,
        sha256: sha256 ?? this.sha256,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'abi': abi,
        'url': url,
        'size': size,
        'sha256': sha256,
      };

  /// Null when [raw] is not an object with at least an https `url`.
  static ReleaseAsset? tryParse(Object? raw) {
    final m = asMap(raw);
    if (m == null) return null;
    final url = asHttpsUrl(m['url']);
    if (url == null) return null;
    final name = asTrimmed(m['name']) ?? _baseOf(url);
    if (name.isEmpty) return null;
    return ReleaseAsset(
      name: name,
      url: url,
      abi: asTrimmed(m['abi']) ?? 'universal',
      size: (asInt(m['size']) ?? 0).clamp(0, 1 << 40),
      sha256: normalizeSha256(m['sha256']) ?? '',
    );
  }

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) =>
      tryParse(json) ?? (throw const FormatException('Invalid release asset'));

  /// Last path segment of an absolute [url].
  static String _baseOf(String url) {
    final segs = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    return segs.isEmpty ? '' : segs.last;
  }

  @override
  bool operator ==(Object other) =>
      other is ReleaseAsset &&
      other.name == name &&
      other.abi == abi &&
      other.url == url &&
      other.size == size &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(name, abi, url, size, sha256);

  @override
  String toString() => 'ReleaseAsset($name, $abi, $size bytes)';
}

/// A titled group of change bullets ("New", "Improved", "Fixed").
@immutable
class ReleaseSection {
  const ReleaseSection({
    required this.title,
    this.icon,
    this.items = const [],
  });

  final String title;

  /// Normalised key: `sparkle`, `improved`, `fix`, `perf`, `design`, `other`.
  final String? icon;

  /// Bullet text exactly as authored (inline markdown intact).
  final List<String> items;

  Map<String, dynamic> toJson() => {
        'title': title,
        if (icon != null) 'icon': icon,
        'items': items,
      };

  factory ReleaseSection.fromJson(Map<String, dynamic> json) => ReleaseSection(
        title: asTrimmed(json['title']) ?? 'Other',
        icon: asTrimmed(json['icon']),
        items: asStringList(json['items']),
      );

  @override
  bool operator ==(Object other) =>
      other is ReleaseSection &&
      other.title == title &&
      other.icon == icon &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(title, icon, Object.hashAll(items));
}

/// A screenshot with an optional caption.
@immutable
class ReleaseGalleryImage {
  const ReleaseGalleryImage({required this.url, this.caption});

  final String url;
  final String? caption;

  Map<String, dynamic> toJson() => {
        'url': url,
        if (caption != null) 'caption': caption,
      };

  /// Null unless [raw] carries an https `url`.
  static ReleaseGalleryImage? tryParse(Object? raw) {
    final m = asMap(raw);
    final url = asHttpsUrl(m == null ? raw : m['url']);
    if (url == null) return null;
    return ReleaseGalleryImage(url: url, caption: m == null ? null : asTrimmed(m['caption']));
  }

  @override
  bool operator ==(Object other) =>
      other is ReleaseGalleryImage && other.url == url && other.caption == caption;

  @override
  int get hashCode => Object.hash(url, caption);
}

/// Everything a release says about itself, ready to lay out.
///
/// [notesMarkdown] is the body with the title heading and every image removed
/// (those live in [title], [bannerUrl] and [gallery]), so a markdown view of it
/// never repeats what the sheet already shows.
@immutable
class ReleaseNotes {
  const ReleaseNotes({
    this.title,
    this.summary,
    this.highlights = const [],
    this.sections = const [],
    this.notesMarkdown = '',
    this.bannerUrl,
    this.gallery = const [],
  });

  static const ReleaseNotes empty = ReleaseNotes();

  final String? title;

  /// One line, at most 160 characters.
  final String? summary;

  /// Up to three short plain-text bullets for a compact card.
  final List<String> highlights;
  final List<ReleaseSection> sections;
  final String notesMarkdown;
  final String? bannerUrl;
  final List<ReleaseGalleryImage> gallery;

  bool get isEmpty =>
      title == null &&
      summary == null &&
      highlights.isEmpty &&
      sections.isEmpty &&
      notesMarkdown.isEmpty &&
      bannerUrl == null &&
      gallery.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Reads the `update.json` shape (also what [toJson] writes). A key that is
  /// present is authoritative, even when empty; a key that is absent is derived
  /// from the markdown `notes`. Never throws.
  factory ReleaseNotes.fromManifest(Map<String, dynamic> manifest) =>
      releaseNotesFromManifest(manifest);

  factory ReleaseNotes.fromJson(Map<String, dynamic> json) =>
      releaseNotesFromManifest(json);

  /// Every key is written, even when empty, so [ReleaseNotes.fromJson] gives
  /// back exactly what was cached instead of re-deriving it.
  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
        'highlights': highlights,
        'sections': [for (final s in sections) s.toJson()],
        'notes': notesMarkdown,
        'images': {
          'banner': bannerUrl,
          'gallery': [for (final g in gallery) g.toJson()],
        },
      };

  @override
  bool operator ==(Object other) =>
      other is ReleaseNotes &&
      other.title == title &&
      other.summary == summary &&
      listEquals(other.highlights, highlights) &&
      listEquals(other.sections, sections) &&
      other.notesMarkdown == notesMarkdown &&
      other.bannerUrl == bannerUrl &&
      listEquals(other.gallery, gallery);

  @override
  int get hashCode => Object.hash(
        title,
        summary,
        Object.hashAll(highlights),
        Object.hashAll(sections),
        notesMarkdown,
        bannerUrl,
        Object.hashAll(gallery),
      );
}

/// One published version of the app.
@immutable
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.build,
    required this.tag,
    this.channel = UpdateChannel.stable,
    this.publishedAt,
    this.minSdk,
    this.notes = ReleaseNotes.empty,
    this.asset,
    this.releaseUrl = '',
    this.prerelease = false,
  });

  /// Marketing name without the build, e.g. `1.1.0` or `1.2.0-beta.1`.
  final String version;

  /// Monotonic build number (the APK's `versionCode`).
  final int build;

  /// Git tag, e.g. `v1.1.0+142`.
  final String tag;
  final UpdateChannel channel;

  /// UTC; null when the release does not say.
  final DateTime? publishedAt;

  /// Lowest Android API level this build runs on.
  final int? minSdk;
  final ReleaseNotes notes;

  /// The APK chosen for *this* device, or null for a notes-only release.
  final ReleaseAsset? asset;

  /// Human page for the release; empty when unknown.
  final String releaseUrl;
  final bool prerelease;

  /// `<version>+<build>` - the key used for "skipped" and "prompted".
  String get id => '$version+$build';

  /// `v<version>+<build>`, the tag CI writes.
  static String tagFor(String version, int build) => 'v$version+$build';

  bool get isInstallable => asset != null;

  ReleaseInfo copyWith({
    String? version,
    int? build,
    String? tag,
    UpdateChannel? channel,
    DateTime? publishedAt,
    int? minSdk,
    ReleaseNotes? notes,
    ReleaseAsset? asset,
    String? releaseUrl,
    bool? prerelease,
  }) =>
      ReleaseInfo(
        version: version ?? this.version,
        build: build ?? this.build,
        tag: tag ?? this.tag,
        channel: channel ?? this.channel,
        publishedAt: publishedAt ?? this.publishedAt,
        minSdk: minSdk ?? this.minSdk,
        notes: notes ?? this.notes,
        asset: asset ?? this.asset,
        releaseUrl: releaseUrl ?? this.releaseUrl,
        prerelease: prerelease ?? this.prerelease,
      );

  /// The same shape as `update.json` (schema 1) with one chosen `asset`.
  Map<String, dynamic> toJson() => {
        'schema': 1,
        'app': 'mine-music',
        'version': version,
        'build': build,
        'tag': tag,
        'channel': channel.name,
        'prerelease': prerelease,
        'publishedAt': publishedAt?.toUtc().toIso8601String(),
        'minSdk': minSdk,
        ...notes.toJson(),
        'asset': asset?.toJson(),
        'releaseUrl': releaseUrl,
      };

  /// Throws [FormatException] only when `version` or `build` is missing - the
  /// caller (cache restore) treats that as "no cache".
  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final version = asTrimmed(json['version']);
    final build = asInt(json['build']);
    if (version == null || build == null) {
      throw const FormatException('Release has no version/build');
    }
    final prerelease = asBool(json['prerelease']) ?? false;
    return ReleaseInfo(
      version: version,
      build: build,
      tag: asTrimmed(json['tag']) ?? tagFor(version, build),
      channel: json['channel'] == null
          ? (prerelease ? UpdateChannel.beta : UpdateChannel.stable)
          : UpdateChannel.parse(json['channel']),
      publishedAt: asDate(json['publishedAt']),
      minSdk: asInt(json['minSdk']),
      notes: ReleaseNotes.fromManifest(json),
      asset: ReleaseAsset.tryParse(json['asset']),
      releaseUrl: asHttpsUrl(json['releaseUrl']) ?? '',
      prerelease: prerelease,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReleaseInfo &&
      other.version == version &&
      other.build == build &&
      other.tag == tag &&
      other.channel == channel &&
      other.publishedAt == publishedAt &&
      other.minSdk == minSdk &&
      other.notes == notes &&
      other.asset == asset &&
      other.releaseUrl == releaseUrl &&
      other.prerelease == prerelease;

  @override
  int get hashCode => Object.hash(version, build, tag, channel, publishedAt,
      minSdk, notes, asset, releaseUrl, prerelease);

  @override
  String toString() => 'ReleaseInfo($tag)';
}

/// Marker for "argument not passed" in [UpdateState.copyWith], so `null` can
/// mean "clear this field".
const Object _keep = Object();

/// A snapshot of the updater. The UI renders this and nothing else.
@immutable
class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.release,
    this.progress = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.bytesPerSecond = 0,
    this.etaSeconds,
    this.error,
    this.failedDuring,
    this.checkedAt,
  });

  final UpdateStatus status;

  /// The release on offer (null when up to date).
  final ReleaseInfo? release;

  /// 0..1 while downloading; 1 when ready. 0 when the size is not known yet.
  final double progress;
  final int receivedBytes;

  /// 0 when unknown.
  final int totalBytes;

  /// Smoothed over about two seconds.
  final double bytesPerSecond;

  /// Null until a speed is known.
  final int? etaSeconds;

  /// A sentence for a person ("You appear to be offline."). May accompany a
  /// non-failed status: a check that failed while a cached update is on offer
  /// keeps that update and records why the refresh failed here.
  final String? error;

  /// Which step broke, when [status] is [UpdateStatus.failed].
  final UpdateStatus? failedDuring;
  final DateTime? checkedAt;

  bool get isBusy =>
      status == UpdateStatus.checking ||
      status == UpdateStatus.downloading ||
      status == UpdateStatus.verifying ||
      status == UpdateStatus.installing;

  /// Pass `null` for [release], [etaSeconds], [error], [failedDuring] or
  /// [checkedAt] to clear it; omit to keep it.
  UpdateState copyWith({
    UpdateStatus? status,
    Object? release = _keep,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    double? bytesPerSecond,
    Object? etaSeconds = _keep,
    Object? error = _keep,
    Object? failedDuring = _keep,
    Object? checkedAt = _keep,
  }) =>
      UpdateState(
        status: status ?? this.status,
        release: identical(release, _keep) ? this.release : release as ReleaseInfo?,
        progress: progress ?? this.progress,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
        etaSeconds: identical(etaSeconds, _keep) ? this.etaSeconds : etaSeconds as int?,
        error: identical(error, _keep) ? this.error : error as String?,
        failedDuring: identical(failedDuring, _keep)
            ? this.failedDuring
            : failedDuring as UpdateStatus?,
        checkedAt: identical(checkedAt, _keep) ? this.checkedAt : checkedAt as DateTime?,
      );

  @override
  bool operator ==(Object other) =>
      other is UpdateState &&
      other.status == status &&
      other.release == release &&
      other.progress == progress &&
      other.receivedBytes == receivedBytes &&
      other.totalBytes == totalBytes &&
      other.bytesPerSecond == bytesPerSecond &&
      other.etaSeconds == etaSeconds &&
      other.error == error &&
      other.failedDuring == failedDuring &&
      other.checkedAt == checkedAt;

  @override
  int get hashCode => Object.hash(status, release, progress, receivedBytes,
      totalBytes, bytesPerSecond, etaSeconds, error, failedDuring, checkedAt);

  @override
  String toString() => 'UpdateState($status${release == null ? '' : ' ${release!.tag}'}'
      '${error == null ? '' : ', "$error"'})';
}
