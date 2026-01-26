import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class PipedService {
  static final PipedService _instance = PipedService._internal();
  factory PipedService() => _instance;
  PipedService._internal();

  final http.Client _httpClient = http.Client();

  // List of reliable Piped instances (Updated for 2025)
  // Source: https://github.com/TeamPiped/Piped/wiki/Instances
  final List<String> _instances = [
    'https://pipedapi.kavin.rocks', // Primary (often busy but standard)
    'https://api.piped.video',      // Official
    'https://pipedapi.mha.fi',      // Reliable EU
    'https://api.piped.yt',         // Reliable
    'https://pipedapi.drgns.space', // Reliable
    'https://api.piped.private.coffee',
  ];

  /// Fetches the audio stream URL for a given YouTube Video ID using Piped API
  Future<String> getAudioStreamUrl(String videoId) async {
    // Iterate through instances until one succeeds
    for (final instance in _instances) {
      try {
        if (kDebugMode) print('PipedService: Trying instance $instance for $videoId');
        
        final apiUrl = '$instance/streams/$videoId';
        final response = await _httpClient.get(
            Uri.parse(apiUrl)
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final audioStreams = data['audioStreams'] as List<dynamic>?;

          if (audioStreams != null && audioStreams.isNotEmpty) {
             // Find best quality (m4a usually)
             // Prioritize m4a/aac for stability, or opus/webm
             var bestStream = audioStreams.firstWhere(
               (s) => s['format'] == 'M4A' || s['mimeType'] == 'audio/mp4',
               orElse: () => audioStreams.first
             );
             
             final playUrl = bestStream['url'] as String?;
             if (playUrl != null && playUrl.isNotEmpty) {
                if (kDebugMode) print('PipedService: Success via $instance');
                return playUrl;
             }
          }
        } 
      } catch (e) {
        if (kDebugMode) print('PipedService: Instance $instance failed: $e');
      }
    }
    
    throw Exception('All Piped instances failed');
  }
}
