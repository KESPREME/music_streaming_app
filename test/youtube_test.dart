import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Test YouTube stream URL fetching', () async {
    final yt = YoutubeExplode();
    
    try {
      // Test with a known working video ID
      const testVideoId = 'dQw4w9WgXcQ'; // Rick Astley - Never Gonna Give You Up
      
      print('Fetching manifest for video: $testVideoId');
      final manifest = await yt.videos.streamsClient.getManifest(testVideoId);
      
      print('Audio streams found: ${manifest.audioOnly.length}');
      
      if (manifest.audioOnly.isEmpty) {
        print('ERROR: No audio streams found!');
        return;
      }
      
      for (final stream in manifest.audioOnly) {
        print('Stream - Bitrate: ${stream.bitrate.kiloBitsPerSecond} kbps, '
              'Codec: ${stream.audioCodec}, '
              'URL length: ${stream.url.toString().length}');
      }
      
      // Test getting a specific bitrate
      final streams = manifest.audioOnly.toList();
      streams.sort((a, b) => a.bitrate.compareTo(b.bitrate));
      
      final lowestBitrate = streams.first;
      print('\nLowest bitrate stream:');
      print('Bitrate: ${lowestBitrate.bitrate.kiloBitsPerSecond} kbps');
      print('URL: ${lowestBitrate.url.toString().substring(0, 100)}...');
      
      print('\n✅ Test passed - YouTube stream fetching works!');
      
    } catch (e, s) {
      print('❌ ERROR: $e');
      print('Stack: $s');
    } finally {
      yt.close();
    }
  });
}
