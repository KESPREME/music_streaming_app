// lib/services/update/version_compare.dart
//
// "Is that release newer than what I am running?" - answered without ever
// throwing, because the inputs are a Play-style `versionName` from the OS and a
// free-form git tag from GitHub, and either can be junk.
//
// Order, most significant first:
//   1. major.minor.patch, numerically (1.10 > 1.9; `1` is `1.0.0`).
//   2. pre-release: `1.2.0-beta.2` is OLDER than `1.2.0` (semver). Two
//      pre-releases compare identifier by identifier, numeric ids numerically
//      and below alphanumeric ones; a longer list wins a tie.
//   3. the build number, so a rebuild of the same name IS an update.
//
// A missing build is 0. `0.0.0` (what a host with no native side reports) is
// older than every real release.

import 'package:flutter/foundation.dart';

import 'update_models.dart';

@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion({
    this.major = 0,
    this.minor = 0,
    this.patch = 0,
    this.preRelease = const <String>[],
    this.build = 0,
  });

  /// Accepts `v1.2.3`, `1`, `1.2`, `1.2.3+45`, `1.2.3-beta.2+45`, `1.2.3-b45`.
  /// Anything it cannot read becomes zeros - it never throws.
  factory AppVersion.parse(String raw) {
    try {
      return _parse(raw);
    } catch (_) {
      return const AppVersion();
    }
  }

  final int major;
  final int minor;
  final int patch;

  /// Dot-separated identifiers after the `-`, lower-cased (`['beta', '2']`).
  final List<String> preRelease;
  final int build;

  bool get isPreRelease => preRelease.isNotEmpty;

  /// True when nothing numeric could be read (`0.0.0`, no build, no suffix).
  bool get isZero =>
      major == 0 && minor == 0 && patch == 0 && preRelease.isEmpty && build == 0;

  /// `1.2.3` or `1.2.3-beta.2` - no build.
  String get name =>
      '$major.$minor.$patch${preRelease.isEmpty ? '' : '-${preRelease.join('.')}'}';

  AppVersion withBuild(int value) => value > 0
      ? AppVersion(
          major: major,
          minor: minor,
          patch: patch,
          preRelease: preRelease,
          build: value,
        )
      : this;

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  int compareTo(AppVersion other) {
    var c = major.compareTo(other.major);
    if (c != 0) return c;
    c = minor.compareTo(other.minor);
    if (c != 0) return c;
    c = patch.compareTo(other.patch);
    if (c != 0) return c;
    c = _comparePre(preRelease, other.preRelease);
    if (c != 0) return c;
    return build.compareTo(other.build);
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, Object.hashAll(preRelease), build);

  @override
  String toString() => build > 0 ? '$name+$build' : name;

  // ---------------------------------------------------------------------------

  static final RegExp _digits = RegExp(r'^\d+');
  static final RegExp _numeric = RegExp(r'^\d+$');

  /// `-b45` at the end of the part after the first dash (or all of it).
  static final RegExp _dashBuild = RegExp(r'(?:^|-)[bB](\d+)$');

  static AppVersion _parse(String raw) {
    var s = raw.trim();
    if (s.length > 128) s = s.substring(0, 128);
    if (s.length > 1 &&
        (s.codeUnitAt(0) == 0x76 || s.codeUnitAt(0) == 0x56) &&
        _isDigit(s.codeUnitAt(1))) {
      s = s.substring(1);
    }

    int? build;
    final plus = s.indexOf('+');
    if (plus >= 0) {
      build = _leadingInt(s.substring(plus + 1));
      s = s.substring(0, plus);
    }

    var pre = <String>[];
    final dash = s.indexOf('-');
    if (dash >= 0) {
      var tail = s.substring(dash + 1);
      s = s.substring(0, dash);
      final m = _dashBuild.firstMatch(tail);
      if (m != null) {
        build ??= _leadingInt(m.group(1)!);
        tail = tail.substring(0, m.start);
      }
      pre = [
        for (final id in tail.split('.'))
          if (id.trim().isNotEmpty) id.trim().toLowerCase(),
      ];
    }

    final core = s.split('.');
    int part(int i) => i < core.length ? (_leadingInt(core[i].trim()) ?? 0) : 0;
    return AppVersion(
      major: part(0),
      minor: part(1),
      patch: part(2),
      preRelease: pre,
      build: build ?? 0,
    );
  }

  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  /// The digits at the start of [s]; capped so absurd input cannot overflow.
  static int? _leadingInt(String s) {
    final m = _digits.firstMatch(s);
    if (m == null) return null;
    final d = m.group(0)!;
    return d.length > 9 ? 999999999 : int.parse(d);
  }

  static int _comparePre(List<String> a, List<String> b) {
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty) return 1; // a release outranks its own pre-releases
    if (b.isEmpty) return -1;
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final c = _compareId(a[i], b[i]);
      if (c != 0) return c;
    }
    return a.length.compareTo(b.length);
  }

  static int _compareId(String a, String b) {
    final an = _numeric.hasMatch(a);
    final bn = _numeric.hasMatch(b);
    if (an && bn) {
      final x = a.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final y = b.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (x.length != y.length) return x.length.compareTo(y.length);
      return x.compareTo(y);
    }
    if (an) return -1; // numeric ids sort below alphanumeric ones
    if (bn) return 1;
    return a.compareTo(b);
  }
}

/// True when [release] is a later version than the one installed.
///
/// [installedBuild] is authoritative when positive; otherwise a `+build` in
/// [installedName] is used. A higher build of the same name counts, an
/// installed `-beta` is older than the same stable, and an installed `0.0.0`
/// (unknown) is older than everything.
bool isNewerRelease({
  required String installedName,
  required int installedBuild,
  required ReleaseInfo release,
}) {
  final installed = AppVersion.parse(installedName).withBuild(installedBuild);
  final candidate = AppVersion.parse(release.version).withBuild(release.build);
  return candidate.isNewerThan(installed);
}
