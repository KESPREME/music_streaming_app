// lib/utils/network_config.dart
class NetworkConfig {
  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 15);

  // Retry configuration
  static const int maxRetries = 3;
  static const Duration initialBackoff = Duration(seconds: 1);

  // Cache configuration
  static const Duration defaultCacheValidity = Duration(hours: 24);
  static const Duration shortCacheValidity = Duration(hours: 2);
  static const Duration longCacheValidity = Duration(days: 7);

  // Bitrates for different network qualities
  static const int poorNetworkBitrate = 32;    // For very poor connections
  static const int moderateNetworkBitrate = 64;  // For moderate connections
  static const int goodNetworkBitrate = 128;     // For good connections
  static const int excellentNetworkBitrate = 192; // For excellent connections

  // Maximum concurrent downloads
  static const int maxConcurrentDownloads = 2;

  // Chunk size for downloads (512KB)
  static const int downloadChunkSize = 512 * 1024;
}
