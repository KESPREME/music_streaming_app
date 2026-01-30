import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/track.dart';
import '../widgets/liquid_card.dart'; 
import '../widgets/glass_options_sheet.dart'; // For long-press options
import '../home_tab_content.dart';
import 'trending_now_screen.dart'; 
import 'all_genres_screen.dart';   
import 'all_artists_screen.dart';  
import 'settings_screen.dart';     
import 'genre_songs_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      extendBody: true, 
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
              ? [const Color(0xFF141414), const Color(0xFF1E1E1E), const Color(0xFF000000)]
              : [const Color(0xFFF7F7F7), const Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
             children: [
               _buildCustomHeader(context),
               _buildCustomTabBar(context),
               Expanded(
                 child: TabBarView(
                   controller: _tabController,
                   children: [
                      _buildFeedTab(context),
                      _buildExploreTab(context),
                   ],
                 ),
               ),
             ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Discover',
            style: GoogleFonts.splineSans(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
          Container(
             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
             decoration: BoxDecoration(
               color: Colors.white.withOpacity(0.05),
               borderRadius: BorderRadius.circular(20),
               border: Border.all(color: Colors.white.withOpacity(0.1)),
             ),
             child: Row(
               children: [
                 const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFFFF1744)), // Red Accent
                 const SizedBox(width: 4),
                 GestureDetector(
                   onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                   child: const Icon(Icons.settings_outlined, size: 20, color: Colors.white),
                 ),
               ],
             ),
           ),
        ],
      ),
    );
  }
  
  Widget _buildCustomTabBar(BuildContext context) {
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
           expandedTabItem(0, "Feed"),
           expandedTabItem(1, "Explore"),
        ],
      ),
    );
  }
  
  Widget expandedTabItem(int index, String title) {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
         final selected = _tabController.index == index;
         return Expanded(
           child: GestureDetector(
             onTap: () => _tabController.animateTo(index),
             child: AnimatedContainer(
               duration: const Duration(milliseconds: 200),
               decoration: BoxDecoration(
                 color: selected ? Colors.white.withOpacity(0.1) : Colors.transparent,
                 borderRadius: BorderRadius.circular(24),
               ),
               alignment: Alignment.center,
               child: Text(
                 title,
                 style: GoogleFonts.splineSans(
                   fontSize: 15,
                   fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                   color: selected ? Colors.white : Colors.grey[500],
                 ),
               ),
             ),
           ),
         );
      }
    );
  }

  Widget _buildFeedTab(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    
    return RefreshIndicator(
      color: const Color(0xFFFF1744),
      backgroundColor: const Color(0xFF1E1E1E),
      onRefresh: () async {
        await musicProvider.fetchTracks(forceRefresh: true);
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 100),
        physics: const BouncingScrollPhysics(),
        children: [
           // 1. Recently Played (Horizontal)
           if (musicProvider.recentlyPlayed.isNotEmpty) ...[
             _buildSectionHeader("Jump Back In"),
             SizedBox(
               height: 190,
               child: ListView.builder(
                 padding: const EdgeInsets.symmetric(horizontal: 20),
                 scrollDirection: Axis.horizontal,
                 itemCount: musicProvider.recentlyPlayed.length,
                 physics: const BouncingScrollPhysics(),
                 itemBuilder: (context, index) {
                    final item = musicProvider.recentlyPlayed[index];
                    return LiquidCard(
                      imageUrl: item.albumArtUrl, 
                      title: item.trackName, 
                      subtitle: item.artistName,
                      width: 140, 
                      height: 140,
                      onTap: () => musicProvider.playTrack(item, playlistTracks: musicProvider.recentlyPlayed),
                      onLongPress: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => GlassOptionsSheet(
                            track: item,
                            isRecentlyPlayedContext: true,
                          ),
                        );
                      },
                    );
                 },
               ),
             ),
           ],
           
           // 2. For You (Vertical List)
           const SizedBox(height: 10),
           _buildSectionHeader("For You"),
           if (musicProvider.recommendedTracks.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFFFF1744)))),
           ...musicProvider.recommendedTracks.map((track) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: InkWell(
                  onTap: () => musicProvider.playTrack(track, playlistTracks: musicProvider.recommendedTracks),
                  onLongPress: () {
                    HapticFeedback.mediumImpact(); // Premium haptic feedback
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => GlassOptionsSheet(track: track),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04), // Glassy list
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            track.albumArtUrl,
                            width: 60, height: 60, fit: BoxFit.cover,
                            errorBuilder: (_,__,___) => Container(color: Colors.grey[800], width: 60, height: 60),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                               Text(
                                 track.trackName,
                                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                 maxLines: 1, overflow: TextOverflow.ellipsis,
                               ),
                               const SizedBox(height: 4),
                               Text(
                                 track.artistName,
                                 style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                                 maxLines: 1, overflow: TextOverflow.ellipsis,
                               ),
                            ],
                          ),
                        ),
                        const Icon(Icons.play_circle_fill, color: Color(0xFFFF1744), size: 30),
                      ],
                    ),
                  ),
                ),
              );
           }),
           const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildExploreTab(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    
    return RefreshIndicator(
      color: const Color(0xFFFF1744),
      backgroundColor: const Color(0xFF1E1E1E),
      onRefresh: () async {
        await musicProvider.fetchTrendingTracks(forceRefresh: true);
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 100), 
        physics: const BouncingScrollPhysics(),
        children: [
           // 1. Trending Now
           _buildSectionHeader("What's Hot", onViewAll: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const TrendingNowScreen()));
           }),
           SizedBox(
             height: 220,
             child: ListView.builder(
               padding: const EdgeInsets.symmetric(horizontal: 20),
               scrollDirection: Axis.horizontal,
               itemCount: musicProvider.trendingTracks.length,
               physics: const BouncingScrollPhysics(),
               itemBuilder: (context, index) {
                  final track = musicProvider.trendingTracks[index];
                  return LiquidCard(
                    imageUrl: track.albumArtUrl,
                    title: track.trackName,
                    subtitle: track.artistName,
                    width: 170, 
                    height: 170,
                    onTap: () => musicProvider.playTrack(track, playlistTracks: musicProvider.trendingTracks),
                  );
               },
             ),
           ),
           
           // 2. Genres
           const SizedBox(height: 20),
           _buildSectionHeader("Vibe Check", onViewAll: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AllGenresScreen()));
           }),
           _buildGenresSection(context, musicProvider),
           
           // 3. Top Artists
           const SizedBox(height: 20),
           _buildSectionHeader("Top Artists", onViewAll: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AllArtistsScreen()));
           }),
           _buildTopArtistsSection(context),
           
           const SizedBox(height: 80), 
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onViewAll}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
           Text(
             title,
             style: GoogleFonts.splineSans(
               fontSize: 20,
               fontWeight: FontWeight.bold,
               color: Colors.white,
             ),
           ),
           if (onViewAll != null)
             GestureDetector(
               onTap: onViewAll,
               child: Container(
                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                 decoration: BoxDecoration(
                   color: const Color(0xFFFF1744).withOpacity(0.1),
                   borderRadius: BorderRadius.circular(12),
                   border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.2)),
                 ),
                 child: Text(
                   "SEE ALL",
                   style: GoogleFonts.splineSans(
                     fontSize: 10,
                     fontWeight: FontWeight.bold,
                     color: const Color(0xFFFF1744), 
                     letterSpacing: 0.5,
                   ),
                 ),
               ),
             ),
        ],
      ),
    );
  }

  Widget _buildGenresSection(BuildContext context, MusicProvider musicProvider) {
    final genres = [
      {'name': 'Pop', 'color': const Color(0xFFFF1744), 'icon': Icons.music_note}, 
      {'name': 'Hip-Hop', 'color': Colors.blueAccent, 'icon': Icons.mic},
      {'name': 'Rock', 'color': Colors.amber[800], 'icon': Icons.electric_bolt},
      {'name': 'Chill', 'color': Colors.tealAccent[400], 'icon': Icons.nightlight_round},
    ];

    return SizedBox(
      height: 110,
      child: ListView.builder(
         padding: const EdgeInsets.symmetric(horizontal: 20),
         scrollDirection: Axis.horizontal,
         itemCount: genres.length,
         physics: const BouncingScrollPhysics(),
         itemBuilder: (context, index) {
            final genre = genres[index];
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: InkWell(
                onTap: () {
                   musicProvider.fetchGenreTracks(genre['name'] as String);
                   Navigator.push(context, MaterialPageRoute(builder: (_) => GenreSongsScreen(genre: genre['name'] as String)));
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                   width: 130,
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     gradient: LinearGradient(
                       begin: Alignment.topLeft,
                       end: Alignment.bottomRight,
                       colors: [
                         (genre['color'] as Color).withOpacity(0.6),
                         (genre['color'] as Color).withOpacity(0.3),
                       ],
                     ),
                     borderRadius: BorderRadius.circular(20),
                     border: Border.all(color: Colors.white.withOpacity(0.1)),
                   ),
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                        Icon(genre['icon'] as IconData, color: Colors.white, size: 28),
                        const SizedBox(height: 8),
                        Text(
                          genre['name'] as String,
                          style: GoogleFonts.splineSans(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        )
                     ],
                   ),
                ),
              ),
            );
         },
      ),
    );
  }
  
  Widget _buildTopArtistsSection(BuildContext context) {
    return SizedBox(
      height: 150, // Increased height for better spacing
      child: FutureBuilder(
         future: Provider.of<MusicProvider>(context, listen: false).fetchTrendingTracks(), 
         builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFFF1744)));
            final tracks = snapshot.data as List<Track>;
            final uniqueNames = <String>{};
            final uniqueTracks = tracks.where((t) => uniqueNames.add(t.artistName)).toList();
            
            if (uniqueTracks.isEmpty) return const SizedBox.shrink();

            return ListView.separated( // Use separated for consistent spacing
               padding: const EdgeInsets.symmetric(horizontal: 20),
               scrollDirection: Axis.horizontal,
               itemCount: uniqueTracks.length,
               physics: const BouncingScrollPhysics(),
               separatorBuilder: (ctx, index) => const SizedBox(width: 20), // Proper spacing
               itemBuilder: (context, index) {
                  final artistName = uniqueTracks[index].artistName;
                  final imageUrl = uniqueTracks[index].albumArtUrl;
                  
                  return InkWell(
                    onTap: () {
                      Provider.of<MusicProvider>(context, listen: false).fetchArtistTracks(artistName);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Loading $artistName..."), duration: const Duration(seconds: 1)));
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Column(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                          Container(
                            padding: const EdgeInsets.all(3), 
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.5), width: 2),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 5, offset: const Offset(0, 3))],
                            ),
                            child: CircleAvatar(
                              radius: 40, // 80x80
                              backgroundColor: Colors.grey[850],
                              backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                              child: imageUrl.isEmpty 
                                ? const Icon(Icons.person, size: 40, color: Colors.white54)
                                : null,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 90, // Constrain text width
                            child: Text(
                              artistName, 
                              style: GoogleFonts.splineSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), 
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                       ],
                    ),
                  );
               },
            );
         },
      ),
    );
  }
}