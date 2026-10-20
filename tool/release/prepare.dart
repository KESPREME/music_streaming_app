// tool/release/prepare.dart
//
// ONE COMMAND THAT TURNS "a build exists" INTO "a release is ready to publish".
//
//   dart run tool/release/prepare.dart plan   --ref refs/heads/master --run-number 42 [--prerelease]
//   dart run tool/release/prepare.dart notes  --repo O/R --name 1.1.0 --build 142 --tag 'v1.1.0+142' \
//        --apk build/app/outputs/flutter-apk/app-release.apk --out build/release
//
// `plan` prints GITHUB_OUTPUT lines (name, build, tag, fileId, prerelease, channel).
// `notes` writes into --out: the renamed APK, its .sha256, update.json, notes.md,
// and the images it will publish (banner + screenshots). It needs git history.
//
// Everything with logic in it lives in tool/release/src and is unit-tested; this
// file only reads arguments, the file system and git.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'src/commit_notes.dart';
import 'src/manifest.dart';
import 'src/version_plan.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: prepare.dart <plan|notes> [options]');
    exit(64);
  }
  final cmd = args.first;
  final opts = _parse(args.skip(1).toList());
  try {
    switch (cmd) {
      case 'plan':
        _plan(opts);
      case 'notes':
        await _notes(opts);
      default:
        stderr.writeln('unknown command: $cmd');
        exit(64);
    }
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}');
    exit(1);
  }
}

Map<String, String> _parse(List<String> a) {
  final m = <String, String>{};
  for (var i = 0; i < a.length; i++) {
    if (!a[i].startsWith('--')) continue;
    final key = a[i].substring(2);
    if (i + 1 < a.length && !a[i + 1].startsWith('--')) {
      m[key] = a[++i];
    } else {
      m[key] = 'true';
    }
  }
  return m;
}

String _req(Map<String, String> o, String k) =>
    o[k] ?? (throw FormatException('missing --$k'));

void _plan(Map<String, String> o) {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final v = readPubspecVersion(pubspec) ??
      (throw const FormatException('pubspec.yaml has no version'));
  final plan = planVersion(
    pubspecVersion: v,
    ref: o['ref'] ?? 'refs/heads/master',
    runNumber: int.parse(o['run-number'] ?? '0'),
    offset: int.parse(o['offset'] ?? '100'),
    forcePrerelease: o['prerelease'] == 'true',
  );
  stdout
    ..writeln('name=${plan.name}')
    ..writeln('build=${plan.build}')
    ..writeln('tag=${plan.tag}')
    ..writeln('fileId=${plan.fileId}')
    ..writeln('prerelease=${plan.prerelease}')
    ..writeln('channel=${plan.channel}');
}

Future<void> _notes(Map<String, String> o) async {
  final repo = _req(o, 'repo');
  final name = _req(o, 'name');
  final build = int.parse(_req(o, 'build'));
  final tag = _req(o, 'tag');
  final apk = File(_req(o, 'apk'));
  final out = Directory(_req(o, 'out'))..createSync(recursive: true);
  final imagesDir = Directory(o['images'] ?? 'release/images');
  final fileId = '$name-b$build';
  final channel = (o['prerelease'] == 'true' || name.contains('-')) ? 'beta' : 'stable';

  if (!apk.existsSync()) throw FormatException('APK not found: ${apk.path}');

  // 1. The APK under its release name, and its checksum.
  final apkName = 'MineMusic-$fileId.apk';
  final target = File('${out.path}/$apkName');
  apk.copySync(target.path);
  final sha = (await sha256.bind(target.openRead()).first).toString();
  File('${out.path}/$apkName.sha256').writeAsStringSync('$sha  $apkName\n');

  // 2. Images: banner + screenshots, each renamed with the build id.
  final banner = _findBanner(imagesDir, o['banner']);
  String? bannerName;
  if (banner != null) {
    bannerName = 'MineMusic-$fileId-banner.${_ext(banner.path)}';
    banner.copySync('${out.path}/$bannerName');
  }
  final captions = _readCaptions(imagesDir);
  final gallery = <(String, String)>[];
  for (final shot in _screenshots(imagesDir)) {
    final base = _base(shot.path);
    final assetName = 'MineMusic-$fileId-$base';
    shot.copySync('${out.path}/$assetName');
    gallery.add((assetName, captions[base] ?? captionFromFileName(base)));
  }

  // 3. Notes: a hand-written file wins; otherwise the commits since last release.
  final curatedFile = File('release/notes/$name.md');
  List<NoteSection> sections;
  String? title;
  String? summary;
  if (curatedFile.existsSync()) {
    final parsed = sectionsFromMarkdown(curatedFile.readAsStringSync());
    sections = parsed.sections;
    title = parsed.title;
    summary = parsed.summary;
    stderr.writeln('notes: using release/notes/$name.md');
  } else {
    final subjects = await _commitSubjects(o['from'], o['to'] ?? 'HEAD');
    sections = sectionsFromCommits(subjects);
    stderr.writeln('notes: ${subjects.length} commits -> '
        '${sections.fold<int>(0, (n, s) => n + s.items.length)} lines');
  }

  final prev = o['from'];
  final body = renderReleaseBody(
    appName: 'Mine Music',
    version: name,
    title: title,
    summary: summary,
    sections: sections,
    bannerUrl: bannerName == null ? null : assetUrl(repo, tag, bannerName),
    gallery: [
      for (final g in gallery) GalleryImage(assetUrl(repo, tag, g.$1), g.$2),
    ],
    compareUrl: prev == null || prev.isEmpty
        ? null
        : 'https://github.com/$repo/compare/${Uri.encodeComponent(prev)}...${Uri.encodeComponent(tag)}',
    sha256: sha,
  );
  File('${out.path}/notes.md').writeAsStringSync(body);

  // 4. update.json for the app.
  final manifest = buildManifest(ManifestInput(
    repo: repo,
    name: name,
    build: build,
    tag: tag,
    channel: channel,
    publishedAt: DateTime.now().toUtc(),
    apkName: apkName,
    apkSize: target.lengthSync(),
    apkSha256: sha,
    sections: sections,
    notesMarkdown: body,
    minSdk: int.tryParse(o['min-sdk'] ?? '') ?? 24,
    title: title ?? 'Mine Music $name',
    summary: summary,
    bannerName: bannerName,
    gallery: gallery,
  ));
  File('${out.path}/update.json').writeAsStringSync(encodeManifest(manifest));

  stdout
    ..writeln('apk=${target.path}')
    ..writeln('sha256=$sha')
    ..writeln('images=${[if (bannerName != null) bannerName, ...gallery.map((g) => g.$1)].length}');
}

File? _findBanner(Directory dir, String? override) {
  if (override != null && File(override).existsSync()) return File(override);
  if (!dir.existsSync()) return null;
  for (final f in dir.listSync().whereType<File>()) {
    final b = _base(f.path).toLowerCase();
    if (b.startsWith('banner.')) return f;
  }
  return null;
}

Iterable<File> _screenshots(Directory dir) {
  if (!dir.existsSync()) return const [];
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(f.path))
      .where((f) => !_base(f.path).toLowerCase().startsWith('banner.'))
      .toList()
    ..sort((a, b) => _base(a.path).compareTo(_base(b.path)));
  return files.take(8);
}

Map<String, String> _readCaptions(Directory dir) {
  final f = File('${dir.path}/captions.json');
  if (!f.existsSync()) return const {};
  try {
    final j = jsonDecode(f.readAsStringSync());
    if (j is Map) return {for (final e in j.entries) e.key.toString(): e.value.toString()};
  } catch (_) {}
  return const {};
}

String _base(String path) => path.replaceAll('\\', '/').split('/').last;
String _ext(String path) => _base(path).split('.').last.toLowerCase();

Future<List<String>> _commitSubjects(String? from, String to) async {
  final range = (from == null || from.isEmpty) ? to : '$from..$to';
  final args = ['log', '--no-merges', '--pretty=format:%s', if (from == null || from.isEmpty) '-n40', range];
  final r = await Process.run('git', args);
  if (r.exitCode != 0) {
    stderr.writeln('git log failed: ${r.stderr}');
    return const [];
  }
  return const LineSplitter().convert(r.stdout as String);
}
