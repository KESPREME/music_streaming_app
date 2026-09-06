import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/animated_equalizer_icon.dart';
import '../widgets/audio_quality_language_sheet.dart';
import '../utils/color_utils.dart';
import '../utils/image_quality_utils.dart';

/// Queue / Playing Next Screen with Apple Music / Muzo liquid glass design (Image 4).
class QueueScreen extends StatelessWidget {
  final VoidCallback? onMinimize;
  final Function(int)? onTabTap;
  final bool isEmbedded;

  const QueueScreen({
    super.key,
    this.onMinimize,
    this.onTabTap,
    this.isEmbedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final queue = musicProvider.queue;
    final currentTrack = musicProvider.currentTrack;
    final palette = musicProvider.paletteGenerator;
    final accentColor = ColorUtils.getVibrantAccent(
      palette,
      const Color(0xFFE89838), // Apple / Muzo gold-amber accent
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1. Blurred album art background (only when standalone)
          if (!isEmbedded) ...[
            const Positioned.fill(
              child: ColoredBox(color: Color(0xFF08080A)),
            ),
            if (currentTrack != null && currentTrack.albumArtUrl.isNotEmpty)
              Positioned.fill(
                child: RepaintBoundary(
                  child: ClipRect(
                    child: Transform.scale(
                      scale: 1.25,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: 65,
                          sigmaY: 65,
                        ),
                        child: SizedBox.expand(
                          child: _buildAlbumArtImage(currentTrack),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.65),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ],

          // 2. Queue content
          Positioned.fill(
            child: isEmbedded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mini track card header (Image 4)
                      if (currentTrack != null)
                        _buildTopMiniTrackHeader(
                          context,
                          currentTrack,
                          musicProvider,
                          accentColor,
                        ),

                      const SizedBox(height: 12),

                      // Pill buttons row: Shuffle, Repeat, Autoplay (∞), Repeat-One
                      _buildPillButtonsRow(context, musicProvider, accentColor),

                      const SizedBox(height: 18),

                      // "Playing Next" header row with subtext & Clear button
                      _buildPlayingNextHeader(context, musicProvider),

                      const SizedBox(height: 8),

                      // Reorderable queue list
                      Expanded(
                        child: queue.isEmpty
                            ? _buildEmptyState(context)
                            : _buildQueueList(
                                context,
                                queue,
                                currentTrack,
                                musicProvider,
                                accentColor,
                              ),
                      ),
                    ],
                  )
                : SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pull handle
                        _buildPullHandle(context),

                        // Mini track card header (Image 4)
                        if (currentTrack != null)
                          _buildTopMiniTrackHeader(
                            context,
                            currentTrack,
                            musicProvider,
                            accentColor,
                          ),

                        const SizedBox(height: 12),

                        // Pill buttons row: Shuffle, Repeat, Autoplay (∞), Repeat-One
                        _buildPillButtonsRow(context, musicProvider, accentColor),

                        const SizedBox(height: 18),

                        // "Playing Next" header row with subtext & Clear button
                        _buildPlayingNextHeader(context, musicProvider),

                        const SizedBox(height: 8),

                        // Reorderable queue list
                        Expanded(
                          child: queue.isEmpty
                              ? _buildEmptyState(context)
                              : _buildQueueList(
                                  context,
                                  queue,
                                  currentTrack,
                                  musicProvider,
                                  accentColor,
                                ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayingNextHeader(
    BuildContext context,
    MusicProvider musicProvider,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Playing Next',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Stack(
                alignment: Alignment.centerLeft,
                children: [
                  const Opacity(
                    opacity: 0.0,
                    child: Text('From Muzo'),
                  ),
                  Text(
                    'From Mine Music',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (musicProvider.canClearQueue)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showClearDialog(context, musicProvider);
              },
              child: Text(
                'Clear',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPullHandle(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        HapticFeedback.lightImpact();
        if (onMinimize != null) {
          onMinimize!();
        } else if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: Center(
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 6),
          width: 38,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }

  Widget _buildTopMiniTrackHeader(
    BuildContext context,
    Track track,
    MusicProvider provider,
    Color accentColor,
  ) {
    final isLiked = provider.isSongLiked(track.id);
    final topPadding = isEmbedded
        ? (MediaQuery.of(context).padding.top + 32.0)
        : 6.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, 4),
      child: Row(
        children: [
          // Album art thumbnail (tapping returns to normal album view)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTabTap?.call(1);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 46,
                height: 46,
                child: _buildAlbumArtImage(track),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Title & Artist (tapping returns to normal album view)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                onTabTap?.call(1);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.trackName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artistName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // Star button
          _buildCircleButton(
            icon: isLiked ? Icons.star_rounded : Icons.star_outline_rounded,
            iconColor: isLiked ? accentColor : Colors.white,
            semanticLabel: 'Favorite',
            onTap: () {
              HapticFeedback.lightImpact();
              provider.toggleLike(track);
            },
          ),

          const SizedBox(width: 8),

          // Multi-Language Audio & Quality Control button ("aあ")
          _buildCircleButtonWidget(
            semanticLabel: 'Pronunciation',
            child: Text(
              'aあ',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              AudioQualityLanguageSheet.show(context);
            },
          ),

          const SizedBox(width: 8),

          // Options button (3 vertical dots matching Image 4)
          _buildCircleButton(
            icon: Icons.more_vert_rounded,
            iconColor: Colors.white,
            semanticLabel: 'Options',
            onTap: () {
              HapticFeedback.lightImpact();
              GlassOptionsSheet.show(
                context,
                track: track,
                isInQueueContext: true,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPillButtonsRow(
    BuildContext context,
    MusicProvider provider,
    Color accentColor,
  ) {
    final shuffleActive = provider.shuffleEnabled;
    final repeatActive = provider.repeatMode == RepeatMode.all;
    final autoplayActive = provider.autoplayEnabled;
    final repeatOneActive = provider.repeatMode == RepeatMode.one;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          // 1. Shuffle
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: _buildPillButton(
                icon: Icons.shuffle_rounded,
                semanticLabel: 'Shuffle',
                isActive: shuffleActive,
                onTap: () {
                  HapticFeedback.selectionClick();
                  provider.toggleShuffle();
                },
              ),
            ),
          ),

          // 2. Repeat
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: _buildPillButton(
                icon: Icons.repeat_rounded,
                semanticLabel: 'Repeat',
                isActive: repeatActive,
                onTap: () {
                  HapticFeedback.selectionClick();
                  provider.cycleRepeatMode();
                },
              ),
            ),
          ),

          // 3. Autoplay / Infinite (∞)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: _buildPillButton(
                icon: Icons.all_inclusive_rounded,
                semanticLabel: 'Autoplay',
                isActive: autoplayActive,
                onTap: () {
                  HapticFeedback.selectionClick();
                  provider.toggleAutoplay();
                },
              ),
            ),
          ),

          // 4. Repeat One
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: _buildPillButton(
                icon: Icons.repeat_one_rounded,
                semanticLabel: 'Repeat One',
                isActive: repeatOneActive,
                onTap: () {
                  HapticFeedback.selectionClick();
                  provider.setRepeatMode(
                    repeatOneActive ? RepeatMode.off : RepeatMode.one,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillButton({
    required IconData icon,
    required String semanticLabel,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: isActive
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.16),
              width: 0.75,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildQueueList(
    BuildContext context,
    List<Track> queue,
    Track? currentTrack,
    MusicProvider musicProvider,
    Color accentColor,
  ) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      physics: const BouncingScrollPhysics(),
      itemCount: queue.length,
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        elevation: 8,
        child: child,
      ),
      itemBuilder: (context, index) {
        final track = queue[index];
        final bool isCurrent = currentTrack?.id == track.id;
        final bool isActuallyPlaying = isCurrent && musicProvider.isPlaying;

        return Dismissible(
          key: ValueKey('${track.id}_${index}_queue'),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) {
            musicProvider.removeFromQueue(track);
          },
          child: Container(
            key: ValueKey('container_${track.id}_$index'),
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isCurrent
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isCurrent
                  ? Border.all(
                      color: accentColor.withValues(alpha: 0.4),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              children: [
                // Album Art Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: _buildAlbumArtImage(track),
                  ),
                ),
                const SizedBox(width: 12),

                // Equalizer indicator if current track
                if (isCurrent) ...[
                  AnimatedEqualizerIcon(
                    isPlaying: isActuallyPlaying,
                    color: accentColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                ],

                // Title and Artist
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.trackName,
                          style: GoogleFonts.plusJakartaSans(
                            color: isCurrent ? accentColor : Colors.white,
                            fontSize: 15,
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artistName,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white.withValues(alpha: 0.60),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),

                // Drag Handle (Image 4: =)
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: Colors.white.withValues(alpha: 0.40),
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      // ignore: deprecated_member_use
      onReorder: (oldIndex, newIndex) {
        musicProvider.reorderQueueItem(oldIndex, newIndex);
      },
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color iconColor,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }

  Widget _buildCircleButtonWidget({
    required Widget child,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildAlbumArtImage(Track track) {
    final rawArt = track.albumArtUrl;
    if (rawArt.isEmpty) return _buildArtPlaceholder();
    final art = ImageQualityUtils.getHighResArtwork(rawArt);
    if (!art.contains('://')) {
      final f = File(art);
      if (f.existsSync()) return Image.file(f, fit: BoxFit.cover);
    }
    return CachedNetworkImage(
      imageUrl: art,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => _buildArtPlaceholder(),
    );
  }

  Widget _buildArtPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Icon(Icons.music_note, color: Colors.white30, size: 20),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.queue_music_rounded,
            size: 56,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Queue is empty',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Songs you play next will appear here',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context, MusicProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear Queue?',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to clear all upcoming songs?',
          style: GoogleFonts.plusJakartaSans(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(color: Colors.white60),
            ),
          ),
          TextButton(
            onPressed: () {
              provider.clearQueue();
              Navigator.pop(ctx);
              showGlassSnackBar(context, 'Queue cleared');
            },
            child: Text(
              'Clear',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
