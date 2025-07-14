import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for SystemUiOverlayStyle
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
// import 'package:google_fonts/google_fonts.dart'; // Import Google Fonts - Commented out

import 'providers/music_provider.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/social_screen.dart';
import 'screens/library_screen.dart';
import 'widgets/mini_player.dart';

// Define the color scheme inspired by YouTube Music and Spotify
class AppColors {
  static const Color primary = Color(0xFFBB86FC); // Vibrant Purple (Material Purple A200)
  static const Color primaryVariant = Color(0xFF3700B3); // Darker Purple (Material Purple A700)
  static const Color secondary = Color(0xFF03DAC6); // Teal Accent (Material Teal A200)
  static const Color secondaryVariant = Color(0xFF018786); // Darker Teal (Material Teal A700)

  static const Color background = Color(0xFF121212); // Standard Dark Background
  static const Color surface = Color(0xFF1E1E1E); // Slightly lighter for cards/surfaces
  static const Color error = Color(0xFFCF6679); // Standard Error Color

  static const Color onPrimary = Colors.black;
  static const Color onSecondary = Colors.black;
  static const Color onBackground = Colors.white;
  static const Color onSurface = Colors.white;
  static const Color onError = Colors.black;

  static const Color spotifyGreen = Color(0xFF1DB954); // Spotify's green for accents
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // Transparent status bar
    statusBarIconBrightness: Brightness.light, // Light icons for dark background
    systemNavigationBarColor: AppColors.background, // Match bottom nav bar
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(
    ChangeNotifierProvider(
      create: (context) => MusicProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // final googleFontsTextTheme = GoogleFonts.robotoTextTheme(textTheme).copyWith(
    //   headlineLarge: GoogleFonts.roboto(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.onBackground, letterSpacing: 0.5),
    //   headlineMedium: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.onBackground, letterSpacing: 0.25),
    //   headlineSmall: GoogleFonts.roboto(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onBackground, letterSpacing: 0.15),
    //   titleLarge: GoogleFonts.roboto(fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.onBackground),
    //   titleMedium: GoogleFonts.roboto(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.onBackground, letterSpacing: 0.15),
    //   titleSmall: GoogleFonts.roboto(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.onBackground, letterSpacing: 0.1),
    //   bodyLarge: GoogleFonts.roboto(fontSize: 16, color: AppColors.onBackground.withOpacity(0.87), letterSpacing: 0.5),
    //   bodyMedium: GoogleFonts.roboto(fontSize: 14, color: AppColors.onBackground.withOpacity(0.70), letterSpacing: 0.25),
    //   bodySmall: GoogleFonts.roboto(fontSize: 12, color: AppColors.onBackground.withOpacity(0.60), letterSpacing: 0.4),
    //   labelLarge: GoogleFonts.roboto(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.onBackground, letterSpacing: 1.25),
    //   labelMedium: GoogleFonts.roboto(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onBackground.withOpacity(0.7)),
    //   labelSmall: GoogleFonts.roboto(fontSize: 10, fontWeight: FontWeight.w400, color: AppColors.onBackground.withOpacity(0.6), letterSpacing: 1.5),
    // );
    final fallbackTextTheme = textTheme.copyWith( // Using fallback standard text theme
      headlineLarge: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.onBackground, letterSpacing: 0.5),
      headlineMedium: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.onBackground, letterSpacing: 0.25),
      headlineSmall: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onBackground, letterSpacing: 0.15),
      titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.onBackground),
      titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.onBackground, letterSpacing: 0.15),
      titleSmall: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.onBackground, letterSpacing: 0.1),
      bodyLarge: TextStyle(fontSize: 16, color: AppColors.onBackground.withOpacity(0.87), letterSpacing: 0.5),
      bodyMedium: TextStyle(fontSize: 14, color: AppColors.onBackground.withOpacity(0.70), letterSpacing: 0.25),
      bodySmall: TextStyle(fontSize: 12, color: AppColors.onBackground.withOpacity(0.60), letterSpacing: 0.4),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.onBackground, letterSpacing: 1.25),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onBackground.withOpacity(0.7)),
      labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w400, color: AppColors.onBackground.withOpacity(0.6), letterSpacing: 1.5),
    );


    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, // Enable Material 3 features
        brightness: Brightness.dark,
        colorScheme: const ColorScheme( // Added const back
          brightness: Brightness.dark,
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          primaryContainer: AppColors.primaryVariant, // M3 uses container colors
          onPrimaryContainer: AppColors.onBackground,
          secondary: AppColors.secondary,
          onSecondary: AppColors.onSecondary,
          secondaryContainer: AppColors.secondaryVariant,
          onSecondaryContainer: AppColors.onBackground,
          tertiary: AppColors.spotifyGreen, // Using Spotify green as a tertiary option
          onTertiary: AppColors.onPrimary,
          tertiaryContainer: Color(0xFF0E5C2A), // Darker green for container
          onTertiaryContainer: AppColors.onBackground,
          error: AppColors.error,
          onError: AppColors.onError,
          errorContainer: Color(0xFFB00020), // Darker red for error container
          onErrorContainer: AppColors.onBackground,
          background: AppColors.background,
          onBackground: AppColors.onBackground,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
          surfaceVariant: const Color(0xFF2C2C2C), // For slightly different surfaces
          onSurfaceVariant: const Color.fromRGBO(255, 255, 255, 0.8),
          outline: const Color(0xFF616161), // Colors.grey[700]
          shadow: const Color(0x80000000), // Colors.black.withOpacity(0.5)
          inverseSurface: AppColors.onBackground, // For elements on dark surface that need light bg
          onInverseSurface: AppColors.background,
          inversePrimary: AppColors.background, // For text on primary color buttons
          surfaceTint: AppColors.primary, // Tint color for surfaces like AppBar
        ),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: fallbackTextTheme, // Using fallback text theme
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.surface, // Use surface color for AppBar
          elevation: 0, // Flat AppBar
          iconTheme: IconThemeData(color: AppColors.onSurface.withOpacity(0.8)),
          titleTextStyle: fallbackTextTheme.headlineSmall?.copyWith(color: AppColors.onSurface),
          systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface, // Use surface for a slightly elevated look
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.onSurface.withOpacity(0.6),
          selectedLabelStyle: fallbackTextTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
          unselectedLabelStyle: fallbackTextTheme.labelSmall,
          type: BottomNavigationBarType.fixed,
          elevation: 8, // Add some elevation
        ),
        cardTheme: CardThemeData( // Changed to CardThemeData
          elevation: 2,
          color: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        dialogTheme: DialogThemeData( // Changed to DialogThemeData
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titleTextStyle: fallbackTextTheme.titleLarge,
          contentTextStyle: fallbackTextTheme.bodyMedium,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            textStyle: fallbackTextTheme.labelLarge,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: fallbackTextTheme.labelLarge,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface.withOpacity(0.5),
          hintStyle: fallbackTextTheme.bodyMedium?.copyWith(color: AppColors.onSurface.withOpacity(0.5)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: AppColors.primary,
          inactiveTrackColor: AppColors.surface,
          thumbColor: AppColors.primary,
          overlayColor: Color.fromRGBO(187, 134, 252, 0.2), // AppColors.primary.withOpacity(0.2)
          trackHeight: 3.0,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
        ),
        iconTheme: IconThemeData(
          color: AppColors.onSurface.withOpacity(0.8),
          size: 24,
        ),
        tabBarTheme: TabBarThemeData( // Changed to TabBarThemeData
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurface.withOpacity(0.7),
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: AppColors.primary, width: 2.0),
          ),
          labelStyle: fallbackTextTheme.labelLarge,
          unselectedLabelStyle: fallbackTextTheme.labelLarge,
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

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const SearchScreen(), // Assuming SearchScreen doesn't require parameters
    const SocialScreen(),
    const LibraryScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      // Apply a more modern bottom navigation bar
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (musicProvider.currentTrack != null) const MiniPlayer(),
          // Customizing the BottomNavigationBar for a more modern look
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).bottomNavigationBarTheme.backgroundColor ?? AppColors.surface,
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.1),
                  blurRadius: 8,
                  offset: Offset(0, -2), // Shadow on top
                ),
              ],
            ),
            child: BottomNavigationBar(
              items: const <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home_filled),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search_outlined),
                  activeIcon: Icon(Icons.search),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.people_outline), // Changed from Icons.chat
                  activeIcon: Icon(Icons.people),
                  label: 'Social',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.library_music_outlined),
                  activeIcon: Icon(Icons.library_music),
                  label: 'Library',
                ),
              ],
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              // Use theme properties for colors and styles
              // Ensure type is BottomNavigationBarType.fixed for more than 3 items with labels
              type: BottomNavigationBarType.fixed,
              showSelectedLabels: true,
              showUnselectedLabels: true,
            ),
          ),
        ],
      ),
    );
  }
}
