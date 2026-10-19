// lib/widgets/playlist/playlist_cover_store.dart
//
// Choosing a cover from the device: pick an image, COPY it into the app's own
// folder, and keep that path. The original can be moved or deleted from the
// gallery without the playlist losing its picture.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'playlist_cover.dart';

/// Opens the system image picker and returns the stored copy's path, or null if
/// the listener cancelled or it could not be saved.
Future<String?> pickAndStorePlaylistCover() async {
  try {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: false);
    final picked = result?.files.single.path;
    if (picked == null) return null;

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}playlist_covers');
    if (!await dir.exists()) await dir.create(recursive: true);
    final dot = picked.lastIndexOf('.');
    final ext = dot > picked.lastIndexOf(Platform.pathSeparator) && dot >= 0
        ? picked.substring(dot).toLowerCase()
        : '.jpg';
    final target = File('${dir.path}${Platform.pathSeparator}cover_${DateTime.now().millisecondsSinceEpoch}$ext');
    await File(picked).copy(target.path);
    return target.path;
  } catch (e) {
    debugPrint('PlaylistCoverStore: pick failed: $e');
    return null;
  }
}

/// Deletes a stored cover that is no longer used. Only touches files this app
/// copied (inside `playlist_covers`), never anything else on the device.
Future<void> deleteStoredCover(String path) async {
  try {
    if (!isLocalImagePath(path) || !path.contains('playlist_covers')) return;
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
