import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';
import '../widgets/glass_snackbar.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context);
    final queue = musicProvider.queue;
    final currentTrack = musicProvider.currentTrack;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Playback Queue',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        actions: [
          IconButton(
            icon: Icon(
              Icons.delete_sweep_rounded,
              color: colorScheme.onSurface.withValues(
                  alpha: musicProvider.canClearQueue ? 0.7 : 0.25),
            ),
            tooltip: "Clear Queue",
            onPressed: musicProvider.canClearQueue
                ? () {
                    _showClearDialog(context, theme, musicProvider);
                  }
                : null,
          ),
        ],
      ),
      body: SafeArea(
        child: queue.isEmpty
            ? _buildEmptyState(theme)
            : ReorderableListView.builder(
                padding: const EdgeInsets.only(
                  top: 10,
                  bottom: 100,
                  left: 16,
                  right: 16,
                ),
                physics: const BouncingScrollPhysics(),
                itemCount: queue.length,
                proxyDecorator: (child, index, animation) => Material(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  child: child,
                ),
                itemBuilder: (context, index) {
                  final track = queue[index];
                  final bool isActuallyPlaying =
                      currentTrack?.id == track.id && musicProvider.isPlaying;

                  return Dismissible(
                    key: ValueKey('${track.id}_${index}_queue'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: Icon(
                        Icons.delete_outline,
                        color: colorScheme.onError,
                      ),
                    ),
                    onDismissed: (direction) {
                      musicProvider.removeFromQueue(track);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActuallyPlaying
                              ? colorScheme.primary
                              : colorScheme.outline,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: Theme(
                          data: theme.copyWith(canvasColor: Colors.transparent),
                          child: TrackTile(
                            key: ValueKey('${track.id}_$index'),
                            track: track,
                            isPlaying: isActuallyPlaying,
                            dense: true,
                            isInQueueContext: true,
                            onTap: () async {
                              try {
                                await musicProvider.playTrack(
                                  track,
                                  setContext: false,
                                  clearQueue: false,
                                );
                              } catch (error) {
                                if (context.mounted) {
                                  showGlassSnackBar(
                                    context,
                                    'Could not play ${track.trackName}',
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  musicProvider.reorderQueueItem(oldIndex, newIndex);
                },
              ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surfaceContainerHighest,
              border: Border.all(color: colorScheme.outline),
            ),
            child: Icon(
              Icons.queue_music_rounded,
              size: 60,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Queue is Empty',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add songs to your queue\nto see them here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(
      BuildContext context, ThemeData theme, MusicProvider provider) {
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear Queue?',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to remove all tracks from the queue?',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          TextButton(
            child: Text(
              'Clear',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
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
