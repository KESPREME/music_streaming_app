// lib/screens/lyrics_screen.dart

// Features: cached loading, auto-scroll, tap-to-seek, animations, word highlighting

import 'dart:async';
import 'dart:ui' as ui; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../models/lyrics_entry.dart';
import '../utils/lyrics_utils.dart';

class LyricsScreen extends StatefulWidget {
  const LyricsScreen({super.key});

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  
  int _currentLineIndex = 0;
  bool _isUserScrolling = false;
  bool _autoScrollEnabled = true;
  Timer? _scrollResumeTimer;
  Timer? _positionUpdateTimer;
  Track? _currentTrack;
  
  // Animation controllers
  late AnimationController _fadeController;
  
  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    // Initial fetch/check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLyrics();
      _startPositionUpdates();
      _fadeController.forward();
    });
    
    // Listen for scroll to detect user scrolling
    _scrollController.addListener(_onScroll);
  }
  
  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollResumeTimer?.cancel();
    _positionUpdateTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }
  
  void _checkLyrics() {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    if (provider.currentTrack != null) {
       // If no synced lyrics or track changed, fetch
       if (!provider.hasSyncedLyrics || provider.currentLyrics == null) {
          provider.fetchLyrics(); // Fetch if not cached
       }
    }
  }

  void _onScroll() {
    if (!_isUserScrolling && _scrollController.position.isScrollingNotifier.value) {
      if (mounted) {
         setState(() {
          _isUserScrolling = true;
          _autoScrollEnabled = false;
        });
      }
    }
    
    // Resume auto-scroll after 3 seconds of no user scrolling
    if (_isUserScrolling) {
        _scrollResumeTimer?.cancel();
        _scrollResumeTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _isUserScrolling = false;
              _autoScrollEnabled = true;
            });
          }
        });
    }
  }
  
  void _startPositionUpdates() {
    _positionUpdateTimer = Timer.periodic(
      const Duration(milliseconds: 100), 
      (_) => _updateCurrentLine(),
    );
  }
  
  void _updateCurrentLine() {
    if (!mounted) return;
    
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final lyrics = musicProvider.currentLyrics;
    
    if (lyrics == null || lyrics.isEmpty) return;

    final positionMs = musicProvider.position.inMilliseconds;
    
    final newIndex = LyricsUtils.findCurrentLineIndex(lyrics, positionMs);
    
    if (newIndex != _currentLineIndex && newIndex >= 0) {
      setState(() {
        _currentLineIndex = newIndex;
      });
      
      if (_autoScrollEnabled && !_isUserScrolling) {
        _scrollToCurrentLine();
      }
    }
  }
  

  
  void _onLineTap(int index, List<LyricsEntry> lyrics) {
    if (index < 0 || index >= lyrics.length) return;
    
    final entry = lyrics[index];
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    
    // Haptic feedback
    HapticFeedback.lightImpact();
    
    // Seek to the line's timestamp
    musicProvider.seekTo(Duration(milliseconds: entry.timeMs));
    
    setState(() {
      _currentLineIndex = index;
      _autoScrollEnabled = true;
      _isUserScrolling = false;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context);
    final track = musicProvider.currentTrack;
    
    // If track changed while screen open, trigger fetch
    if (track != null && _currentTrack?.id != track.id) {
       _currentTrack = track;
       WidgetsBinding.instance.addPostFrameCallback((_) => musicProvider.fetchLyrics());
    }

    // Get colors from palette
    final Color domColor = musicProvider.paletteGenerator?.dominantColor?.color ?? const Color(0xFF1E1E1E);
    final Color darkColor = musicProvider.paletteGenerator?.darkMutedColor?.color ?? Colors.black;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black, // Fallback
      body: Stack(
        children: [
          // 1. Background Gradient
          AnimatedContainer(
            duration: const Duration(milliseconds: 800),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  domColor.withOpacity(0.6),
                  darkColor.withOpacity(0.8),
                  Colors.black,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
          
          // 2. Lyrics List (Behind Header)
          Positioned.fill(
             child: _buildBody(context, musicProvider),
          ),

          // 3. Header (Overlay with Blur)
          Positioned(
             top: 0, left: 0, right: 0,
             child: ClipRect(
                child: BackdropFilter(
                   filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                   child: Container(
                      color: Colors.black.withOpacity(0.4), // Semi-transparent background
                      child: SafeArea(
                        bottom: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 8), // Extra breathing room below notch
                            _buildHeader(context, track, musicProvider),
                          ],
                        ),
                      ),
                   ),
                ),
             ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Track? track, MusicProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
           // Back Button
           IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              highlightColor: Colors.white.withOpacity(0.2),
            ),
          ),
          
          // Title
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track?.trackName.toUpperCase() ?? 'LYRICS',
                  style: GoogleFonts.splineSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (track != null)
                  Text(
                    track.artistName,
                    style: GoogleFonts.splineSans(
                      fontSize: 12,
                      color: Colors.white60,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
          
          // Auto-scroll toggle or Loading indicator
          if (provider.isLoadingLyrics)
             const SizedBox(
               width: 32, height: 32,
               child: CircularProgressIndicator(color: Colors.white30, strokeWidth: 2),
             )
          else
            IconButton(
              icon: Icon(
                _autoScrollEnabled ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                color: _autoScrollEnabled ? Colors.white : Colors.white38,
              ),
              onPressed: () {
                 setState(() {
                   _autoScrollEnabled = !_autoScrollEnabled;
                   if (_autoScrollEnabled) {
                     _isUserScrolling = false;
                     _scrollToCurrentLine();
                   }
                 });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, MusicProvider provider) {
    if (provider.isLoadingLyrics) {
       return Center(child: Text('Syncing lyrics...', style: GoogleFonts.splineSans(color: Colors.white54)));
    }
    
    if (provider.lyricsError != null || provider.currentLyrics == null || provider.currentLyrics!.isEmpty) {
      // Error view (centered, needs padding for header)
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 100), // Avoid header
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_rounded, size: 60, color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 16),
              Text(
                 provider.lyricsError ?? 'No synced lyrics available',
                 style: GoogleFonts.splineSans(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                 onPressed: () => provider.fetchLyrics(),
                 style: OutlinedButton.styleFrom(
                   foregroundColor: Colors.white,
                   side: BorderSide(color: Colors.white.withOpacity(0.3)),
                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                 ),
                 child: const Text("Retry"),
              )
            ],
          ),
        ),
      );
    }
    
    return _buildLyricsList(context, provider.currentLyrics!);
  }

  Widget _buildLyricsList(BuildContext context, List<LyricsEntry> lyrics) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top + 80; // Header height approx

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
          stops: const [0.0, 0.15, 0.8, 1.0], // Increased top fade zone
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: FadeTransition(
        opacity: _fadeController,
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.only(
             top: screenHeight * 0.4, // Start lower down (Apple Music style)
             bottom: screenHeight * 0.5,
             left: 24,
             right: 24
          ),
          physics: const BouncingScrollPhysics(),
          itemCount: lyrics.length,
          itemBuilder: (context, index) {
            return _buildLyricLine(index, lyrics);
          },
        ),
      ),
    );
  }
  
  // Adjusted scroll logic
  void _scrollToCurrentLine() {
    if (!_scrollController.hasClients) return;
    
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Heuristic: Estimate line height + spacing. 
    // Large font (34) + Spacing (16) + Wrapping factor (~1.5 lines avg) ~= 80px
    const double estimatedLineHeight = 80.0; 
    
    // Target offset:
    // We want the current line to be roughly at 30% of screen height.
    // The list has large top padding (40% of screen).
    
    // Exact calculation is hard without keys, but let's tune the offset.
    // If we simply scroll to (index * height), the large top padding pushes it down.
    // We want scrollOffset = (index * height) roughly?
    
    final offset = (double.parse(_currentLineIndex.toString()) * estimatedLineHeight); 
    
    // Soft constraint
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 800), // Slower, smoother
      curve: Curves.linearToEaseOut, // Very smooth deceleration
    );
  }
  
  Widget _buildLyricLine(int index, List<LyricsEntry> lyrics) {
    final entry = lyrics[index];
    final isCurrentLine = index == _currentLineIndex;
    final isPastLine = index < _currentLineIndex;
    
    if (entry.text.trim().isEmpty) return const SizedBox(height: 40);
    
    return GestureDetector(
      onTap: () => _onLineTap(index, lyrics),
      behavior: HitTestBehavior.translucent, 
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 12), // More spacing
        alignment: Alignment.center, // Enforce center
        child: ConstrainedBox( // Fixed width constraint for readability
          constraints: const BoxConstraints(maxWidth: 340), // "Fixed width" requested
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            style: GoogleFonts.splineSans(
              fontSize: isCurrentLine ? 34 : 24, // Bigger fonts as requested
              fontWeight: isCurrentLine ? FontWeight.w800 : FontWeight.w600,
              color: isCurrentLine
                  ? Colors.white
                  : isPastLine
                      ? Colors.white38
                      : Colors.white60,
              height: 1.3,
              shadows: isCurrentLine ? [
                 Shadow(
                   color: Colors.black.withOpacity(0.5), // Stronger shadow for contrast
                   blurRadius: 30,
                   offset: const Offset(0, 4),
                 ),
                 Shadow(
                   color: Colors.white.withOpacity(0.2), // Glow
                   blurRadius: 10,
                   offset: const Offset(0, 0),
                 )
              ] : [],
            ),
            child: Text(
              entry.text,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
