import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Deep link routes the app understands.
enum DeepLinkRoute {
  /// minemusic://track/<id>
  track,
  /// minemusic://album/<id>
  album,
  /// minemusic://playlist/<id>
  playlist,
  /// minemusic://artist/<id>
  artist,
  /// minemusic://search?q=<query>
  search,
  /// minemusic://nowplaying
  nowPlaying,
}

/// Parsed deep link.
class DeepLink {
  const DeepLink({required this.route, this.id, this.query});

  final DeepLinkRoute route;
  final String? id;
  final String? query;
}

/// Listens for `minemusic://` links and emits parsed [DeepLink]s.
///
/// Handles cold start (initial link) and warm start (stream).
class DeepLinkService {
  DeepLinkService() : _appLinks = AppLinks();

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;
  bool _initialHandled = false;

  final _controller = StreamController<DeepLink>.broadcast();
  Stream<DeepLink> get links => _controller.stream;

  /// True if the URI targets our scheme and parses to a known route.
  DeepLink? parseUri(Uri uri) {
    if (uri.scheme != 'minemusic') return null;

    switch (uri.host) {
      case 'track':
      case 'album':
      case 'playlist':
      case 'artist':
        final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
        if (id == null || id.isEmpty) return null;
        return DeepLink(route: _routeFor(uri.host), id: id);
      case 'search':
        final q = uri.queryParameters['q'];
        if (q == null || q.isEmpty) return null;
        return DeepLink(route: DeepLinkRoute.search, query: q);
      case 'nowplaying':
        return const DeepLink(route: DeepLinkRoute.nowPlaying);
      default:
        return null;
    }
  }

  DeepLinkRoute _routeFor(String host) {
    switch (host) {
      case 'album':
        return DeepLinkRoute.album;
      case 'playlist':
        return DeepLinkRoute.playlist;
      case 'artist':
        return DeepLinkRoute.artist;
      default:
        return DeepLinkRoute.track;
    }
  }

  void start() {
    if (_sub != null) return;

    // Cold start: initial link arrives once, before the first frame.
    unawaited(_appLinks.getInitialLink().then((uri) {
      if (_initialHandled) return;
      _initialHandled = true;
      _emit(uri);
    }));

    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        // app_links replays the initial link through the stream on some
        // platforms; dedupe so cold start doesn't fire twice.
        if (!_initialHandled) {
          _initialHandled = true;
        }
        _emit(uri);
      },
      onError: (Object e) {
        debugPrint('DeepLinkService: stream error: $e');
      },
    );
  }

  void _emit(Uri? uri) {
    if (uri == null) return;
    final link = parseUri(uri);
    if (link != null) {
      _controller.add(link);
    } else if (kDebugMode) {
      debugPrint('DeepLinkService: ignored ${uri.toString()}');
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}
