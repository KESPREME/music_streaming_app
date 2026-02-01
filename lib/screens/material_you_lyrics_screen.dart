import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../models/lyrics_entry.dart';
import '../utils/lyrics_utils.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouLyricsScreen extends StatefulWidget {
  const MaterialYouLyricsScreen({super.key});

  @override
  State<MaterialYouLyricsScreen> createState() => _MaterialYouLyricsScreenState();
}

class _MaterialYouLyricsScreenState extends State<MaterialYouLyricsScreen> {
  final ScrollController _scrollController = ScrollController();
  
  int _currentLineIndex = 0;
  bool _isUserScrolling = false;
  bool _autoScrollEnabled = true;
  Timer? _scrollResumeTimer;
  Timer? _positionUpdateTimer;
  String? _currentTrackId;
  
  final List<GlobalKey> _itemKeys = [];
  
  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLyrics();
      _startPositionUpdates();
    });
    
    _scrollController.addListener(_onScroll);
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    final provider = Provider.of<MusicProvider>(context, listen: false);
    final track = provider.currentTrack;
    
    if (track != null && _currentTrackId != track.id) {
      final wasNull = _currentTrackId == null;
      _currentTrackId = track.id;
      
      _currentLineIndex = 0;
      _itemKeys.clear();
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          provider.fetchLyrics(forceRefresh: !wasNull);
        }
      });
    }
  }
  
  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollResumeTimer?.cancel();
    _positionUpdateTimer?.cancel();
    super.dispose();
  }
  
  void _checkLyrics() {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    if (provider.currentTrack != null) {
      _currentTrackId = provider.currentTrack!.id;
      if (!provider.hasSyncedLyrics || provider.currentLyrics == null) {
        provider.fetchLyrics();
      } else {
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
    
    if (_isUserScrolling) {
      _scrollResumeTimer?.cancel();
      _scrollResumeTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isUserScrolling = false;
            _autoScrollEnabled = true;
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
    
    HapticFeedback.lightImpact();
    
    musicProvider.seekTo(Duration(milliseconds: entry.timeMs));
    
    setState(() {
      _currentLineIndex = index;
      _autoScrollEnabled = true;
      _isUserScrolling = false;
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrentLine());
  }
  
  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final track = musicProvider.currentTrack;
    final colorScheme = Theme.of(context).colorScheme;
    
    // Extract dynamic color
    final palette = musicProvider.paletteGenerator;
    final vibrantColor = palette?.vibrantColor?.color ?? MaterialYouTokens.primaryVibrant;
    
    return PopScope(
      canPop: true,
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity! > 300) { // Swipe Down to dismiss
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          backgroundColor: MaterialYouTokens.surfaceDark,
          appBar: AppBar(
            backgroundColor: MaterialYouTokens.surfaceDark,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 100, // Increased further to clear notch comfortably
            leading: Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 40.0), // Push down
              child: IconButton(
                icon: Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: colorScheme.onSurface),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            title: Padding(
              padding: const EdgeInsets.only(top: 40.0), // Push title down
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Text(
                   track?.trackName.toUpperCase() ?? 'LYRICS',
                   style: MaterialYouTypography.titleSmall(colorScheme.onSurface)
                       .copyWith(letterSpacing: 1.0),
                   maxLines: 1,
                   overflow: TextOverflow.ellipsis,
                 ),
                 if (track != null) ...[
                   const SizedBox(height: 4),
                   Text(
                     track.artistName,
                     style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
                     maxLines: 1,
                     overflow: TextOverflow.ellipsis,
                   ),
                 ],
                ],
              ),
            ),
            centerTitle: true,
            actions: [
            if (musicProvider.isLoadingLyrics)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 40, 16, 0), // Push down
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 40.0), // Push down
                child: IconButton(
                  icon: Icon(
                    _autoScrollEnabled ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                    color: _autoScrollEnabled 
                        ? vibrantColor 
                        : colorScheme.onSurfaceVariant,
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
              ),
          ],
        ),
        body: Stack(
          children: [
            _buildBody(context, musicProvider, colorScheme, vibrantColor),
            // Playback tile at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildPlaybackTile(context, musicProvider, track, colorScheme, vibrantColor),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildPlaybackTile(BuildContext context, MusicProvider provider, Track? track, ColorScheme colorScheme, Color vibrantColor) {
    if (track == null) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MaterialYouTokens.surfaceContainerDark,
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeLarge),
        boxShadow: const [
          MaterialYouTokens.elevation3,
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Album art
            ClipRRect(
              borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
              child: track.albumArt != null && track.albumArt!.isNotEmpty
                  ? Image.network(
                      track.albumArt!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholderArt(vibrantColor),
                    )
                  : _buildPlaceholderArt(vibrantColor),
            ),
            
            const SizedBox(width: 12),
            
            // Track info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.trackName,
                    style: MaterialYouTypography.titleSmall(colorScheme.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artistName,
                    style: MaterialYouTypography.bodySmall(colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Previous button
            IconButton(
              icon: const Icon(Icons.skip_previous_rounded),
              iconSize: 28,
              color: colorScheme.onSurface,
              onPressed: provider.skipToPrevious,
            ),
            
            // Play/Pause button
            Material(
              elevation: 2,
              surfaceTintColor: Colors.transparent, // FIX: No white tint
              color: vibrantColor,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () {
                  if (provider.isPlaying) {
                     provider.pauseTrack();
                  } else {
                     provider.resumeTrack();
                  }
                },
                customBorder: const CircleBorder(),
                child: Container(
                  height: 48,
                  width: 48,
                  alignment: Alignment.center,
                  child: Icon(
                    provider.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Next button
            IconButton(
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 28,
              color: colorScheme.onSurface,
              onPressed: provider.skipToNext,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderArt(Color vibrantColor) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: vibrantColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(MaterialYouTokens.shapeSmall),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: vibrantColor,
        size: 24,
      ),
    );
  }

  Widget _buildBody(BuildContext context, MusicProvider provider, ColorScheme colorScheme, Color vibrantColor) {
    if (provider.isLoadingLyrics) {
      return Center(
        child: Text(
          'Syncing lyrics...',
          style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
        ),
      );
    }
    
    if (provider.lyricsError != null || provider.currentLyrics == null || provider.currentLyrics!.isEmpty) {
      if (provider.currentLyrics == null) return const SizedBox();
      
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lyrics_rounded,
                size: 60,
                color: colorScheme.onSurface.withOpacity(0.1),
              ),
              const SizedBox(height: 16),
              Text(
                provider.lyricsError ?? 'No synced lyrics available',
                style: MaterialYouTypography.bodyLarge(colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => provider.fetchLyrics(forceRefresh: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: vibrantColor,
                  side: BorderSide(color: vibrantColor),
                ),
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    }
    
    return _buildLyricsList(context, provider.currentLyrics!, colorScheme, vibrantColor);
  }

  Widget _buildLyricsList(BuildContext context, List<LyricsEntry> lyrics, ColorScheme colorScheme, Color vibrantColor) {
    final screenHeight = MediaQuery.of(context).size.height;

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: screenHeight * 0.3,
        bottom: screenHeight * 0.3 + 100, // Extra padding for playback tile
        left: 20,
        right: 20,
      ),
      physics: const BouncingScrollPhysics(),
      itemCount: lyrics.length,
      itemBuilder: (context, index) {
        return _buildLyricLine(index, lyrics, colorScheme, vibrantColor);
      },
    );
  }
  
  void _scrollToCurrentLine() {
    if (_currentLineIndex >= 0 && _currentLineIndex < _itemKeys.length) {
      final key = _itemKeys[_currentLineIndex];
      final keyContext = key.currentContext;
      
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
        );
      } else {
        if (_scrollController.hasClients) {
          final screenHeight = MediaQuery.of(context).size.height;
          final paddingTop = screenHeight * 0.3;
          const double estimatedItemHeight = 100.0;
          
          final itemTop = paddingTop + (_currentLineIndex * estimatedItemHeight);
          final targetOffset = itemTop - (screenHeight / 2) + (estimatedItemHeight / 2);
          
          _scrollController.animateTo(
            targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOutCubic,
          );
        }
      }
    }
  }
  
  Widget _buildLyricLine(int index, List<LyricsEntry> lyrics, ColorScheme colorScheme, Color vibrantColor) {
    final entry = lyrics[index];
    final isCurrentLine = index == _currentLineIndex;
    final isPastLine = index < _currentLineIndex;
    
    if (entry.text.trim().isEmpty) return const SizedBox(height: 40);
    
    Key? key;
    if (index < _itemKeys.length) {
      key = _itemKeys[index];
    }
    
    return GestureDetector(
      key: key,
      onTap: () => _onLineTap(index, lyrics),
      behavior: HitTestBehavior.translucent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
          color: isCurrentLine 
              ? vibrantColor.withOpacity(0.1) 
              : Colors.transparent,
          border: Border.all(
            color: isCurrentLine 
                ? vibrantColor.withOpacity(0.3) 
                : Colors.transparent,
            width: 1.0,
          ),
        ),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          opacity: isCurrentLine ? 1.0 : (isPastLine ? 0.4 : 0.5),
          child: Text(
            entry.text,
            textAlign: TextAlign.center,
            style: MaterialYouTypography.headlineSmall(colorScheme.onSurface).copyWith(
              fontSize: 24,
              fontWeight: isCurrentLine ? FontWeight.w800 : FontWeight.w600,
              color: isCurrentLine 
                  ? vibrantColor 
                  : colorScheme.onSurface,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
