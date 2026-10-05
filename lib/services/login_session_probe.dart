import 'auth_models.dart';

/// Parsing of a WebView sign-in into a storable session.
///
/// The login screen used to hold this logic inline, which made three of its
/// assumptions untestable - and two of them were wrong:
///
///  * it required `SAPISID` *and* `__Secure-3PSID`. Google has been dropping
///    `__Secure-3PSID` from Android WebView sign-ins, so the screen could sit
///    there showing a completed Google login and never noticing.
///  * it folded the jar into a flat `name -> value` map, so a youtube.com
///    cookie silently overwrote the music.youtube.com one of the same name.
///
/// Everything here is pure so the rules can be pinned by tests, and the screen
/// only has to hand over what the platform gave it.
class LoginSessionProbe {
  const LoginSessionProbe._();

  /// Hosts whose cookies form a YouTube session.
  ///
  /// A jar is read per-host rather than merged into one map, because the same
  /// cookie name legitimately carries a different value per host.
  static const sessionHosts = <String>[
    'https://music.youtube.com',
    'https://www.youtube.com',
    'https://youtube.com',
  ];

  /// True once the jar can actually sign a request.
  ///
  /// Absence of a signing cookie is the only reliable "not signed in yet"
  /// signal - the page can look finished long before the jar settles.
  static bool hasSigningCookie(Iterable<AuthCookie> cookies) => cookies.any(
        // The value matters as much as the name: a blank SAPISID signs nothing,
        // and treating it as a live session is how the UI shows "connected"
        // while every request comes back unauthenticated.
        (c) => !c.isExpired &&
            c.value.isNotEmpty &&
            isSigningCookieName(c.name),
      );

  /// Build a cookie from whatever the platform reported.
  ///
  /// [expiresAt] is in seconds since the epoch, which is what the WebView's
  /// cookie model reports, so it converts here rather than at every call site.
  /// An unset or non-positive expiry is a session cookie and is deliberately
  /// kept as "never expires" rather than defaulted to the epoch, which would
  /// discard the cookie on the very next load.
  static AuthCookie cookie({
    required String name,
    required String value,
    String? domain,
    int? expiresAt,
  }) =>
      AuthCookie(
        name: name,
        value: value,
        domain: (domain == null || domain.trim().isEmpty) ? '' : domain.trim(),
        expiresAt: (expiresAt == null || expiresAt <= 0)
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000),
      );

  /// Collapse a multi-host jar to one cookie per name.
  ///
  /// Later hosts win, and the caller should therefore pass them in priority
  /// order. Music first: a session cookie scoped to the music origin is the one
  /// every request this app makes actually needs.
  static List<AuthCookie> coalesce(List<AuthCookie> cookies) {
    final byName = <String, AuthCookie>{};
    for (final c in cookies) {
      if (c.name.isEmpty) continue;
      byName[c.name] = c;
    }
    return byName.values.toList();
  }

  /// The profile YouTube reports for the signed-in channel.
  ///
  /// `DELEGATED_SESSION_ID` is the one field worth trusting: it is what Google
  /// itself puts in `context.user.onBehalfOfUser`, and answering a request with
  /// a value it cannot tie back to the cookie earns a 401. Name and avatar are
  /// simply absent from `ytcfg`, so they stay empty rather than being invented -
  /// an account named "YouTube Music" that is really someone's kitchen
  /// playlist is worse than an unnamed one.
  ///
  /// `sessionIndex` is preserved in [YouTubeProfile.authUser] only when there is
  /// more than one channel to choose between; a lone channel needs no selection.
  static YouTubeProfile? profileFromYtcfg(
    Map<String, dynamic>? cfg, {
    String? fallbackName,
  }) {
    if (cfg == null) return null;

    final loggedIn = cfg['LOGGED_IN'];
    if (loggedIn == false) return null;

    final rawSync = cfg['DELEGATED_SESSION_ID'];
    // `normalizeDataSyncId` answers '' for a blank input rather than null, so
    // the empty case has to be folded here or every "no identity" check below
    // silently passes.
    final normalizedSync =
        normalizeDataSyncId(rawSync is String ? rawSync : null);
    final dataSyncId = normalizedSync.isEmpty ? null : normalizedSync;

    final pageId = _asNonEmptyString(cfg['PAGE_CL']) ??
        _asNonEmptyString(cfg['PAGE_ID']) ??
        _asNonEmptyString(cfg['CHANNEL_ID']);

    final sessionIndex = cfg['SESSION_INDEX'];
    final index = sessionIndex is int ? sessionIndex : int.tryParse('$sessionIndex');

    // No channel-scoped identity at all: we know a session exists but cannot
    // say which channel it is. The caller keeps whatever it already had rather
    // than committing a guess.
    if (dataSyncId == null && pageId == null) return null;

    final id = index != null && index > 0 ? '$dataSyncId#$index' : dataSyncId;

    return YouTubeProfile(
      profileId: pageId != null
          ? 'page_$pageId'
          : (id != null ? 'sync_$id' : 'profile:unknown'),
      name: fallbackName ?? '',
      pageId: pageId,
      dataSyncId: dataSyncId,
      // Only meaningful when the account actually has several channels; with
      // one, sending an index Google did not ask for is a 401 risk for nothing.
      authUser: index != null && index > 0 ? '$_authUserPrefix$index' : null,
      isBrandAccount: pageId != null,
    );
  }

  static const _authUserPrefix = '0';

  static String? _asNonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Name-exact check for the cookie that can sign an InnerTube request.
///
/// A substring test for "SAPISID" also matches `SAPISIDHASH` and friends, which
/// are derived values and cannot be signed with.
bool isSigningCookieName(String name) => const <String>[
      'SAPISID',
      '__Secure-3PAPISID',
      '__Secure-1PAPISID',
    ].contains(name);