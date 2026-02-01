import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/material_you_track_tile.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

/// Material You Queue Screen - Clean, flat design with NO blur
class MaterialYouQueueScreen extends StatelessWidget {
  const MaterialYouQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final musicProvider = Provider.of<MusicProvider>(context);
    final queue = musicProvider.queue;
    final currentTrack = musicProvider.currentTrack;

    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      appBar: AppBar(
        title: Text(
          'Playback Queue',
          style: MaterialYouTypography.headlineMedium(colorScheme.onSurface),
        ),
        centerTitle: true,
        backgroundColor: MaterialYouTokens.surfaceDark,
        elevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        actions: [
          if (queue.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded, color: colorScheme.onSurfaceVariant),
              tooltip: "Clear Queue",
              onPressed: () {
                _showClearDialog(context, colorScheme, musicProvider);
              },
            ),
        ],
      ),
      body: queue.isEmpty
          ? _buildEmptyState(colorScheme)
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(top: 10, bottom: 100, left: 8, right: 8),
              physics: const BouncingScrollPhysics(),
              itemCount: queue.length,
              proxyDecorator: (child, index, animation) => Material(
                elevation: 6,
                surfaceTintColor: Colors.transparent, // FIX: No white tint
                color: MaterialYouTokens.surfaceContainerDark,
                borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
                child: child,
              ),
              itemBuilder: (context, index) {
                final track = queue[index];
                final bool isActuallyPlaying = currentTrack?.id == track.id && musicProvider.isPlaying;

                return Dismissible(
                  key: ValueKey('${track.id}_${index}_queue'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  onDismissed: (direction) {
                    musicProvider.removeFromQueue(track);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isActuallyPlaying
                          ? MaterialYouTokens.primaryVibrant.withOpacity(0.08)
                          : MaterialYouTokens.surfaceVariantDark,
                      borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
                      border: Border.all(
                        color: isActuallyPlaying
                            ? MaterialYouTokens.primaryVibrant.withOpacity(0.3)
                            : Colors.transparent,
                      ),
                    ),
                    child: MaterialYouTrackTile(
                      key: ValueKey('${track.id}_$index'),
                      track: track,
                      isPlaying: isActuallyPlaying,
                      dense: true,
                      isInQueueContext: true,
                      onTap: () {
                        // Optional: Jump to playing this track
                      },
                      onOptionsPressed: () {
                        // Show options
                      },
                    ),
                  ),
                );
              },
              onReorder: (oldIndex, newIndex) {
                musicProvider.reorderQueueItem(oldIndex, newIndex);
              },
            ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.queue_music_rounded,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Queue is Empty',
            style: MaterialYouTypography.headlineLarge(colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'Add songs to your queue\nto see them here.',
            textAlign: TextAlign.center,
            style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context, ColorScheme colorScheme, MusicProvider provider) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: MaterialYouTokens.surfaceContainerDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MaterialYouTokens.shapeExtraLarge),
        ),
        title: Text(
          'Clear Queue?',
          style: MaterialYouTypography.headlineMedium(colorScheme.onSurface),
        ),
        content: Text(
          'Are you sure you want to remove all tracks from the queue?',
          style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: MaterialYouTypography.labelLarge(colorScheme.onSurfaceVariant),
            ),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Clear',
              style: MaterialYouTypography.labelLarge(Colors.white),
            ),
            onPressed: () {
              provider.clearQueue();
              Navigator.pop(dialogContext);
            },
          ),
        ],
      ),
    );
  }
}
