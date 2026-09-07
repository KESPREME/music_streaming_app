import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/music_provider.dart';
import '../models/track.dart';
import '../utils/color_utils.dart';
import '../utils/image_quality_utils.dart';
import '../widgets/animated_equalizer_icon.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/global_music_overlay.dart';
import '../widgets/themed_album_detail_screen.dart';

class ArtistDetailScreen extends StatefulWidget {
  final String artistId;
  final String artistName;
  final String? artistImage;
  final bool searchByName;

  const ArtistDetailScreen({
    super.key,
    required this.artistId,
    required this.artistName,
    this.artistImage,
    this.searchByName = false,
  });

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  bool _isLoading = true;
  List<Track> _topSongs = [];
  List<dynamic> _albums = [];
  List<dynamic> _singles = [];
  String? _error;
  String? _resolvedArtistImage;

  @override
  void initState() {
    super.initState();
    _resolvedArtistImage = widget.artistImage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchDetails();
      }
    });
  }

  Future<void> _fetchDetails() async {
    if (!mounted) return;
    try {
      final provider = Provider.of<MusicProvider>(context, listen: false);
      String artistIdToFetch = widget.artistId;

      if (widget.searchByName ||
          widget.artistId.isEmpty ||
          widget.artistId.startsWith('artist_') ||
          !widget.artistId.contains('UC')) {
        await provider.fetchArtistTracks(widget.artistName)
            .timeout(const Duration(seconds: 10));

        final results = provider.artistTracks;
        if (results.isNotEmpty) {
          final exactMatch = results.firstWhere(
            (track) => track.artistName.toLowerCase() == widget.artistName.toLowerCase(),
            orElse: () => results.first,
          );
          artistIdToFetch = exactMatch.id;
          if (_resolvedArtistImage == null || _resolvedArtistImage!.isEmpty) {
            _resolvedArtistImage = exactMatch.albumArtUrl;
          }
        } else {
          if (mounted) {
            setState(() {
              _error = 'Could not find artist: ${widget.artistName}';
              _isLoading = false;
            });
          }
          return;
        }
      }

      if (artistIdToFetch.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'Could not find artist: ${widget.artistName}';
            _isLoading = false;
          });
        }
        return;
      }

      final details = await provider.fetchArtistDetails(artistIdToFetch)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      setState(() {
        _topSongs = (details['tracks'] as List?)?.cast<Track>() ?? [];
        _albums = details['albums'] ?? [];
        _singles = details['singles'] ?? [];
        _isLoading = false;
        _error = null;
        if ((_resolvedArtistImage == null || _resolvedArtistImage!.isEmpty) && _topSongs.isNotEmpty) {
          _resolvedArtistImage = _topSongs.first.albumArtUrl;
        }
      });
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = 'Request timed out. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load artist details.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final palette = musicProvider.paletteGenerator;
    final accentColor = ColorUtils.getVibrantAccent(
      palette,
      Theme.of(context).colorScheme.primary,
    );

    return PlayerAwarePopScope(
      child: Scaffold(
        backgroundColor: const Color(0xFF08080A),
        body: Stack(
          children: [
            // 1. Ambient blurred artist photo wash
            if (_resolvedArtistImage != null && _resolvedArtistImage!.isNotEmpty)
              Positioned.fill(
                child: RepaintBoundary(
                  child: ClipRect(
                    child: Transform.scale(
                      scale: 1.35,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                        child: CachedNetworkImage(
                          imageUrl: ImageQualityUtils.getHighResArtwork(_resolvedArtistImage!),
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 2. Liquid gradient merge overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.30),
                      Colors.black.withValues(alpha: 0.65),
                      const Color(0xFF08080A).withValues(alpha: 0.95),
                      const Color(0xFF08080A),
                    ],
                    stops: const [0.0, 0.35, 0.70, 1.0],
                  ),
                ),
              ),
            ),

            // 3. Scrollable content
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildSliverAppBar(context),
                if (_isLoading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    ),
                  )
                else if (_error != null && _topSongs.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off_rounded, size: 56, color: Colors.white.withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isLoading = true;
                                  _error = null;
                                });
                                _fetchDetails();
                              },
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  // Artist Hero Header
                  SliverToBoxAdapter(
                    child: _buildArtistHero(context, accentColor),
                  ),

                  // Top Songs Section
                  if (_topSongs.isNotEmpty) ...[
                    _buildSectionHeader('Top Songs'),
                    _buildTopSongsList(context, musicProvider, accentColor),
                  ],

                  // Albums Section
                  if (_albums.isNotEmpty) ...[
                    _buildSectionHeader('Albums'),
                    _buildAlbumsCarousel(_albums),
                  ],

                  // Singles & EPs Section
                  if (_singles.isNotEmpty) ...[
                    _buildSectionHeader('Singles & EPs'),
                    _buildAlbumsCarousel(_singles),
                  ],

                  const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.5),
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  Widget _buildArtistHero(BuildContext context, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        children: [
          // Circular Hero Avatar with glowing halo
          Center(
            child: Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.60),
                    blurRadius: 28,
                    spreadRadius: -4,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.30),
                    blurRadius: 36,
                    spreadRadius: -6,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_resolvedArtistImage != null && _resolvedArtistImage!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: ImageQualityUtils.getHighResArtwork(_resolvedArtistImage!),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildAvatarPlaceholder(),
                      )
                    else
                      _buildAvatarPlaceholder(),

                    // Subtle refractive glass ring
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Artist Name with Verified Badge
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  widget.artistName,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.verified_rounded, color: accentColor, size: 20),
            ],
          ),

          const SizedBox(height: 4),

          Text(
            'Artist',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 18),

          // Action Buttons: Play Pill, Shuffle, Radio
          if (_topSongs.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Shuffle
                _buildCircleButton(
                  icon: Icons.shuffle_rounded,
                  semanticLabel: 'Shuffle',
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    final shuffled = List<Track>.from(_topSongs)..shuffle();
                    final provider = Provider.of<MusicProvider>(context, listen: false);
                    provider.playTrack(shuffled.first, playlistTracks: shuffled);
                  },
                ),

                const SizedBox(width: 14),

                // Hero Play Pill
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    final provider = Provider.of<MusicProvider>(context, listen: false);
                    provider.playTrack(_topSongs.first, playlistTracks: _topSongs);
                  },
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
                        const SizedBox(width: 6),
                        Text(
                          'Play',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                // Artist Radio
                _buildCircleButton(
                  icon: Icons.radio_rounded,
                  semanticLabel: 'Artist Radio',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final provider = Provider.of<MusicProvider>(context, listen: false);
                    if (_topSongs.isNotEmpty) {
                      provider.playTrack(_topSongs.first);
                      showGlassSnackBar(context, 'Starting radio for ${widget.artistName}');
                    }
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAvatarPlaceholder() {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: const Center(
        child: Icon(Icons.person_rounded, size: 64, color: Colors.white24),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
        child: Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildTopSongsList(
    BuildContext context,
    MusicProvider provider,
    Color accentColor,
  ) {
    final count = _topSongs.length > 5 ? 5 : _topSongs.length;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final track = _topSongs[index];
            final isCurrent = provider.currentTrack?.id == track.id;
            final isActuallyPlaying = isCurrent && provider.isPlaying;
            final rankNumber = index + 1;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: isCurrent ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                leading: SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(
                    child: isCurrent
                        ? AnimatedEqualizerIcon(
                            isPlaying: isActuallyPlaying,
                            color: accentColor,
                            size: 15,
                          )
                        : Text(
                            '$rankNumber',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white.withValues(alpha: 0.50),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                title: Text(
                  track.trackName,
                  style: GoogleFonts.plusJakartaSans(
                    color: isCurrent ? accentColor : Colors.white,
                    fontSize: 15,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  track.albumName.isNotEmpty ? track.albumName : track.artistName,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (track.durationMs != null && track.durationMs! > 0)
                      Text(
                        _formatDuration(track.durationMs!),
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white.withValues(alpha: 0.40),
                          fontSize: 12,
                        ),
                      ),
                    IconButton(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 19,
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        GlassOptionsSheet.show(context, track: track);
                      },
                    ),
                  ],
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  provider.playTrack(track, playlistTracks: _topSongs);
                },
              ),
            );
          },
          childCount: count,
        ),
      ),
    );
  }

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, "0")}';
  }

  Widget _buildAlbumsCarousel(List<dynamic> items) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final name = item.name as String;
            final imageUrl = item.imageUrl as String;
            final id = item.id as String;

            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ThemedAlbumDetailScreen(
                      albumId: id,
                      albumName: name,
                      artistName: widget.artistName,
                      albumImage: imageUrl,
                    ),
                  ),
                );
              },
              child: Container(
                width: 140,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(
                          imageUrl: ImageQualityUtils.getHighResArtwork(imageUrl),
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey[900],
                            child: const Icon(Icons.album_rounded, color: Colors.white24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
