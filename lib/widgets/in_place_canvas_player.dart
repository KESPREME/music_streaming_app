import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/track.dart';
import '../services/canvas_video_manager.dart';

/// In-place looping animated cover art (canvas video) player matching BitChord
/// and Apple Music motion artwork architecture.
///
/// Mounts silently directly inside the hero artwork slot on the normal player screen,
/// keeping the still album art underneath and crossfading in when the first frame is ready.
class InPlaceCanvasPlayer extends StatefulWidget {
  final Track track;
  final bool isPlaying;
  final BoxFit fit;
  final ValueChanged<bool>? onRenderedChanged;

  const InPlaceCanvasPlayer({
    required this.track,
    required this.isPlaying,
    this.fit = BoxFit.cover,
    this.onRenderedChanged,
    super.key,
  });

  @override
  State<InPlaceCanvasPlayer> createState() => _InPlaceCanvasPlayerState();
}

class _InPlaceCanvasPlayerState extends State<InPlaceCanvasPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    CanvasVideoManager.instance.isRenderedNotifier.addListener(_onRenderedStateChanged);
    _initForTrack();
  }

  void _onRenderedStateChanged() {
    final rendered = CanvasVideoManager.instance.isRendered;
    widget.onRenderedChanged?.call(rendered);
    if (rendered) {
      _fadeController.forward();
    } else {
      _fadeController.reset();
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant InPlaceCanvasPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.track.id != oldWidget.track.id) {
      _initForTrack();
    } else if (widget.isPlaying != oldWidget.isPlaying) {
      CanvasVideoManager.instance.setPlaying(widget.isPlaying);
    }
  }

  @override
  void dispose() {
    CanvasVideoManager.instance.isRenderedNotifier.removeListener(_onRenderedStateChanged);
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _initForTrack() async {
    _fadeController.reset();
    widget.onRenderedChanged?.call(false);
    await CanvasVideoManager.instance.attachTrack(
      widget.track,
      isPlaying: widget.isPlaying,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerController?>(
      valueListenable: CanvasVideoManager.instance.controllerNotifier,
      builder: (context, controller, child) {
        if (controller == null || !controller.value.isInitialized) {
          return const SizedBox.shrink();
        }

        final videoSize = controller.value.size;
        if (videoSize.width <= 0 || videoSize.height <= 0) {
          return const SizedBox.shrink();
        }

        return FadeTransition(
          opacity: _fadeAnimation,
          child: SizedBox.expand(
            child: FittedBox(
              fit: widget.fit,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: videoSize.width,
                height: videoSize.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}
