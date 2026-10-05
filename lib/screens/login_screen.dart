import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/auth_models.dart';
import '../services/auth_service.dart';
import '../services/login_session_probe.dart';

/// Google sign-in, captured into [AuthService].
///
/// The cookie jar is read per host and handed to [LoginSessionProbe], which
/// holds the rules. Two things this screen deliberately does not do:
///
///  * It never calls `deleteAllCookies()`. Wiping the whole store tore down
///    every saved account's cookies the moment the screen opened - including
///    the session the app was happily running on - and made adding a second
///    account impossible, because the account it just deleted was the only
///    thing that had been signed in. `prompt=select_account` gets Google to
///    offer the chooser instead, with no collateral damage.
///  * It never reports success from the page alone. The page finishing says
///    nothing about whether the jar can sign a request, which is the only
///    definition of "logged in" that matters here.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.addAnotherAccount = false});

  /// Ask Google for the account chooser instead of reusing the cookie that is
  /// already in the WebView.
  final bool addAnotherAccount;

  /// Opens the WebView and returns the saved account id, or null if the user
  /// backed out without completing a sign-in.
  static Future<String?> open(BuildContext context,
      {bool addAnotherAccount = false}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LoginScreen(addAnotherAccount: addAnotherAccount),
      ),
    );
  }

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final CookieManager _cookieManager = CookieManager.instance();

  bool _isLoading = true;
  String? _busyReason;
  Timer? _pollTimer;

  /// Guards against two overlapping polls both committing a session. The timer
  /// and the WebView callbacks can both fire, and a double save would race two
  /// writes of the same registry.
  bool _committing = false;

  /// Whether the capture has already been retried from the music origin.
  ///
  /// Guards the redirect below from re-arming itself: once we have asked for
  /// music.youtube.com, a second request would restart the whole dance on every
  /// poll and could never settle.
  bool _visitedMusicOrigin = false;
  bool _isOnMusicOrigin = false;

  InAppWebViewController? _controller;

  @override
  void initState() {
    super.initState();

    // Poll as well as listen to navigation. The jar settles a beat after the
    // page lands, so a load-stop check alone misses it; a poll alone cannot
    // distinguish "still typing your password" from "done but redirecting".
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) unawaited(_tryComplete());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Read the jar and, if it can sign, capture the channel identity too.
  Future<void> _tryComplete() async {
    if (_committing) return;
    try {
      final jar = await _readJar();
      if (jar.isEmpty || !LoginSessionProbe.hasSigningCookie(jar)) return;

      // A signing cookie can appear while the WebView is still on
      // accounts.google.com, where there is no ytcfg and no music-scoped
      // cookies. Committing there would store a session with no channel
      // identity and no music-origin values, so visit the music origin once and
      // let its load-stop run the capture with a complete jar.
      if (!_visitedMusicOrigin && !_isOnMusicOrigin) {
        _visitedMusicOrigin = true;
        await _controller?.loadUrl(
          urlRequest: URLRequest(url: WebUri('https://music.youtube.com')),
        );
        return;
      }

      _committing = true;
      _pollTimer?.cancel();

      // The channel identity lives in ytcfg on the music origin. It is best
      // effort: a jar that can sign is a valid session even if the page never
      // gave us a profile, and refusing to save in that case would log the
      // user out over a missing convenience field.
      final profile = await _readProfile();
      await AuthService().saveSession(
        cookies: jar,
        profile: profile,
      );

      if (!mounted) return;
      Navigator.of(context)
          .pop(profile?.profileId ?? AuthService().activeAccountId);
    } catch (e, st) {
      debugPrint('LoginScreen: capture failed: $e\n$st');
      // Stay on the screen. Silently swallowing this is what made a completed
      // Google login look like a broken app.
      if (mounted) {
        setState(() => _busyReason = 'Could not read the session. Try again.');
      }
      _committing = false;
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) unawaited(_tryComplete());
      });
    }
  }

  /// Merge the per-host jars, music origin first so its values win.
  ///
  /// Two platform quirks are handled here and neither is cosmetic:
  ///
  ///  * Android reports `domain` and `expiresDate` only when the WebView
  ///    supports `GET_COOKIE_INFO`, and many builds do not. A null domain
  ///    therefore falls back to the host the cookie was read from, otherwise
  ///    every Android cookie looks host-agnostic and gets replayed anywhere.
  ///  * `expiresDate` is milliseconds, while `AuthCookie` stores a `DateTime`.
  ///    Reading it as seconds would date every cookie 50,000 years in the past
  ///    and silently drop the whole jar on the next load.
  Future<List<AuthCookie>> _readJar() async {
    final merged = <AuthCookie>[];
    for (final host in LoginSessionProbe.sessionHosts) {
      try {
        final cookies = await _cookieManager.getCookies(url: WebUri(host));
        for (final c in cookies) {
          final name = c.name;
          final value = c.value?.toString() ?? '';
          if (name.isEmpty || value.isEmpty) continue;
          final domain = (c.domain?.isNotEmpty ?? false) ? c.domain! : _hostOf(host);
          merged.add(LoginSessionProbe.cookie(
            name: name,
            value: value,
            domain: domain,
            expiresAt: _expiresSeconds(c),
          ));
        }
      } catch (e) {
        debugPrint('LoginScreen: cookie read failed for $host: $e');
      }
    }
    return LoginSessionProbe.coalesce(merged);
  }

  static int? _expiresSeconds(Cookie cookie) {
    final ms = cookie.expiresDate;
    if (ms == null || ms <= 0) return null;
    return ms ~/ 1000;
  }

  static String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host ?? '';
  }

  /// Pull the signed-in channel out of the page's ytcfg.
  Future<YouTubeProfile?> _readProfile() async {
    final controller = _controller;
    if (controller == null) return null;
    try {
      final raw = await controller.evaluateJavascript(
        source: r'''
          (function () {
            if (typeof ytcfg === 'undefined' || !ytcfg.get) return '';
            var out = {
              LOGGED_IN: ytcfg.get('LOGGED_IN'),
              DELEGATED_SESSION_ID: ytcfg.get('DELEGATED_SESSION_ID'),
              SESSION_INDEX: ytcfg.get('SESSION_INDEX'),
              PAGE_CL: ytcfg.get('PAGE_CL'),
              PAGE_ID: ytcfg.get('PAGE_ID')
            };
            return JSON.stringify(out);
          })();
        ''',
      );
      final text = raw is String ? raw : null;
      if (text == null || text.isEmpty) return null;
      final decoded = text.contains('{')
          ? _decodeLoose(text)
          : null;
      return LoginSessionProbe.profileFromYtcfg(decoded);
    } catch (e) {
      debugPrint('LoginScreen: ytcfg read failed: $e');
      return null;
    }
  }

  /// `evaluateJavascript` hands back whatever the page returned, which is a
  /// JSON string here. Tolerate it being handed back already unquoted rather
  /// than throwing the identity away over one layer of encoding.
  Map<String, dynamic>? _decodeLoose(String text) {
    var body = text;
    if (body.length >= 2 && body.startsWith('"') && body.endsWith('"')) {
      body = body.substring(1, body.length - 1);
    }
    for (final candidate in [body, Uri.decodeComponent(body)]) {
      try {
        final decoded = json.decode(candidate);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // try the next shape
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Log in to YouTube')),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(_signInUrl()),
            ),
            initialSettings: InAppWebViewSettings(
              userAgent: _userAgent,
              javaScriptEnabled: true,
              // The WebView is the sign-in surface only; caching it serves a
              // stale consent interstitial on the next attempt.
              cacheEnabled: false,
              clearCache: true,
            ),
            onWebViewCreated: (controller) => _controller = controller,
            onLoadStart: (controller, url) {
              _isOnMusicOrigin =
                  url?.host.toLowerCase().contains('music.youtube.com') ?? false;
              if (mounted) setState(() => _isLoading = true);
            },
            onLoadStop: (controller, url) async {
              if (url?.host.toLowerCase().contains('music.youtube.com') ??
                  false) {
                _isOnMusicOrigin = true;
              }
              if (mounted) setState(() => _isLoading = false);
              await _tryComplete();
            },
            onUpdateVisitedHistory: (controller, url, isReload) async {
              await _tryComplete();
            },
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
          if (_busyReason != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _busyReason!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tryComplete,
        label: const Text("I'm logged in"),
        icon: const Icon(Icons.check),
      ),
    );
  }

  /// `prompt=select_account` is what makes "add another account" possible
  /// without deleting the cookies that hold the existing ones.
  String _signInUrl() {
    const base =
        'https://accounts.google.com/ServiceLogin?service=youtube';
    return widget.addAnotherAccount ? '$base&prompt=select_account' : base;
  }

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36';
}