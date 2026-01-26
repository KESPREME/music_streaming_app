import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// A custom AudioSource that streams directly from YoutubeExplode's client.
/// This bypasses ExoPlayer's HTTP stack, preventing 403 Forbidden errors
/// caused by header/User-Agent mismatches.
class YoutubeExplodeSource extends StreamAudioSource {
  final AudioOnlyStreamInfo _streamInfo;
  final http.Client _client = http.Client();
  final Map<String, String>? _headers;

  YoutubeExplodeSource(this._streamInfo, {Map<String, String>? headers}) 
      : _headers = headers,
        super(tag: _streamInfo);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final startOffset = start ?? 0;
    final contentLength = _streamInfo.size.totalBytes;
    final endOffset = end ?? (contentLength - 1);
    
    // YoutubeExplode's 'get' doesn't support start offset.
    // So we must manually make the HTTP request using the URL from streamInfo.
    
    try {
      final url = _streamInfo.url.toString();
      final request = http.Request('GET', Uri.parse(url));
      request.headers['Range'] = 'bytes=$startOffset-$endOffset';
      request.headers['Accept-Encoding'] = 'gzip';
      
      // Inject custom auth headers (Cookie, Authorization, etc)
      if (_headers != null) {
        request.headers.addAll(_headers!);
      }
      
      // CRITICAL: Dynamic User-Agent Selection
      // Only apply dynamic/fallback UA if NOT provided in headers
      if (!request.headers.containsKey('User-Agent')) {
          if (url.contains('c=ANDROID')) {
             request.headers['User-Agent'] = 'com.google.android.youtube/17.31.35 (Linux; U; Android 11) gzip';
          } else if (url.contains('c=IOS')) {
             request.headers['User-Agent'] = 'com.google.ios.youtube/19.29.1 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X)';
          }
      }
      
      final response = await _client.send(request);
      
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('YoutubeExplodeSource: HTTP ${response.statusCode}');
      }
      
      return StreamAudioResponse(
        sourceLength: contentLength,
        contentLength: (endOffset - startOffset) + 1,
        offset: startOffset,
        stream: response.stream,
        contentType: 'audio/webm',
      );
    } catch (e) {
      print('YoutubeExplodeSource Error: $e');
      throw Exception('YoutubeExplodeSource failed: $e');
    }
  }
}
