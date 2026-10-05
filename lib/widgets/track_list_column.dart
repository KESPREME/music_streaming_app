import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../presentation/home/home_tokens.dart' as t;

/// One compact row: artwork, title, artist, overflow.
///
/// The overflow button exists only here. In card mode there is nowhere to put it
/// without covering artwork, and a long press still reaches the same sheet, so
/// nothing is lost by dropping it - it is simply not offered where it does not
/// fit.
class TrackListRow extends StatelessWidget {
  const TrackListRow({
    super.key,
    required this.track,
    required this.onPlay,
    required this.onOptions,
    this.isPlaying = false,
  });

  final Track track;
  final VoidCallback onPlay;
  final VoidCallback onOptions;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: t.HomeTokens.rowVerticalPadding),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(t.HomeTokens.rowArtRadius),
            child: SizedBox(
              width: t.HomeTokens.rowArtSize,
              height: t.HomeTokens.rowArtSize,
              child: track.albumArtUrl.isNotEmpty
                  ? Image.network(
                      track.albumArtUrl,
                      fit: BoxFit.cover,
                      // The artwork is an identifier here. If it fails, a blank
                      // tile still reads as a row; a broken-image glyph reads
                      // as an error the user has to dismiss mentally.
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.music_note_rounded,
                            size: 18, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.music_note_rounded,
                          size: 18, color: theme.colorScheme.onSurfaceVariant),
                    ),
            ),
          ),
          const SizedBox(width: t.HomeTokens.rowArtGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.trackName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.HomeTokens.compactTitle(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: isPlaying
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.HomeTokens.compactMetadata(context)
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: t.HomeTokens.rowArtGap),
          SizedBox(
            width: t.HomeTokens.rowOverflowSize,
            height: t.HomeTokens.rowOverflowSize,
            child: IconButton(
              onPressed: onOptions,
              padding: EdgeInsets.zero,
              iconSize: 19,
              tooltip: 'More options',
              icon: Icon(Icons.more_vert_rounded,
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal rail of fixed-height columns of [TrackListRow].
///
/// Paging by column rather than by item is what makes this read as a list rather
/// than as one very long row: four rows land in one column, the next column
/// peeks, and the eye reads down-then-across the way a printed tracklist does.
///
/// The height is set by the tallest column, so a short tail column does not
/// leave a ragged bottom edge.
class TrackListColumns extends StatelessWidget {
  const TrackListColumns({
    super.key,
    required this.tracks,
    required this.onPlay,
    required this.onOptions,
    this.isPlaying,
  });

  final List<Track> tracks;
  final void Function(Track) onPlay;
  final void Function(Track) onOptions;
  final bool Function(Track)? isPlaying;

  @override
  Widget build(BuildContext context) {
    final perColumn = t.HomeTokens.tracksPerColumn;

    final columns = <List<Track>>[];
    for (var i = 0; i < tracks.length; i += perColumn) {
      columns.add(tracks.sublist(
          i, (i + perColumn).clamp(0, tracks.length)));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = t.HomeTokens.trackColumnWidth(constraints.maxWidth);
        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
              horizontal: t.HomeTokens.contentPadding),
          physics: const BouncingScrollPhysics(),
          itemCount: columns.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(
                  right: t.HomeTokens.trackColumnGap),
              child: SizedBox(
                width: columnWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final track in columns[index])
                      TrackListRow(
                        track: track,
                        onPlay: () => onPlay(track),
                        onOptions: () => onOptions(track),
                        isPlaying: isPlaying?.call(track) ?? false,
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Height [TrackListColumns] reserves, for a section that must lay out before
/// its content exists.
///
/// Exported rather than re-derived at the call site because a skeleton or a
/// header that guesses this number differently from the real thing produces
/// exactly the jump the reservation exists to prevent.
double trackListColumnsHeight(BuildContext context, int trackCount) {
  final perColumn = t.HomeTokens.tracksPerColumn;
  // As tall as the TALLEST column, and never taller.
  //
  // Columns scroll horizontally, so the row count does not stack: nine tracks
  // are two columns of 4 and 5 side by side, still 4 rows tall. Rounding up to
  // a multiple of [tracksPerColumn] - as if they stacked - reserved a whole
  // dead column for every column past the first, which is what left a
  // screen-tall hole under a four-row list.
  final rows = trackCount <= 0 ? perColumn : math.min(trackCount, perColumn);
  // Each row is artwork plus its vertical padding; rows never share that space.
  return rows *
      (t.HomeTokens.rowArtSize + t.HomeTokens.rowVerticalPadding * 2);
}

/// The transform for a [TrackListColumns] body swapping layouts lives in
/// `home_layout_switch.dart`, next to the switch that applies it.
