import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart' as svc;
import 'services/playback/mine_audio_handler.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;
import 'design/glass/chrome_glass.dart';
import 'package:video_player_win/video_player_win.dart';

import 'core/navigation/root_navigator.dart';
import 'core/navigation/shell_back.dart';
import 'core/perf_trace.dart';
import 'providers/music_provider.dart';
import 'providers/theme_provider.dart';
import 'presentation/home/home_view_mode.dart';
import 'services/audio_output_service.dart';
import 'providers/accent_controller.dart';
import 'services/deep_link_service.dart';
import 'screens/search_screen.dart';
import 'widgets/themed_artist_detail_screen.dart';
import 'widgets/themed_playlist_detail_screen.dart';
import 'theme/app_font.dart';
import 'theme/glass_theme.dart';
import 'services/auth_service.dart';
import 'services/equalizer_service.dart'; // Equalizer
import 'presentation/explore/explore_screen.dart';
import 'services/explore/explore_controller.dart';
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
  // Opt-in only (--dart-define=PERF_TRACE=true). No-op in every normal build.
  PerfTrace.install();

  // Warm the glass shader programs to disk-backed RAM before the first frame.
  //
  // This was never called, so the nav bar and mini player compiled their
  // shaders lazily on first paint - the first glass surface in the app was the
  // one that stuttered. Placed early on purpose: it is documented as pure
  // disk-to-RAM I/O with no GPU work, so the audio and equalizer awaits below
  // overlap with it instead of waiting on it.
  //
  // initialize() is also what installs the package's accessibility bridge
  // (Reduce Motion / High Contrast). Without it, glass animates even when the
  // user has asked the OS for less motion.
  try {
    await lgw.LiquidGlassWidgets.initialize();
  } catch (e, s) {
    // Non-fatal. Worst case the first glass surface compiles on first paint.
    FlutterError.reportError(FlutterErrorDetails(
      exception: e,
      stack: s,
      library: 'mine_music/glass',
      context: ErrorDescription('while pre-warming glass shaders'),
    ));
  }

  // Framework errors reach logcat through this hook. Without it a widget
  // assertion only ever appears in the on-screen banner, with no stack, which
  // makes it unreproducible outside the device it happened on.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrintSynchronously(
        'APP_FATAL ${details.exceptionAsString()}\n${details.stack}');
  };
  
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    WindowsVideoPlayer.registerWith();
  }
  
  // 120 Hz: requested natively in MainActivity.requestHighRefreshRate().
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  // These two are initialised separately on purpose. Sharing one try/catch
  // meant a failing EqualizerService reported itself as an audio init failure,
  // and a failing JustAudioBackground.init - no media session, so the player
  // cannot start - was only ever debugPrint'd, which release builds strip.
  // The result was a cold start with a silently broken session and nothing on
  // screen to explain why nothing played.
  try {
    // The media session. One handler over however many decks the engine runs
    // (a crossfade needs two; just_audio_background supports one).
    MineAudioHandler.shared = await svc.AudioService.init(
      builder: () => MineAudioHandler(),
      config: const svc.AudioServiceConfig(
        androidNotificationChannelId:
            'com.example.music_streaming_app.channel.audio',
        androidNotificationChannelName: 'Music Playback',
        androidNotificationOngoing: true,
      ),
    );
  } catch (e, s) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: e,
      stack: s,
      library: 'mine_music/audio',
      context: ErrorDescription('while setting up the media session'),
    ));
  }

  try {
    // Initialize Equalizer Service
    await EqualizerService().initialize();
  } catch (e, s) {
    debugPrint('EqualizerService init failed (non-fatal): $e');
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  
  // Restore the saved session BEFORE the first MusicProvider is constructed.
  //
  // `MusicProvider`'s `AuthSessionReset` reads `AuthService().isLoggedIn` in its
  // constructor to decide whether a later change is a real identity flip. That
  // happens during `runApp`. If the cookies were still sitting unread in
  // preferences at that point, it would latch "anonymous", and the restore
  // would then register as a login: reset the InnerTube session, clear the
  // stream cache, and refetch the feed on every cold start.
  //
  // This is why the session appeared to be forgotten after a restart - `init()`
  // existed but had no call site anywhere in the app.
  try {
    await AuthService().init();
  } catch (e, s) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: e,
      stack: s,
      library: 'mine_music/auth',
      context: ErrorDescription('while restoring the saved session'),
    ));
  }

  // Load the theme BEFORE the first frame. It used to load in a post-frame
  // callback, so a listener who had chosen pure black saw one frame (and, with
  // the fade, a short animation) of the album-art backdrop on every cold start
  // before it went black. The preferences are already warm from the session
  // restore above, so this costs a few milliseconds, not a splash screen. It
  // swallows its own errors and falls back to the defaults.
  final themeProvider = ThemeProvider();
  await themeProvider.initialize();

  runApp(
    // Wrap outside MaterialApp: `brightnessResolver` is invoked with a context
    // from inside it, so the glass shader reads the app's Theme rather than the
    // raw OS brightness. Without it, glass shadows and borders disappear
    // whenever the app theme and the system theme disagree.
    lgw.LiquidGlassWidgets.wrap(
      brightnessResolver: Theme.maybeBrightnessOf,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => AccentController()),
          ChangeNotifierProvider(
            create: (context) => MusicProvider(
              accentController: context.read<AccentController>(),
            ),
          ),
          ChangeNotifierProvider(create: (context) => AuthService()),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider(
            create: (context) => AudioOutputService()..init(),
          ),
          // Per-section Home layout choices (rows vs cards). Reads and writes
          // its own preferences key, so it loads lazily rather than needing an
          // init step in main() before the first frame.
          ChangeNotifierProvider(
            create: (context) => HomeViewModeStore(),
          ),
        ],
        child: const MyApp(),
      ),
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
      Provider.of<HomeViewModeStore>(context, listen: false).initialize();
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
    // Selected, not watched: only this one flag rebuilds the app's theme, not
    // every unrelated ThemeProvider change.
    final amoled = context.select<ThemeProvider, bool>((t) => t.isAmoled);
    final glassRendering =
        context.select<ThemeProvider, GlassRendering>((t) => t.glassRendering);
    // The font setting (Settings > Appearance): watched so a change rebuilds
    // the theme, and with it every style that inherits from it.
    context.select<ThemeProvider, (String, int)>((t) => (t.fontFamily, t.fontWeightDelta));
    final baseTextTheme = AppFont.textTheme(Theme.of(context).textTheme, shiftWeights: false);
    final textTheme = AppFont.shiftTextTheme(baseTextTheme.copyWith(
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
    ));

    return MaterialApp(
      navigatorKey: rootNavigatorKey, // Assigned Key
      navigatorObservers: [AppRouteObserver.instance],
      debugShowCheckedModeBanner: false,
      theme: GlassTheme.build(accent,
          textTheme: textTheme,
          amoled: amoled,
          glassRendering: glassRendering),
      // Integrate Global Music Overlay here.
      //
      // The transparency Material is required, not cosmetic: liquid_glass_widgets
      // ships no Material ancestor of its own, and under MaterialApp a bare Text
      // with no Material above it renders with debug yellow underlines. It paints
      // nothing, so the ambient canvas behind every screen still shows through.
      builder: (context, child) {
        return Material(
          type: MaterialType.transparency,
          child: GlobalMusicOverlay(child: child!),
        );
      },
      home: const MainScreen(),
    );
  }
}

class ThemedExploreScreen extends StatefulWidget {
  const ThemedExploreScreen({super.key, this.isActive = false});

  final bool isActive;

  @override
  State<ThemedExploreScreen> createState() => _ThemedExploreScreenState();
}

class _ThemedExploreScreenState extends State<ThemedExploreScreen> {
  ExploreController? _controller;

  @override
  void didUpdateWidget(ThemedExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive && _controller != null) {
      if (_controller!.session == null) {
        _controller!.start(seed: context.read<MusicProvider>().currentTrack);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ExploreController>(
      create: (ctx) {
        final c = bootstrapExploreController(ctx, autoStart: false);
        _controller = c;
        if (widget.isActive) {
          c.start(seed: ctx.read<MusicProvider>().currentTrack);
        }
        return c;
      },
      child: ExploreScreen(embedded: true, isActive: widget.isActive),
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
  bool _searchSuspended = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late final lgw.GlassTabBarMinimizeController _minimizeController;
  late final ValueNotifier<({int index, bool searchMode})> _tabState;

  @override
  void initState() {
    super.initState();
    _tabState = ValueNotifier((index: 0, searchMode: false));
    _minimizeController = lgw.GlassTabBarMinimizeController(
      behavior: lgw.GlassBarMinimizeBehavior.onScrollDown,
    );
    // The shell's PopScope must know, at the moment back is pressed, whether a
    // page is open on the nested navigator. This screen does not rebuild when
    // one is pushed, so it listens.
    ShellPageTracker.canPop.addListener(_onShellPagesChanged);
  }

  bool _shellSyncScheduled = false;

  /// Observers fire inside the navigator's own update, where setState is not
  /// allowed; a route change animates, so the next frame is soon enough.
  void _onShellPagesChanged() {
    if (!mounted || _shellSyncScheduled) return;
    _shellSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shellSyncScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ShellPageTracker.canPop.removeListener(_onShellPagesChanged);
    _tabState.dispose();
    _minimizeController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    final mainNav = mainNavigatorKey.currentState;
    if (mainNav != null && mainNav.canPop()) {
      mainNav.popUntil((route) => route.isFirst);
    }
    if (_currentIndex == index && !_searchMode && !_searchSuspended) return;
    _minimizeController.expand();
    if (_searchMode || _searchSuspended) {
      _searchSuspended = false;
      _exitSearch();
    }
    final wasExplore = _currentIndex == 1;
    final isExplore = index == 1;
    setState(() => _currentIndex = index);
    _tabState.value = (index: index, searchMode: false);
    if (isExplore) {
      context.read<MusicProvider>().setHideMiniPlayer(true);
    } else if (wasExplore) {
      context.read<MusicProvider>().setHideMiniPlayer(false);
    }
  }

  void _enterSearch() {
    HapticFeedback.lightImpact();
    _minimizeController.expand();
    setState(() {
      _searchMode = true;
      _searchSuspended = false;
    });
    _tabState.value = (index: _currentIndex, searchMode: true);
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _exitSearch() {
    HapticFeedback.lightImpact();
    _searchFocus.unfocus();
    _searchController.clear();
    Provider.of<MusicProvider>(context, listen: false).clearSearchResults();
    _minimizeController.expand();
    setState(() {
      _searchMode = false;
      _searchSuspended = false;
    });
    _tabState.value = (index: _currentIndex, searchMode: false);
  }

  void _pushDetailFromSearch(Widget screen) {
    _searchFocus.unfocus();
    setState(() {
      _searchSuspended = true;
    });
    final nav = mainNavigatorKey.currentState ?? Navigator.of(context);
    nav.push(MaterialPageRoute(builder: (_) => screen)).then((_) {
      if (mounted) {
        setState(() {
          _searchSuspended = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild ONLY when expansion state flips, not on every playback tick
    // (~1s position updates). Actions still use read.
    final isPanelOpen = context.select<MusicProvider, bool>(
      (p) => p.isPlayerExpanded,
    );
    final hasMiniPlayer = context.select<MusicProvider, bool>(
      (p) => p.currentTrack != null && !p.hideMiniPlayer,
    );

    // If mini player disappeared (queue cleared, track ended, or hidden),
    // ensure the bar expands back if it was minimized.
    if (!hasMiniPlayer && _minimizeController.minimized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _minimizeController.minimized) {
          _minimizeController.expand();
        }
      });
    }

    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context);

    // Tab switch requested from a pushed route (Explore tab bar).
    // Consumed post-frame so setState never runs during build.
    final requestedTab =
        context.select<MusicProvider, int?>((p) => p.requestedTab);
    if (requestedTab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Provider.of<MusicProvider>(context, listen: false)
            .clearRequestedTab();
        _onItemTapped(requestedTab);
      });
    }

    final mainNav = mainNavigatorKey.currentState;
    final canPopInner = ShellPageTracker.canPop.value || (mainNav != null && mainNav.canPop());
    final showSearchOverlay = _searchMode && !_searchSuspended;

    return PopScope(
      canPop: (_currentIndex == 0 && !_searchMode && !isPanelOpen && !canPopInner),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // Back closes the TOPMOST thing. The player has a navigator of its own
        // (lyric provider sheet, options sheets, queue), and only this root
        // handler hears the system back - so it forwards to that navigator
        // before it brings the player down. See [resolveShellBack].
        final playerNav = musicProvider.playerNavigatorKey.currentState;
        // Read live, not from this build: a page pushed since the last build
        // must be what back closes (it used to fall through to "go Home").
        final shellNav = mainNavigatorKey.currentState;
        switch (resolveShellBack(
          isPanelOpen: isPanelOpen,
          playerCanPop: playerNav != null && playerNav.canPop(),
          detailCanPop: shellNav != null && shellNav.canPop(),
          searchMode: _searchMode,
          tabIndex: _currentIndex,
        )) {
          case ShellBackAction.popPlayerRoute:
            playerNav!.pop();
          case ShellBackAction.collapsePlayer:
            musicProvider.setPlayerExpanded(false);
          case ShellBackAction.popDetail:
            // maybePop, not pop: the page decides (selection or reorder mode
            // closes first, exactly like its own back button).
            shellNav?.maybePop();
          case ShellBackAction.exitSearch:
            _exitSearch();
          case ShellBackAction.goHome:
            _onItemTapped(0);
          case ShellBackAction.none:
            break;
        }
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent, // Ambient canvas shines through
        body: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final music = context.read<MusicProvider>();
            final hasMini = music.currentTrack != null && !music.hideMiniPlayer;
            if (hasMini) {
              _minimizeController.handleNotification(notification);
            }
            return false;
          },
          child: Stack(
            children: [
              // z-0: ambient album-art canvas (visible where screens are
              // transparent; opaque screens are migrated in P5).
              const AmbientBackdrop(),
              Navigator(
                key: mainNavigatorKey,
                // Sheets and dialogs shown from inside the shell open here,
                // UNDER the nav bar and pill; this lets them step aside.
                observers: [ModalRouteTracker.shell, ShellPageTracker.instance],
                onGenerateRoute: (settings) {
                  return MaterialPageRoute(
                    settings: settings,
                    builder: (_) => ValueListenableBuilder<({int index, bool searchMode})>(
                      valueListenable: _tabState,
                      builder: (context, state, _) {
                        return FadeIndexedStack(
                          index: state.index,
                          children: [
                            TickerMode(
                              enabled: state.index == 0,
                              child: const ThemedHomeScreen(),
                            ),
                            TickerMode(
                              enabled: state.index == 1 && !state.searchMode,
                              child: ThemedExploreScreen(
                                isActive: state.index == 1 && !state.searchMode,
                              ),
                            ),
                            TickerMode(
                              enabled: state.index == 2,
                              child: ThemedLibraryScreen(
                                isActive: state.index == 2,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
              // Search overlay (in-place transition). The nav bar's search
              // pill morphs into the input; the overlay shows only tabs +
              // results.
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
                child: showSearchOverlay
                    ? Builder(
                        key: const ValueKey('search_overlay'),
                        builder: (_) => themeProvider.isMaterialYou
                            ? ThemedSearchScreen(onPushDetail: _pushDetailFromSearch)
                            : SearchScreen(
                                key: const ValueKey('embedded_search'),
                                embedded: true,
                                externalController: _searchController,
                                externalFocusNode: _searchFocus,
                                onPushDetail: _pushDetailFromSearch,
                              ),
                      )
                    : const SizedBox.shrink(key: ValueKey('search_gone')),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          // The nav bar (and the pill it hosts) is painted over the shell's
          // navigator, so a sheet opened from a tab could never cover it.
          child: StepAsideForModals(
          child: themeProvider.isMaterialYou
              ? Row(
                  children: [
                    Expanded(
                      child: ThemedNavBar(
                        currentIndex: _currentIndex,
                        onTap: _onItemTapped,
                        items: const [
                          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), activeIcon: Icon(Icons.home_filled), label: 'Home'),
                          BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), activeIcon: Icon(Icons.explore_rounded), label: 'Explore'),
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
                      child: showSearchOverlay
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
                )
              : ThemedNavBar(
                  currentIndex: _currentIndex,
                  onTap: _onItemTapped,
                  searchMode: showSearchOverlay,
                  minimizeController: hasMiniPlayer ? _minimizeController : null,
                  onMinimizedTabTap: _minimizeController.expand,
                  onExpandPlayer: () =>
                      Provider.of<MusicProvider>(context, listen: false)
                          .setPlayerExpanded(true),
                  onSearchToggle: (active) {
                    if (active) {
                      _enterSearch();
                    } else {
                      _exitSearch();
                    }
                  },
                  searchController: _searchController,
                  searchFocusNode: _searchFocus,
                  onSearchSubmitted: (query) {
                    _searchFocus.unfocus();
                    if (query.trim().isEmpty) return;
                    final mp = Provider.of<MusicProvider>(context, listen: false);
                    // Honors the visible filter chip instead of forcing tracks.
                    mp.resubmitActiveSearch(query);
                  },
                  onSearchCancel: () {
                    _exitSearch();
                    _onItemTapped(0);
                  },
                  items: const [
                    BottomNavigationBarItem(icon: Icon(Icons.home_rounded), activeIcon: Icon(Icons.home_filled), label: 'Home'),
                    BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), activeIcon: Icon(Icons.explore_rounded), label: 'Explore'),
                    BottomNavigationBarItem(icon: Icon(Icons.library_music_outlined), activeIcon: Icon(Icons.library_music_rounded), label: 'Library'),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}
