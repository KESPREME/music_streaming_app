// tool/release/src/version_plan.dart
//
// WHAT VERSION IS THIS BUILD?
//
// pubspec.yaml says `version: 1.1.0+3`. That is the number a developer edits by
// hand, and it is not good enough for shipping: the build number (Android's
// versionCode) must go UP on every release or Android refuses the update, and
// nobody remembers to bump it. So CI derives it:
//
//   name   = the `1.1.0` part of pubspec (or of the pushed tag)
//   build  = workflow run number + [offset]  (monotonic, needs no commit back)
//   tag    = v<name>+<build>                 e.g. v1.1.0+142
//
// The offset exists because installs already in the wild carry versionCode 1.
//
// Pure Dart, no I/O: the rules are unit-tested (test/release_tools_test.dart).

class VersionPlan {
  const VersionPlan({
    required this.name,
    required this.build,
    required this.prerelease,
  });

  /// `1.1.0` or `1.2.0-beta.1`.
  final String name;
  final int build;
  final bool prerelease;

  String get tag => 'v$name+$build';
  String get channel => prerelease ? 'beta' : 'stable';

  /// File-name-safe id used for assets: `1.1.0-b142`.
  String get fileId => '$name-b$build';

  @override
  String toString() => tag;
}

final RegExp _tagPattern =
    RegExp(r'^v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)(?:\+(\d+))?$');
final RegExp _pubspecPattern =
    RegExp(r'^(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)(?:\+(\d+))?$');

/// Decides the version of the build being made.
///
/// [ref] is `GITHUB_REF` (`refs/heads/master`, `refs/tags/v1.2.0`).
/// A pushed tag wins: `v1.2.0` ships as 1.2.0, `v1.2.0+500` pins the build.
VersionPlan planVersion({
  required String pubspecVersion,
  required String ref,
  required int runNumber,
  int offset = 100,
  bool forcePrerelease = false,
}) {
  if (runNumber < 0) throw ArgumentError.value(runNumber, 'runNumber');
  final fallbackBuild = runNumber + offset;

  if (ref.startsWith('refs/tags/')) {
    final tag = ref.substring('refs/tags/'.length);
    final m = _tagPattern.firstMatch(tag);
    if (m == null) {
      throw FormatException('Tag "$tag" is not v<major>.<minor>.<patch>[+build]');
    }
    final name = m.group(1)!;
    final build = m.group(2) == null ? fallbackBuild : int.parse(m.group(2)!);
    return VersionPlan(
      name: name,
      build: build,
      prerelease: forcePrerelease || name.contains('-'),
    );
  }

  final m = _pubspecPattern.firstMatch(pubspecVersion.trim());
  if (m == null) {
    throw FormatException('pubspec version "$pubspecVersion" is not x.y.z[+n]');
  }
  final name = m.group(1)!;
  final pinned = m.group(2) == null ? 0 : int.parse(m.group(2)!);
  // Never go below what pubspec says, never repeat an earlier build.
  final build = pinned > fallbackBuild ? pinned : fallbackBuild;
  return VersionPlan(
    name: name,
    build: build,
    prerelease: forcePrerelease || name.contains('-'),
  );
}

/// The `version:` value from pubspec.yaml text, or null.
String? readPubspecVersion(String pubspec) {
  final m = RegExp(r'^version:\s*([^\s#]+)', multiLine: true).firstMatch(pubspec);
  return m?.group(1);
}
