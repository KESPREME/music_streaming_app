import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../providers/theme_provider.dart'; // Add theme provider
import '../widgets/mini_player.dart'; // Glass mini player
import '../widgets/material_you_playback_bar.dart'; // Material You playback bar
import '../screens/themed_now_playing_screen.dart';
import '../utils/color_utils.dart';

class GlobalMusicOverlay extends StatefulWidget {
  final Widget child;

  const GlobalMusicOverlay({super.key, required this.child});

  @override
  State<GlobalMusicOverlay> createState() => _GlobalMusicOverlayState();
}

class _GlobalMusicOverlayState extends State<GlobalMusicOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _panelController;
  // FIX: Add HeroController for nested Navigator to prevent null check errors
  late HeroController _heroController;
  
  // Height of the phone screen
  double get screenHeight => MediaQuery.of(context).size.height;

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
        vsync: this,
        // FIX: Changed from 0ms to 300ms for smooth panel animations
        duration: const Duration(milliseconds: 300), 
        lowerBound: 0.0,
        upperBound: 1.0,
        value: 0.0 
    );
    
    // FIX: Initialize HeroController for nested Navigator
    _heroController = HeroController();
    
    // Sync with Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<MusicProvider>(context, listen: false);
      _panelController.addListener(() {
        final isExpanded = _panelController.value > 0.5;
        if (_GlobalMusicOverlayState._isExpanded != isExpanded) {
           _GlobalMusicOverlayState._isExpanded = isExpanded;
           provider.setPlayerExpanded(isExpanded);
        }
      });
    });
  }
  
  // Static Tracker to avoid race conditions with Provider listener updates
  static bool _isExpanded = false;

  @override
  void dispose() {
    _panelController.dispose();
    super.dispose();
  }

  // --- Gesture Handling ---

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    double sensitivity = details.primaryDelta! / screenHeight; 
    _panelController.value -= sensitivity;
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    double velocity = details.primaryVelocity!;
    double currentPos = _panelController.value;

    double target = 0.0; 

    if (velocity < -500 || (velocity.abs() < 500 && currentPos > 0.3)) {
      target = 1.0;
    }
    _animatePanelTo(target);
  }

  // Track last synced state to prevent animation loops
  bool? _lastSyncedExpanded;
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // FIX: Moved sync logic from build() to prevent rebuild loops
    // Use post-frame callback to avoid triggering during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = Provider.of<MusicProvider>(context, listen: false);
      final isExpanded = provider.isPlayerExpanded;
      
      // Only animate if state changed and not already at target
      if (_lastSyncedExpanded != isExpanded) {
        _lastSyncedExpanded = isExpanded;
        if (isExpanded && _panelController.value < 0.9 && !_panelController.isAnimating) {
          _animatePanelTo(1.0);
        } else if (!isExpanded && _panelController.value > 0.1 && !_panelController.isAnimating) {
          _animatePanelTo(0.0);
        }
      }
    });
  }

  void _animatePanelTo(double target) {
    _panelController.animateTo(
      target, 
      duration: const Duration(milliseconds: 400), 
      curve: Curves.easeOutCubic 
    );
    // Provider update happens in listener
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context); // Get theme provider
    final hasTrack = musicProvider.currentTrack != null;
    final isGlassTheme = themeProvider.isGlassmorphism; // Check if glass theme
    
    // FIX: Removed animation sync logic from build() - now in didChangeDependencies()

    return Stack(
      children: [
        // 1. The App Content (Navigator)
        widget.child,

        // Only show player stack if there is a track
        if (hasTrack)
          AnimatedBuilder(
            animation: _panelController,
            builder: (context, child) {
              final value = _panelController.value;
              final double topOffset = lerpDouble(screenHeight, 0, value)!;
              // FIX: Also hide mini player when bottom sheet flag is set
              final double miniPlayerOpacity = musicProvider.hideMiniPlayer 
                  ? 0.0 
                  : (1.0 - (value * 3)).clamp(0.0, 1.0); 

              return Stack(
                children: [
                   // A. Mini Player (Fades out) - Switch based on theme
                  Positioned(
                    left: 0, right: 0,
                    bottom: 0, 
                    child: Opacity(
                      opacity: miniPlayerOpacity,
                      child: IgnorePointer(
                        ignoring: miniPlayerOpacity < 0.1,
                        child: Material( // Fix: Material widget to prevent underlining
                          type: MaterialType.transparency,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onVerticalDragUpdate: _handleVerticalDragUpdate,
                                onVerticalDragEnd: _handleVerticalDragEnd,
                                child: isGlassTheme
                                    ? MiniPlayer(
                                        onExpand: () => _animatePanelTo(1.0),
                                      )
                                    : MaterialYouPlaybackBar(
                                        track: musicProvider.currentTrack!,
                                        provider: musicProvider,
                                        accentColor: ColorUtils.getVibrantAccent(
                                          musicProvider.paletteGenerator,
                                          const Color(0xFF00B4D8), // Light blue accent
                                        ),
                                      ),
                              ),
                              // Keeps the MiniPlayer floating above NavBars
                              const SizedBox(height: 100), 
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // B. Now Playing Screen (Slides Up)
                  Positioned(
                    top: topOffset,
                    left: 0, right: 0,
                    height: screenHeight,
                    child: Opacity(
                      opacity: (value > 0.01) ? 1.0 : 0.0, 
                      child: GestureDetector(
                        onVerticalDragUpdate: _handleVerticalDragUpdate,
                        onVerticalDragEnd: _handleVerticalDragEnd,
                        child: Navigator(
                          key: musicProvider.playerNavigatorKey, // Assign Key
                          // FIX: Add HeroController observer to prevent null check errors
                          observers: [_heroController],
                          onGenerateRoute: (settings) {
                            // FIX: Added null check for currentTrack
                            final track = musicProvider.currentTrack;
                            if (track == null) {
                              return MaterialPageRoute(
                                builder: (context) => const SizedBox.shrink(),
                              );
                            }
                            return MaterialPageRoute(
                              builder: (context) => Material( 
                                elevation: 0,
                                color: Colors.transparent, 
                                child: ThemedNowPlayingScreen(
                                  track: track,
                                  onMinimize: () => _animatePanelTo(0.0),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
          ),
      ],
    );
  }
}

class PlayerAwarePopScope extends StatelessWidget {
  final Widget child;
  
  const PlayerAwarePopScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final isPanelOpen = musicProvider.isPlayerExpanded;

    return PopScope(
      canPop: !isPanelOpen,
      onPopInvoked: (didPop) {
        if (didPop) return;
        
        if (isPanelOpen) {
           // Priority 1: Check if Player's Internal Navigator needs to pop (Sidebar/Lyrics/etc)
           final playerNav = musicProvider.playerNavigatorKey.currentState;
           if (playerNav != null && playerNav.canPop()) {
             playerNav.pop();
             return;
           }
        
           // Priority 2: Minimize Player
           musicProvider.setPlayerExpanded(false);
        }
      },
      child: child,
    );
  }
}
