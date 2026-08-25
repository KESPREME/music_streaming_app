// lib/utils/network_config.dart
class NetworkConfig {
  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 15);

  // Retry configuration
  static const int maxRetries = 3;

  // Cache configuration
  static const Duration defaultCacheValidity = Duration(hours: 24);

  // Bitrates for different network qualities
  static const int poorNetworkBitrate = 32;    // For very poor connections
  static const int moderateNetworkBitrate = 64;  // For moderate connections
  static const int goodNetworkBitrate = 128;     // For good connections
  static const int excellentNetworkBitrate = 192; // For excellent connections
}

