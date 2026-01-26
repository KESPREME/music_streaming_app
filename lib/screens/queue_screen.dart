import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/track_tile.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context);
    final queue = musicProvider.queue;
    final currentTrack = musicProvider.currentTrack;
    
    // palette
    final Color domColor = musicProvider.paletteGenerator?.dominantColor?.color ?? const Color(0xFF1E1E1E);
    final Color darkColor = musicProvider.paletteGenerator?.darkMutedColor?.color ?? Colors.black;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Playback Queue', 
          style: GoogleFonts.splineSans(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20)
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (queue.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white70),
              tooltip: "Clear Queue",
              onPressed: () {
                _showClearDialog(context, theme, musicProvider);
              },
            ),
        ],
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.black.withOpacity(0.2)),
          ),
        ),
      ),
      body: Stack(
        children: [
          // 1. Dynamic Background
          Container(
             decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  domColor.withOpacity(0.8),
                  darkColor.withOpacity(0.9),
                  Colors.black,
                ],
              ),
            ),
          ),
          
          // 2. Queue Content
          SafeArea(
            child: queue.isEmpty
              ? _buildEmptyState(theme)
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(top: 10, bottom: 100, left: 16, right: 16),
                  physics: const BouncingScrollPhysics(),
                  itemCount: queue.length,
                  proxyDecorator: (child, index, animation) => Material(
                    color: Colors.transparent,
                    child: Container(
                       decoration: BoxDecoration(
                         color: Colors.white.withOpacity(0.1),
                         borderRadius: BorderRadius.circular(12),
                         boxShadow: [
                           BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0,4))
                         ]
                       ),
                       child: child
                    ),
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
                          color: Colors.redAccent.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
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
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(isActuallyPlaying ? 0.3 : 0.05)),
                        ),
                        child: Theme(
                          data: theme.copyWith(canvasColor: Colors.transparent), 
                          child: TrackTile(
                            key: ValueKey('${track.id}_$index'),
                            track: track,
                            isPlaying: isActuallyPlaying,
                            dense: true,
                            isInQueueContext: true,
                            onTap: () {
                               // Optional: Jump to playing this track
                            },
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
        ],
      )
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
     return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.02)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Icon(Icons.queue_music_rounded, size: 60, color: Colors.white.withOpacity(0.5)),
            ),
            const SizedBox(height: 24),
            Text(
              'Queue is Empty',
              style: GoogleFonts.splineSans(
                color: Colors.white.withOpacity(0.9),
                fontSize: 20,
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add songs to your queue\nto see them here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.splineSans(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
  }

  void _showClearDialog(BuildContext context, ThemeData theme, MusicProvider provider) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E).withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear Queue?', style: GoogleFonts.splineSans(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to remove all tracks from the queue?', 
          style: GoogleFonts.splineSans(color: Colors.white70)
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: GoogleFonts.splineSans(color: Colors.white)),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          TextButton(
            child: Text('Clear', style: GoogleFonts.splineSans(color: const Color(0xFFFF1744), fontWeight: FontWeight.bold)),
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
