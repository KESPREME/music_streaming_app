import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/track.dart';
import '../providers/music_provider.dart';
import '../widgets/playlist_selection_dialog.dart';
import '../widgets/themed_playlist_detail_screen.dart';
import '../widgets/themed_queue_screen.dart';
import '../screens/material_you_equalizer_screen.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/artist_picker_sheet.dart';
import '../widgets/glass_player_control.dart';
import '../widgets/wavy_progress_bar.dart';
import '../main.dart';
import '../utils/color_utils.dart';
import '../theme/glass_tokens.dart';

/// Full-screen player with Muzo-style visual design.
///
/// Features:
/// - Pull-down handle at top (Muzo parity)
/// - Compact header with album art thumbnail, title, artist, actions
/// - Large centered album art
/// - Waveform visualizer
/// - Track info with like/download actions
/// - Wavy progress bar
/// - Player controls
/// - Footer actions
class NowPlayingScreen extends StatefulWidget {
  final Track track;
  final VoidCallback? onMinimize;

  const NowPlayingScreen({required this.track, this.onMinimize, super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  static const Color _defaultPrimaryColor = Color(0xFF6200EE);

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, musicProvider, child) {
        final currentTrack = musicProvider.currentTrack ?? widget.track;
        final palette = musicProvider.paletteGenerator;
        final accentColor =
            ColorUtils.getVibrantAccent(palette, _defaultPrimaryColor);
        final isPlaying = musicProvider.isPlaying;

        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: const Color(0xFF121212),
          body: Stack(
            children: [
              // Blurred album art background
              Positioned.fill(
                child: currentTrack.albumArtUrl.isEmpty
                    ? const ColoredBox(color: Color(0xFF121212))
                    : RepaintBoundary(
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: GlassTokens.playerBackdropBlur,
                            sigmaY: GlassTokens.playerBackdropBlur,
                          ),
                          child: SizedBox.expand(
                            child: _buildAlbumArtImage(currentTrack),
                          ),
                        ),
                      ),
              ),
              // Scrim overlay
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(
                    alpha: GlassTokens.playerScrimOpacity,
                  ),
                ),
              ),

              // Main content
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Pull-down handle + compact header
                    _buildPullDownHandle(context),
                    _buildCompactHeader(context, currentTrack, musicProvider),

                    // Body: Album art, visualizer, info, controls
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildAlbumArt(currentTrack),
                            const SizedBox(height: 8),
                            _buildWaveformVisualizer(musicProvider, accentColor),
                            const SizedBox(height: 8),
                            _buildTrackInfo(context, currentTrack, musicProvider, accentColor),
                            _buildProgressBar(context, musicProvider),
                            _buildPlayerControls(context, musicProvider, isPlaying),
                            _buildFooterActions(context, musicProvider, accentColor),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Pull-down handle (Muzo parity) ──────────────────────────────────────

  Widget _buildPullDownHandle(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        HapticFeedback.lightImpact();
        if (widget.onMinimize != null) {
          widget.onMinimize!();
        } else {
          if (Navigator.canPop(context)) Navigator.pop(context);
        }
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Center(
          child: Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
        ),
      ),
    );
  }

  // ── Compact header (Muzo parity) ────────────────────────────────────────

  Widget _buildCompactHeader(
      BuildContext context, Track track, MusicProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Album art thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: track.albumArtUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: track.albumArtUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 44,
                      height: 44,
                      color: Colors.grey[900],
                    ),
                  )
                : Container(
                    width: 44,
                    height: 44,
                    color: Colors.grey[900],
                  ),
          ),
          const SizedBox(width: 12),

          // Title and Artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.trackName,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  track.artistName,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Like button
          GlassPlayerControl(
            icon: provider.isSongLiked(track.id)
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            onPressed: () => provider.toggleLike(track),
            semanticLabel: 'Like',
            tooltip: 'Like track',
            selected: provider.isSongLiked(track.id),
            primary: false,
          ),

          const SizedBox(width: 4),

          // Options button
          GlassPlayerControl(
            icon: Icons.more_horiz,
            onPressed: () => _showOptionsBottomSheet(context, track, provider),
            semanticLabel: 'Options',
            tooltip: 'Open options',
            selected: false,
            primary: false,
          ),
        ],
      ),
    );
  }

  // ── Album art ───────────────────────────────────────────────────────────

  Widget _buildAlbumArt(Track track) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 32,
              spreadRadius: -4,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Hero(
            tag: 'albumArt_${track.id}',
            child: _buildAlbumArtImage(track),
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumArtImage(Track track) {
    final art = track.albumArtUrl;
    if (art.isEmpty) return _buildArtPlaceholder();
    if (!art.contains('://')) {
      final f = File(art);
      if (f.existsSync()) return Image.file(f, fit: BoxFit.cover);
    }
    return Image.network(art,
        fit: BoxFit.cover, errorBuilder: (c, e, s) => _buildArtPlaceholder());
  }

  Widget _buildArtPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child:
          const Icon(Icons.music_note_rounded, size: 80, color: Colors.white24),
    );
  }

  // ── Waveform visualizer ─────────────────────────────────────────────────

  Widget _buildWaveformVisualizer(MusicProvider provider, Color accentColor) {
    return SizedBox(
      height: 40,
      child: Center(
        child: _WaveformPlaceholder(
          isPlaying: provider.isPlaying,
          color: accentColor,
        ),
      ),
    );
  }

  // ── Track info ──────────────────────────────────────────────────────────

  Widget _buildTrackInfo(BuildContext context, Track track,
      MusicProvider provider, Color accentColor) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.trackName,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () async {
                      if (track.artistName.isNotEmpty &&
                          track.artistName != 'Unknown Artist') {
                        await ArtistPickerSheet.showIfNeeded(
                            context, provider, track.artistName);
                      }
                    },
                    child: Text(
                      track.artistName,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder<bool>(
                  future: provider.isTrackDownloaded(track.id),
                  builder: (context, snapshot) {
                    final isDownloaded = snapshot.data ?? false;
                    final isDownloading =
                        provider.isDownloading[track.id] ?? false;

                    if (isDownloading) {
                      return Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: accentColor),
                        ),
                      );
                    }

                    return GlassPlayerControl(
                      icon: isDownloaded
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                      onPressed: () async {
                        if (isDownloaded) {
                          showGlassSnackBar(context, 'Track already downloaded');
                        } else {
                          await provider.downloadTrack(track);
                        }
                      },
                      semanticLabel: 'Download',
                      tooltip: 'Download track',
                      selected: isDownloaded,
                      primary: false,
                    );
                  },
                ),
                GlassPlayerControl(
                  icon: provider.isSongLiked(track.id)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  onPressed: () => provider.toggleLike(track),
                  semanticLabel: 'Like',
                  tooltip: 'Like track',
                  selected: provider.isSongLiked(track.id),
                  primary: false,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ── Progress bar ────────────────────────────────────────────────────────

  Widget _buildProgressBar(BuildContext context, MusicProvider provider) {
    final accent = Theme.of(context).colorScheme.primary;
    return WavyProgressBar(
      provider: provider,
      accentColor: accent,
    );
  }

  // ── Player controls ─────────────────────────────────────────────────────

  Widget _buildPlayerControls(
      BuildContext context, MusicProvider provider, bool isPlaying) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GlassPlayerControl(
          icon: Icons.shuffle_rounded,
          onPressed: provider.toggleShuffle,
          semanticLabel: 'Shuffle',
          tooltip: 'Toggle shuffle',
          selected: provider.shuffleEnabled,
          primary: false,
        ),
        GlassPlayerControl(
          icon: Icons.skip_previous_rounded,
          onPressed: provider.skipToPrevious,
          semanticLabel: 'Previous track',
          tooltip: 'Previous track',
          selected: false,
          primary: false,
        ),
        GlassPlayerControl(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onPressed: () {
            if (provider.isPlaying) {
              provider.pauseTrack();
            } else {
              provider.resumeTrack();
            }
          },
          semanticLabel: isPlaying ? 'Pause' : 'Play',
          tooltip: isPlaying ? 'Pause' : 'Play',
          selected: true,
          primary: true,
        ),
        GlassPlayerControl(
          icon: Icons.skip_next_rounded,
          onPressed: provider.skipToNext,
          semanticLabel: 'Next track',
          tooltip: 'Next track',
          selected: false,
          primary: false,
        ),
        GlassPlayerControl(
          icon: provider.repeatMode == RepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          onPressed: provider.cycleRepeatMode,
          semanticLabel: 'Repeat',
          tooltip: 'Toggle repeat',
          selected: provider.repeatMode != RepeatMode.off,
          primary: false,
        ),
      ],
    );
  }

  // ── Footer actions ──────────────────────────────────────────────────────

  Widget _buildFooterActions(
      BuildContext context, MusicProvider provider, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassPlayerControl(
                icon: provider.isCasting
                    ? Icons.cast_connected_rounded
                    : Icons.cast_rounded,
                onPressed: () {
                  _showDevicesSheet(context, provider, accentColor);
                },
                semanticLabel: 'Cast',
                tooltip: 'Cast to device',
                selected: provider.isCasting,
                primary: false,
              ),
              const SizedBox(width: 4),
              Text(
                provider.isCasting ? 'Casting' : 'Devices',
                style: GoogleFonts.plusJakartaSans(
                  color: provider.isCasting ? accentColor : Colors.white60,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassPlayerControl(
                icon: Icons.playlist_play_rounded,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ThemedQueueScreen(),
                    ),
                  );
                },
                semanticLabel: 'Queue',
                tooltip: 'Open queue',
                selected: false,
                primary: false,
              ),
              const SizedBox(width: 4),
              Text(
                'Up Next',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white60,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Options bottom sheet ────────────────────────────────────────────────

  void _showOptionsBottomSheet(
      BuildContext context, Track track, MusicProvider musicProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      elevation: 0,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withValues(alpha: 0.7),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.1), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: SafeArea(
              child: Wrap(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  _buildOptionTile(
                      icon: Icons.playlist_add_rounded,
                      title: 'Add to Playlist',
                      onTap: () {
                        final rootContext = rootNavigatorKey.currentContext;
                        Navigator.pop(context);
                        if (rootContext != null && rootContext.mounted) {
                          showPlaylistSelectionDialog(rootContext, track);
                        }
                      }),
                  _buildOptionTile(
                      icon: Icons.share_rounded,
                      title: 'Share',
                      onTap: () async {
                        Navigator.pop(context);
                        String shareText =
                            'Listening to: ${track.trackName} by ${track.artistName}';
                        await SharePlus.instance.share(ShareParams(text: shareText));
                      }),
                  _buildOptionTile(
                      icon: Icons.album_rounded,
                      title: 'Go to Album',
                      onTap: () {
                        Navigator.pop(context);
                        if (widget.onMinimize != null) widget.onMinimize!();
                        final albumName = track.albumName.isNotEmpty
                            ? track.albumName
                            : track.trackName;
                        rootNavigatorKey.currentState?.push(MaterialPageRoute(
                          builder: (_) => ThemedPlaylistDetailScreen(
                            playlistId: '',
                            playlistName: albumName,
                            playlistImage: track.albumArtUrl,
                            searchAlbumByName: true,
                            artistNameHint: track.artistName,
                          ),
                        ));
                      }),
                  _buildOptionTile(
                      icon: Icons.person_rounded,
                      title: 'Go to Artist',
                      onTap: () async {
                        final musicProvider =
                            Provider.of<MusicProvider>(context, listen: false);
                        final rootContext = rootNavigatorKey.currentContext;
                        Navigator.pop(context);
                        if (widget.onMinimize != null) widget.onMinimize!();
                        if (rootContext != null && rootContext.mounted) {
                          await ArtistPickerSheet.showIfNeeded(
                            rootContext,
                            musicProvider,
                            track.artistName,
                          );
                        }
                      }),
                  _buildOptionTile(
                      icon: Icons.graphic_eq_rounded,
                      title: 'Equalizer',
                      onTap: () async {
                        final rootContext = rootNavigatorKey.currentContext;
                        Navigator.pop(context);
                        await Future.delayed(const Duration(milliseconds: 100));
                        if (rootContext != null && rootContext.mounted) {
                          Navigator.of(rootContext, rootNavigator: false).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const MaterialYouEqualizerScreen()),
                          );
                        }
                      }),
                  _buildOptionTile(
                      icon: Icons.timer_rounded,
                      title: 'Sleep Timer',
                      onTap: () {
                        final rootContext = rootNavigatorKey.currentContext;
                        Navigator.pop(context);
                        if (rootContext != null && rootContext.mounted) {
                          _showSleepTimerDialog(rootContext, musicProvider);
                        }
                      }),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile(
      {required IconData icon,
      required String title,
      required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title,
          style: GoogleFonts.plusJakartaSans(
              color: Colors.white, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }

  void _showSleepTimerDialog(
      BuildContext context, MusicProvider musicProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withValues(alpha: 0.7),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.1), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text("Sleep Timer",
                          style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ),
                    _buildTimerOption(
                        context, musicProvider, '15 Minutes', 15),
                    _buildTimerOption(
                        context, musicProvider, '30 Minutes', 30),
                    _buildTimerOption(context, musicProvider, '1 Hour', 60),
                    _buildTimerOption(
                        context, musicProvider, 'End of Track', 0),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimerOption(
      BuildContext context, MusicProvider provider, String title, int minutes) {
    return ListTile(
      title: Text(title,
          style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
      onTap: () {
        provider.setSleepTimer(minutes);
        Navigator.pop(context);
      },
    );
  }

  void _showDevicesSheet(
      BuildContext context, MusicProvider provider, Color accentColor) {
    provider.startCastingDiscovery();

    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withValues(alpha: 0.7),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: SizedBox(
                  height: 400,
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 20),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Connect to a Device',
                                style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            if (provider.isCasting)
                              TextButton(
                                onPressed: () {
                                  provider.disconnectCastDevice();
                                  Navigator.pop(context);
                                },
                                child: Text('Disconnect',
                                    style: GoogleFonts.plusJakartaSans(
                                        color: Colors.redAccent)),
                              )
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (provider.isSearchingDevices &&
                          provider.castDevices.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20.0),
                          child: CircularProgressIndicator(
                              color: Colors.white),
                        ),
                      Expanded(
                        child: Consumer<MusicProvider>(
                            builder: (context, provider, _) {
                          if (provider.castDevices.isEmpty &&
                              !provider.isSearchingDevices) {
                            return Center(
                                child: Text("No devices found",
                                    style: GoogleFonts.plusJakartaSans(
                                        color: Colors.white60)));
                          }
                          return ListView.builder(
                            itemCount: provider.castDevices.length,
                            itemBuilder: (context, index) {
                              final device = provider.castDevices[index];
                              final isConnected =
                                  provider.castService.connectedDevice
                                          ?.host ==
                                      device.host;

                              return ListTile(
                                leading: Icon(Icons.tv_rounded,
                                    color: isConnected
                                        ? accentColor
                                        : Colors.white),
                                title: Text(device.name,
                                    style: GoogleFonts.plusJakartaSans(
                                        color: isConnected
                                            ? accentColor
                                            : Colors.white)),
                                trailing: isConnected
                                    ? Icon(Icons.check_rounded,
                                        color: accentColor)
                                    : null,
                                onTap: () {
                                  provider.connectToCastDevice(device);
                                  Navigator.pop(context);
                                },
                              );
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).whenComplete(() {
      provider.stopCastingDiscovery();
    });
  }
}

/// Simple waveform placeholder that animates when playing.
class _WaveformPlaceholder extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const _WaveformPlaceholder({required this.isPlaying, required this.color});

  @override
  State<_WaveformPlaceholder> createState() => _WaveformPlaceholderState();
}

class _WaveformPlaceholderState extends State<_WaveformPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(_WaveformPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(24, (i) {
            final phase = (_controller.value * 6.28) + (i * 0.4);
            final h = 8.0 + (16.0 * (0.5 + 0.5 * sin(phase)));
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        );
      },
    );
  }
}
