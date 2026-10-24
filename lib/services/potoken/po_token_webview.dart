import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import '../innertube/innertube_service.dart';

/// Result of a successful PO-token session for one video.
class PoTokenResult {
  const PoTokenResult({required this.playerRequest, required this.streaming});

  /// Token attached to the /player request body
  /// (`serviceIntegrityDimensions.poToken`).
  final String playerRequest;

  /// Token appended to stream URLs (`&pot=`).
  final String streaming;
}

/// Flutter port of Metrolist's PoTokenWebView: runs YouTube's BotGuard inside
/// a headless WebView and mints per-video PO tokens, unlocking WEB_REMIX
/// playback (all token-less clients are bot-gated as of Aug 2026).
class PoTokenWebGenerator {
  PoTokenWebGenerator._();

  // Google's own public WEB key: it is sent by youtube.com in the clear on
  // every request and cannot be rotated by us. Secret scanning flags it; it is
  // an identifier, not a credential. See SECURITY.md.
  static const String _googleApiKey = 'AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw';
  static const String _requestKey = 'O43z0dpjhgX20SCx4KAo';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.3';

  static const Duration _initTimeout = Duration(seconds: 45);
  static const Duration _generateTimeout = Duration(seconds: 15);

  static PoTokenWebGenerator? _instance;
  static PoTokenWebGenerator get instance => _instance ??= PoTokenWebGenerator._();

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _ctl;
  DateTime? _expiresAt;
  final _ready = Completer<void>();
  bool _readyCompleted = false;
  final Map<String, Completer<String>> _pending = {};
  int _requestCounter = 0;
  final http.Client _httpClient = http.Client();

  bool get isReady => _ready.isCompleted;

  /// Initialize the BotGuard session (idempotent). Safe to call before every
  /// token request.
  Future<void> ensureReady() async {
    if (isReady) return;
    await _init();
    await _ready.future.timeout(const Duration(seconds: 50));
  }

  /// Mint a PO token bound to [identifier] (a videoId or visitorData).
  Future<String> generate(String identifier) async {
    await ensureReady();
    final requestKey = '$identifier#${_requestCounter++}';
    final completer = Completer<String>();
    _pending[requestKey] = completer;

    final js = '''
(function() {
    var requestKey = "$requestKey"
    try {
        var u8Identifier = new Uint8Array([
            ${identifier.codeUnits.join(',')}
        ])
        obtainPoToken(u8Identifier).then(function(poTokenU8) {
            PoTokenWebView.onObtainPoTokenResult(requestKey, poTokenU8.join(","))
        }).catch(function(error) {
            PoTokenWebView.onObtainPoTokenError(requestKey, String(error))
        })
    } catch (error) {
        PoTokenWebView.onObtainPoTokenError(requestKey, String(error))
    }
})()''';

    await _ctl!.evaluateJavascript(source: js);
    return completer.future.timeout(_generateTimeout, onTimeout: () {
      _pending.remove(requestKey);
      throw Exception('PoTokenWebGenerator: generate timed out');
    });
  }

  /// Convenience: mint both tokens for one video playback.
  /// Metrolist parity (PoTokenGenerator.getWebClientPoToken): the FIRST mint
  /// uses the session id (visitorData) and becomes playerRequestPoToken; the
  /// second uses the videoId and becomes streamingDataPoToken.
  Future<PoTokenResult> generateForVideo(String videoId) async {
    final visitor = InnerTubeService.instance.visitorData;
    if (visitor == null || visitor.isEmpty) {
      throw Exception('PoTokenWebGenerator: visitorData not captured yet');
    }
    final playerRequest = await generate(visitor);
    final streaming = await generate(videoId);
    return PoTokenResult(playerRequest: playerRequest, streaming: streaming);
  }

  Future<void> _init() async {
    final html = await rootBundle.loadString('assets/po_token.html');
    // Trigger the chain exactly like Metrolist: append the interface call
    // after the first closing script tag.
    final data = html.replaceFirst(
        '</script>', '\nPoTokenWebView.downloadAndRunBotguard()</script>');

    final completer = _ready;
    _webView = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: data,
        baseUrl: WebUri('https://www.youtube.com'),
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: _userAgent,
        transparentBackground: true,
      ),
      // Handlers must exist BEFORE the page parses (the appended snippet
      // calls the bridge during load).
      onWebViewCreated: (controller) {
        _ctl = controller;
        controller.addJavaScriptHandler(
          handlerName: 'PoTokenWebView',
          callback: (args) => _onJsCall(args),
        );
      },
      onConsoleMessage: (controller, consoleMessage) {
        final msg = consoleMessage.message;
        if (msg.contains('Uncaught')) {
          debugPrint('PoTokenWebView JS error: $msg');
          if (!_readyCompleted) {
            _readyCompleted = true;
            completer.completeError(Exception('PoTokenWebView: $msg'));
          }
        } else if (kDebugMode) {
          debugPrint('PoTokenWebView JS: $msg');
        }
      },
    );

    await _webView!.run();
  }

  Future<dynamic> _onJsCall(List<dynamic> args) async {
    if (args.isEmpty || args.first is! String) return null;
    final event = args.first as String;
    try {
      switch (event) {
        case 'downloadAndRunBotguard':
          await _downloadAndRunBotguard();
          break;
        case 'onRunBotguardResult':
          await _onRunBotguardResult(args[1] as String);
          break;
        case 'onMinterCreated':
          if (!_readyCompleted) {
            _readyCompleted = true;
            _expiresAt = DateTime.now().add(const Duration(hours: 6));
            _ready.complete();
          }
          break;
        case 'onObtainPoTokenResult':
          final requestKey = args[1] as String;
          final u8csv = args[2] as String;
          final token = _u8ToBase64Url(u8csv);
          _pending.remove(requestKey)?.complete(token);
          break;
        case 'onObtainPoTokenError':
          final requestKey = args[1] as String;
          _pending
              .remove(requestKey)
              ?.completeError(Exception('obtainPoToken: ${args[2]}'));
          break;
        case 'onJsInitializationError':
          final error = Exception('init: ${args[1]}');
          if (!_readyCompleted) {
            _readyCompleted = true;
            _ready.completeError(error);
          } else {
            _pending.values.toList().forEach((c) => c.completeError(error));
            _pending.clear();
          }
          break;
      }
    } catch (e) {
      debugPrint('PoTokenWebGenerator handler error: $e');
    }
    return null;
  }

  Future<void> _downloadAndRunBotguard() async {
    final body = await _botguardPost(
      'https://www.youtube.com/api/jnn/v1/Create',
      '[ "$_requestKey" ]',
    );
    final parsed = _parseChallengeData(body);
    await _ctl!.evaluateJavascript(source: '''
try {
    data = $parsed
    runBotGuard(data).then(function (result) {
        this.webPoSignalOutput = result.webPoSignalOutput
        PoTokenWebView.onRunBotguardResult(result.botguardResponse)
    }, function (error) {
        PoTokenWebView.onJsInitializationError(String(error))
    })
} catch (error) {
    PoTokenWebView.onJsInitializationError(String(error))
}''');
  }

  Future<void> _onRunBotguardResult(String botguardResponse) async {
    final body = await _botguardPost(
      'https://www.youtube.com/api/jnn/v1/GenerateIT',
      '[ "$_requestKey", "$botguardResponse" ]',
    );
    final parsed = _parseIntegrityTokenData(body);
    await _ctl!.evaluateJavascript(source: '''
try {
    this.integrityToken = ${parsed.$1}
    createPoTokenMinter(webPoSignalOutput, integrityToken).then(function() {
        PoTokenWebView.onMinterCreated()
    }).catch(function(error) {
        PoTokenWebView.onJsInitializationError(String(error))
    })
} catch (error) {
    PoTokenWebView.onJsInitializationError(String(error))
}''');
  }

  Future<String> _botguardPost(String url, String data) async {
    final response = await _httpClient.post(
      Uri.parse(url),
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
        'Content-Type': 'application/json+protobuf',
        'x-goog-api-key': _googleApiKey,
        'x-user-agent': 'grpc-web-javascript/0.1',
      },
      body: data,
    );
    if (response.statusCode != 200 || response.body.isEmpty) {
      throw Exception(
          'botguard request failed (${response.statusCode}) $url');
    }
    return response.body;
  }

  /// Port of JavaScriptUtil.parseChallengeData → JS-embeddable object string.
  String _parseChallengeData(String raw) {
    final scrambled = jsonDecode(raw) as List<dynamic>;
    List<dynamic> challengeData;
    if (scrambled.length > 1 && scrambled[1] is String) {
      challengeData =
          jsonDecode(_descramble(scrambled[1] as String)) as List<dynamic>;
    } else {
      challengeData = scrambled[0] as List<dynamic>;
    }

    String? stringAt(List<dynamic> list, int index) {
      if (index >= list.length) return null;
      final v = list[index];
      if (v is String) return v;
      return null;
    }

    final interpreterJavascript = (challengeData[1] is List)
        ? (challengeData[1] as List<dynamic>)
            .whereType<String>()
            .toList()
        : <String>[];

    final out = jsonEncode({
      'messageId': challengeData[0],
      'interpreterJavascript': {
        'privateDoNotAccessOrElseSafeScriptWrappedValue':
            interpreterJavascript.isNotEmpty ? interpreterJavascript.first : null,
        'privateDoNotAccessOrElseTrustedResourceUrlWrappedValue':
            stringAt(challengeData, 2),
      },
      'interpreterHash': challengeData[3],
      'program': challengeData[4],
      'globalName': challengeData[5],
      'clientExperimentsStateBlob': challengeData[7],
    });
    return out;
  }

  /// Port of parseIntegrityTokenData → (JS Uint8Array string, expirySeconds).
  (String, int) _parseIntegrityTokenData(String raw) {
    final data = jsonDecode(raw) as List<dynamic>;
    final u8 = _base64ToU8(data[0] as String);
    return (u8, (data[1] as num).toInt());
  }

  String _descramble(String scrambled) {
    final bytes = _youtubeBase64Decode(scrambled);
    // Kotlin parity: (byte + 97).toByte() then UTF-8 decode.
    return utf8.decode(bytes.map((b) => (b + 97) & 0xFF).toList());
  }

  String _base64ToU8(String base64) {
    final bytes = _youtubeBase64Decode(base64);
    return 'new Uint8Array([${bytes.join(',')}])';
  }

  List<int> _youtubeBase64Decode(String input) {
    final normalized = input
        .replaceAll('-', '+')
        .replaceAll('_', '/')
        .replaceAll('.', '=');
    return base64Decode(normalized);
  }

  String _u8ToBase64Url(String u8csv) {
    final bytes = u8csv
        .split(',')
        .map((s) => int.parse(s.trim()) & 0xFF)
        .toList(growable: false);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> dispose() async {
    await _webView?.dispose();
    _webView = null;
    _instance = null;
  }
}
