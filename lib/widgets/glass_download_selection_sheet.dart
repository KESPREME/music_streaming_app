import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../theme/glass_tokens.dart';
import 'glass_surface.dart';
import 'glass_snackbar.dart';

class GlassDownloadSelectionSheet extends StatefulWidget {
  final List<Track> tracks;
  final String? playlistName;

  const GlassDownloadSelectionSheet({
    super.key,
    required this.tracks,
    this.playlistName,
  });

  @override
  State<GlassDownloadSelectionSheet> createState() =>
      _GlassDownloadSelectionSheetState();
}

class _GlassDownloadSelectionSheetState
    extends State<GlassDownloadSelectionSheet> {
  final Set<String> _selectedIds = {};
  bool _isAllSelected = false;

  @override
  void initState() {
    super.initState();
    // Initially select none? Or all? Usually "Select to Download" implies user wants to pick.
    // Let's start with empty selection to let user choose, or maybe select all if that's more convenient?
    // User requested "Select to Download", so manual selection is key.
    // Let's provide a "Select All" button/toggle.
  }

  void _toggleAll() {
    setState(() {
      if (_isAllSelected) {
        _selectedIds.clear();
        _isAllSelected = false;
      } else {
        _selectedIds.addAll(widget.tracks.map((t) => t.id));
        _isAllSelected = true;
      }
    });
  }

  void _downloadSelected(MusicProvider provider) {
    if (_selectedIds.isEmpty) return;

    final selectedTracks =
        widget.tracks.where((t) => _selectedIds.contains(t.id)).toList();
    provider.downloadTracks(selectedTracks);

    Navigator.pop(context);
    showGlassSnackBar(
      context,
      'Queued ${selectedTracks.length} tracks for download',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75, // Tall sheet
      child: GlassSurface(
        tier: GlassTier.sheet,
        borderRadius: GlassTokens.radiusSheet,
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Tracks',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (widget.playlistName != null)
                          Text(
                            'from ${widget.playlistName}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _toggleAll,
                    child: Text(
                      _isAllSelected ? 'Deselect All' : 'Select All',
                      style: GoogleFonts.plusJakartaSans(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, thickness: 0.5),

            // List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80), // Space for fab/bar
                itemCount: widget.tracks.length,
                itemBuilder: (context, index) {
                  final track = widget.tracks[index];
                  final isSelected = _selectedIds.contains(track.id);

                  return CheckboxListTile(
                    value: isSelected,
                    activeColor: colorScheme.onSurface,
                    checkColor: colorScheme.surface,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedIds.add(track.id);
                        } else {
                          _selectedIds.remove(track.id);
                        }
                        _isAllSelected =
                            _selectedIds.length == widget.tracks.length;
                      });
                    },
                    secondary: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        track.albumArtUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey[800],
                          width: 40,
                          height: 40,
                        ),
                      ),
                    ),
                    title: Text(
                      track.trackName,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artistName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    controlAffinity: ListTileControlAffinity.trailing,
                  );
                },
              ),
            ),

            // Action Button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: Consumer<MusicProvider>(
                  builder: (context, provider, _) {
                    return ElevatedButton(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : () => _downloadSelected(provider),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.onSurface,
                        foregroundColor: colorScheme.surface,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                        disabledBackgroundColor:
                            colorScheme.onSurface.withValues(alpha: 0.12),
                      ),
                      child: Text(
                        'Download ${_selectedIds.length} Tracks',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
