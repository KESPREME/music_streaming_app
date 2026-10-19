// lib/widgets/playlist/playlist_cover.dart
//
// A playlist's picture, decided in one place so every screen agrees:
//
//   1. the cover the listener chose (a web image, or a file from the device);
//   2. otherwise a 2x2 of its first four distinct song covers;
//   3. otherwise the first song's cover;
//   4. otherwise a deep gradient with the playlist's initial, in a hue taken
//      from its name so two empty playlists are not the same grey square.

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/playlist.dart';
import '../../utils/app_image_cache.dart';
import '../../utils/image_quality_utils.dart';

/// True for a path on this device (as opposed to a web URL).
bool isLocalImagePath(String s) =>
    s.startsWith('/') || s.startsWith('file:') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(s);

/// The covers (distinct, non-empty) a playlist would collage, first four.
List<String> playlistCollageCovers(Playlist p) => p.tracks
    .map((t) => t.albumArtUrl)
    .where((u) => u.isNotEmpty)
    .toSet()
    .take(4)
    .toList(growable: false);

/// A stable, pleasant hue for [name].
Color playlistHue(String name) {
  final h = name.toLowerCase().codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.5, 0.32).toColor();
}

class PlaylistCover extends StatelessWidget {
  const PlaylistCover({
    super.key,
    required this.playlist,
    required this.size,
    this.radius = 14,
    this.shadow = false,
  });

  final Playlist playlist;
  final double size;
  final double radius;
  final bool shadow;

  Widget _net(String url, double s) => CachedNetworkImage(
        imageUrl: ImageQualityUtils.getHighResArtwork(url),
        width: s,
        height: s,
        fit: BoxFit.cover,
        memCacheWidth: s > 120 ? AppImageCache.cardMemCache : AppImageCache.thumbnailMemCache,
        fadeInDuration: const Duration(milliseconds: 160),
        placeholder: (_, __) => _fallback(),
        errorWidget: (_, __, ___) => _fallback(),
      );

  Widget _fallback() {
    final hue = playlistHue(playlist.name);
    final initial = playlist.name.trim().isEmpty ? '♪' : playlist.name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(hue, Colors.white, 0.18)!, hue, Color.lerp(hue, Colors.black, 0.55)!],
        ),
      ),
      child: Text(initial,
          style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.9), fontSize: size * 0.4, fontWeight: FontWeight.w800)),
    );
  }

  Widget _body() {
    final chosen = playlist.imageUrl;
    if (chosen.isNotEmpty) {
      if (isLocalImagePath(chosen)) {
        final path = chosen.startsWith('file:') ? Uri.parse(chosen).toFilePath() : chosen;
        return Image.file(File(path),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: AppImageCache.cardMemCache,
            errorBuilder: (_, __, ___) => _fallback());
      }
      return _net(chosen, size);
    }
    final covers = playlistCollageCovers(playlist);
    if (covers.length >= 4) {
      final half = size / 2;
      return SizedBox(
        width: size,
        height: size,
        child: Wrap(children: [for (final c in covers) _net(c, half)]),
      );
    }
    if (covers.isNotEmpty) return _net(covers.first, size);
    return _fallback();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 16, offset: const Offset(0, 8))]
            : null,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: _body()),
    );
  }
}
