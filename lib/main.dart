import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'dart:async';

import 'core/navigation/root_navigator.dart';
import 'providers/music_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/accent_controller.dart';
import 'services/deep_link_service.dart';
import 'screens/search_screen.dart';
import 'widgets/themed_artist_detail_screen.dart';
import 'widgets/themed_playlist_detail_screen.dart';
import 'theme/glass_theme.dart';
import 'services/auth_service.dart';
import 'services/equalizer_service.dart'; // Equalizer
import 'screens/discover_screen.dart';
import 'screens/search_screen.dart';
import 'widgets/themed_nav_bar.dart';
import 'widgets/themed_home_screen.dart';
import 'widgets/themed_search_screen.dart';
import 'widgets/glass_circle_button.dart';
import 'widgets/fade_indexed_stack.dart';
import 'widgets/themed_library_screen.dart';
import 'widgets/global_music_overlay.dart'; // Import Global Overlay
import 'widgets/ambient_backdrop.dart';

class AppColors {
  static const Color background = Colors.black; // Pure black AMOLED canvas
  static const Color onBackground = Colors.white;

  static const Color spotifyGreen = Color(0xFF1DB954);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // FIX: Request high refresh rate for smoother 120Hz animations
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  try {
    // Initialize JustAudioBackground
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.music_streaming_app.channel.audio',
      androidNotificationChannelName: 'Music Playback',
      androidNotificationOngoing: true,
    );

    // Initialize Equalizer Service
    await EqualizerService().initialize();
  } catch (e) {
    debugPrint("Initialization Error: $e");
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AccentController()),
        ChangeNotifierProvider(
          create: (context) => MusicProvider(
            accentController: context.read<AccentController>(),
          ),
        ),
        ChangeNotifierProvider(create: (context) => AuthService()),
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final DeepLinkService _deepLinks = DeepLinkService();
  StreamSubscription<DeepLink>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    // Initialize theme + accent providers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ThemeProvider>(context, listen: false).initialize();
      Provider.of<AccentController>(context, listen: false).initialize();
      _deepLinks.start();
      _deepLinkSub = _deepLinks.links.listen(_handleDeepLink);
    });
  }

  void _handleDeepLink(DeepLink link) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    final provider = Provider.of<MusicProvider>(context, listen: false);
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    switch (link.route) {
      case DeepLinkRoute.track:
        provider.playTrackById(link.id!);
        break;
      case DeepLinkRoute.album:
        Navigator.push(
          navContext,
          MaterialPageRoute(
            builder: (_) => ThemedPlaylistDetailScreen(
              playlistId: link.id!,
              playlistName: 'Album',
              searchAlbumByName: true,
            ),
          ),
        );
        break;
      case DeepLinkRoute.playlist:
        Navigator.push(
          navContext,
          MaterialPageRoute(
            builder: (_) => ThemedPlaylistDetailScreen(
              playlistId: link.id!,
              playlistName: 'Playlist',
            ),
          ),
        );
        break;
      case DeepLinkRoute.artist:
        provider.navigateToArtistById(link.id!).then((_) {
          if (!navContext.mounted) return;
          final artist = provider.currentArtistDetails;
          if (artist == null) return;
          Navigator.push(
          navContext,
            MaterialPageRoute(
              builder: (_) => ThemedArtistDetailScreen(
                artistId: artist.id,
                artistName: artist.name,
                artistImage: artist.imageUrl,
              ),
            ),
          );
        });
        break;
      case DeepLinkRoute.search:
        // Search lives as an overlay on MainScreen; push a dedicated search
        // route instead of a named route that doesn't exist.
        Navigator.push(
          navContext,
          MaterialPageRoute(
            builder: (_) => SearchScreen(initialQuery: link.query),
          ),
        );
        break;
      case DeepLinkRoute.nowPlaying:
        if (provider.currentTrack != null) {
          provider.setPlayerExpanded(true);
        }
        break;
    }
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _deepLinks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<AccentController>().accent;
    final baseTextTheme = GoogleFonts.outfitTextTheme(Theme.of(context).textTheme);
    final textTheme = baseTextTheme.copyWith(
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
      titleLarge: baseTextTheme.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
      titleMedium: baseTextTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
      titleSmall: baseTextTheme.titleSmall?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(fontSize: 16, color: Colors.white.withValues(alpha: 0.87)),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(fontSize: 14, color: Colors.white.withValues(alpha: 0.70)),
      bodySmall: baseTextTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.white.withValues(alpha: 0.60)),
      labelLarge: baseTextTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
    );

    return MaterialApp(
      navigatorKey: rootNavigatorKey, // Assigned Key
      debugShowCheckedModeBanner: false,
      theme: GlassTheme.build(accent, textTheme: textTheme),
      // Integrate Global Music Overlay here
      builder: (context, child) {
        return GlobalMusicOverlay(child: child!);
      },
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _searchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  final List<Widget> _screens = const [
    ThemedHomeScreen(),
    DiscoverScreen(),
    ThemedLibraryScreen(),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (_currentIndex == index && !_searchMode) return;
    if (_searchMode) _exitSearch();
    setState(() => _currentIndex = index);
  }

  void _enterSearch() {
    HapticFeedback.lightImpact();
    setState(() => _searchMode = true);
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _exitSearch() {
    HapticFeedback.lightImpact();
    _searchFocus.unfocus();
    _searchController.clear();
    Provider.of<MusicProvider>(context, listen: false).clearSearchResults();
    setState(() => _searchMode = false);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild ONLY when expansion state flips, not on every playback tick
    // (~1s position updates). Actions still use read.
    final isPanelOpen = context.select<MusicProvider, bool>(
      (p) => p.isPlayerExpanded,
    );
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return PopScope(
      canPop: (_currentIndex == 0 && !_searchMode && !isPanelOpen),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // Priority 1: Close Player Panel
        if (isPanelOpen) {
           musicProvider.setPlayerExpanded(false);
           return;
        }

        // Priority 2: Exit search
        if (_searchMode) {
           _exitSearch();
           return;
        }

        // Priority 3: Go to Home Tab if not there
        if (_currentIndex != 0) {
           _onItemTapped(0);
        }
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent, // Ambient canvas shines through
        body: Stack(
          children: [
            // z-0: ambient album-art canvas (visible where screens are
            // transparent; opaque screens are migrated in P5).
            const AmbientBackdrop(),
            FadeIndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
            // Search overlay (Muzo-style in-place transition).
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.03),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _searchMode
                  ? Builder(
                      key: const ValueKey('search_overlay'),
                      builder: (_) => themeProvider.isMaterialYou
                          ? const ThemedSearchScreen()
                          : SearchScreen(
                              key: const ValueKey('embedded_search'),
                              embedded: true,
                              externalController: _searchController,
                              externalFocusNode: _searchFocus,
                            ),
                    )
                  : const SizedBox.shrink(key: ValueKey('search_gone')),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: ThemedNavBar(
                    currentIndex: _currentIndex,
                    onTap: _onItemTapped,
                    searchMode: _searchMode,
                    searchController: _searchController,
                    searchFocusNode: _searchFocus,
                    onSearchSubmitted: (query) {
                      _searchFocus.unfocus();
                      if (query.trim().isEmpty) return;
                    },
                    items: const [
                      BottomNavigationBarItem(icon: Icon(Icons.home_rounded), activeIcon: Icon(Icons.home_filled), label: 'Home'),
                      BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), activeIcon: Icon(Icons.explore_rounded), label: 'Discover'),
                      BottomNavigationBarItem(icon: Icon(Icons.library_music_outlined), activeIcon: Icon(Icons.library_music_rounded), label: 'Library'),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Companion circle: search <-> home (Muzo morph).
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: _searchMode
                      ? GlassCircleButton(
                          key: const ValueKey('home_circle'),
                          icon: Icons.home_outlined,
                          onTap: () {
                            _exitSearch();
                            _onItemTapped(0);
                          },
                          semanticLabel: 'Close search',
                        )
                      : GlassCircleButton(
                          key: const ValueKey('search_circle'),
                          icon: Icons.search_rounded,
                          onTap: _enterSearch,
                          semanticLabel: 'Search',
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
