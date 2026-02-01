import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'providers/music_provider.dart';
import 'providers/theme_provider.dart';
import 'services/auth_service.dart';
import 'services/equalizer_service.dart'; // Equalizer
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/social_screen.dart';
import 'screens/library_screen.dart';
import 'widgets/themed_nav_bar.dart';
import 'widgets/themed_home_screen.dart';
import 'widgets/themed_search_screen.dart';
import 'widgets/themed_library_screen.dart';
import 'widgets/global_music_overlay.dart'; // Import Global Overlay

class AppColors {
  static const Color primary = Color(0xFF00B4D8); // Light Blue (Material You)
  static const Color primaryVariant = Color(0xFF0096C7); // Medium Blue
  static const Color secondary = Color(0xFF03DAC6); // Teal Accent
  static const Color secondaryVariant = Color(0xFF018786);

  static const Color background = Color(0xFF121212); // Dark Background
  static const Color surface = Color(0xFF1E1E1E); // Surface
  static const Color error = Color(0xFFCF6679);

  static const Color onPrimary = Colors.white;
  static const Color onSecondary = Colors.black;
  static const Color onBackground = Colors.white;
  static const Color onSurface = Colors.white;
  static const Color onError = Colors.black;

  static const Color spotifyGreen = Color(0xFF1DB954);
  static const Color accent = Color(0xFFFF1744); // Red Accent requested by user
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
    print("Initialization Error: $e");
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
        ChangeNotifierProvider(create: (context) => MusicProvider()),
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
  @override
  void initState() {
    super.initState();
    // Initialize theme provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ThemeProvider>(context, listen: false).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final googleFontsTextTheme = GoogleFonts.outfitTextTheme(textTheme).copyWith(
      headlineLarge: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.onBackground),
      headlineMedium: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.onBackground),
      headlineSmall: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.onBackground),
      titleLarge: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.onBackground),
      titleMedium: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.onBackground),
      titleSmall: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onBackground),
      bodyLarge: GoogleFonts.outfit(fontSize: 16, color: AppColors.onBackground.withOpacity(0.87)),
      bodyMedium: GoogleFonts.outfit(fontSize: 14, color: AppColors.onBackground.withOpacity(0.70)),
      bodySmall: GoogleFonts.outfit(fontSize: 12, color: AppColors.onBackground.withOpacity(0.60)),
      labelLarge: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onBackground),
    );

    return MaterialApp(
      navigatorKey: rootNavigatorKey, // Assigned Key
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          secondary: AppColors.secondary,
          onSecondary: AppColors.onSecondary,
          error: AppColors.error,
          onError: AppColors.onError,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
        ),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: googleFontsTextTheme,
      ),
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
  List<int> _navigationHistory = [0];

  final List<Widget> _screens = [
    const ThemedHomeScreen(),
    const ThemedSearchScreen(),
    const SocialScreen(),
    const ThemedLibraryScreen(),
  ];

  void _onItemTapped(int index) {
      if (_currentIndex == index) return;
      setState(() {
        if (_navigationHistory.last != index) {
            _navigationHistory.add(index);
        }
        _currentIndex = index;
      });
  }

  @override
  Widget build(BuildContext context) {
    // Access Provider to check Player Expansion state
    final musicProvider = Provider.of<MusicProvider>(context);
    final isPanelOpen = musicProvider.isPlayerExpanded;

    return PopScope(
      canPop: (_navigationHistory.length == 1 && _currentIndex == 0 && !isPanelOpen),
      onPopInvoked: (didPop) {
        if (didPop) return;

        // Priority 1: Close Player Panel
        if (isPanelOpen) {
           musicProvider.setPlayerExpanded(false);
           return;
        }

        // Priority 2: Navigate Back in Tabs
        setState(() {
          if (_navigationHistory.length > 1) {
            _navigationHistory.removeLast();
            _currentIndex = _navigationHistory.last;
          } else if (_currentIndex != 0) {
             _currentIndex = 0;
             _navigationHistory = [0];
          }
        });
      },
      child: Scaffold(
        extendBody: true, 
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: ThemedNavBar(
          currentIndex: _currentIndex,
          onTap: _onItemTapped,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: 'Search'),
            BottomNavigationBarItem(icon: Icon(Icons.people_rounded), label: 'Social'), // Social Icon
            BottomNavigationBarItem(icon: Icon(Icons.library_music_rounded), label: 'Library'),
          ],
        ),
      ),
    );
  }
}
