import 'package:flutter/material.dart';

import '../models/track.dart';
import 'playlist/add_to_playlist_sheet.dart';

/// "Add to a playlist..." for one song. Kept as the single entry point the
/// song options use; the sheet itself (new playlist first, many playlists at
/// once, "already in", search) lives in `playlist/add_to_playlist_sheet.dart`.
Future<void> showPlaylistSelectionDialog(
  BuildContext context,
  Track trackToAdd,
) =>
    showAddToPlaylistSheet(context, [trackToAdd]);
