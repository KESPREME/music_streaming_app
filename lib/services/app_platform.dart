// lib/services/app_platform.dart
//
// The few things only the host can answer: which version is installed, which
// ABIs it runs, whether it may install an APK, and how to leave without being
// killed. One channel (`mine_music/app`), every call guarded - on a desktop, in
// a test, or before the engine is attached it degrades instead of throwing.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the OS says about this install.
@immutable
class AppInfo {
  const AppInfo({
    required this.versionName,
    required this.versionCode,
    this.packageName = '',
    this.abis = const [],
    this.sdkInt = 0,
    this.lastUpdateMs,
  });

  /// What a host with no native side reports (tests, desktop). Never a real
  /// release number, so an update check against it always sees something newer.
  static const AppInfo unknown =
      AppInfo(versionName: '0.0.0', versionCode: 0, packageName: 'unknown');

  final String versionName;

  /// The OS build number (`versionCode`). With ABI splits it carries an offset,
  /// which is why updates compare [versionName] first.
  final int versionCode;
  final String packageName;
  final List<String> abis;
  final int sdkInt;
  final int? lastUpdateMs;

  bool get isKnown => this != unknown && versionName != '0.0.0';

  static AppInfo fromMap(Map<Object?, Object?> m) => AppInfo(
        versionName: (m['versionName'] as String?) ?? '0.0.0',
        versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
        packageName: (m['packageName'] as String?) ?? '',
        abis: [for (final a in (m['abis'] as List?) ?? const []) a.toString()],
        sdkInt: (m['sdkInt'] as num?)?.toInt() ?? 0,
        lastUpdateMs: (m['lastUpdateTime'] as num?)?.toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is AppInfo &&
      other.versionName == versionName &&
      other.versionCode == versionCode &&
      other.packageName == packageName;

  @override
  int get hashCode => Object.hash(versionName, versionCode, packageName);
}

/// Outcome of asking the system to install an APK.
enum InstallResult {
  /// The system installer is on screen.
  started,

  /// "Install unknown apps" is off for this app; the settings page was opened.
  needsPermission,

  /// Not Android, or the file is not where it should be.
  unavailable,
}

class AppPlatform {
  AppPlatform._();

  @visibleForTesting
  static MethodChannel channel = const MethodChannel('mine_music/app');

  static Future<AppInfo>? _info;

  /// The installed version. Cached; asks the host once.
  static Future<AppInfo> info() => _info ??= _loadInfo();

  /// Forget the cached answer (a test, or right after an update).
  @visibleForTesting
  static void resetCache() => _info = null;

  static Future<AppInfo> _loadInfo() async {
    try {
      final m = await channel.invokeMapMethod<Object?, Object?>('appInfo');
      if (m == null) return AppInfo.unknown;
      return AppInfo.fromMap(m);
    } catch (_) {
      return AppInfo.unknown;
    }
  }

  /// Sends the task to the background, as Spotify and YouTube Music do on back
  /// from their root screen. Finishing the activity instead forgets the Flutter
  /// view and makes the next launch a cold one. Falls back to the normal exit
  /// when the host cannot.
  static Future<void> leaveApp() async {
    var moved = false;
    try {
      moved = await channel.invokeMethod<bool>('moveToBack') ?? false;
    } catch (_) {}
    if (!moved) await SystemNavigator.pop();
  }

  static Future<bool> canInstall() async {
    try {
      return await channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openInstallSettings() async {
    try {
      await channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {}
  }

  /// Hands [path] to the system installer. Only files under the app's cache
  /// `updates/` folder are accepted by the host.
  static Future<InstallResult> installApk(String path) async {
    try {
      final r = await channel.invokeMethod<String>('install', {'path': path});
      return switch (r) {
        'started' => InstallResult.started,
        'needs_permission' => InstallResult.needsPermission,
        _ => InstallResult.unavailable,
      };
    } catch (_) {
      return InstallResult.unavailable;
    }
  }
}
