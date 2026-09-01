import 'package:flutter/material.dart';

/// Root navigator key — lets player-originated actions (options sheet,
/// equalizer, detail screens) push above the global overlay stack.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
