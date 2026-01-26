import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class CobaltService {
  static final CobaltService _instance = CobaltService._internal();
  factory CobaltService() => _instance;
  CobaltService._internal();

  final http.Client _httpClient = http.Client();

  // List of reliable Cobalt instances
  // These run yt-dlp (Python) on the backend
  final List<String> _instances = [
    'https://cobalt.kwiatekmiki.pl', // Community
    'https://co.wuk.sh',             // Popular
    'https://cobalt.q1.wtf',         // Community
    'https://api.cobalt.tools',      // Official (might have bot protection)
    'https://cobalt.synced.ly',
  ];

  /// Fetches the audio stream URL for a given YouTube Video ID using Cobalt API
  Future<String> getAudioStreamUrl(String videoId) async {
    final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';
    
    // Iterate through instances until one succeeds
    for (final instance in _instances) {
      try {
        if (kDebugMode) print('CobaltService: Trying instance $instance for $videoId');
        
        final apiUrl = '$instance/api/json';
        final response = await _httpClient.post(
          Uri.parse(apiUrl),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
          body: jsonEncode({
            'url': youtubeUrl,
            'isAudioOnly': true,
            'aFormat': 'mp3', // Request MP3 for best compatibility
            'filenamePattern': 'classic',
          }),
        ).timeout(const Duration(seconds: 15)); // Short timeout per instance

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          // Check for success status
          if (data['status'] == 'stream' || data['status'] == 'redirect' || data['status'] == 'success') {
             final playUrl = data['url'] as String?;
             if (playUrl != null && playUrl.isNotEmpty) {
               if (kDebugMode) print('CobaltService: Success via $instance');
               return playUrl;
             }
          } else if (data['status'] == 'error') {
             if (kDebugMode) print('CobaltService: Instance $instance returned error: ${data['text']}');
          }
        } else {
          if (kDebugMode) print('CobaltService: Instance $instance failed with status ${response.statusCode}');
        }
      } catch (e) {
        if (kDebugMode) print('CobaltService: Instance $instance failed: $e');
      }
    }
    
    throw Exception('All Cobalt instances failed');
  }
}
