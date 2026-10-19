import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Root navigator key — lets player-originated actions (options sheet,
/// equalizer, detail screens) push above the global overlay stack.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Main navigator key — hosts detail screens (Artist, Album, Playlist)
/// inside MainScreen so that ThemedNavBar and the mini-player pill remain
/// permanently visible and synchronized with scroll minimization.
final GlobalKey<NavigatorState> mainNavigatorKey = GlobalKey<NavigatorState>();

/// Route observer for the ROOT navigator: whether a full page sits above the
/// shell ([isAtRoot]) and, through [ModalRouteTracker], whether a sheet or
/// dialog is open.
///
/// Only PAGE routes count toward [isAtRoot]. It used to count every route, so a
/// bottom sheet or dialog opened on the root navigator from Home made the app
/// believe it had left MainScreen - and the overlay then drew its floating mini
/// pill (meant for pushed pages with no nav bar) straight on top of the sheet.
class AppRouteObserver extends ModalRouteTracker {
  static final AppRouteObserver instance = AppRouteObserver._();
  AppRouteObserver._();

  final ValueNotifier<bool> isAtRoot = ValueNotifier<bool>(true);
  final Set<Route<dynamic>> _pages = {};

  void _sync() => isAtRoot.value = _pages.isEmpty;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    // The first route is the shell itself.
    if (previousRoute != null && route is PageRoute) _pages.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _pages.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _pages.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null && _pages.remove(oldRoute) && newRoute is PageRoute) {
      _pages.add(newRoute);
    }
    _sync();
  }
}

/// Tracks sheets, dialogs and menus ([PopupRoute]s) open on a navigator.
///
/// The mini pill and the nav bar are painted ABOVE the navigators that show
/// sheets (the pill in `MaterialApp.builder`, the nav bar over the shell's own
/// navigator), so a modal could never cover them: the pill sat on top of the
/// sign-in sheet, the song options, every dialog. Every navigator that can show
/// a modal gets one of these, and [anyModalOpen] tells the chrome to step aside.
///
/// One instance per navigator (Flutter allows an observer on one navigator
/// only); they share the open set.
class ModalRouteTracker extends NavigatorObserver {
  ModalRouteTracker();

  /// For the shell's nested navigator ([mainNavigatorKey]).
  static final ModalRouteTracker shell = ModalRouteTracker();

  static final Set<Route<dynamic>> _open = {};
  static final ValueNotifier<bool> _anyOpen = ValueNotifier<bool>(false);

  /// True while any tracked navigator shows a sheet, dialog or menu.
  static ValueListenable<bool> get anyModalOpen => _anyOpen;

  static void _update() => _anyOpen.value = _open.isNotEmpty;

  @visibleForTesting
  static void debugReset() {
    _open.clear();
    _update();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PopupRoute) {
      _open.add(route);
      _update();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_open.remove(route)) _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_open.remove(route)) _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute != null && _open.remove(oldRoute)) _update();
    if (newRoute is PopupRoute) {
      _open.add(newRoute);
      _update();
    }
  }
}

/// Slides [child] down and out of the way while a sheet or dialog is open, and
/// back when it closes. Untappable while hidden. Instant under reduce motion.
class StepAsideForModals extends StatelessWidget {
  const StepAsideForModals({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ValueListenableBuilder<bool>(
      valueListenable: ModalRouteTracker.anyModalOpen,
      child: child,
      builder: (context, open, child) => IgnorePointer(
        ignoring: open,
        child: AnimatedSlide(
          offset: open ? const Offset(0, 1.4) : Offset.zero,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
          curve: open ? Curves.easeInCubic : Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: open ? 0 : 1,
            duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The root navigator's state, if the app has one up yet.
NavigatorState? get rootNavigatorState => rootNavigatorKey.currentState;

/// Push [page] ABOVE the whole shell - nav bar and mini-player included.
///
/// `Navigator.push(context, ...)` resolves to the NEAREST enclosing navigator,
/// and in this app that is [mainNavigatorKey]: the nested navigator inside
/// MainScreen that deliberately keeps ThemedNavBar and the mini-player pill
/// visible while a detail screen is open. That is exactly right for artist,
/// album and playlist pages, and exactly wrong for anything full-bleed.
///
/// Getting it wrong is invisible until a page has a body that does not paint
/// its own background. A login WebView showed the nav bar, the mini-player and
/// the FAB through the Google sign-in page, because the route was a child of
/// MainScreen rather than a sibling of it.
///
/// So: detail screens keep pushing normally. Full-screen auth, account and
/// settings surfaces go through here.
Future<T?> pushAboveShell<T>(
  BuildContext context,
  Widget page, {
  RouteSettings? settings,
}) {
  final rootContext = rootNavigatorKey.currentContext;
  // MaterialPageRoute is opaque by default and exposes no `opaque` parameter,
  // which is what we want: an opaque route is what keeps the shell out of the
  // new screen's pixels.
  if (rootContext == null) {
    // Before first frame, or after teardown. Falling back to the ambient
    // navigator is better than dropping the navigation entirely.
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(builder: (_) => page, settings: settings),
    );
  }
  return Navigator.of(rootContext, rootNavigator: true).push<T>(
    MaterialPageRoute<T>(builder: (_) => page, settings: settings),
  );
}

