// tool/release/src/manifest.dart
//
// `update.json`: the one file the app reads to learn about a release.
//
// CI publishes it next to the APK. It carries everything the "Software Update"
// screen shows - version, notes, banner and screenshots - and the one thing the
// installer must be able to trust: the APK's size and SHA-256. The app prefers
// this file over parsing the GitHub release page, so the notes and the checksum
// can never disagree with the build they came with.
//
// The schema is documented in docs/RELEASING.md and read by
// lib/services/update/update_repository.dart. Change both together.

import 'dart:convert';

import 'commit_notes.dart';

/// An APK built for one ABI (arm64 is the one worth shipping: about a third of
/// the universal download, and almost every phone sold since 2017 runs it).
class ApkAsset {
  const ApkAsset({
    required this.name,
    required this.abi,
    required this.size,
    required this.sha256,
  });

  final String name;
  final String abi;
  final int size;
  final String sha256;
}

class ManifestInput {
  const ManifestInput({
    required this.repo,
    required this.name,
    required this.build,
    required this.tag,
    required this.channel,
    required this.publishedAt,
    required this.apkName,
    required this.apkSize,
    required this.apkSha256,
    required this.sections,
    required this.notesMarkdown,
    this.minSdk = 24,
    this.title,
    this.summary,
    this.bannerName,
    this.gallery = const [],
    this.extraApks = const [],
  });

  final String repo;
  final String name;
  final int build;
  final String tag;
  final String channel;
  final DateTime publishedAt;
  final String apkName;
  final int apkSize;
  final String apkSha256;
  final List<NoteSection> sections;
  final String notesMarkdown;
  final int minSdk;
  final String? title;
  final String? summary;

  /// File name of the banner asset on the release.
  final String? bannerName;

  /// (file name, caption) of each screenshot asset on the release.
  final List<(String, String)> gallery;

  /// Per-ABI APKs offered alongside the universal one. The app takes the first
  /// that matches its CPU and falls back to the universal APK.
  final List<ApkAsset> extraApks;
}

/// `https://github.com/<repo>/releases/download/<tag>/<file>`, URL-encoded.
String assetUrl(String repo, String tag, String file) =>
    'https://github.com/$repo/releases/download/${Uri.encodeComponent(tag)}/${Uri.encodeComponent(file)}';

String releasePageUrl(String repo, String tag) =>
    'https://github.com/$repo/releases/tag/${Uri.encodeComponent(tag)}';

/// Up to three short lines for the compact update card.
List<String> highlightsOf(List<NoteSection> sections) => [
      for (final s in sections) ...s.items,
    ].take(3).toList();

Map<String, Object?> buildManifest(ManifestInput i) {
  for (final sha in [i.apkSha256, for (final a in i.extraApks) a.sha256]) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw ArgumentError.value(sha, 'apkSha256', 'must be 64 lowercase hex');
    }
  }
  return {
    'schema': 1,
    'app': 'mine-music',
    'version': i.name,
    'build': i.build,
    'tag': i.tag,
    'channel': i.channel,
    'publishedAt': i.publishedAt.toUtc().toIso8601String(),
    'minSdk': i.minSdk,
    if (i.title != null) 'title': i.title,
    if (i.summary != null) 'summary': i.summary,
    'highlights': highlightsOf(i.sections),
    'sections': [for (final s in i.sections) s.toJson()],
    'notes': i.notesMarkdown,
    'images': {
      if (i.bannerName != null) 'banner': assetUrl(i.repo, i.tag, i.bannerName!),
      'gallery': [
        for (final g in i.gallery)
          {'url': assetUrl(i.repo, i.tag, g.$1), 'caption': g.$2},
      ],
    },
    'assets': [
      for (final a in i.extraApks)
        {
          'name': a.name,
          'abi': a.abi,
          'url': assetUrl(i.repo, i.tag, a.name),
          'size': a.size,
          'sha256': a.sha256,
        },
      {
        'name': i.apkName,
        'abi': 'universal',
        'url': assetUrl(i.repo, i.tag, i.apkName),
        'size': i.apkSize,
        'sha256': i.apkSha256,
      },
    ],
    'releaseUrl': releasePageUrl(i.repo, i.tag),
  };
}

String encodeManifest(Map<String, Object?> manifest) =>
    const JsonEncoder.withIndent('  ').convert(manifest);

/// `MineMusic-1.1.0-b142-banner.png`: asset names are shared across the whole
/// release, so every image carries the build id and cannot clash with an
/// earlier release's file of the same name.
String captionFromFileName(String file) {
  var s = file.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
  s = s.replaceFirst(RegExp(r'^(screenshot|screen|shot)[-_ ]*\d*[-_ ]*', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'[-_]+'), ' ').trim();
  if (s.isEmpty) return 'Screenshot';
  return s[0].toUpperCase() + s.substring(1);
}
