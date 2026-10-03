import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../utils/app_image_cache.dart';
import '../../core/test_environment.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/track.dart';

/// Top floating liquid-glass island pill with 5 core actions and a
/// flowy fluid contextual dropdown menu (matching Muzo reference video).
class ExploreTopPill extends StatefulWidget {
  const ExploreTopPill({
    super.key,
    required this.track,
    required this.isPlaying,
    required this.isLiked,
    required this.accent,
    required this.onTogglePlay,
    required this.onToggleLike,
    required this.onOpenPlayer,
    required this.onOpenArtist,
    required this.onRefreshFeed,
    required this.onAddToPlaylist,
  });

  final Track? track;
  final bool isPlaying;
  final bool isLiked;
  final Color accent;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleLike;
  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenArtist;
  final VoidCallback onRefreshFeed;
  final VoidCallback onAddToPlaylist;

  @override
  State<ExploreTopPill> createState() => _ExploreTopPillState();
}

class _ExploreTopPillState extends State<ExploreTopPill> {
  bool _menuOpen = false;

  bool get _isTesting => TestEnvironment.isTesting;

  void _closeMenu() {
    if (_menuOpen) setState(() => _menuOpen = false);
  }

  void _toggleMenu() {
    HapticFeedback.selectionClick();
    setState(() => _menuOpen = !_menuOpen);
  }

  void _copySongLink(BuildContext context, Track track) {
    _closeMenu();
    final url = 'https://music.youtube.com/watch?v=${track.id}';
    Clipboard.setData(ClipboardData(text: url));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Song link copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xE61C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _shareSong(Track track) {
    _closeMenu();
    HapticFeedback.lightImpact();
    final shareText =
        'Listen to ${track.trackName} by ${track.artistName}\nhttps://music.youtube.com/watch?v=${track.id}';
    SharePlus.instance.share(ShareParams(text: shareText));
  }

  void _showSongCodeDialog(BuildContext context, Track track) {
    _closeMenu();
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _SongCodeDialog(track: track, accent: widget.accent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    return Stack(
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      children: [
        // Fullscreen tap barrier to dismiss dropdown when open
        if (_menuOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeMenu,
            ),
          ),

        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 1. Floating Capsule Island Pill with Soft-Body Liquid Glass Physics
            SizedBox(
              width: 260,
              height: 50,
              child: LiquidGlassLens(
                touch: _isTesting
                    ? null
                    : LiquidGlassTouch(
                        flex: const LiquidGlassFlex.pronounced().copyWith(
                          stretch: 22.0,
                          squeeze: 0.70,
                          lean: 0.50,
                          grip: 0.80,
                          holdScale: 0.045,
                          tapScale: 0.030,
                          compressInward: true,
                        ),
                      ),
                style: LiquidGlassStyle(
                  shape: LiquidGlassShape.continuousRoundedRectangle(
                    cornerRadius: 25.0,
                    borderWidth: 1.2,
                    borderColor: Colors.white.withValues(alpha: 0.40),
                    lightDirection: 135.0,
                    lightIntensity: 1.25,
                  ),
                  appearance: const LiquidGlassAppearance(
                    color: Color(0x18FFFFFF),
                    blur: LiquidGlassBlur(sigmaX: 20, sigmaY: 20),
                    saturation: 1.15,
                  ),
                  refraction: const LiquidGlassRefraction(
                    distortion: 0.12,
                    distortionWidth: 28,
                    magnification: 1.04,
                    chromaticAberration: 0.003,
                  ),
                ),
                child: Container(
                  width: 260,
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: const BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.40),
                        blurRadius: 18,
                        spreadRadius: 0,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Action 1: Star / Favorite
                      _PillIconButton(
                        icon: widget.isLiked
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: widget.isLiked ? widget.accent : Colors.white,
                        onTap: widget.onToggleLike,
                        tooltip: widget.isLiked ? 'Favorited' : 'Favorite',
                      ),
                      const SizedBox(width: 18),

                      // Action 2: Play / Pause
                      _PillIconButton(
                        icon: widget.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        onTap: widget.onTogglePlay,
                        tooltip: 'Playback toggle',
                      ),
                      const SizedBox(width: 18),

                      // Action 3: Up Arrow (Now Playing)
                      _PillIconButton(
                        icon: Icons.arrow_upward_rounded,
                        color: Colors.white,
                        onTap: widget.onOpenPlayer,
                        tooltip: 'Open Player',
                      ),
                      const SizedBox(width: 18),

                      // Action 4: Song Code / Muzo Code
                      _PillIconButton(
                        icon: Icons.grid_view_rounded,
                        color: Colors.white,
                        size: 21,
                        onTap: () {
                          if (track != null) _showSongCodeDialog(context, track);
                        },
                        tooltip: 'Song Code',
                      ),
                      const SizedBox(width: 18),

                      // Action 5: More Options (...) with flowy 90-degree transition
                      _PillIconButton(
                        icon: Icons.more_horiz_rounded,
                        color: Colors.white,
                        rotationTurns: _menuOpen ? 0.25 : 0.0,
                        onTap: _toggleMenu,
                        tooltip: 'More Options',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 2. Flowy Liquid Glass Dropdown Menu with Elastic Bounce Transition
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              reverseDuration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  alignment: Alignment.topRight,
                  scale: animation,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: _menuOpen && track != null
                  ? Column(
                      key: const ValueKey('top_menu_open'),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const SizedBox(height: 10),
                        _GlassDropdownMenu(
                          track: track,
                          onShare: () => _shareSong(track),
                          onAddToPlaylist: () {
                            _closeMenu();
                            widget.onAddToPlaylist();
                          },
                          onRefresh: () {
                            _closeMenu();
                            widget.onRefreshFeed();
                          },
                          onCopyLink: () => _copySongLink(context, track),
                          onViewArtist: () {
                            _closeMenu();
                            widget.onOpenArtist();
                          },
                          onSongCode: () => _showSongCodeDialog(context, track),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(key: ValueKey('top_menu_closed')),
            ),
          ],
        ),
      ],
    );
  }
}

class _PillIconButton extends StatefulWidget {
  const _PillIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
    this.size = 24.0,
    this.rotationTurns = 0.0,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;
  final double size;
  final double rotationTurns;

  @override
  State<_PillIconButton> createState() => _PillIconButtonState();
}

class _PillIconButtonState extends State<_PillIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.tooltip,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: SizedBox(
          width: 32,
          height: 48,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.86 : 1.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              child: AnimatedRotation(
                turns: widget.rotationTurns,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                child: Icon(
                  widget.icon,
                  color: widget.color,
                  size: widget.size,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted contextual liquid glass dropdown menu.
class _GlassDropdownMenu extends StatelessWidget {
  const _GlassDropdownMenu({
    required this.track,
    required this.onShare,
    required this.onAddToPlaylist,
    required this.onRefresh,
    required this.onCopyLink,
    required this.onViewArtist,
    required this.onSongCode,
  });

  final Track track;
  final VoidCallback onShare;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onRefresh;
  final VoidCallback onCopyLink;
  final VoidCallback onViewArtist;
  final VoidCallback onSongCode;

  bool get _isTesting => TestEnvironment.isTesting;

  @override
  Widget build(BuildContext context) {
    final artistLabel = track.artistName.length > 18
        ? '${track.artistName.substring(0, 16)}...'
        : track.artistName;

    return SizedBox(
      width: 224,
      height: 280,
      child: LiquidGlassLens(
        touch: _isTesting
            ? null
            : const LiquidGlassTouch(
                flex: LiquidGlassFlex.subtle(),
              ),
        style: LiquidGlassStyle(
          shape: LiquidGlassShape.continuousRoundedRectangle(
            cornerRadius: 22.0,
            borderWidth: 1.2,
            borderColor: Colors.white.withValues(alpha: 0.35),
            lightDirection: 135.0,
            lightIntensity: 1.2,
          ),
          appearance: const LiquidGlassAppearance(
            color: Color(0x22FFFFFF),
            blur: LiquidGlassBlur(sigmaX: 24, sigmaY: 24),
            saturation: 1.2,
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.10,
            distortionWidth: 24,
            magnification: 1.02,
            chromaticAberration: 0.002,
          ),
        ),
        child: Container(
          width: 224,
          height: 280,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.45),
                blurRadius: 28,
                spreadRadius: 0,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuItem(
                icon: Icons.share_rounded,
                label: 'Share Song',
                onTap: onShare,
              ),
              _MenuItem(
                icon: Icons.playlist_add_rounded,
                label: 'Add to Playlist',
                onTap: onAddToPlaylist,
              ),
              _MenuItem(
                icon: Icons.refresh_rounded,
                label: 'Refresh Feed',
                onTap: onRefresh,
              ),
              _MenuItem(
                icon: Icons.link_rounded,
                label: 'Copy Song Link',
                onTap: onCopyLink,
              ),
              _MenuItem(
                icon: Icons.person_outline_rounded,
                label: 'View Artist ($artistLabel)',
                onTap: onViewArtist,
              ),
              _MenuItem(
                icon: Icons.grid_view_rounded,
                label: 'Mine Music Code',
                onTap: onSongCode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.90)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Visual Song Code Dialog matching "Muzo Code" in video.
typedef _SongCodeDialog = SongCodeDialog;

class SongCodeDialog extends StatelessWidget {
  const SongCodeDialog({super.key, required this.track, required this.accent});

  final Track track;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 310,
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: const Color(0xF018181C),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.60),
              blurRadius: 40,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Track cover
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: track.albumArtUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: track.albumArtUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: AppImageCache.thumbnailMemCache,
                                memCacheHeight: AppImageCache.thumbnailMemCache,
                              )
                          : Container(color: Colors.white10),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    track.trackName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artistName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.70),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  // Stylized soundwave code bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(24, (i) {
                      final h = 8.0 + (i % 5) * 6.0;
                      return Container(
                        width: 3.5,
                        height: h,
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: accent,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 22),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(21),
                        color: Colors.white.withValues(alpha: 0.15),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 1.0,
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
