import 'package:flutter/material.dart';

/// Root navigator key — lets player-originated actions (options sheet,
/// equalizer, detail screens) push above the global overlay stack.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Main navigator key — hosts detail screens (Artist, Album, Playlist)
/// inside MainScreen so that ThemedNavBar and the mini-player pill remain
/// permanently visible and synchronized with scroll minimization.
final GlobalKey<NavigatorState> mainNavigatorKey = GlobalKey<NavigatorState>();

/// Route observer that tracks whether the navigator is currently at the root route.
class AppRouteObserver extends NavigatorObserver {
  static final AppRouteObserver instance = AppRouteObserver._();
  AppRouteObserver._();

  final ValueNotifier<bool> isAtRoot = ValueNotifier<bool>(true);
  int _routeDepth = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null) {
      _routeDepth++;
      isAtRoot.value = (_routeDepth == 0);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (_routeDepth > 0) {
      _routeDepth--;
      isAtRoot.value = (_routeDepth == 0);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (_routeDepth > 0) {
      _routeDepth--;
      isAtRoot.value = (_routeDepth == 0);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
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

