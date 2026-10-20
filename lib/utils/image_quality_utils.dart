// lib/utils/image_quality_utils.dart

/// Utility for resolving and upgrading music artwork to FHD+ resolution.
class ImageQualityUtils {
  ImageQualityUtils._();

  /// Upgrades an image URL to FHD+ / maximum available resolution.
  ///
  /// - `lh3.googleusercontent.com` / `googleusercontent.com`:
  ///   Upgrades `=w\d+-h\d+` to `=w1200-h1200-l90-rj` (crisp 1200x1200px).
  /// - `i.ytimg.com` / `img.youtube.com`:
  ///   Upgrades `default.jpg`, `mqdefault.jpg`, `hqdefault.jpg`, `sddefault.jpg`
  ///   to `maxresdefault.jpg` (1280x720px).
  static String getHighResArtwork(String? url) {
    if (url == null || url.trim().isEmpty) return '';

    var cleanUrl = url.trim();
    // A protocol-relative link (//lh3...) is not a URL the image loader can fetch.
    if (cleanUrl.startsWith('//')) cleanUrl = 'https:$cleanUrl';

    // 1. Google User Content (YouTube Music high-res format)
    if (cleanUrl.contains('googleusercontent.com')) {
      if (cleanUrl.contains(RegExp(r'=w\d+-h\d+'))) {
        return cleanUrl.replaceAll(
          RegExp(r'=w\d+-h\d+[^"\s]*'),
          '=w1200-h1200-l90-rj',
        );
      } else if (cleanUrl.contains(RegExp(r'=s\d+'))) {
        return cleanUrl.replaceAll(
          RegExp(r'=s\d+[^"\s]*'),
          '=s1200',
        );
      } else if (!cleanUrl.contains('=')) {
        return '$cleanUrl=w1200-h1200-l90-rj';
      }
    }

    // 2. YouTube Video Thumbnails
    //
    // Only an UNSIGNED link is rewritten. InnerTube video thumbnails carry a signed
    // ?sqp=...&rs=... query; editing the path under a signature gets the request
    // refused, and maxresdefault does not exist for many videos at all. A signed
    // link is returned as it came (and [candidates] keeps the original as the
    // fallback for the unsigned ones that 404).
    if ((cleanUrl.contains('ytimg.com') || cleanUrl.contains('youtube.com')) &&
        !cleanUrl.contains('?')) {
      return cleanUrl.replaceAll(
        RegExp(r'/(default|mqdefault|hqdefault|sddefault)\.jpg'),
        '/maxresdefault.jpg',
      );
    }

    return cleanUrl;
  }

  /// Alias for getHighResArtwork
  static String getHighQualityUrl(String? url) => getHighResArtwork(url);

  /// The URLs to try for one picture, best first: the upgraded link, then the one
  /// the source gave. An upgrade is a guess (a resolution that may not exist); the
  /// original is known to be what the source served. Empty and duplicate entries
  /// are dropped, so a link with nothing to upgrade yields one candidate.
  static List<String> candidates(String? url) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return const [];
    final normal = raw.startsWith('//') ? 'https:$raw' : raw;
    final upgraded = getHighResArtwork(normal);
    return <String>{if (upgraded.isNotEmpty) upgraded, normal}.toList();
  }
}
