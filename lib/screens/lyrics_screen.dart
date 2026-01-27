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
import '../widgets/glass_playback_bar.dart';

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
  
  // Keys for robust scrolling
  final List<GlobalKey> _itemKeys = [];
  
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
       } else {
         // Ensure keys are initialized if lyrics exist
         _ensureKeys(provider.currentLyrics!.length);
       }
    }
  }

  void _ensureKeys(int count) {
    if (_itemKeys.length != count) {
      _itemKeys.clear();
      for (var i = 0; i < count; i++) {
        _itemKeys.add(GlobalKey());
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
              // Re-align when auto-scroll resumes
              if (_autoScrollEnabled) _scrollToCurrentLine();
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

    // Sync keys length
    _ensureKeys(lyrics.length);

    final positionMs = musicProvider.position.inMilliseconds;
    
    final newIndex = LyricsUtils.findCurrentLineIndex(lyrics, positionMs);
    
    if (newIndex != _currentLineIndex && newIndex >= 0) {
      setState(() {
        _currentLineIndex = newIndex;
      });
      
      if (_autoScrollEnabled && !_isUserScrolling) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
           if (mounted) _scrollToCurrentLine();
        });
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
    
    // Scroll to it
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentLine());
  }
  
  @override
  Widget build(BuildContext context) {
    // ... [Same build setup codes]
    final theme = Theme.of(context);
    final musicProvider = Provider.of<MusicProvider>(context);
    final track = musicProvider.currentTrack;
    
    // If track changed while screen open, trigger fetch
    if (track != null && _currentTrack?.id != track.id) {
       _currentTrack = track;
       WidgetsBinding.instance.addPostFrameCallback((_) => musicProvider.fetchLyrics());
    }

    // Dynamic Color Extraction (Matching NowPlayingScreen)
    final palette = musicProvider.paletteGenerator;
    
    List<Color> bgColors = [
       const Color(0xFF1E1B4B), // Top default
       const Color(0xFF111827), // Mid default
       const Color(0xFF0A0A0A), // Bot default
    ];
    Color accentColor = const Color(0xFF6200EE);

    if (palette != null) {
        final darkVibrant = palette.darkVibrantColor?.color;
        final vibrant = palette.vibrantColor?.color;
        final muted = palette.mutedColor?.color;
        final darkMuted = palette.darkMutedColor?.color;
        final dominant = palette.dominantColor?.color;

        final topColor = darkVibrant ?? darkMuted ?? dominant ?? const Color(0xFF1E1B4B);
        final middleColor = vibrant?.withOpacity(0.4) ?? muted?.withOpacity(0.4) ?? const Color(0xFF111827);
        const bottomColor = Color(0xFF0A0A0A);

        bgColors = [topColor, middleColor, bottomColor];
        accentColor = vibrant ?? dominant ?? const Color(0xFF6200EE);
    }
    
    return PopScope(
      canPop: true,
      child: Scaffold(
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
                  colors: bgColors,
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
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.15),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.6),
                              accentColor.withOpacity(0.05),
                            ],
                          ),
                          border: Border(
                            bottom: BorderSide(color: Colors.white.withOpacity(0.1), width: 0.5),
                          ),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header matching NowPlayingScreen height/padding
                              _buildHeader(context, track, musicProvider),
                            ],
                          ),
                        ),
                     ),
                  ),
               ),
            ),
            
            // 4. Glass Playback Bar (Bottom)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: track != null ? GlassPlaybackBar(
                track: track,
                provider: musicProvider,
                accentColor: accentColor, // Use dynamic color
              ) : const SizedBox(),
            ),
          ],
        ),
      ),
    );
  }

  // ... [Header widget code remains same, skipping for brevity in this tool call context logic if I could, but I must replace contiguous block]
  // Ideally, I should preserve _buildHeader unchanged, but let's re-include it concisely to be safe.
  
  Widget _buildHeader(BuildContext context, Track? track, MusicProvider provider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 16), // Increased top padding as requested
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
          
          // Auto-scroll toggle
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
      if (provider.currentLyrics == null) return const SizedBox(); // Wait for fetch
      
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
                 onPressed: () => provider.fetchLyrics(forceRefresh: true),
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

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
          stops: const [0.0, 0.15, 0.8, 1.0], 
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: FadeTransition(
        opacity: _fadeController,
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.only(
             top: screenHeight * 0.45, // Deeper start
             bottom: screenHeight * 0.5 + 160, // Extra padding for playback bar
             left: 20,
             right: 20
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
  
  // ROBUST SCROLL LOGIC
  void _scrollToCurrentLine() {
    if (_currentLineIndex >= 0 && _currentLineIndex < _itemKeys.length) {
      final key = _itemKeys[_currentLineIndex];
      final keyContext = key.currentContext;
      
      if (keyContext != null) {
        // Precise centering using Scrollable.ensureVisible
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.5, // Center vertically
          duration: const Duration(milliseconds: 350), // Snappier scroll for better sync
          curve: Curves.easeInOutCubic,
        );
      } else {
        // Fallback if item not rendered yet (e.g. far jump)
        if (_scrollController.hasClients) {
             final screenHeight = MediaQuery.of(context).size.height;
             final paddingTop = screenHeight * 0.45;
             const double estimatedItemHeight = 120.0; // Better average for large text
             
             // Calculate target offset to center the item
             // Offset = (ItemTop) - (HalfScreen) + (HalfItem)
             final itemTop = paddingTop + (_currentLineIndex * estimatedItemHeight);
             final targetOffset = itemTop - (screenHeight / 2) + (estimatedItemHeight / 2);
             
             _scrollController.animateTo(
               targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent), 
               duration: const Duration(milliseconds: 350), 
               curve: Curves.easeInOutCubic
             );
        }
      }
    }
  }
  
  Widget _buildLyricLine(int index, List<LyricsEntry> lyrics) {
    final entry = lyrics[index];
    final isCurrentLine = index == _currentLineIndex;
    final isPastLine = index < _currentLineIndex;
    
    if (entry.text.trim().isEmpty) return const SizedBox(height: 40);
    
    // Assign Key
    Key? key;
    if (index < _itemKeys.length) {
      key = _itemKeys[index];
    }
    
    return GestureDetector(
      key: key, // Attach GlobalKey
      onTap: () => _onLineTap(index, lyrics),
      behavior: HitTestBehavior.translucent, 
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic, // Liquid feel
        margin: const EdgeInsets.symmetric(
           vertical: 16, // Fixed vertical spacing to PREVENT layout jumps
           horizontal: 12, 
        ), 
        alignment: Alignment.center,
        child: AnimatedScale(
          scale: isCurrentLine ? 1.05 : 0.95, // Subtle, fluid scale
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            tween: Tween<double>(begin: 0, end: isCurrentLine ? 12.0 : 0.0),
            builder: (context, sigma, child) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      color: isCurrentLine 
                          ? Colors.white.withOpacity(0.06) // Very translucent
                          : Colors.transparent,
                      border: Border.all(
                        color: isCurrentLine 
                            ? Colors.white.withOpacity(0.12) 
                            : Colors.transparent,
                        width: 1.0,
                      ),
                      gradient: isCurrentLine 
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withOpacity(0.1),
                                Colors.white.withOpacity(0.02),
                              ],
                            )
                          : null,
                    ),
                    child: child,
                  ),
                ),
              );
            },
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              opacity: isCurrentLine ? 1.0 : (isPastLine ? 0.4 : 0.5),
              child: Text(
                entry.text,
                textAlign: TextAlign.center,
                style: GoogleFonts.splineSans(
                   fontSize: 26, // Slightly clearer text
                   fontWeight: isCurrentLine ? FontWeight.w800 : FontWeight.w600,
                   color: Colors.white,
                   height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
