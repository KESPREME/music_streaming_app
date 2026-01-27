import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'providers/music_provider.dart';
import 'services/auth_service.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/social_screen.dart';
import 'screens/library_screen.dart';
import 'widgets/mini_player.dart';
import 'widgets/glass_nav_bar.dart';
import 'now_playing_screen.dart'; // Import NowPlayingScreen
import 'dart:ui'; // Import dart:ui for lerpDouble

class AppColors {
  static const Color primary = Color(0xFF6200EE); // Deep Purple
  static const Color primaryVariant = Color(0xFF3700B3);
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



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
    
    // Initialize JustAudioBackground with error handling
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.music_streaming_app.channel.audio',
      androidNotificationChannelName: 'Music Playback',
      androidNotificationOngoing: true,
    );
  } catch (e) {
    print("Initialization Error: $e");
    // Continue running app even if background init fails (will degrade gracefully)
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
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          primaryContainer: AppColors.primaryVariant,
          onPrimaryContainer: AppColors.onBackground,
          secondary: AppColors.secondary,
          onSecondary: AppColors.onSecondary,
          secondaryContainer: AppColors.secondaryVariant,
          onSecondaryContainer: AppColors.onBackground,
          tertiary: AppColors.spotifyGreen,
          onTertiary: AppColors.onPrimary,
          tertiaryContainer: Color(0xFF0E5C2A),
          onTertiaryContainer: AppColors.onBackground,
          error: AppColors.error,
          onError: AppColors.onError,
          errorContainer: Color(0xFFB00020),
          onErrorContainer: AppColors.onBackground,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
          surfaceContainerHighest: Color(0xFF2C2C2C),
          onSurfaceVariant: Color.fromRGBO(255, 255, 255, 0.8),
          outline: Color(0xFF616161),
          shadow: Color(0x80000000),
          inverseSurface: AppColors.onBackground,
          onInverseSurface: AppColors.background,
          inversePrimary: AppColors.background,
          surfaceTint: AppColors.primary,
        ),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: googleFontsTextTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.onSurface),
          titleTextStyle: googleFontsTextTheme.headlineSmall,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface.withOpacity(0.9),
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.onSurface.withOpacity(0.6),
          selectedLabelStyle: googleFontsTextTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
          unselectedLabelStyle: googleFontsTextTheme.labelSmall,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titleTextStyle: googleFontsTextTheme.titleLarge,
          contentTextStyle: googleFontsTextTheme.bodyMedium,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            textStyle: googleFontsTextTheme.labelLarge,
            elevation: 0,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: googleFontsTextTheme.labelLarge,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          hintStyle: googleFontsTextTheme.bodyMedium?.copyWith(color: AppColors.onSurface.withOpacity(0.5)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: AppColors.primary,
          inactiveTrackColor: Color(0xFF333333),
          thumbColor: AppColors.primary,
          overlayColor: Color.fromRGBO(98, 0, 238, 0.2),
          trackHeight: 4.0,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8.0),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 16.0),
        ),
        iconTheme: const IconThemeData(
          color: AppColors.onSurface,
          size: 24,
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurface.withOpacity(0.6),
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: AppColors.primary, width: 3.0),
          ),
          labelStyle: googleFontsTextTheme.labelLarge,
          unselectedLabelStyle: googleFontsTextTheme.labelLarge,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  List<int> _navigationHistory = [0]; // History stack starting at Home
  
  late AnimationController _panelController;

  final List<Widget> _screens = [
    const HomeScreen(),
    const SearchScreen(), 
    const SocialScreen(),
    const LibraryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
       vsync: this,
       duration: const Duration(milliseconds: 500), 
    );
  }

  @override
  void dispose() {
    _panelController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    // Collapse panel if navigating tabs
    if (_panelController.value > 0) _animatePanelTo(0.0);

    setState(() {
      _historyAdd(index);
      _selectedIndex = index;
    });
  }

  void _historyAdd(int index) {
    if (_navigationHistory.last != index) {
      _navigationHistory.add(index);
    }
  }

  // --- Panel Animation Logic ---
  
  void _animatePanelTo(double target) {
    _panelController.animateTo(
      target, 
      duration: const Duration(milliseconds: 400), 
      curve: Curves.easeOutCubic // Liquid feel - corrected from springOut
    );
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    final double delta = -details.primaryDelta! / screenHeight;
    _panelController.value += delta;
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity = -details.primaryVelocity! / MediaQuery.of(context).size.height; 
    
    if (velocity > 0.5) {
      _animatePanelTo(1.0); // Fling Up
    } else if (velocity < -0.5) {
      _animatePanelTo(0.0); // Fling Down
    } else {
      if (_panelController.value > 0.4) {
        _animatePanelTo(1.0);
      } else {
        _animatePanelTo(0.0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final hasTrack = musicProvider.currentTrack != null;
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: (_navigationHistory.length == 1 && _selectedIndex == 0 && _panelController.value == 0),
      onPopInvoked: (didPop) {
        if (didPop) return;
        
        if (_panelController.value > 0.1) {
          _animatePanelTo(0.0);
          return;
        }

        setState(() {
          if (_navigationHistory.length > 1) {
            _navigationHistory.removeLast();
            _selectedIndex = _navigationHistory.last;
          } else if (_selectedIndex != 0) {
             _selectedIndex = 0;
             _navigationHistory = [0];
          }
        });
      },
      child: Scaffold(
        extendBody: true, 
        body: Stack(
          children: [
            // 1. Main Content Layer
            Positioned.fill(
              child: IndexedStack(
                index: _selectedIndex,
                children: _screens,
              ),
            ),
            
            // 2. Panel Layer (MiniPlayer & NowPlaying)
            if (hasTrack)
              AnimatedBuilder(
                animation: _panelController,
                builder: (context, child) {
                  final value = _panelController.value;
                  final topOffset = lerpDouble(screenHeight, 0, value)!;
                  final miniPlayerOpacity = (1.0 - (value * 3)).clamp(0.0, 1.0); 

                  return Stack(
                    children: [
                      // A. Mini Player (Fades out)
                      Positioned(
                        left: 0, right: 0,
                        bottom: 0, 
                        child: Opacity(
                          opacity: miniPlayerOpacity,
                          child: IgnorePointer(
                            ignoring: miniPlayerOpacity < 0.1,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onVerticalDragUpdate: _handleVerticalDragUpdate,
                                  onVerticalDragEnd: _handleVerticalDragEnd,
                                  child: MiniPlayer(
                                    onExpand: () => _animatePanelTo(1.0),
                                  ),
                                ),
                                const SizedBox(height: 100), // Height 65 + Margin 25 + Padding 10 
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      // B. Now Playing Screen (Slides Up)
                      Positioned(
                        top: topOffset,
                        left: 0, right: 0,
                        height: screenHeight,
                        child: Opacity(
                          opacity: (value > 0.01) ? 1.0 : 0.0, 
                          child: GestureDetector(
                            onVerticalDragUpdate: _handleVerticalDragUpdate,
                            onVerticalDragEnd: _handleVerticalDragEnd,
                            child: Material( 
                              elevation: 0,
                              color: Colors.transparent, 
                              child: NowPlayingScreen(
                                track: musicProvider.currentTrack!,
                                onMinimize: () => _animatePanelTo(0.0),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
              ),

            // 3. Navigation Bar (Only visible when panel is collapsed)
            AnimatedBuilder(
              animation: _panelController,
              builder: (context, child) {
                return Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Transform.translate(
                    offset: Offset(0, _panelController.value * kBottomNavigationBarHeight),
                    child: Opacity(
                      opacity: (1.0 - _panelController.value).clamp(0.0, 1.0),
                      child: GlassNavBar(
                        currentIndex: _selectedIndex,
                        onTap: _onItemTapped,
                         items: const [
                          BottomNavigationBarItem(
                            icon: Icon(Icons.home_outlined),
                            activeIcon: Icon(Icons.home_rounded),
                            label: 'Home',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.search_rounded),
                            activeIcon: Icon(Icons.search_rounded),
                            label: 'Search',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.people_outline_rounded),
                            activeIcon: Icon(Icons.people_rounded),
                            label: 'Social',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.library_music_outlined),
                            activeIcon: Icon(Icons.library_music_rounded),
                            label: 'Library',
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
            ),
          ],
        ),
      ),
    );
  }
}
