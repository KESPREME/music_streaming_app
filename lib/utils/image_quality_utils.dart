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
    if (cleanUrl.contains('ytimg.com') || cleanUrl.contains('youtube.com')) {
      return cleanUrl.replaceAll(
        RegExp(r'/(default|mqdefault|hqdefault|sddefault)\.jpg'),
        '/maxresdefault.jpg',
      );
    }

    return cleanUrl;
  }

  /// Alias for getHighResArtwork
  static String getHighQualityUrl(String? url) => getHighResArtwork(url);
}
