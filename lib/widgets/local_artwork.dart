// lib/widgets/local_artwork.dart
//
// The embedded cover of a file on this device, read once through MediaStore and
// cached by the provider. A file with no cover gets a tinted note, in a hue
// taken from its album so a folder of uncovered files is not one grey wall.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import 'playlist/playlist_cover.dart' show playlistHue;

class LocalArtwork extends StatefulWidget {
  const LocalArtwork({super.key, required this.track, required this.size});

  final Track track;
  final double size;

  @override
  State<LocalArtwork> createState() => _LocalArtworkState();
}

class _LocalArtworkState extends State<LocalArtwork> {
  Future<Uint8List?>? _art;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _art ??= _load();
  }

  @override
  void didUpdateWidget(LocalArtwork old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id) _art = _load();
  }

  Future<Uint8List?> _load() {
    try {
      return context.read<MusicProvider>().localArtwork(widget.track.previewUrl.isNotEmpty ? widget.track.previewUrl : widget.track.id);
    } catch (_) {
      return Future.value(null);
    }
  }

  Widget _fallback() {
    final hue = playlistHue(widget.track.albumName.isEmpty ? widget.track.trackName : widget.track.albumName);
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(hue, Colors.white, 0.1)!, Color.lerp(hue, Colors.black, 0.55)!],
        ),
      ),
      child: Icon(Icons.music_note_rounded, color: Colors.white.withValues(alpha: 0.55), size: widget.size * 0.42),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _art,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) return _fallback();
        return Image.memory(
          bytes,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (_, __, ___) => _fallback(),
        );
      },
    );
  }
}
