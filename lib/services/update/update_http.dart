// lib/services/update/update_http.dart
//
// What the repository and the downloader share: the identity we send, the
// sentences a person reads when something goes wrong, and the one place that
// decides "offline" from an exception.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// GitHub rejects API calls with no `User-Agent`.
const String kUpdateUserAgent = 'MineMusic-Updater';

/// Shown when the device has no route out.
const String kOfflineMessage = 'You appear to be offline.';

/// Shown when we got no usable answer and cannot tell why.
const String kUnreachableMessage =
    'GitHub could not be reached. Try again in a moment.';

/// Shown when a download dies part-way (the partial file is kept).
const String kDownloadInterruptedMessage =
    'The download was interrupted. Check your connection and try again.';

/// Shown when a downloaded file fails its checksum or size check.
const String kDownloadCorruptMessage =
    'The download was damaged and was removed. Try again.';

/// True when [error] means "no network" rather than "the server said no".
///
/// `package:http` wraps the underlying `SocketException` in a
/// [http.ClientException] on some platforms, so the message is checked too.
bool looksOffline(Object error) {
  if (error is SocketException) return true;
  if (error is http.ClientException) {
    final m = error.message.toLowerCase();
    return m.contains('socketexception') ||
        m.contains('failed host lookup') ||
        m.contains('network is unreachable') ||
        m.contains('no address associated') ||
        m.contains('nodename nor servname');
  }
  return false;
}

/// `dir/name` with the platform separator (no dependency on `package:path`).
String joinPath(Directory dir, String name) {
  final base = dir.path;
  final sep = Platform.pathSeparator;
  if (base.endsWith('/') || base.endsWith(r'\')) return '$base$name';
  return '$base$sep$name';
}

/// The last path segment of [path], for either separator.
String baseName(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? path : path.substring(i + 1);
}

/// Debug-only trace; release builds stay silent.
void logUpdate(String message) {
  if (kDebugMode) debugPrint('[update] $message');
}
