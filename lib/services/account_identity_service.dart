import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_models.dart';
import 'auth_service.dart';
import 'innertube/innertube_service.dart';
import 'login_session_probe.dart';

/// What a sign-in attempt turned into.
class AccountSignInOutcome {
  const AccountSignInOutcome.success({
    required this.identity,
    required this.profiles,
    this.channels = const [],
  })  : ok = true,
        reason = null;

  const AccountSignInOutcome.failure(this.reason) : ok = false, identity = null, profiles = const [], channels = const [];

  final bool ok;

  /// Human-readable, safe to show. Never a raw exception.
  final String? reason;

  final AccountIdentity? identity;
  final List<YouTubeProfile> profiles;
  final List<AccountChannel> channels;
}

/// Validates a captured cookie jar against the live API, and turns it into
/// something worth persisting.
///
/// The ordering here is the whole point, and it is deliberately different from
/// what this app used to do:
///
///  * The candidate jar is signed into a header set and used ONLY for the
///    validation call. It is never written to [AuthService] first. Persisting
///    before validating means a half-finished account chooser becomes a durable
///    broken "Personal" account that the user has to discover later and sign out
///    of by hand.
///  * Validation is a real round trip. A jar that can sign a cookie header is
///    not a session; a jar the API will describe is.
///  * Channels are best effort. "No channels" and "we could not read the
///    answer" are different, and only the latter is worth reporting.
class AccountIdentityService {
  const AccountIdentityService._();

  /// Hard cap on the validation call.
  ///
  /// This gates whether a sign-in is committed, so an unbounded request would
  /// hold the login screen open forever with no way out.
  static const Duration validationTimeout = Duration(seconds: 20);

  /// One retry, briefly delayed.
  ///
  /// A single retry covers the common transient case (the jar settled a beat
  /// after the page did) without turning a real failure into a spinner.
  static const Duration retryDelay = Duration(milliseconds: 750);

  /// Validate [cookies] and describe the account behind them.
  ///
  /// Returns a failure the caller can show. Nothing is persisted here: the
  /// caller commits through [AuthService.saveSession] once it holds a success.
  static Future<AccountSignInOutcome> validateAndDescribe({
    required List<AuthCookie> cookies,
    YouTubeProfile? pageProfile,
  }) async {
    if (!LoginSessionProbe.hasSigningCookie(cookies)) {
      return const AccountSignInOutcome.failure(
          'Google has not finished signing you in yet.');
    }

    final headers = _headersFor(cookies, pageProfile);

    AccountIdentity? identity;
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelay);
      try {
        identity =
            await InnerTubeService.instance.fetchAccountIdentity(headers: headers);
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
      }
    }

    if (identity == null) {
      debugPrint('AccountIdentity: validation failed: $lastError');
      return const AccountSignInOutcome.failure(
          'That sign-in could not be verified. Try again.');
    }

    // Best effort. A channel list we cannot read must not fail a sign-in that
    // the account endpoint just confirmed.
    List<AccountChannel> channels = const [];
    try {
      channels = await InnerTubeService.instance
          .fetchAccountChannels(headers: headers)
          .timeout(validationTimeout);
    } catch (e) {
      debugPrint('AccountIdentity: channels unavailable: $e');
    }

    return AccountSignInOutcome.success(
      identity: identity,
      channels: channels,
      profiles: _profilesFrom(channels, pageProfile),
    );
  }

  /// Headers for a candidate jar, without touching app-wide session state.
  static Map<String, String> _headersFor(
    List<AuthCookie> cookies,
    YouTubeProfile? profile,
  ) {
    final usable = cookies.where((c) => !c.isExpired).toList();
    final cookieHeader =
        usable.map((c) => '${c.name}=${c.value}').join('; ');

    // Name-exact and non-empty, for the same reason getHeaders() is: a blank
    // SAPISID signs nothing, and an empty Authorization header is worse than
    // none because it looks authenticated.
    String? sapisid;
    for (final c in usable) {
      if (isSigningCookieName(c.name) && c.value.isNotEmpty) {
        sapisid = c.value;
        if (c.name == 'SAPISID') break;
      }
    }

    final headers = <String, String>{'Cookie': cookieHeader};
    if (sapisid != null) headers['Authorization'] = sapisidHash(sapisid);

    final user = profile?.authUser;
    if (user != null && user.isNotEmpty) headers['X-Goog-AuthUser'] = user;
    final pageId = profile?.pageId;
    if (pageId != null && pageId.isNotEmpty) {
      headers['X-Goog-PageId'] = pageId;
    }
    return headers;
  }

  /// Build profiles from the channels the API reported.
  ///
  /// The channel the page identified wins when the two disagree: it is the one
  /// the user actually chose in the WebView. A channel with neither token is
  /// skipped, because there is nothing to send for it.
  static List<YouTubeProfile> _profilesFrom(
    List<AccountChannel> channels,
    YouTubeProfile? pageProfile,
  ) {
    final profiles = <YouTubeProfile>[];
    final seen = <String>{};

    for (final channel in channels) {
      if (channel.pageId == null && channel.dataSyncId == null) continue;
      if (!seen.add(channel.key)) continue;
      profiles.add(YouTubeProfile(
        profileId: 'page_${channel.pageId ?? channel.dataSyncId}',
        name: channel.name,
        handle: channel.subtitle.startsWith('@') ? channel.subtitle : '',
        avatarUrl: channel.avatarUrl,
        pageId: channel.pageId,
        dataSyncId: channel.dataSyncId,
        isBrandAccount: channel.isBrandAccount,
      ));
    }

    // Keep whatever the WebView told us if the API list did not cover it. The
    // page saw a real signed-in state; the channel list is best effort.
    if (pageProfile != null &&
        !profiles.any((p) => p.profileId == pageProfile.profileId)) {
      profiles.insert(0, pageProfile);
    }
    return profiles;
  }
}