import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Playlist;
import '../models/playlist.dart';
import '../models/track.dart';

class PlaylistImportService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Import a YouTube or YouTube Music playlist
  Future<Playlist> importYoutubePlaylist(String url) async {
    try {
      final playlistRaw = await _yt.playlists.get(url);
      final videos = await _yt.playlists.getVideos(playlistRaw.id).toList();

      final tracks = videos.map((video) {
        return Track(
          id: video.id.value,
          trackName: video.title,
          artistName: video.author,
          albumName: "YouTube Playlist",
          previewUrl: video.url,
          albumArtUrl: video.thumbnails.highResUrl,
          source: 'youtube',
          duration: video.duration,
        );
      }).toList();

      return Playlist(
        id: playlistRaw.id.value,
        name: playlistRaw.title,
        imageUrl: playlistRaw.thumbnails.highResUrl,
        tracks: tracks,
      );
    } catch (e) {
      throw Exception('Failed to import YouTube playlist: $e');
    }
  }

  /// Parse a public Spotify playlist URL to extract songs and search them on YouTube
  Future<Playlist> importSpotifyPlaylist(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('Failed to load Spotify webpage: ${response.statusCode}');
      }

      final document = html_parser.parse(response.body);
      
      // Basic scraping of meta tags where Spotify embeds playlist details
      // Or looking for ld+json or tracklist segments
      
      // Look for the initial track list data from open.spotify.com
      // We can also extract track names from <meta property="music:song"> if available
      // Or scrape list items.
      
      List<String> rawQueries = [];
      String playlistName = 'Imported Spotify Playlist';
      String imageUrl = '';

      final titleElement = document.querySelector('title');
      if (titleElement != null) {
        playlistName = titleElement.text.replaceAll(' - Spotify', '');
      }
      
      final imageElement = document.querySelector('meta[property="og:image"]');
      if (imageElement != null) {
        imageUrl = imageElement.attributes['content'] ?? '';
      }

      // Try finding meta tags for songs
      final songElements = document.querySelectorAll('meta[content*="Spotify"]');
      // Spotify often uses meta property="og:description" which contains artists or track list snippet
      
      // The most robust way without API on public links is looking for the embedded JSON 
      // id="initial-state" or looking for track rows.
      // Easiest is to search for text inside the tracklist.
      // For a robust implementation we will search for specific meta properties if available, 
      // but if not, we extract the title. 
      // Actually Spotify's open page has <meta name="music:song" content="...">
      // Let's scrape the tracks using elements that match generic Spotify classes or <meta> tags
      
      final trackMetas = document.querySelectorAll('meta[name="music:song"]');
      for (var meta in trackMetas) {
         // This typically contains a URL to the track, we'd have to parse that too.
         // Let's try the common structured data scripts
      }
      
      // A more universal approach is to grab all elements that look like track rows.
      // However, YouTubeExplode search is the bottleneck. Let's find "Artist - Song" pairs.
      
      // Let's look for standard Open Graph description which often lists artists/songs.
      final descElement = document.querySelector('meta[property="og:description"]');
      if (descElement != null) {
        // e.g., "Listen to Top 50 by Spotify..."
      }
      
      // Assuming we can find the tracks via class names (which change often).
      // Let's implement a fallback regex to find track info in the JSON blob Spotify embeds.
      final htmlStr = response.body;
      final entityRegex = RegExp(r'"name":"([^"]+)".*?"artists":\[{"name":"([^"]+)"');
      final matches = entityRegex.allMatches(htmlStr);
      
      // Use a Set to avoid duplicates (Spotify's JSON has a lot of duplicated entities)
      final Set<String> uniqueQueries = {};
      
      for (var match in matches) {
        final trackName = match.group(1);
        final artistName = match.group(2);
        
        // Skip some common generic names that appear in the JSON chunk
        if (trackName != null && artistName != null && trackName != playlistName && artistName != 'Spotify') {
           uniqueQueries.add('$trackName $artistName');
        }
      }
      
      if (uniqueQueries.isEmpty) {
        throw Exception('Could not extract any tracks from the Spotify page.');
      }

      final List<Track> tracks = [];
      int count = 0;
      
      // Limit to 50 to avoid massive loading times/API ratelimits on YT side
      final maxQueries = uniqueQueries.take(50).toList();

      for (String query in maxQueries) {
        try {
          final searchResult = await _yt.search(query);
          if (searchResult.isNotEmpty) {
             final video = searchResult.first;
             tracks.add(Track(
               id: video.id.value,
               trackName: video.title,
               artistName: video.author,
               albumName: 'Spotify Import',
               previewUrl: video.url,
               albumArtUrl: video.thumbnails.highResUrl,
               source: 'youtube', // Stored as youtube since it streams from youtube
               duration: video.duration,
             ));
          }
        } catch (e) {
          // Skip on search error
        }
        count++;
      }

      return Playlist(
        id: 'spotify_import_${DateTime.now().millisecondsSinceEpoch}',
        name: playlistName,
        imageUrl: imageUrl,
        tracks: tracks,
      );
      
    } catch (e) {
      throw Exception('Failed to import Spotify playlist: $e');
    }
  }
}
