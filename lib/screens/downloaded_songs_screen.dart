import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';

class DownloadedSongsScreen extends StatefulWidget {
  const DownloadedSongsScreen({super.key});

  @override
  State<DownloadedSongsScreen> createState() => _DownloadedSongsScreenState();
}

class _DownloadedSongsScreenState extends State<DownloadedSongsScreen> {
  List<Track> _downloadedTracks = [];
  bool _isLoading = true;
  late ScrollController _scrollController;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadDownloadedSongs();
  }

  void _onScroll() {
    final isScrolled = _scrollController.hasClients && _scrollController.offset > 10;
    if (isScrolled != _isScrolled) {
      setState(() {
        _isScrolled = isScrolled;
      });
    }
  }

  Future<void> _loadDownloadedSongs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
      final tracks = await musicProvider.getDownloadedTracks();

      setState(() {
        _downloadedTracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading downloaded songs: $e')),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
              ? [const Color(0xFF121212), const Color(0xFF1E1E1E), const Color(0xFF000000)]
              : [const Color(0xFFF7F7F7), const Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Consumer<MusicProvider>(
                  builder: (context, musicProvider, child) {
                    final downloadingTracks = musicProvider.currentlyDownloadingTracks;

                    return CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverAppBar(
                          surfaceTintColor: Colors.transparent,
                          backgroundColor: Colors.transparent,
                          floating: true,
                          pinned: true,
                          elevation: 0,
                          expandedHeight: 100,
                          leading: IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                            color: isDark ? Colors.white : Colors.black,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          flexibleSpace: ClipRRect(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                sigmaX: _isScrolled ? 10 : 0,
                                sigmaY: _isScrolled ? 10 : 0,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                color: _isScrolled ? Colors.black.withOpacity(0.5) : Colors.transparent,
                                child: FlexibleSpaceBar(
                                  titlePadding: const EdgeInsets.only(left: 50, bottom: 16),
                                  title: Text(
                                    'Downloaded',
                                    style: GoogleFonts.splineSans(
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black,
                                      fontSize: 20,
                                    ),
                                  ),
                                  background: Container(color: Colors.transparent),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_downloadedTracks.isEmpty && downloadingTracks.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.download_done_rounded,
                                    size: 80,
                                    color: Colors.white.withOpacity(0.1),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No downloaded songs yet',
                                    style: GoogleFonts.splineSans(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Download songs to listen offline',
                                    style: GoogleFonts.splineSans(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          // Currently downloading section
                          if (downloadingTracks.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: Text(
                                  'Downloading',
                                  style: GoogleFonts.splineSans(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          if (downloadingTracks.isNotEmpty)
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final track = downloadingTracks[index];
                                  final progress = musicProvider.downloadProgress[track.id] ?? 0.0;
                                  return _buildDownloadingItem(track, progress, musicProvider);
                                },
                                childCount: downloadingTracks.length,
                              ),
                            ),

                          // Downloaded section
                          if (_downloadedTracks.isNotEmpty)
                             SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8), // More top padding
                                child: Text(
                                  'Downloaded',
                                  style: GoogleFonts.splineSans(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          if (_downloadedTracks.isNotEmpty)
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final track = _downloadedTracks[index];
                                  return _buildDownloadedItem(track, musicProvider);
                                },
                                childCount: _downloadedTracks.length,
                              ),
                            ),
                        ],
                        const SliverPadding(padding: EdgeInsets.only(bottom: 120)), // Bottom padding
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildDownloadingItem(Track track, double progress, MusicProvider musicProvider) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          track.albumArtUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 56,
            height: 56,
            color: Colors.grey[850],
            child: const Icon(Icons.music_note, color: Colors.white30),
          ),
        ),
      ),
      title: Text(
        track.trackName,
        style: GoogleFonts.splineSans(color: Colors.white, fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E676)), // Green Accent
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 4),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.splineSans(color: Colors.white.withOpacity(0.5), fontSize: 12),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.cancel_rounded, color: Colors.white54),
        onPressed: () {
          musicProvider.cancelDownload(track.id);
        },
      ),
    );
  }

  Widget _buildDownloadedItem(Track track, MusicProvider musicProvider) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          track.albumArtUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 56,
            height: 56,
            color: Colors.grey[850],
            child: const Icon(Icons.music_note, color: Colors.white30),
          ),
        ),
      ),
      title: Text(
        track.trackName,
        style: GoogleFonts.splineSans(color: Colors.white, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        track.artistName,
        style: GoogleFonts.splineSans(color: Colors.white.withOpacity(0.6), fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
           IconButton(
            icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
            onPressed: () {
              musicProvider.playOfflineTrack(track); // Assuming this method handles setting the queue properly for offline
            },
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: Colors.white.withOpacity(0.5)),
            onPressed: () async {
               // Add confirmation dialog if needed
               await musicProvider.deleteDownloadedTrack(track.id);
               _loadDownloadedSongs(); 
            },
          ),
        ],
      ),
      onTap: () => musicProvider.playOfflineTrack(track),
    );
  }
}
