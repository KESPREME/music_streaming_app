import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../widgets/track_tile.dart'; // Using the styled TrackTile

class QueueScreen extends StatelessWidget {
  const QueueScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context);
    final queue = musicProvider.queue;
    final currentTrack = musicProvider.currentTrack;

    return Scaffold(
      appBar: AppBar(
        title: Text('Playback Queue', style: theme.textTheme.headlineSmall),
        actions: [
          if (queue.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all_outlined),
              tooltip: "Clear Queue",
              onPressed: () {
                // Confirmation dialog before clearing
                showDialog(
                  context: context,
                  builder: (BuildContext dialogContext) => AlertDialog(
                    title: Text('Clear Queue?', style: theme.dialogTheme.titleTextStyle),
                    content: Text('Are you sure you want to remove all upcoming tracks from the queue?', style: theme.dialogTheme.contentTextStyle),
                    actions: [
                      TextButton(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                      TextButton(
                        child: Text('Clear', style: TextStyle(color: theme.colorScheme.error)),
                        onPressed: () {
                          musicProvider.clearQueue();
                          Navigator.pop(dialogContext);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: queue.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.queue_music_outlined, size: 80, color: theme.colorScheme.onSurface.withOpacity(0.4)),
                  const SizedBox(height: 20),
                  Text(
                    'Queue is Empty',
                    style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add songs to your queue to see them here.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ],
              ),
            )
          : ReorderableListView.builder(
              itemCount: queue.length,
              itemBuilder: (context, index) {
                final track = queue[index];
                // Check if this track from the queue is the currently playing track
                // This is important because the queue might contain the current track
                // if it was added explicitly via "Play Next" or "Add to Queue" while also being part of the main playlist.
                final bool isActuallyPlaying = currentTrack?.id == track.id && musicProvider.isPlaying;

                return Material( // Wrap with Material for InkWell splash effects if TrackTile doesn't have its own
                  key: ValueKey('${track.id}_$index'), // Corrected Unique key for reordering
                  color: Colors.transparent, // Make Material transparent
                  child: TrackTile(
                    track: track,
                    isPlaying: isActuallyPlaying, // Highlight if it's the one actually playing
                    dense: true, // Use dense variant for queue items
                    isInQueueContext: true, // Indicate this tile is in the queue
                    onTap: () {
                      // Tapping a track in queue should play it and remove preceding tracks from queue.
                      // This requires a new method in MusicProvider.
                      // musicProvider.playFromQueue(index);
                       ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Play from queue index $index (not fully implemented in provider)")),
                      );
                    },
                    // Add a trailing remove button or handle via swipe
                    // For now, PopupMenu in TrackTile can have "Remove from Queue"
                  ),
                );
              },
              onReorder: (oldIndex, newIndex) {
                musicProvider.reorderQueueItem(oldIndex, newIndex);
              },
              proxyDecorator: (Widget child, int index, Animation<double> animation) {
                return Material(
                  elevation: 4.0,
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  child: child,
                );
              },
            ),
    );
  }
}
