import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Removes Google's identity cookies from the WebView jar, and nothing else.
///
/// Why not `deleteAllCookies()`: that tears down every saved account's cookies
/// the moment the screen opens, including the session the app is happily
/// running on, and makes "add another account" impossible because the account
/// it just deleted was the only thing signed in.
///
/// Why not a server logout: signing out on accounts.google.com invalidates a
/// PREVIOUSLY SAVED account on Google's side too. The user's other accounts
/// would stop working in this app without any action of theirs.
///
/// So: overwrite the specific cookies, with Max-Age=0, on the specific origins.
/// Deliberately scoped, and best effort - if the platform refuses we carry on,
/// because failing to clear the jar must not block a sign-in.
class GoogleCookieCleaner {
  const GoogleCookieCleaner(this._manager);

  final CookieManager _manager;

  /// Origins that can hold a YouTube session.
  static const origins = <String>[
    'https://music.youtube.com',
    'https://www.youtube.com',
    'https://youtube.com',
    'https://accounts.google.com',
  ];

  /// The identity cookies worth clearing.
  ///
  /// The SAPISID family is what signs a request, and SID/SSID/HSID are the
  /// session pair the account id is derived from - clearing only the former
  /// leaves a jar that still looks like a distinct account.
  static const names = <String>[
    'SAPISID',
    '__Secure-3PAPISID',
    '__Secure-1PAPISID',
    'APISID',
    '__Secure-1PSID',
    '__Secure-3PSID',
    'SSID',
    'SID',
    'HSID',
    'NID',
  ];

  /// Every (url, name, domain) we will expire.
  ///
  /// Three domain forms per cookie because the original scope is not recorded:
  /// a host-only cookie, `Domain=host`, and `Domain=.host`. Expiring only one
  /// leaves the other two alive.
  static List<({WebUri url, String name, String? domain})> plan() {
    final out = <({WebUri url, String name, String? domain})>[];
    for (final origin in origins) {
      final host = Uri.parse(origin).host;
      for (final name in names) {
        out.add((url: WebUri(origin), name: name, domain: null));
        out.add((url: WebUri(origin), name: name, domain: host));
        out.add((url: WebUri(origin), name: name, domain: '.$host'));
      }
    }
    return out;
  }

  /// Expire the Google identity cookies. Never throws.
  Future<void> clear() async {
    for (final step in plan()) {
      try {
        await _manager.setCookie(
          url: step.url,
          name: step.name,
          value: '',
          maxAge: 0,
          domain: step.domain,
        );
      } catch (e) {
        // Best effort by design: see the class doc.
        debugPrint('GoogleCookieCleaner: could not clear ${step.name}: $e');
      }
    }
  }
}