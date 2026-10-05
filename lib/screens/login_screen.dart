import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/navigation/root_navigator.dart';
import '../design/tokens/motion.dart';
import '../design/tokens/space.dart';
import '../services/account_identity_service.dart';
import '../services/auth_models.dart';
import '../services/auth_service.dart';
import '../services/google_cookie_cleaner.dart';
import '../services/login_session_probe.dart';
import '../widgets/glass_circle_button.dart';

/// Google sign-in, captured into [AuthService].
///
/// Two decisions here were not obvious, and both cost a real bug somewhere:
///
///  * **Nothing is captured automatically.** Persisting on page-finish is a
///    race: the jar settles after the page does, so auto-capture commits
///    whatever half of the account chooser happened to be showing and closes
///    the screen, leaving a durable account that cannot sign anything. So the
///    jar is only READ to decide whether to offer the confirm button, and
///    nothing is written until the user taps "Use this profile".
///  * **The session is validated before it is stored.** A jar that can sign a
///    cookie header is not proof of a working session; a jar the API will
///    describe is. See [AccountIdentityService].
///
/// The cookie jar is read per host and handed to [LoginSessionProbe], which
/// holds the rules. This screen owns no parsing.
///
/// Sign-out does NOT clear the WebView jar; a fresh sign-in does, but only the
/// Google identity cookies (see [GoogleCookieCleaner]) so other saved accounts
/// keep working.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.addAnotherAccount = false});

  /// Ask Google for the account chooser and clear the existing jar, so a
  /// second account can be added without touching the first.
  final bool addAnotherAccount;

  /// Opens the WebView and returns the saved account id, or null if the user
  /// backed out without completing a sign-in.
  ///
  /// Pushed ABOVE the shell: a sign-in page is full-bleed, and pushing it into
  /// the nested detail navigator would leave the tab bar and the mini-player
  /// floating over Google's sign-in form.
  static Future<String?> open(BuildContext context,
      {bool addAnotherAccount = false}) {
    return pushAboveShell<String>(
      context,
      LoginScreen(addAnotherAccount: addAnotherAccount),
    );
  }

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Where the capture currently stands. Drives every label on the screen, so the
/// UI cannot claim more certainty than it has.
enum _LoginPhase {
  /// Page has not exposed a signed-in identity yet. Nothing to offer.
  waiting,

  /// A jar that can sign is present. Awaiting the user's confirmation.
  ready,

  /// Round-tripping the account endpoint.
  checking,

  /// The attempt did not take. [LoginScreen] holds the reason.
  failed,
}

class _LoginScreenState extends State<LoginScreen> {
  final CookieManager _cookieManager = CookieManager.instance();

  /// Whether the WebView has finished painting. Drives the close button, which
  /// is hidden until there is something to close.
  bool _pageReady = false;
  bool _isLoading = true;

  _LoginPhase _phase = _LoginPhase.waiting;
  String? _reason;

  /// Re-arms the read on every navigation and on a slow poll.
  ///
  /// Reading is cheap and side-effect free - it only decides whether to OFFER
  /// the confirm button - so being eager here costs nothing and means the
  /// button is already there when the user looks for it.
  Timer? _pollTimer;

  /// Guards against overlapping reads committing twice.
  bool _busy = false;

  /// A confirmed jar, held between the tap and the validation round trip.
  List<AuthCookie>? _candidate;

  InAppWebViewController? _controller;

  @override
  void initState() {
    super.initState();

    if (widget.addAnotherAccount) {
      // Scoped to the Google identity cookies: enough for Google to offer the
      // chooser, without touching the cookies holding any other saved account.
      unawaited(GoogleCookieCleaner(_cookieManager).clear());
    }

    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) unawaited(_refreshReadiness());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Read the jar and decide whether to offer the confirm button.
  ///
  /// Never writes anything.
  Future<void> _refreshReadiness() async {
    if (_busy || _phase == _LoginPhase.checking) return;
    try {
      final jar = await _readJar();
      if (!mounted) return;
      if (jar.isEmpty || !LoginSessionProbe.hasSigningCookie(jar)) {
        if (_phase != _LoginPhase.failed) {
          setState(() {
            _phase = _LoginPhase.waiting;
            _reason = null;
          });
        }
        return;
      }
      _candidate = jar;
      if (_phase != _LoginPhase.failed) {
        setState(() => _phase = _LoginPhase.ready);
      }
    } catch (e) {
      debugPrint('LoginScreen: readiness read failed: $e');
    }
  }

  /// Confirm the captured profile, validate it, then commit.
  Future<void> _confirmProfile() async {
    final jar = _candidate;
    if (jar == null || _busy) return;

    _busy = true;
    setState(() {
      _phase = _LoginPhase.checking;
      _reason = null;
    });
    HapticFeedback.lightImpact();

    final outcome = await AccountIdentityService.validateAndDescribe(
      cookies: jar,
      pageProfile: await _readProfile(),
    );

    if (!mounted) return;
    _busy = false;

    if (!outcome.ok) {
      // Stay on the screen and say why. Closing here is what strands people:
      // the account is not saved, and the sheet they came from says signed in.
      setState(() {
        _phase = _LoginPhase.failed;
        _reason = outcome.reason ?? 'That sign-in could not be verified.';
      });
      HapticFeedback.heavyImpact();
      return;
    }

    final identity = outcome.identity!;
    final profiles = outcome.profiles;

    await AuthService().saveSession(
      cookies: jar,
      email: identity.email.isEmpty ? null : identity.email,
      displayName: identity.name,
      avatarUrl: identity.avatarUrl,
      profile: profiles.isEmpty ? null : profiles.first,
      incomingProfiles: profiles,
    );

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(AuthService().activeAccountId);
  }

  /// Merge the per-host jars, music origin first so its values win.
  ///
  /// Two platform quirks are handled here and neither is cosmetic:
  ///
  ///  * Android reports `domain` and `expiresDate` only when the WebView
  ///    supports `GET_COOKIE_INFO`, and many builds do not. A null domain
  ///    therefore falls back to the host the cookie was read from, otherwise
  ///    every Android cookie looks host-agnostic.
  ///  * `expiresDate` is milliseconds, while the probe takes seconds. Reading it
  ///    as seconds would date every cookie 50,000 years in the past and silently
  ///    drop the whole jar.
  Future<List<AuthCookie>> _readJar() async {
    final merged = <AuthCookie>[];
    for (final host in LoginSessionProbe.sessionHosts) {
      try {
        final cookies = await _cookieManager.getCookies(url: WebUri(host));
        for (final c in cookies) {
          final name = c.name;
          final value = c.value?.toString() ?? '';
          if (name.isEmpty || value.isEmpty) continue;
          final domain =
              (c.domain?.isNotEmpty ?? false) ? c.domain! : _hostOf(host);
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

  static String _hostOf(String url) => Uri.tryParse(url)?.host ?? '';

  /// Pull the signed-in channel out of the page's ytcfg.
  ///
  /// Best effort. A jar that validates is a real session even if the page never
  /// exposed a profile, and refusing to save over a missing convenience field
  /// would log the user out for nothing.
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
      if (raw is! String || raw.isEmpty) return null;
      return LoginSessionProbe.profileFromYtcfg(_decodeLoose(raw));
    } catch (e) {
      debugPrint('LoginScreen: ytcfg read failed: $e');
      return null;
    }
  }

  /// `evaluateJavascript` hands back whatever the page returned, which is a
  /// JSON string here. Tolerate it arriving already unquoted rather than
  /// discarding a real identity over one layer of encoding.
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

  String get _hint {
    switch (_phase) {
      case _LoginPhase.waiting:
        return widget.addAnotherAccount
            ? 'Finish signing in, then use this profile.'
            : 'Sign in with Google, then use this profile.';
      case _LoginPhase.ready:
      case _LoginPhase.checking:
        return 'Switch using the avatar, then use this profile.';
      case _LoginPhase.failed:
        return _reason ?? 'No signed-in profile is available on this page yet.';
    }
  }

  String get _actionLabel {
    switch (_phase) {
      case _LoginPhase.ready:
        return 'Use this profile';
      case _LoginPhase.checking:
        return 'Checking';
      case _LoginPhase.waiting:
      case _LoginPhase.failed:
        return 'Use this profile';
    }
  }

  bool get _actionEnabled => _phase == _LoginPhase.ready || _phase == _LoginPhase.failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Explicitly opaque, and independent of the theme. This screen is pushed
    // into the nested detail navigator when it is reached from the frozen
    // Material You settings screen, and a transparent Scaffold there lets
    // MainScreen's tab bar, mini-player and FAB show through Google's form.
    final background = theme.scaffoldBackgroundColor;

    // System insets, read once here and applied to the layers below.
    //
    // The status bar inset is not decoration. A full-bleed WebView puts
    // YouTube's own header - hamburger, logo, "Open App", search, avatar - at
    // the very top of the viewport, where it renders UNDER the clock and the
    // notification icons. Two overlapping bars of system chrome is not something
    // the user can read past. Insetting the page gives YTM's header clear air.
    final media = MediaQuery.of(context);
    final topInset = media.padding.top;
    final bottomInset = media.padding.bottom;

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          // Opaque base for the whole screen, including the inset bands. A
          // WebView that has not painted is transparent, and a transparent band
          // behind the status bar would show the shell again.
          Positioned.fill(child: ColoredBox(color: background)),

          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            bottom: 0,
            child: _webView(),
          ),

          // Only over the page area, so the spinner is centred in the content
          // the user is actually looking at rather than in the padded viewport.
          if (_isLoading)
            Positioned(
              top: topInset,
              left: 0,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: background,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),

          // Chrome floats over the page rather than displacing it, so nothing
          // reflows when the header appears or the phase changes.
          if (_pageReady)
            Positioned(
              top: topInset + Spacing.xs,
              left: Spacing.md,
              child: _CloseButton(onTap: () => Navigator.of(context).maybePop()),
            ),

          if (_pageReady)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset,
              child: _Header(
                hint: _hint,
                actionLabel: _actionLabel,
                enabled: _actionEnabled,
                busy: _phase == _LoginPhase.checking,
                failed: _phase == _LoginPhase.failed,
                onConfirm: _confirmProfile,
              ),
            ),
        ],
      ),
    );
  }

  Widget _webView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_signInUrl())),
      initialSettings: InAppWebViewSettings(
        userAgent: _userAgent,
        javaScriptEnabled: true,
        // The WebView is the sign-in surface only; caching it serves a stale
        // consent interstitial on the next attempt.
        cacheEnabled: false,
        clearCache: true,
      ),
      onWebViewCreated: (controller) => _controller = controller,
      onLoadStart: (controller, url) {
        if (mounted) setState(() => _isLoading = true);
      },
      onLoadStop: (controller, url) async {
        final onMusicOrigin =
            url?.host.toLowerCase().contains('music.youtube.com') ?? false;
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _pageReady = true;
        });

        // ytcfg and the music-scoped cookies do not exist on
        // accounts.google.com. Visit the music origin once, and let its
        // load-stop do the reading with a complete jar.
        if (onMusicOrigin) {
          await _refreshReadiness();
        } else if (LoginSessionProbe.hasSigningCookie(await _readJar())) {
          await _controller?.loadUrl(
            urlRequest: URLRequest(url: WebUri('https://music.youtube.com')),
          );
        }
      },
    );
  }

  /// `prompt=select_account` is what makes "add another account" possible
  /// without deleting the cookies that hold the existing ones.
  String _signInUrl() {
    const base = 'https://accounts.google.com/ServiceLogin?service=youtube';
    return widget.addAnotherAccount ? '$base&prompt=select_account' : base;
  }

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36';
}

/// Floating circular close, matching the header affordance on the sign-in
/// surface it replaces.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCircleButton(
      onTap: onTap,
      icon: Icons.close_rounded,
      semanticLabel: 'Close',
    );
  }
}

/// Title, honest hint, and the one action that commits a session.
class _Header extends StatelessWidget {
  const _Header({
    required this.hint,
    required this.actionLabel,
    required this.enabled,
    required this.busy,
    required this.failed,
    required this.onConfirm,
  });

  final String hint;
  final String actionLabel;
  final bool enabled;
  final bool busy;
  final bool failed;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      // Opaque rather than a scrim: this sits over a WebView, and a
      // translucent panel over a scrolling page is unreadable exactly where the
      // hint text lands.
      color: theme.scaffoldBackgroundColor,
      // No bottom inset here - the caller already positioned this panel above
      // the system inset. Applying it in both places doubles the gap and pushes
      // the button further from the gesture bar than any other screen.
      padding: const EdgeInsets.fromLTRB(
          Spacing.screenX, Spacing.lg, Spacing.screenX, Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Sign in to YouTube Music',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Spacing.xs),
          // Two lines, because the honest version of this sentence does not fit
          // one on a narrow screen and truncating it to "Switch using the
          // avat..." tells the user nothing.
          Text(
            hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: enabled && !busy ? onConfirm : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor:
                    failed ? theme.colorScheme.errorContainer : null,
                foregroundColor:
                    failed ? theme.colorScheme.onErrorContainer : null,
              ),
              child: AnimatedSwitcher(
                duration: Motion.fast,
                switchInCurve: Motion.enter,
                switchOutCurve: Motion.exit,
                // Scale rather than a fade: a cross-fade would put two labels
                // in the tree at once, and the button is the one thing on this
                // screen that must not say two things at the same time.
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                  child: child,
                ),
                child: Text(
                  actionLabel,
                  key: ValueKey(actionLabel),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}