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

