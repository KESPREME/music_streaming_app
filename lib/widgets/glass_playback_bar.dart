import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../theme/glass_tokens.dart';
import 'glass_options_sheet.dart';
import 'glass_player_control.dart';
import 'glass_surface.dart';
import 'wavy_progress_bar.dart';

class GlassPlaybackBar extends StatelessWidget {
  final Track track;
  final MusicProvider provider;
  final Color accentColor;

  const GlassPlaybackBar({
    super.key,
    required this.track,
    required this.provider,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!provider.isMiniPlayerVisible) return const SizedBox.shrink();

    return GlassSurface(
      tier: GlassTier.floating,
      borderRadius: GlassTokens.radiusCard,
      padding: const EdgeInsets.fromLTRB(
        GlassTokens.hMargin,
        10,
        GlassTokens.hMargin,
        30,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Wavy Progress Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: WavyProgressBar(
              provider: provider,
              accentColor: accentColor,
            ),
          ),

          const SizedBox(height: 4),

          // 2. Control Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Share
              Semantics(
                label: 'Share',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.share_outlined, color: Colors.white70),
                  tooltip: 'Share',
                  onPressed: () {
                    SharePlus.instance.share(
                      ShareParams(
                        text:
                            'Listening to ${track.trackName} by ${track.artistName}',
                      ),
                    );
                  },
                ),
              ),

              // Playback Controls
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassPlayerControl(
                    icon: Icons.skip_previous_rounded,
                    onPressed: provider.skipToPrevious,
                    semanticLabel: 'Previous track',
                    tooltip: 'Previous track',
                  ),
                  const SizedBox(width: 20),
                  GlassPlayerControl(
                    icon: provider.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    onPressed: () {
                      if (provider.isPlaying) {
                        provider.pauseTrack();
                      } else {
                        provider.resumeTrack();
                      }
                    },
                    semanticLabel: provider.isPlaying ? 'Pause' : 'Play',
                    tooltip: provider.isPlaying ? 'Pause' : 'Play',
                    selected: true,
                    primary: true,
                  ),
                  const SizedBox(width: 20),
                  GlassPlayerControl(
                    icon: Icons.skip_next_rounded,
                    onPressed: provider.skipToNext,
                    semanticLabel: 'Next track',
                    tooltip: 'Next track',
                  ),
                ],
              ),

              // Options
              Semantics(
                label: 'More options',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.more_vert_rounded,
                      color: Colors.white70),
                  tooltip: 'More options',
                  onPressed: () {
                    GlassOptionsSheet.show(context, track: track);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
