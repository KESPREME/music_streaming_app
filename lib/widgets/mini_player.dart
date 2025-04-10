import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../now_playing_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final currentTrack = musicProvider.currentTrack;

        if (currentTrack == null) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NowPlayingScreen(track: currentTrack),
              ),
            ).then((_) {
              // Force rebuild when returning from now playing screen
              (context as Element).markNeedsBuild();
            });
          },
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFF1D1D1D),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Progress bar with StreamBuilder for real-time updates
                StreamBuilder<Duration>(
                  stream: musicProvider.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final duration = musicProvider.duration;

                    return LinearProgressIndicator(
                      value: duration.inSeconds > 0
                          ? (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0)
                          : 0.0,
                      backgroundColor: Colors.grey[800],
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                      minHeight: 2,
                    );
                  },
                ),
                // Player content
                Expanded(
                  child: Row(
                    children: [
                      // Album Art
                      Container(
                        width: 50,
                        height: 50,
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.grey[800],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            currentTrack.albumArtUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.music_note,
                                color: Colors.white,
                                size: 30,
                              );
                            },
                          ),
                        ),
                      ),
                      // Track Info
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                currentTrack.trackName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                currentTrack.artistName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Play/Pause Button
                      IconButton(
                        icon: Icon(
                          musicProvider.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 30,
                        ),
                        onPressed: () {
                          if (musicProvider.isPlaying) {
                            musicProvider.pauseTrack();
                          } else {
                            musicProvider.resumeTrack();
                          }
                        },
                      ),
                      // Next Button
                      IconButton(
                        icon: const Icon(
                          Icons.skip_next,
                          color: Colors.white,
                          size: 30,
                        ),
                        onPressed: () {
                          musicProvider.skipToNext();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
