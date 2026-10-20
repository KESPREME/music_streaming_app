// lib/widgets/home_collection_play_disc.dart
//
// The quick-play disc on an album or playlist card (YouTube Music's pattern: a
// play button in the artwork's bottom-right corner). The card's tap opens the page;
// this plays it without opening anything.
//
// An album has no videoId, so its songs are fetched first: the disc spins while
// that happens, then plays from the first song. If the songs cannot be loaded it
// says so. No backdrop blur - a rail of blurred discs is the GPU cost this app
// keeps avoiding; a tinted dark disc with a hairline reads as glass on artwork.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../presentation/home/home_collections.dart';
import '../providers/music_provider.dart';
import '../services/home/home_models.dart';
import 'glass_snackbar.dart';
import 'jelly_press.dart';

class HomeCollectionPlayDisc extends StatefulWidget {
  const HomeCollectionPlayDisc({super.key, required this.item, this.size = 34});

  final HomeItem item;

  /// The visible disc. The touch target is [target], always at least 44.
  final double size;

  static const double target = 44;

  @override
  State<HomeCollectionPlayDisc> createState() => _HomeCollectionPlayDiscState();
}

class _HomeCollectionPlayDiscState extends State<HomeCollectionPlayDisc> {
  bool _busy = false;

  Future<void> _play() async {
    if (_busy) return;
    final provider = context.read<MusicProvider>();
    // The navigator outlives this card (a rebuild or a scroll can drop the card
    // while the songs are still loading).
    final host = Navigator.of(context).context;
    setState(() => _busy = true);
    final tracks = await loadHomeCollectionTracks(provider, widget.item);
    if (mounted) setState(() => _busy = false);
    if (tracks.isEmpty) {
      if (host.mounted) showGlassSnackBar(host, "Couldn't load \"${widget.item.title}\"");
      return;
    }
    await provider.playTrackList(tracks, initialIndex: 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      // Its own node: without container the label merges into the card's, and a
      // screen reader would find one card with a tap and no separate Play button.
      container: true,
      button: true,
      label: 'Play ${widget.item.title}',
      excludeSemantics: true,
      child: JellyPress(
        profile: JellyProfile.circle,
        haptic: JellyHaptic.light,
        onTap: _play,
        child: SizedBox(
          width: HomeCollectionPlayDisc.target,
          height: HomeCollectionPlayDisc.target,
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
