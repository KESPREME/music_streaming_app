// lib/widgets/collection_play_disc.dart
//
// The quick-play disc on an album or playlist card (YouTube Music's pattern: a
// play button in the artwork's bottom-right corner). The card's tap opens the
// page; this plays it without opening anything.
//
// The songs may have to be fetched first (an album has no videoId; a playlist from
// the account is a request away), so the disc spins while that happens, then plays
// from the first song. If the songs cannot be loaded it says so. No backdrop blur -
// a rail of blurred discs is the GPU cost this app keeps avoiding; a tinted dark
// disc with a hairline reads as glass on artwork.
//
// Used by Home (feed albums and playlists, the listener's own playlists) and by the
// Library (own and account playlists).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import 'glass_snackbar.dart';
import 'jelly_press.dart';

/// How to start [tracks]. The default plays them in order from the first.
typedef CollectionPlay = Future<void> Function(MusicProvider provider, List<Track> tracks);

class CollectionPlayDisc extends StatefulWidget {
  const CollectionPlayDisc({
    super.key,
    required this.title,
    required this.loadTracks,
    this.play,
    this.emptyMessage,
    this.size = 34,
  });

  /// Names the disc for a screen reader ("Play <title>") and the failure message.
  final String title;

  /// The collection's songs. Empty means they could not be had.
  final Future<List<Track>> Function() loadTracks;

  /// Overrides how playback starts (a playlist records that it was played).
  final CollectionPlay? play;

  /// Said when [loadTracks] returns nothing, instead of "Couldn't load" - an empty
  /// playlist loaded fine, there is just nothing in it.
  final String? emptyMessage;

  /// The visible disc. The touch target is [target], always at least 44.
  final double size;

  static const double target = 44;

  @override
  State<CollectionPlayDisc> createState() => _CollectionPlayDiscState();
}

class _CollectionPlayDiscState extends State<CollectionPlayDisc> {
  bool _busy = false;

  Future<void> _play() async {
    if (_busy) return;
    final provider = context.read<MusicProvider>();
    // The navigator outlives this card (a rebuild or a scroll can drop the card
    // while the songs are still loading).
    final host = Navigator.of(context).context;
    setState(() => _busy = true);
    List<Track> tracks;
    try {
      tracks = await widget.loadTracks();
    } catch (_) {
      tracks = const [];
    }
    if (mounted) setState(() => _busy = false);
    if (tracks.isEmpty) {
      if (host.mounted) {
        showGlassSnackBar(host, widget.emptyMessage ?? "Couldn't load \"${widget.title}\"");
      }
      return;
    }
    final custom = widget.play;
    if (custom != null) {
      await custom(provider, tracks);
    } else {
      await provider.playTrackList(tracks, initialIndex: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      // Its own node: without `container` the label merges into the card's, and a
      // screen reader would find one card with a tap and no separate Play button.
      container: true,
      button: true,
      label: 'Play ${widget.title}',
      excludeSemantics: true,
      child: JellyPress(
        profile: JellyProfile.circle,
        haptic: JellyHaptic.light,
        onTap: _play,
        child: SizedBox(
          width: CollectionPlayDisc.target,
          height: CollectionPlayDisc.target,
          child: Center(
            child: Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.52),
                border: Border.all(color: Colors.white.withValues(alpha: 0.30), width: 0.8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.30), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Center(
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(Icons.play_arrow_rounded, color: Colors.white, size: s * 0.62),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
