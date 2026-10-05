import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_models.dart';

/// Persistent YouTube session: the accounts, their cookies, and which channel
/// each one is acting as.
///
/// ## What lives where, and why
///
/// Cookies are account-session-grade secrets. They sit in the platform keystore
/// via `flutter_secure_storage`, never in plain `SharedPreferences`. The
/// non-secret parts of the account registry - which accounts exist, which is
/// selected, their display names - stay in preferences so a keystore failure
/// degrades to "signed out" rather than to a crash on launch.
///
/// ## Migration
///
/// The previous implementation kept one flat `name -> value` map under
/// `youtube_cookies` in plain preferences. That entry is read lazily and folded
/// into a single account, so an app update never signs anyone out. It is
/// rewritten into secure storage the first time it is seen.
class AuthService extends ChangeNotifier {
  AuthService._internal();

  static final AuthService _instance = AuthService._internal();
  static AuthService get instance => _instance;
  factory AuthService() => _instance;

  static const String _prefKeyLegacyCookies = 'youtube_cookies';
  static const String _prefKeyAccounts = 'youtube_account_sessions_v2';
  static const String _prefKeyActiveAccount = 'active_google_account_id_v2';
  static const String _prefKeyActiveProfile = 'active_youtube_profile_id_v2';

  /// The only secure-store key. One blob keeps the write atomic: a partial
  /// write cannot leave an account list that disagrees with its selection.
  static const String _accountKey = 'accounts';

  /// The default Android options already write through a keystore-held key and
  /// migrate existing data automatically, so no deprecated flag is passed.
  /// Falls back to plain storage on a device whose keystore is unusable, which
  /// degrades to "less protected" rather than to a crash on launch.
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  List<GoogleAccountSession> _accounts = const [];
  String? _activeAccountId;
  String? _activeProfileId;

  /// Guards against a second restore. Loading the session notifies listeners, and
  /// `MusicProvider` treats any change in [isLoggedIn] as an identity flip - it
  /// resets the InnerTube session, clears the stream cache and refetches the
  /// feed. A restore that ran twice, or ran after `MusicProvider` had already
  /// latched the anonymous state, would fire that whole teardown on a cold start
  /// that did not actually change identity. See `main.dart`, where this is
  /// awaited before `runApp` for the same reason.
  bool _restored = false;

  // ── State ──────────────────────────────────────────────────────────────

  List<GoogleAccountSession> get accounts => List.unmodifiable(_accounts);
  String? get activeAccountId => _activeAccountId;
  String? get activeProfileId => _activeProfileId;

  GoogleAccountSession? get activeAccount {
    if (_accounts.isEmpty) return null;
    for (final a in _accounts) {
      if (a.accountId == _activeAccountId) return a;
    }
    return _accounts.first;
  }

  YouTubeProfile? get activeProfile => activeAccount?.activeProfile;

  /// The account currently acting, when it can actually sign a request.
  GoogleAccountSession? get usableAccount {
    final account = activeAccount;
    if (account == null || !account.isUsable) return null;
    return account;
  }

  bool get isLoggedIn => usableAccount != null;

  /// Every known identity, flattened for a switcher list.
  ///
  /// Insertion order for accounts, then profile order within each.
  List<(String accountId, String profileId)> get allIdentities => [
        for (final account in _accounts)
          for (final profile in account.profiles)
            (account.accountId, profile.profileId),
      ];

  /// The identity next to one in switcher order, or null at either end.
  ///
  /// Deliberately does not wrap: wrapping means the list silently rotates under
  /// the listener while they are reading it.
  (String, String)? adjacentIdentity({
    required bool forward,
    String? accountId,
    String? profileId,
  }) {
    final items = allIdentities;
    if (items.isEmpty) return null;
    var index = profileId == null
        ? -1
        : items.indexWhere((e) => e.$1 == accountId && e.$2 == profileId);
    // The caller may not know which profile is selected. Fall back to the
    // active account's own position rather than reporting "no neighbour".
    if (index < 0 && accountId != null) {
      index = items.indexWhere((e) => e.$1 == accountId);
    }
    if (index < 0) return null;
    final next = index + (forward ? 1 : -1);
    if (next < 0 || next >= items.length) return null;
    return items[next];
  }

  /// Cookie header for the active account, scoped to [host].
  String cookieHeader({String host = 'music.youtube.com'}) {
    final account = usableAccount;
    if (account == null) return '';
    return account.cookies
        .where((c) => !c.isExpired && c.appliesTo(host))
        .map((c) => '${c.name}=${c.value}')
        .join('; ');
  }

  /// The cookie value to sign with, honouring the `__Secure-` variants.
  String? get signingCookie => usableAccount?.signingCookie;

  /// `SAPISIDHASH {timestamp}_{sha1(timestamp + " " + sapisid + " " + origin)}`.
  String authorizationHeader({String origin = 'https://music.youtube.com'}) {
    final sapisid = signingCookie;
    if (sapisid == null || sapisid.isEmpty) return '';
    return sapisidHash(sapisid, origin: origin);
  }

  /// `X-Goog-AuthUser` - which jar entry is speaking.
  String? get authUser => activeProfile?.authUser;

  /// `X-Goog-PageId` / `PLUS_PAGE_ID` - brand channels only.
  String? get channelPageId => activeProfile?.pageId;

  /// `context.user.onBehalfOfUser`. Never inferred; only ever what the shell
  /// reported while signed in.
  String? get dataSyncId => activeProfile?.dataSyncId;

  /// Non-secret discriminator for caches that hold personalized content.
  ///
  /// A personalized home feed must never be served to an anonymous session, or
  /// the reverse: signing out has to land on an empty cache rather than on the
  /// previous user's recommendations. This is a label derived from the account
  /// and channel ids, never from a cookie value, because it is used as a
  /// preferences key and preferences are plaintext on disk.
  String get identityKey {
    final account = activeAccount;
    if (account == null) return 'anon';
    final profile = activeProfile?.profileId;
    return profile == null ? account.accountId : '${account.accountId}_$profile';
  }

  /// Headers an authenticated InnerTube request needs.
  Map<String, String> getHeaders({String host = 'music.youtube.com'}) {
    if (!isLoggedIn) return const {};
    final headers = <String, String>{
      'Cookie': cookieHeader(host: host),
      'Authorization': authorizationHeader(),
    };
    final user = authUser;
    if (user != null && user.isNotEmpty) headers['X-Goog-AuthUser'] = user;
    final pageId = channelPageId;
    if (pageId != null && pageId.isNotEmpty) {
      headers['X-Goog-PageId'] = pageId;
    }
    return headers;
  }

  String? getCookie(String name, {String host = 'music.youtube.com'}) {
    final account = usableAccount;
    if (account == null) return null;
    for (final c in account.cookies) {
      if (c.name == name && !c.isExpired && c.appliesTo(host)) return c.value;
    }
    return null;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  /// Load the saved session. Must complete before the first `MusicProvider` is
  /// constructed, otherwise a signed-in user starts the app anonymous.
  ///
  /// Idempotent: safe to call more than once, only the first call reads storage.
  Future<void> init() async {
    if (_restored) return;
    _restored = true;
    try {
      await _load();
      if (_accounts.isNotEmpty) notifyListeners();
    } catch (e) {
      // A corrupt or unreadable store must leave the app anonymous, never crash
      // it on launch. The next successful sign-in overwrites the keys.
      debugPrint('AuthService: could not restore saved session: $e');
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    var accounts = <GoogleAccountSession>[];
    try {
      final raw = await _secure.read(key: _accountKey);
      if (raw != null && raw.isNotEmpty) {
        accounts = _decodeAccounts(raw);
      }
    } catch (e) {
      debugPrint('AuthService: secure store unreadable, trying mirror: $e');
    }
    // Fall back to the preferences mirror. It is written on every save
    // precisely so a device whose keystore is unusable degrades to "less
    // protected" rather than to "signed out" - which means it has to be READ,
    // not merely written.
    if (accounts.isEmpty) {
      final mirrored = prefs.getString(_prefKeyAccounts);
      if (mirrored != null && mirrored.isNotEmpty) {
        accounts = _decodeAccounts(mirrored);
      }
    }

    // Lazy migration: the old single flat jar becomes one account. Never
    // destructive - if it cannot be read we simply stay anonymous, and the next
    // sign-in writes the new format.
    if (accounts.isEmpty) {
      final legacy = prefs.getString(_prefKeyLegacyCookies);
      if (legacy != null && legacy.isNotEmpty) {
        accounts = _migrateLegacyJar(legacy);
        if (accounts.isNotEmpty) {
          await _persist(
              accounts: accounts,
              activeAccountId: accounts.first.accountId,
              activeProfileId: accounts.first.activeProfile?.profileId,
              prefs: prefs);
        }
      }
    }

    if (accounts.isEmpty) return;

    // An account whose signing cookie has expired is not a session. Keeping it
    // would leave the app reporting itself signed in while sending cookies
    // Google has already rejected, which surfaces as "logged in but nothing
    // works" - worse than being visibly signed out, because the listener has no
    // way to tell what to fix.
    final usable = accounts.where((a) => a.isUsable).toList();
    if (usable.isEmpty) return;
    _accounts = usable;

    var activeId = prefs.getString(_prefKeyActiveAccount);
    if (activeId == null || !_accounts.any((a) => a.accountId == activeId)) {
      activeId = _accounts.first.accountId;
    }
    _activeAccountId = activeId;

    final account = _accounts.firstWhere((a) => a.accountId == activeId);
    var profileId = prefs.getString(_prefKeyActiveProfile);
    if (profileId != null &&
        !account.profiles.any((p) => p.profileId == profileId)) {
      profileId = null;
    }
    _activeProfileId = profileId ?? account.activeProfile?.profileId;
  }

  List<GoogleAccountSession> _decodeAccounts(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <GoogleAccountSession>[];
    for (final entry in decoded) {
      if (entry is Map) {
        final parsed = GoogleAccountSession.tryParse(
            entry.map((k, v) => MapEntry(k.toString(), v)));
        if (parsed != null) out.add(parsed);
      }
    }
    return out;
  }

  List<GoogleAccountSession> _migrateLegacyJar(String legacy) {
    try {
      final decoded = jsonDecode(legacy);
      if (decoded is! Map) return const [];
      final cookies = <AuthCookie>[];
      decoded.forEach((key, value) {
        final name = key.toString();
        final cookieValue = value.toString();
        if (name.isNotEmpty && cookieValue.isNotEmpty) {
          cookies.add(AuthCookie(name: name, value: cookieValue));
        }
      });
      if (cookies.isEmpty) return const [];
      final accountId = deriveAccountId(cookies, null);
      return [
        GoogleAccountSession(
          accountId: accountId,
          cookies: cookies,
          profiles: [
            YouTubeProfile(
              profileId: deriveProfileId(name: 'Personal'),
              name: 'Personal',
              isBrandAccount: false,
            ),
          ],
          activeProfileId: deriveProfileId(name: 'Personal'),
        ),
      ];
    } catch (e) {
      debugPrint('AuthService: legacy jar unreadable: $e');
      return const [];
    }
  }

  Future<void> _persist({
    required List<GoogleAccountSession> accounts,
    required String? activeAccountId,
    required String? activeProfileId,
    SharedPreferences? prefs,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final payload = jsonEncode(accounts.map((a) => a.toJson()).toList());
    try {
      await _secure.write(key: _accountKey, value: payload);
      // Mirror to preferences as well. Not for secrecy - the cookie header inside
      // it is encrypted when the secure store is readable - but because losing
      // the keystore should mean "signed out", not "corrupt", and this keeps a
      // plain copy available to migrate from.
      await store.setString(_prefKeyAccounts, payload);
    } catch (e) {
      debugPrint('AuthService: secure write failed, keeping prefs copy: $e');
      await store.setString(_prefKeyAccounts, payload);
    }

    if (activeAccountId != null) {
      await store.setString(_prefKeyActiveAccount, activeAccountId);
    } else {
      await store.remove(_prefKeyActiveAccount);
    }
    if (activeProfileId != null) {
      await store.setString(_prefKeyActiveProfile, activeProfileId);
    } else {
      await store.remove(_prefKeyActiveProfile);
    }
  }

  // ── Mutation ───────────────────────────────────────────────────────────

  /// Save a freshly captured sign-in.
  ///
  /// [cookies] replaces the whole jar for the account rather than merging,
  /// because cookies rotate on re-login and a merge accumulates stale entries.
  Future<void> saveSession({
    required List<AuthCookie> cookies,
    String? email,
    String? displayName,
    YouTubeProfile? profile,
  }) async {
    if (cookies.isEmpty) return;

    final accountId = deriveAccountId(cookies, profile?.dataSyncId);
    final existing = _accounts.where((a) => a.accountId == accountId).toList();

    // A channel switch is another identity under the SAME Google login, never a
    // new account. For a fresh sign-in, matching a non-empty email upgrades the
    // existing entry instead of adding a duplicate after cookies rotate.
    var match = existing.isNotEmpty ? existing.first : null;
    if (match == null && email != null && email.trim().isNotEmpty) {
      for (final a in _accounts) {
        if (a.email.trim().toLowerCase() == email.trim().toLowerCase()) {
          match = a;
          break;
        }
      }
    }

    var profiles = match?.profiles ?? const <YouTubeProfile>[];
    String? activeProfileId = match?.activeProfileId;

    if (profile != null) {
      // Replace a placeholder we invented from a name, and never keep two
      // entries for the same real identity.
      final hasRealIdentity = profile.hasRealIdentity;
      profiles = [
        for (final known in profiles)
          if (known.profileId != profile.profileId &&
              !(hasRealIdentity && known.profileId.startsWith('profile:')))
            known,
        profile,
      ];
      activeProfileId = profile.profileId;
    }

    final session = GoogleAccountSession(
      accountId: match?.accountId ?? accountId,
      cookies: cookies,
      name: displayName ?? match?.name ?? '',
      email: email ?? match?.email ?? '',
      profiles: profiles,
      activeProfileId: activeProfileId,
    );

    _accounts = [
      for (final a in _accounts)
        if (a.accountId != session.accountId) a,
      session,
    ];

    _activeAccountId = session.accountId;
    if (activeProfileId != null) _activeProfileId = activeProfileId;

    await _persist(
      accounts: _accounts,
      activeAccountId: _activeAccountId,
      activeProfileId: _activeProfileId,
    );
    // Also drop the legacy key: its job is done and leaving it means a later
    // keystore failure silently resurrects a stale jar.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyLegacyCookies);

    notifyListeners();
  }

  /// Back-compatible entry point for a bare cookie map.
  ///
  /// Kept because the login screen hands over a map, and because the previous
  /// signature is referenced by tests. Domain and expiry are absent from a plain
  /// map, so those are simply left unset rather than invented.
  Future<void> saveCookies(Map<String, String> newCookies) async {
    await saveSession(
      cookies: [
        for (final entry in newCookies.entries)
          if (entry.key.isNotEmpty && entry.value.isNotEmpty)
            AuthCookie(name: entry.key, value: entry.value),
      ],
    );
  }

  /// Act as a different identity without re-authenticating.
  Future<void> selectIdentity(String accountId, String? profileId) async {
    final index = _accounts.indexWhere((a) => a.accountId == accountId);
    if (index < 0) return;
    if (_activeAccountId == accountId && _activeProfileId == profileId) return;

    _activeAccountId = accountId;
    final account = _accounts[index];
    _activeProfileId = profileId != null &&
            account.profiles.any((p) => p.profileId == profileId)
        ? profileId
        : account.profiles.isEmpty
            ? null
            : account.profiles.first.profileId;

    // Fold the choice into the stored session so it survives a restart.
    _accounts = [
      for (final a in _accounts)
        if (a.accountId == accountId)
          a.copyWith(activeProfileId: _activeProfileId)
        else
          a,
    ];

    await _persist(
      accounts: _accounts,
      activeAccountId: _activeAccountId,
      activeProfileId: _activeProfileId,
    );
    notifyListeners();
  }

  /// Record channels YouTube reported for the active account.
  ///
  /// Stale placeholders are dropped once real channels arrive. The current
  /// selection is never cleared by an empty or partial response - that would
  /// silently sign the listener out of the identity they chose.
  Future<void> applyDetectedProfiles(List<YouTubeProfile> detected) async {
    final account = activeAccount;
    if (account == null) return;
    if (detected.isEmpty) return;

    final stalePlaceholders = account.profiles
        .where((p) => p.profileId.startsWith('profile:'))
        .map((p) => p.profileId)
        .toSet();

    final merged = <YouTubeProfile>[
      for (final known in account.profiles)
        if (!stalePlaceholders.contains(known.profileId) &&
            !detected.any((d) => d.profileId == known.profileId))
          known,
      ...detected,
    ];

    var activeId = _activeProfileId;
    if (activeId != null && !merged.any((p) => p.profileId == activeId)) {
      activeId = account.activeProfileId;
    }

    _accounts = [
      for (final a in _accounts)
        if (a.accountId == account.accountId)
          a.copyWith(profiles: merged, activeProfileId: activeId)
        else
          a,
    ];
    _activeProfileId = activeId;

    await _persist(
      accounts: _accounts,
      activeAccountId: _activeAccountId,
      activeProfileId: _activeProfileId,
    );
    notifyListeners();
  }

  /// Remove one account, falling back to another if one remains.
  Future<void> removeAccount(String accountId) async {
    final remaining = _accounts.where((a) => a.accountId != accountId).toList();
    if (remaining.length == _accounts.length) return;

    _accounts = remaining;
    final removedActive = _activeAccountId == accountId;
    if (removedActive) {
      _activeAccountId = remaining.isEmpty ? null : remaining.first.accountId;
      _activeProfileId =
          remaining.isEmpty ? null : remaining.first.activeProfile?.profileId;
    }

    await _persist(
      accounts: _accounts,
      activeAccountId: _activeAccountId,
      activeProfileId: _activeProfileId,
    );
    notifyListeners();
  }

  /// Clear everything (sign out).
  Future<void> logout() async {
    _accounts = const [];
    _activeAccountId = null;
    _activeProfileId = null;
    try {
      await _secure.delete(key: _accountKey);
    } catch (e) {
      debugPrint('AuthService: secure delete failed: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyLegacyCookies);
    await prefs.remove(_prefKeyAccounts);
    await prefs.remove(_prefKeyActiveAccount);
    await prefs.remove(_prefKeyActiveProfile);
    notifyListeners();
  }

  // ── Test support ───────────────────────────────────────────────────────

  /// Forget that a restore happened, and drop all in-memory state.
  ///
  /// Test-only: lets one process exercise more than one stored session.
  @visibleForTesting
  void debugResetRestoreFlag() {
    _restored = false;
    _accounts = const [];
    _activeAccountId = null;
    _activeProfileId = null;
  }
}

/// The SAPISIDHASH scheme, standalone so it can be tested and reused.
///
/// No token is ever minted or stored: the cookie *is* the credential and lasts
/// until sign-out. Every request re-signs with a fresh timestamp.
String sapisidHash(String sapisid,
    {String origin = 'https://music.youtube.com', DateTime? at}) {
  final timestamp =
      ((at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000).toString();
  final digest = sha1.convert(utf8.encode('$timestamp $sapisid $origin'));
  return 'SAPISIDHASH ${timestamp}_$digest';
}
