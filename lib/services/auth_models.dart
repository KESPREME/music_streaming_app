import 'dart:convert';

/// The signed-in viewer, as YouTube reports them.
///
/// Sourced from `account/account_menu`. This is the only place a real display
/// name, email and avatar come from - the cookie jar carries none of them, so
/// without this call every account has to render as an unnamed placeholder.
class AccountIdentity {
  const AccountIdentity({
    required this.name,
    this.email = '',
    this.avatarUrl,
  });

  final String name;
  final String email;
  final String? avatarUrl;

  /// What to show when YouTube gave us only a handle.
  String get subtitle {
    if (email.isNotEmpty) return email;
    if (name.startsWith('@')) return 'YouTube account';
    return 'YouTube account';
  }
}

/// One channel this session can act as: the account's own, or a brand channel.
///
/// [pageId] and [dataSyncId] are the two things a request must carry to be made
/// AS that channel. An entry with neither is dropped by the parser - there is
/// nothing to send, and offering a channel that silently keeps the current one
/// is worse than not offering it.
class AccountChannel {
  const AccountChannel({
    required this.name,
    this.subtitle = '',
    this.avatarUrl,
    this.pageId,
    this.dataSyncId,
    this.activeOnWeb = false,
  });

  final String name;
  final String subtitle;
  final String? avatarUrl;
  final String? pageId;
  final String? dataSyncId;

  /// Whether YouTube's own switcher marks this channel active.
  ///
  /// Deliberately NOT the same as "the one this app is acting as": that is our
  /// choice, this is Google's. They are independent and conflating them would
  /// make a tick lie.
  final bool activeOnWeb;

  /// Stable identity for this channel across refetches.
  String get key => pageId ?? dataSyncId ?? name;

  bool get isBrandAccount => pageId != null;

  /// A line under the name. Never blank - a row with a name and nothing else
  /// looks broken rather than terse.
  String get displaySubtitle {
    if (subtitle.isNotEmpty) return subtitle;
    return isBrandAccount ? 'Brand channel' : 'Your channel';
  }
}

/// One captured cookie, with the metadata needed to use it honestly.
///
/// [domain] is kept because a YouTube sign-in produces cookies scoped to both
/// `youtube.com` and `music.youtube.com`. Flattening both jars into one
/// name-keyed map means the same-named cookie from the wrong host can win, and a
/// value scoped to `youtube.com` gets replayed to `music.youtube.com`.
///
/// [expiresAt] is kept because without it a stale jar looks valid forever: the
/// app would report itself signed in and send cookies Google has already
/// rejected, which surfaces as "logged in but nothing works".
class AuthCookie {
  const AuthCookie({
    required this.name,
    required this.value,
    this.domain = '',
    this.expiresAt,
  });

  final String name;
  final String value;
  final String domain;

  /// Null when the cookie is a session cookie with no stated expiry.
  final DateTime? expiresAt;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Whether this cookie should be sent to [host].
  ///
  /// A cookie with no domain is assumed to belong to the host it was captured
  /// from, which is what the WebView cookie manager reports for a session cookie.
  bool appliesTo(String host) {
    // No domain is a session cookie, which the WebView reports without one.
    // Sending it to the host it was captured from is the only answer available.
    if (domain.isEmpty) return true;
    final d = domain.startsWith('.') ? domain.substring(1) : domain;
    // Exact match, or the host is a subdomain of the cookie's domain.
    //
    // The reverse is deliberately NOT accepted: a cookie scoped to
    // `music.youtube.com` does not belong on `youtube.com`, and neither does one
    // scoped to `youtube.com` get replayed to a host that is not underneath it.
    // Comparing the tail in either direction is what let a music-scoped value
    // leak onto the parent domain.
    return host == d || host.endsWith('.$d');
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        if (domain.isNotEmpty) 'domain': domain,
        if (expiresAt != null) 'expiresAt': expiresAt!.millisecondsSinceEpoch,
      };

  static AuthCookie? tryParse(Object? raw) {
    if (raw is Map) {
      final name = raw['name']?.toString() ?? '';
      final value = raw['value']?.toString() ?? '';
      if (name.isEmpty || value.isEmpty) return null;
      final ms = raw['expiresAt'];
      return AuthCookie(
        name: name,
        value: value,
        domain: raw['domain']?.toString() ?? '',
        expiresAt:
            ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null,
      );
    }
    // Legacy shape: a bare "name" -> "value" string, which is all the previous
    // implementation ever wrote. Readable so an existing install keeps its
    // session through the upgrade.
    if (raw is String) {
      return AuthCookie(name: raw, value: '');
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AuthCookie &&
      other.name == name &&
      other.value == value &&
      other.domain == domain &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(name, value, domain, expiresAt);
}

/// A YouTube profile (channel) available under one Google login.
///
/// One Google account carries every identity the browser has ever signed into,
/// plus every brand channel hanging off them. Nothing in the cookie says which
/// one is meant, so this is the only place that answer can live.
class YouTubeProfile {
  const YouTubeProfile({
    required this.profileId,
    required this.name,
    this.handle = '',
    this.avatarUrl,
    this.pageId,
    this.dataSyncId,
    this.authUser,
    this.isBrandAccount = false,
  });

  final String profileId;
  final String name;
  final String handle;
  final String? avatarUrl;

  /// `X-Goog-PageId` / `PLUS_PAGE_ID`. Present for a brand channel, absent for
  /// a personal one.
  final String? pageId;

  /// `context.user.onBehalfOfUser`. Never guess this: Google answers an
  /// `onBehalfOfUser` it cannot tie to the cookie with a 401.
  final String? dataSyncId;

  /// `X-Goog-AuthUser` - which jar entry is speaking.
  final String? authUser;

  final bool isBrandAccount;

  /// Whether this profile carries a real identity, as opposed to a placeholder
  /// derived from a display name before YouTube told us anything.
  bool get hasRealIdentity => pageId != null || dataSyncId != null;

  /// What to show under the name when there is no handle.
  String get subtitle => handle.isNotEmpty
      ? handle
      : (isBrandAccount ? 'Brand account' : 'Personal');

  YouTubeProfile copyWith({
    String? name,
    String? handle,
    String? avatarUrl,
    String? pageId,
    String? dataSyncId,
    String? authUser,
    bool? isBrandAccount,
  }) =>
      YouTubeProfile(
        profileId: profileId,
        name: name ?? this.name,
        handle: handle ?? this.handle,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        pageId: pageId ?? this.pageId,
        dataSyncId: dataSyncId ?? this.dataSyncId,
        authUser: authUser ?? this.authUser,
        isBrandAccount: isBrandAccount ?? this.isBrandAccount,
      );

  Map<String, dynamic> toJson() => {
        'id': profileId,
        'name': name,
        'handle': handle,
        if (avatarUrl != null) 'avatar': avatarUrl,
        if (pageId != null) 'pageId': pageId,
        if (dataSyncId != null) 'dataSyncId': dataSyncId,
        if (authUser != null) 'authUser': authUser,
        'brand': isBrandAccount,
      };

  static YouTubeProfile? tryParse(Map<String, dynamic> raw) {
    final id = raw['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return YouTubeProfile(
      profileId: id,
      name: raw['name']?.toString() ?? '',
      handle: raw['handle']?.toString() ?? '',
      avatarUrl: raw['avatar']?.toString(),
      pageId: raw['pageId']?.toString(),
      dataSyncId: raw['dataSyncId']?.toString(),
      authUser: raw['authUser']?.toString(),
      isBrandAccount: raw['brand'] == true,
    );
  }
}

/// A Google login, kept independently from every other captured login.
///
/// Each account owns its own cookie snapshot. Cookies rotate when the account is
/// used again, so a shared jar across accounts would sign one of them out.
class GoogleAccountSession {
  const GoogleAccountSession({
    required this.accountId,
    required this.cookies,
    this.name = '',
    this.email = '',
    this.avatarUrl,
    this.profiles = const [],
    this.activeProfileId,
  });

  final String accountId;
  final List<AuthCookie> cookies;
  final String name;
  final String email;

  /// Channel avatar from `account/account_menu`.
  ///
  /// The cookie jar carries no identity at all, so without this an account can
  /// only ever render as an unnamed placeholder with a letter in a circle.
  final String? avatarUrl;

  final List<YouTubeProfile> profiles;
  final String? activeProfileId;

  /// Best available picture for this account.
  ///
  /// Prefers the account's own avatar, then the active channel's. Returns null
  /// rather than a placeholder URL so callers can decide what an absent avatar
  /// means in their own layout.
  String? get bestAvatarUrl {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) return avatarUrl;
    return activeProfile?.avatarUrl;
  }

  /// What to show as the account's name.
  ///
  /// Never empty. An unnamed row reads as a broken row rather than as
  /// anonymity, so this always resolves to something a person would recognise.
  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (email.trim().isNotEmpty) return email.trim().split('@').first;
    final channel = activeProfile?.name.trim() ?? '';
    if (channel.isNotEmpty) return channel;
    return 'YouTube account';
  }

  YouTubeProfile? get activeProfile {
    if (profiles.isEmpty) return null;
    for (final p in profiles) {
      if (p.profileId == activeProfileId) return p;
    }
    return profiles.first;
  }

  /// Whether the jar still holds a cookie we can sign with.
  ///
  /// Name-exact, and the value must be non-empty. A substring test for "SAPISID"
  /// also matches `__Secure-3PAPISID`, which is how an app declares itself signed
  /// in while holding no cookie it can actually sign with - every request goes
  /// out unsigned and playback silently degrades.
  bool get hasSigningCookie => cookies.any((c) {
        if (!_sapisIdNames.contains(c.name)) return false;
        if (c.value.isEmpty) return false;
        return !c.isExpired;
      });

  /// The cookie to sign with, in preference order.
  ///
  /// Plain `SAPISID` first: it is the origin-scoped form. The `__Secure-` forms
  /// exist for partitioned logins, which is why a jar holding only those still
  /// counts as signed in.
  String? get signingCookie {
    for (final name in _sapisIdNames) {
      for (final c in cookies) {
        if (c.name == name && c.value.isNotEmpty && !c.isExpired) {
          return c.value;
        }
      }
    }
    return null;
  }

  bool get isUsable => cookies.isNotEmpty && hasSigningCookie;

  GoogleAccountSession copyWith({
    List<AuthCookie>? cookies,
    String? name,
    String? email,
    List<YouTubeProfile>? profiles,
    String? activeProfileId,
  }) =>
      GoogleAccountSession(
        accountId: accountId,
        cookies: cookies ?? this.cookies,
        name: name ?? this.name,
        email: email ?? this.email,
        profiles: profiles ?? this.profiles,
        activeProfileId: activeProfileId ?? this.activeProfileId,
      );

  Map<String, dynamic> toJson() => {
        'id': accountId,
        'cookie': cookies.map((c) => '${c.name}=${c.value}').join('; '),
        'cookies': cookies.map((c) => c.toJson()).toList(),
        'name': name,
        'email': email,
        'avatarUrl': avatarUrl,
        'activeProfileId': activeProfileId,
        'profiles': profiles.map((p) => p.toJson()).toList(),
      };

  static GoogleAccountSession? tryParse(Map<String, dynamic> raw) {
    final id = raw['id']?.toString();
    if (id == null || id.isEmpty) return null;

    final cookies = <AuthCookie>[];
    final structured = raw['cookies'];
    if (structured is List) {
      for (final entry in structured) {
        final parsed = AuthCookie.tryParse(entry);
        if (parsed != null) cookies.add(parsed);
      }
    }
    // Fall back to the flat header form if the structured list is absent.
    if (cookies.isEmpty) {
      final header = raw['cookie']?.toString() ?? '';
      for (final part in header.split(';')) {
        final eq = part.indexOf('=');
        if (eq <= 0) continue;
        final name = part.substring(0, eq).trim();
        final value = part.substring(eq + 1).trim();
        if (name.isNotEmpty && value.isNotEmpty) {
          cookies.add(AuthCookie(name: name, value: value));
        }
      }
    }

    final profiles = <YouTubeProfile>[];
    final rawProfiles = raw['profiles'];
    if (rawProfiles is List) {
      for (final entry in rawProfiles) {
        if (entry is Map) {
          final parsed = YouTubeProfile.tryParse(
              entry.map((k, v) => MapEntry(k.toString(), v)));
          if (parsed != null) profiles.add(parsed);
        }
      }
    }

    return GoogleAccountSession(
      accountId: id,
      cookies: cookies,
      name: raw['name']?.toString() ?? '',
      email: raw['email']?.toString() ?? '',
      // Absent is a normal state, not a parse failure: an account saved before
      // avatars existed simply has none.
      avatarUrl: (raw['avatarUrl'] as String?)?.trim().isNotEmpty ?? false
          ? raw['avatarUrl'] as String
          : null,
      profiles: profiles,
      activeProfileId: raw['activeProfileId']?.toString(),
    );
  }
}

/// Cookie names that can carry an API session id, in signing-preference order.
const List<String> _sapisIdNames = [
  'SAPISID',
  '__Secure-3PAPISID',
  '__Secure-1PAPISID',
];

/// Public alias - the check is about whether we CAN sign, which is exactly the
/// question [GoogleAccountSession.hasSigningCookie] answers.
bool isApiSessionCookie(String name, String value) =>
    _sapisIdNames.contains(name) && value.isNotEmpty;

/// Derive a stable account id.
///
/// Preferring the channel's data sync id means the same account keeps its id
/// across a cookie rotation; the cookie hash is the fallback for a login that
/// has not reported a channel yet.
String deriveAccountId(List<AuthCookie> cookies, String? dataSyncId) {
  if (dataSyncId != null && dataSyncId.trim().isNotEmpty) {
    return 'acct_$dataSyncId';
  }

  // The id must survive a cookie refresh. Google rotates `SAPISID` and rewrites
  // expiry metadata on every sign-in, so hashing the whole jar - which is what
  // this used to do - minted a brand new account id per login, and the registry
  // grew without bound while the user's real account list filled with duplicates.
  // These three are the session pair plus its sub-session and are the stable
  // handle for one browser session.
  final byName = <String, String>{for (final c in cookies) c.name: c.value};
  final stable = <String?>[
    byName['SSID'],
    byName['SID'],
    byName['HSID'],
  ].where((v) => v != null && v.isNotEmpty).toList();
  if (stable.isNotEmpty) {
    return 'acct_${_shortHash(stable.join('|'))}';
  }

  // No session pair: the signing cookie alone is a better identity handle than
  // the full jar. With nothing at all, collapse to one bucket rather than
  // fragment per call - an unidentifiable jar is not two accounts.
  for (final name in _sapisIdNames) {
    final value = byName[name];
    if (value != null && value.isNotEmpty) return 'acct_${_shortHash(value)}';
  }
  return 'acct_unknown';
}

/// Derive a profile id.
///
/// `profile:` marks a provisional id built from a display name before YouTube
/// told us anything real; it is replaced once a channel reports back.
String deriveProfileId({
  String? pageId,
  String? dataSyncId,
  String? name,
}) {
  if (pageId != null && pageId.isNotEmpty) return 'page_$pageId';
  if (dataSyncId != null && dataSyncId.isNotEmpty) return 'sync_$dataSyncId';
  return 'profile:${_shortHash(name ?? '')}';
}

String _shortHash(String input) {
  // A short, stable, non-cryptographic digest is all that is needed: this is an
  // identity label, not a secret, and it is never used to authenticate anything.
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(input)) {
    hash = (hash ^ unit) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// `DATASYNC_ID` arrives as `"account||delegated"` when a channel is acting
/// delegated. Prefer the delegated half; fall back to the account half.
String normalizeDataSyncId(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return '';
  if (!value.contains('||')) return value;
  final parts = value.split('||');
  if (parts.length < 2) return value;
  final delegated = parts[1].trim();
  if (delegated.isNotEmpty) return delegated;
  final account = parts[0].trim();
  return account;
}
