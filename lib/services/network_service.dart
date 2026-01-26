// lib/services/network_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
// import 'package:flutter/foundation.dart'; // Unused
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/network_config.dart';

enum NetworkQuality {
  offline,
  poor,
  moderate,
  good,
  excellent
}

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;

  NetworkService._internal() {
    _initConnectivityListener();
    _checkNetworkQuality();
  }

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: NetworkConfig.connectTimeout,
    receiveTimeout: NetworkConfig.receiveTimeout,
    sendTimeout: NetworkConfig.sendTimeout,
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
  ));

  final Connectivity _connectivity = Connectivity();
  final InternetConnectionChecker _connectionChecker = InternetConnectionChecker.instance;
  final DefaultCacheManager _cacheManager = DefaultCacheManager();

  StreamSubscription? _connectivitySubscription;
  NetworkQuality _networkQuality = NetworkQuality.moderate;
  bool _isConnected = true;

  // Getters
  NetworkQuality get networkQuality => _networkQuality;
  bool get isConnected => _isConnected;

  // Stream controllers
  final _networkQualityController = StreamController<NetworkQuality>.broadcast();
  final _connectivityController = StreamController<bool>.broadcast();

  // Streams
  Stream<NetworkQuality> get onNetworkQualityChanged => _networkQualityController.stream;
  Stream<bool> get onConnectivityChanged => _connectivityController.stream;

  void _initConnectivityListener() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((_) async {
      await _checkConnectivity();
      await _checkNetworkQuality();
    });
  }

  Future<void> _checkConnectivity() async {
    final isConnected = await _connectionChecker.hasConnection;
    if (_isConnected != isConnected) {
      _isConnected = isConnected;
      _connectivityController.add(_isConnected);
      print('Network connectivity changed to: ${_isConnected ? 'connected' : 'disconnected'}');
    }
  }

  Future<void> _checkNetworkQuality() async {
    if (!_isConnected) {
      _updateNetworkQuality(NetworkQuality.offline);
      return;
    }

    try {
      // Check current connection type
      final connectivityResult = await _connectivity.checkConnectivity();

      // If on mobile network, check if it's Jio (known problematic network)
      if (connectivityResult.contains(ConnectivityResult.mobile)) {
        final isJio = await _isJioNetwork();
        if (isJio) {
          // Jio networks often have connectivity issues, so treat as poor by default
          _updateNetworkQuality(NetworkQuality.poor);
          return;
        }
      }

      // Measure download speed
      final stopwatch = Stopwatch()..start();

      // Use a small test file (Google's favicon is reliable and small)
      final response = await http.get(
          Uri.parse('https://www.google.com/favicon.ico'),
          headers: {'Cache-Control': 'no-cache'}
      ).timeout(const Duration(seconds: 5), onTimeout: () {
        throw TimeoutException('Network test timed out');
      });

      stopwatch.stop();

      final downloadTime = stopwatch.elapsedMilliseconds;
      final downloadSizeKb = response.bodyBytes.length / 1024;
      final speedKbps = downloadSizeKb / (downloadTime / 1000);

      print('Network speed test: $speedKbps Kbps');

      // Determine network quality based on speed and connection type
      NetworkQuality quality;

      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        if (speedKbps < 50) {
          quality = NetworkQuality.poor;
        } else if (speedKbps < 200) {
          quality = NetworkQuality.moderate;
        } else if (speedKbps < 1000) {
          quality = NetworkQuality.good;
        } else {
          quality = NetworkQuality.excellent;
        }
      } else {
        // Mobile networks
        if (speedKbps < 30) {
          quality = NetworkQuality.poor;
        } else if (speedKbps < 100) {
          quality = NetworkQuality.moderate;
        } else if (speedKbps < 500) {
          quality = NetworkQuality.good;
        } else {
          quality = NetworkQuality.excellent;
        }
      }

      _updateNetworkQuality(quality);
    } catch (e) {
      print('Error checking network quality: $e');
      // If we can't measure speed but have connectivity, assume moderate
      if (_isConnected) {
        _updateNetworkQuality(NetworkQuality.moderate);
      } else {
        _updateNetworkQuality(NetworkQuality.offline);
      }
    }
  }

  Future<bool> _isJioNetwork() async {
    try {
      // This is a heuristic approach - check for Jio DNS or IP ranges
      // Most Jio connections use Jio's DNS servers
      final dnsServers = await _getDnsServers();
      final isJioDns = dnsServers.any((dns) =>
      dns.contains('49.44.') ||
          dns.contains('49.45.') ||
          dns.contains('8.8.') // Jio often uses Google DNS
      );

      return isJioDns;
    } catch (_) {
      // Error is not used, just print a generic message.
      print('Could not determine carrier-specific network details.');
      return false;
    }
  }

  Future<List<String>> _getDnsServers() async {
    try {
      // This is a simplified approach - in a real app, you might need
      // platform-specific code to get actual DNS servers
      final result = await Process.run('getprop', ['net.dns1']);
      final dns1 = result.stdout.toString().trim();

      final result2 = await Process.run('getprop', ['net.dns2']);
      final dns2 = result2.stdout.toString().trim();

      return [dns1, dns2].where((dns) => dns.isNotEmpty).toList();
    } catch (_) {
      // If we can't get DNS servers, return empty list
      return [];
    }
  }

  void _updateNetworkQuality(NetworkQuality quality) {
    if (_networkQuality != quality) {
      print('Network quality changed from $_networkQuality to $quality');
      _networkQuality = quality;
      _networkQualityController.add(_networkQuality);
    }
  }

  // Get optimal bitrate based on network quality
  int getOptimalBitrate() {
    switch (_networkQuality) {
      case NetworkQuality.offline:
        return 0; // Offline mode
      case NetworkQuality.poor:
        return NetworkConfig.poorNetworkBitrate;
      case NetworkQuality.moderate:
        return NetworkConfig.moderateNetworkBitrate;
      case NetworkQuality.good:
        return NetworkConfig.goodNetworkBitrate;
      case NetworkQuality.excellent:
        return NetworkConfig.excellentNetworkBitrate;
    }
  }

  // HTTP GET with retry, timeout, and caching
  Future<dynamic> get(
      String url, {
        Map<String, String>? headers,
        bool useCache = true,
        Duration cacheExpiry = NetworkConfig.defaultCacheValidity,
        int maxRetries = NetworkConfig.maxRetries,
        Duration? timeout,
      }) async {
    // Check connectivity first
    if (!_isConnected) {
      // Try to get from cache if offline
      if (useCache) {
        final cachedData = await _getCachedResponse(url);
        if (cachedData != null) {
          return cachedData;
        }
      }
      throw Exception('No internet connection');
    }

    // Try to get from cache first if enabled
    if (useCache) {
      final cachedData = await _getCachedResponse(url);
      if (cachedData != null) {
        // Return cached data and refresh in background
        _refreshCacheInBackground(url, headers, cacheExpiry, timeout);
        return cachedData;
      }
    }

    // Set up options
    final options = Options(
      headers: headers,
      sendTimeout: timeout ?? NetworkConfig.sendTimeout,
      receiveTimeout: timeout ?? NetworkConfig.receiveTimeout,
    );

    // Implement retry logic with exponential backoff
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        final response = await _dio.get(
          url,
          options: options,
        );

        // Cache the successful response
        if (useCache) {
          await _cacheResponse(url, response.data, cacheExpiry);
        }

        return response.data;
      } on DioException {
        attempts++;

        // If it's the last attempt, rethrow
        if (attempts >= maxRetries) {
          // Try to return cached data if available, even if expired
          if (useCache) {
            final cachedData = await _getCachedResponse(url, ignoreExpiry: true);
            if (cachedData != null) {
              return cachedData;
            }
          }
          rethrow;
        }

        // Calculate backoff time (exponential with jitter)
        final backoffSeconds = pow(2, attempts) + (Random().nextInt(1000) / 1000.0);
        print('Request failed, retrying in $backoffSeconds seconds...');
        await Future.delayed(Duration(milliseconds: (backoffSeconds * 1000).round()));

        // Check connectivity again before retrying
        await _checkConnectivity();
        if (!_isConnected) {
          // Try to get from cache if we're offline now
          if (useCache) {
            final cachedData = await _getCachedResponse(url, ignoreExpiry: true);
            if (cachedData != null) {
              return cachedData;
            }
          }
          throw Exception('Lost internet connection');
        }
      }
    }

    throw Exception('Failed after $maxRetries attempts');
  }

  // Cache response data
  Future<void> _cacheResponse(String url, dynamic data, Duration expiry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'cache_${url.hashCode}';
      final expiryKey = 'expiry_${url.hashCode}';

      // Store data and expiry time
      final expiryTime = DateTime.now().add(expiry).millisecondsSinceEpoch;
      await prefs.setString(cacheKey, jsonEncode(data));
      await prefs.setInt(expiryKey, expiryTime);
    } catch (_) {
      print('Error caching response for key: $url');
    }
  }

  // Get cached response data
  Future<dynamic> _getCachedResponse(String url, {bool ignoreExpiry = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'cache_${url.hashCode}';
      final expiryKey = 'expiry_${url.hashCode}';

      // Check if we have cached data
      if (!prefs.containsKey(cacheKey)) {
        return null;
      }

      // Check expiry if needed
      if (!ignoreExpiry) {
        final expiryTime = prefs.getInt(expiryKey) ?? 0;
        if (DateTime.now().millisecondsSinceEpoch > expiryTime) {
          return null; // Cache expired
        }
      }

      // Return cached data
      final cachedData = prefs.getString(cacheKey);
      if (cachedData != null) {
        return jsonDecode(cachedData);
      }
    } catch (_) {
      print('Error getting cached response for key: $url');
    }

    return null;
  }

  // Refresh cache in background
  Future<void> _refreshCacheInBackground(
      String url,
      Map<String, String>? headers,
      Duration cacheExpiry,
      Duration? timeout,
      ) async {
    try {
      final options = Options(
        headers: headers,
        sendTimeout: timeout ?? NetworkConfig.sendTimeout,
        receiveTimeout: timeout ?? NetworkConfig.receiveTimeout,
      );

      final response = await _dio.get(url, options: options);
      await _cacheResponse(url, response.data, cacheExpiry);
    } catch (_) {
      // Ignore errors during background refresh
      print('Background cache refresh failed for url: $url');
    }
  }

  // HTTP POST with retry and timeout
  Future<dynamic> post(
      String url, {
        dynamic data,
        Map<String, String>? headers,
        int maxRetries = NetworkConfig.maxRetries,
        Duration? timeout,
      }) async {
    if (!_isConnected) {
      throw Exception('No internet connection');
    }

    // Set up options
    final options = Options(
      headers: headers,
      sendTimeout: timeout ?? NetworkConfig.sendTimeout,
      receiveTimeout: timeout ?? NetworkConfig.receiveTimeout,
    );

    // Implement retry logic with exponential backoff
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        final response = await _dio.post(
          url,
          data: data,
          options: options,
        );

        return response.data;
      } on DioException {
        attempts++;

        // If it's the last attempt, rethrow
        if (attempts >= maxRetries) {
          rethrow;
        }

        // Calculate backoff time (exponential with jitter)
        final backoffSeconds = pow(2, attempts) + (Random().nextInt(1000) / 1000.0);
        await Future.delayed(Duration(milliseconds: (backoffSeconds * 1000).round()));

        // Check connectivity again before retrying
        await _checkConnectivity();
        if (!_isConnected) {
          throw Exception('Lost internet connection');
        }
      }
    }

    throw Exception('Failed after $maxRetries attempts');
  }

  // Download file with retry, resume capability, and progress tracking
  Future<String> downloadFile(
      String url,
      String savePath, {
        Function(double)? onProgress,
        CancelToken? cancelToken,
        int maxRetries = NetworkConfig.maxRetries,
        Duration? timeout,
      }) async {
    if (!_isConnected) {
      throw Exception('No internet connection');
    }

    // Check if file exists and get size for resume
    final file = File(savePath);
    int startBytes = 0;

    if (await file.exists()) {
      try {
        startBytes = await file.length();
        } catch (_) {
        // If we can't get length, start from beginning
        startBytes = 0;
      }
    }

    // Set up options with range header for resume
    final options = Options(
      headers: startBytes > 0 ? {'Range': 'bytes=$startBytes-'} : null,
      sendTimeout: timeout ?? const Duration(minutes: 30),
      receiveTimeout: timeout ?? const Duration(minutes: 30),
    );

    // Implement retry logic with exponential backoff
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        await _dio.download(
          url,
          startBytes > 0 ? '$savePath.temp' : savePath,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              final progress = (startBytes + received) / (startBytes + total);
              onProgress?.call(progress);
            }
          },
          options: options,
          // Use chunked download for large files
          deleteOnError: false,
        );

        // If we were resuming, append the temp file to the original
        if (startBytes > 0) {
          final tempFile = File('$savePath.temp');
          if (await tempFile.exists()) {
            final raf = await file.open(mode: FileMode.append);
            await raf.writeFrom(await tempFile.readAsBytes());
            await raf.close();
            await tempFile.delete();
          }
        }

        return savePath;
      } on DioException {
        // Don't retry if canceled
        if (cancelToken?.isCancelled ?? false) {
          throw Exception('Download canceled');
        }

        attempts++;

        // If it's the last attempt, rethrow
        if (attempts >= maxRetries) {
          rethrow;
        }

        // Calculate backoff time (exponential with jitter)
        final backoffSeconds = pow(2, attempts) + (Random().nextInt(1000) / 1000.0);
        await Future.delayed(Duration(milliseconds: (backoffSeconds * 1000).round()));

        // Check connectivity again before retrying
        await _checkConnectivity();
        if (!_isConnected) {
          throw Exception('Lost internet connection');
        }

        // Update start bytes in case we downloaded some data
        if (await file.exists()) {
          try {
            startBytes = await file.length();
          } catch (_) {
            // If we can't get length, continue from last known position
          }
        }
      }
    }

    throw Exception('Failed after $maxRetries attempts');
  }

  // Download file using cache manager (better for smaller files like images)
  Future<File> downloadCachedFile(
      String url, {
        String? key,
        Map<String, String>? headers,
      }) async {
    if (!_isConnected) {
      // Try to get from cache if offline
      try {
        final fileInfo = await _cacheManager.getFileFromCache(key ?? url);
        if (fileInfo != null) {
          return fileInfo.file;
        }
      } catch (_) {
        print('Error getting file from cache for key: ${key ?? url}');
      }
      throw Exception('No internet connection');
    }

    try {
      final fileInfo = await _cacheManager.downloadFile(
        url,
        key: key,
      );

      return fileInfo.file;
    } catch (e) {
      // Try to get from cache if download fails
      try {
        final fileInfo = await _cacheManager.getFileFromCache(key ?? url);
        if (fileInfo != null) {
          return fileInfo.file;
        }
      } catch (_) {
        print('Error getting file from cache for key: ${key ?? url}');
      }
      rethrow;
    }
  }

  // Check if a URL is reachable
  Future<bool> isUrlReachable(String url, {Duration? timeout}) async {
    if (!_isConnected) {
      return false;
    }

    try {
      final response = await _dio.head(
        url,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
          sendTimeout: timeout ?? const Duration(seconds: 5),
          receiveTimeout: timeout ?? const Duration(seconds: 5),
        ),
      );
      return response.statusCode != null && response.statusCode! < 400;
    } catch (_) {
      return false;
    }
  }

  // Force network quality check
  Future<NetworkQuality> checkNetworkQualityNow() async {
    await _checkConnectivity();
    await _checkNetworkQuality();
    return _networkQuality;
  }

  // Get current connection type
  Future<ConnectivityResult> getConnectionType() async {
    final results = await _connectivity.checkConnectivity();
    return results.isNotEmpty ? results.first : ConnectivityResult.none;
  }


  // Clear cache
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) =>
      key.startsWith('cache_') || key.startsWith('expiry_')
      ).toList();

      for (final key in keys) {
        await prefs.remove(key);
      }

      await _cacheManager.emptyCache();
    } catch (_) {
      print('Error clearing network service cache.');
    }
  }

  // Clean up resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _networkQualityController.close();
    _connectivityController.close();
  }
}

