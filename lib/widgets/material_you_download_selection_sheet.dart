import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouDownloadSelectionSheet extends StatefulWidget {
  final List<Track> tracks;
  final String? playlistName;

  const MaterialYouDownloadSelectionSheet({
    super.key,
    required this.tracks,
    this.playlistName,
  });

  @override
  State<MaterialYouDownloadSelectionSheet> createState() => _MaterialYouDownloadSelectionSheetState();
}

class _MaterialYouDownloadSelectionSheetState extends State<MaterialYouDownloadSelectionSheet> {
  final Set<String> _selectedIds = {};
  bool _isAllSelected = false;

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

    final selectedTracks = widget.tracks.where((t) => _selectedIds.contains(t.id)).toList();
    provider.downloadTracks(selectedTracks);
    
    Navigator.pop(context);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Downloading ${selectedTracks.length} tracks',
          style: MaterialYouTypography.bodyMedium(Theme.of(context).colorScheme.onInverseSurface),
        ),
        backgroundColor: Theme.of(context).colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Tracks',
                        style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
                      ),
                      if (widget.playlistName != null)
                        Text(
                          widget.playlistName!,
                          style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _toggleAll,
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                  ),
                  child: Text(_isAllSelected ? 'Deselect All' : 'Select All'),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: widget.tracks.length,
              itemBuilder: (context, index) {
                final track = widget.tracks[index];
                final isSelected = _selectedIds.contains(track.id);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      track.albumArtUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_,__,___) => Container(
                        width: 48,
                        height: 48,
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  title: Text(
                    track.trackName,
                    style: MaterialYouTypography.bodyLarge(colorScheme.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.artistName,
                    style: MaterialYouTypography.bodyMedium(colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Checkbox(
                    value: isSelected,
                    activeColor: colorScheme.primary,
                    checkColor: colorScheme.onPrimary,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selectedIds.add(track.id);
                        } else {
                          _selectedIds.remove(track.id);
                        }
                        _isAllSelected = _selectedIds.length == widget.tracks.length;
                      });
                    },
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedIds.remove(track.id);
                      } else {
                        _selectedIds.add(track.id);
                      }
                      _isAllSelected = _selectedIds.length == widget.tracks.length;
                    });
                  },
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
                  return FilledButton(
                    onPressed: _selectedIds.isEmpty ? null : () => _downloadSelected(provider),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    child: Text(
                      'Download ${_selectedIds.length} Tracks',
                      style: MaterialYouTypography.labelLarge(colorScheme.onPrimary).copyWith(fontSize: 16),
                    ),
                  );
                }
              ),
            ),
          ),
        ],
      ),
    );
  }
}
