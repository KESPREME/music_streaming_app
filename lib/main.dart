import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'providers/music_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/accent_controller.dart';
import 'theme/glass_theme.dart';
import 'services/auth_service.dart';
import 'services/equalizer_service.dart'; // Equalizer
import 'services/firestore_service.dart';
import 'widgets/themed_social_screen.dart';
import 'widgets/themed_nav_bar.dart';
import 'widgets/themed_home_screen.dart';
import 'widgets/themed_search_screen.dart';
import 'widgets/themed_settings_screen.dart';
import 'widgets/glass_surface.dart';
import 'widgets/themed_library_screen.dart';
import 'widgets/global_music_overlay.dart'; // Import Global Overlay

class AppColors {
  static const Color background = Colors.black; // Pure black AMOLED canvas
  static const Color onBackground = Colors.white;

  static const Color spotifyGreen = Color(0xFF1DB954);
}

// Define global key for root navigation
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // FIX: Request high refresh rate for smoother 120Hz animations
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  try {
    await Firebase.initializeApp();
    
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
        Provider<FirestoreService>(create: (context) => FirestoreService()),
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
  @override
  void initState() {
    super.initState();
    // Initialize theme + accent providers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ThemeProvider>(context, listen: false).initialize();
      Provider.of<AccentController>(context, listen: false).initialize();
    });
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
  late PageController _pageController;

  final List<Widget> _screens = [
    const ThemedHomeScreen(),
    const ThemedSocialScreen(),
    const ThemedLibraryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
    });
    // Use jumpToPage to avoid scrolling through intermediate pages
    _pageController.jumpToPage(index);
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild ONLY when expansion state flips, not on every playback tick
    // (~1s position updates). Actions still use read.
    final isPanelOpen = context.select<MusicProvider, bool>(
      (p) => p.isPlayerExpanded,
    );
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);

    return PopScope(
      canPop: (_currentIndex == 0 && !isPanelOpen),
      onPopInvoked: (didPop) {
        if (didPop) return;

        // Priority 1: Close Player Panel
        if (isPanelOpen) {
           musicProvider.setPlayerExpanded(false);
           return;
        }

        // Priority 2: Go to Home Tab if not there
        if (_currentIndex != 0) {
           _onItemTapped(0);
        }
      },
      child: Scaffold(
        extendBody: true,
        body: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          physics: const BouncingScrollPhysics(), // Smooth bounce effect
          children: _screens,
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                _NavCircle(
                  icon: Icons.search_rounded,
                  label: 'Search',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ThemedSearchScreen()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ThemedNavBar(
                    currentIndex: _currentIndex,
                    onTap: _onItemTapped,
                    items: const [
                      BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
                      BottomNavigationBarItem(icon: Icon(Icons.people_rounded), label: 'Social'),
                      BottomNavigationBarItem(icon: Icon(Icons.library_music_rounded), label: 'Library'),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _NavCircle(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ThemedSettingsScreen()),
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



/// Floating glass circle for nav destinations outside the pill (Muzo-style).
class _NavCircle extends StatelessWidget {
  const _NavCircle({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tier: GlassTier.chrome,
      borderRadius: 30,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 54,
            height: 54,
            child: Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 24,
                semanticLabel: label),
          ),
        ),
      ),
    );
  }
}
