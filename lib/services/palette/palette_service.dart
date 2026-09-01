import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../models/track.dart';

/// Artwork source decision returned by the injected [artSourceResolver].
class PaletteArtSource {
  final ImageProvider? provider;
  final bool isLocalFile;
  /// Non-null when a legacy artwork path was recovered and persisted.
  final String? recoveredArtPath;
  const PaletteArtSource({
    required this.provider,
    required this.isLocalFile,
    this.recoveredArtPath,
  });
}

/// Owns album-palette generation, caching (LRU 15) and track-race guarding.
///
/// The provider injects context: which image to analyze, whether the app is
/// backgrounded, where to feed album-adaptive accents, and the proactive
/// artwork-backfill hook. Zero playback knowledge.
class PaletteService extends ChangeNotifier {
  PaletteService({
    required this.artSourceResolver,
    required this.feedAlbumAccent,
    required this.isInBackground,
    required this.backfillArtwork,
  });

  final Future<PaletteArtSource> Function(Track track) artSourceResolver;
  final void Function(PaletteGenerator palette) feedAlbumAccent;
  final bool Function() isInBackground;
  final Future<void> Function(Track track) backfillArtwork;

  static const int _cacheLimit = 15;

  PaletteGenerator? _paletteGenerator;
  PaletteGenerator? get palette => _paletteGenerator;

  final Map<String, PaletteGenerator> _cache = {};

  void clear() {
    _paletteGenerator = null;
    notifyListeners();
  }

  void clearForEmptyArt() {
    _paletteGenerator = null;
    clearAlbumAccentOnEmptyArt?.call();
    notifyListeners();
  }

  /// Overridden by the owner when accent feeding must reset to null.
  void Function()? clearAlbumAccentOnEmptyArt;

  Future<void> updateForTrack(Track track) async {
    if (track.albumArtUrl.isEmpty) {
      _paletteGenerator = null;
      clearAlbumAccentOnEmptyArt?.call();
      notifyListeners();
      return;
    }

    // BATTERY: skip expensive palette work while backgrounded.
    if (isInBackground()) {
      if (kDebugMode) debugPrint('PaletteService: Skipping palette generation (background)');
      return;
    }

    final trackId = track.id;

    // 1. Cache hit for instant update.
    final cached = _cache[trackId];
    if (cached != null) {
      if (kDebugMode) debugPrint('PaletteService: Using cached palette for ${track.trackName}');
      _paletteGenerator = cached;
      feedAlbumAccent(cached);
      notifyListeners();
      return;
    }

    try {
      if (kDebugMode) debugPrint('PaletteService: Generating palette for ${track.trackName}...');

      final source = await artSourceResolver(track);
      ImageProvider? imageProvider = source.provider;
      if (imageProvider != null && source.recoveredArtPath != null) {
        if (kDebugMode) {
          debugPrint('PaletteService: Recovered legacy art for ${track.trackName}');
        }
      }

      imageProvider ??= NetworkImage(track.albumArtUrl);

      final gen = await PaletteGenerator.fromImageProvider(
        ResizeImage(imageProvider, width: 100, height: 100),
        maximumColorCount: 15,
      );

      // Strict check: only apply if the same track is still current.
      if (isCurrentTrack(trackId)) {
        _paletteGenerator = gen;
        feedAlbumAccent(gen);

        if (_cache.length > _cacheLimit) {
          _cache.remove(_cache.keys.first);
        }
        _cache[trackId] = gen;

        notifyListeners();
        if (kDebugMode) {
          debugPrint('PaletteService: Palette updated for ${track.trackName} (${source.isLocalFile ? "Local" : "Network"})');
        }

        // PROACTIVE: backfill local artwork for downloaded tracks.
        if (!source.isLocalFile) {
          unawaited(backfillArtwork(track));
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PaletteService: Error generating palette for ${track.trackName}: $e');
    }
  }

  /// Set by the owner so the service can race-guard without owning playback.
  bool Function(String trackId)? isCurrentTrackImpl;
  bool isCurrentTrack(String trackId) => isCurrentTrackImpl?.call(trackId) ?? false;
}
