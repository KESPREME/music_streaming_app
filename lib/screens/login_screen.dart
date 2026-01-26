import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  InAppWebViewController? _webViewController;
  final CookieManager _cookieManager = CookieManager.instance();
  bool _isLoading = true;
  Timer? _cookieTimer;

  @override
  void initState() {
    super.initState();
    _cookieManager.deleteAllCookies();
    
    // Periodically check for cookies (every 2 seconds)
    _cookieTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
       if (mounted) await _checkCookies();
    });
  }
  
  @override
  void dispose() {
    _cookieTimer?.cancel();
    super.dispose();
  }

  // Check cookies for successful login
  Future<void> _checkCookies() async {
      try {
        final List<Cookie> youtubeCookies = await _cookieManager.getCookies(url: WebUri("https://youtube.com"));
        final List<Cookie> musicCookies = await _cookieManager.getCookies(url: WebUri("https://music.youtube.com"));
        
        final allCookies = [...youtubeCookies, ...musicCookies];
        
        String? sapisid;
        String? secure3psid;
        final Map<String, String> cookieMap = {};
        
        for (final cookie in allCookies) {
             cookieMap[cookie.name] = cookie.value;
             if (cookie.name == 'SAPISID') sapisid = cookie.value;
             // Handle variants of 3PSID
             if (cookie.name == '__Secure-3PSID') secure3psid = cookie.value;
        }
        
        // Check if we found the keys
        if (sapisid != null && secure3psid != null) {
          _cookieTimer?.cancel(); 
          await AuthService().saveCookies(cookieMap);
          
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Logged in successfully!')),
             );
             Navigator.of(context).pop(true);
          }
        }
      } catch (e) {
         // Ignore errors during check
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log In via Google')),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
               url: WebUri('https://accounts.google.com/ServiceLogin?service=youtube'),
            ),
            initialSettings: InAppWebViewSettings(
              userAgent: 'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36',
              javaScriptEnabled: true,
              cacheEnabled: true,
              clearCache: true, // Start clean
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            onLoadStart: (controller, url) {
              if (mounted) setState(() => _isLoading = true);
            },
            onLoadStop: (controller, url) async {
              if (mounted) setState(() => _isLoading = false);
              await _checkCookies();
            },
            // Handle URL changes to trigger cookie checks
            onUpdateVisitedHistory: (controller, url, androidIsReload) async {
               await _checkCookies();
            },
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verifying login...')));
            await _checkCookies();
        },
        label: const Text('I\'m Logged In'),
        icon: const Icon(Icons.check),
      ),
    );
  }
}
