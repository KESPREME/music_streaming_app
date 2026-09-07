import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/track.dart';
import '../themed_options_sheet.dart';

/// Multi-column horizontal pager grid for artist Top Songs matching BitChord and Screenshot 7.
///
/// 4 songs per column, up to 20 songs, horizontally scrollable so browsing top songs
/// does not push the discography carousels off screen.
class TopSongsPagerGrid extends StatelessWidget {
  final List<Track> songs;
  final Function(List<Track> queue, int index) onSongTap;
  final Track? currentTrack;
  final bool isPlaying;
  final Color accentColor;

  const TopSongsPagerGrid({
    super.key,
    required this.songs,
    required this.onSongTap,
    this.currentTrack,
    this.isPlaying = false,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();

    final top = songs.take(20).toList();
    // Chunk into groups of 4
    final columns = <List<Track>>[];
    for (var i = 0; i < top.length; i += 4) {
      columns.add(top.sublist(i, (i + 4 > top.length) ? top.length : i + 4));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final columnWidth = screenWidth * 0.88;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: Text(
            'Top songs',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: 4 * 60.0, // 4 rows of 60dp each
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: columns.length,
            itemBuilder: (context, colIndex) {
              final column = columns[colIndex];
              return Container(
                width: columnWidth,
                margin: const EdgeInsets.only(right: 12.0),
                child: Column(
                  children: column.map((song) {
                    final songIndex = top.indexOf(song);
                    final isCurrent = currentTrack?.id == song.id;

                    return SizedBox(
                      height: 60,
                      child: InkWell(
                        onTap: () => onSongTap(top, songIndex),
                        onLongPress: () {
                          ThemedOptionsSheet.show(context, track: song);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6.0,
                            vertical: 5.0,
                          ),
                          child: Row(
                            children: [
                              // 48x48 Squircle artwork thumbnail
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  color: Colors.white.withValues(alpha: 0.08),
                                  child: CachedNetworkImage(
                                    imageUrl: song.albumArt,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Icon(
                                      Icons.music_note_rounded,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Title & Artist
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.trackName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: isCurrent ? accentColor : Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      song.artistName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // More ⋮ button
                              IconButton(
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: Colors.white.withValues(alpha: 0.5),
                                  size: 20,
                                ),
                                onPressed: () {
                                  ThemedOptionsSheet.show(context, track: song);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
