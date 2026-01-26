import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _prefKeyCookies = 'youtube_cookies';
  Map<String, String> _cookies = {};

  bool get isLoggedIn => _cookies.isNotEmpty && _cookies.containsKey('SAPISID');

  /// Initialize and load saved cookies
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final cookieString = prefs.getString(_prefKeyCookies);
    if (cookieString != null) {
      try {
        _cookies = Map<String, String>.from(jsonDecode(cookieString));
        notifyListeners();
      } catch (e) {
        print('AuthService: Failed to parse saved cookies: $e');
      }
    }
  }

  /// Save cookies extracted from WebView
  Future<void> saveCookies(Map<String, String> newCookies) async {
    _cookies = newCookies;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyCookies, jsonEncode(_cookies));
    notifyListeners();
  }
  
  /// Clear cookies (Logout)
  Future<void> logout() async {
    _cookies.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyCookies);
    notifyListeners();
  }

  /// Get the full Cookie header string
  String get cookieHeader {
    if (_cookies.isEmpty) return '';
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Generate SAPISIDHASH authorization header
  /// Format: SAPISIDHASH {timestamp}_{sha1(timestamp + " " + SAPISID + " " + origin)}
  String getAuthorizationHeader({String origin = 'https://music.youtube.com'}) {
    final sapisid = _cookies['SAPISID'];
    if (sapisid == null) return '';

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final content = '$timestamp $sapisid $origin';
    final hash = sha1.convert(utf8.encode(content)).toString();

    return 'SAPISIDHASH ${timestamp}_$hash';
  }
  
  /// Get auth headers for InnerTube/Requests
  Map<String, String> getHeaders() {
      if (!isLoggedIn) return {};
      return {
        'Cookie': cookieHeader,
        'Authorization': getAuthorizationHeader(),
        // 'X-Origin': 'https://music.youtube.com', // Optional but good
      };
  }
  
  /// Get specific cookie value
  String? getCookie(String name) => _cookies[name];
}
