import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:rxdart/rxdart.dart';

class UpdateInfo {
  final String version;
  final String changelog;
  final String downloadUrl;
  final bool isAvailable;

  UpdateInfo({
    required this.version,
    required this.changelog,
    required this.downloadUrl,
    required this.isAvailable,
  });
}

class UpdateService {
  // Using a sample repo or the user's expected GitHub repo
  static const String _repoOwner = 'KESPREME';
  static const String _repoName = 'music_streaming_app';
  static const String _apiUrl = 'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  final Dio _dio = Dio();
  
  // Expose download progress
  final BehaviorSubject<double> _downloadProgress = BehaviorSubject<double>.seeded(0.0);
  Stream<double> get downloadProgress => _downloadProgress.stream;

  Future<UpdateInfo> checkForUpdate() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      final response = await _dio.get(_apiUrl);
      if (response.statusCode == 200) {
        final data = response.data;
        String latestVersion = data['tag_name'] as String;
        
        // Remove 'v' prefix if present for comparison
        if (latestVersion.toLowerCase().startsWith('v')) {
          latestVersion = latestVersion.substring(1);
        }
        
        // Ensure current version has no prefix either
        String current = currentVersion;
        if (current.toLowerCase().startsWith('v')) {
          current = current.substring(1);
        }

        bool isAvailable = _compareVersions(latestVersion, current);
        String downloadUrl = '';
        
        if (data['assets'] != null && data['assets'].isNotEmpty) {
          // Find the apk asset
          for (var asset in data['assets']) {
            if (asset['name'].toString().endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'];
              break;
            }
          }
        }

        return UpdateInfo(
          version: latestVersion,
          changelog: data['body'] ?? 'No changelog available.',
          downloadUrl: downloadUrl,
          isAvailable: isAvailable && downloadUrl.isNotEmpty,
        );
      }
    } catch (e) {
      print('Error checking for update: $e');
    }
    
    return UpdateInfo(version: '', changelog: '', downloadUrl: '', isAvailable: false);
  }

  Future<void> downloadAndInstallUpdate(String url) async {
    try {
      _downloadProgress.add(0.0);
      
      final Directory tempDir = await getTemporaryDirectory();
      final String savePath = '${tempDir.path}/update.apk';
      
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            _downloadProgress.add(received / total);
          }
        },
      );
      
      _downloadProgress.add(1.0);
      
      // Install the APK
      final result = await OpenFile.open(savePath);
      print('Install result: ${result.message}');
    } catch (e) {
      print('Error downloading update: $e');
      _downloadProgress.add(-1.0); // Error state
    }
  }

  // Returns true if latest > current
  bool _compareVersions(String latest, String current) {
    try {
      List<int> latestParts = latest.split('.').map(int.parse).toList();
      List<int> currentParts = current.split('.').map(int.parse).toList();

      for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return latestParts.length > currentParts.length;
    } catch (e) {
      return latest != current;
    }
  }

  void dispose() {
    _downloadProgress.close();
  }
}
