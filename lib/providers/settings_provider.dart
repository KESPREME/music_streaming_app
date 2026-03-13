import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeModeOption { system, light, dark }
enum AudioQuality { low, medium, high }
enum SortOrder { artist, album, recentlyAdded, mostPlayed }

class SettingsProvider extends ChangeNotifier {
  SharedPreferences? _prefs;

  // Appearance - Mostly in ThemeProvider, but we can add explicit ThemeMode if needed.
  ThemeModeOption _themeMode = ThemeModeOption.system;
  ThemeModeOption get themeMode => _themeMode;

  bool _enableAnimations = true;
  bool get enableAnimations => _enableAnimations;

  double _blurIntensity = 8.0; // For Glass UI
  double get blurIntensity => _blurIntensity;

  // Playback
  bool _gaplessPlayback = false;
  bool get gaplessPlayback => _gaplessPlayback;

  double _crossfadeDuration = 0.0;
  double get crossfadeDuration => _crossfadeDuration;

  bool _normalizeVolume = false;
  bool get normalizeVolume => _normalizeVolume;

  bool _autoPlayNext = true;
  bool get autoPlayNext => _autoPlayNext;

  bool _pauseOnHeadphoneDisconnect = true;
  bool get pauseOnHeadphoneDisconnect => _pauseOnHeadphoneDisconnect;

  // Audio
  AudioQuality _audioQuality = AudioQuality.high;
  AudioQuality get audioQuality => _audioQuality;

  double _bufferSize = 2.0; // seconds
  double get bufferSize => _bufferSize;

  bool _preferCache = true;
  bool get preferCache => _preferCache;

  bool _enableAudioPreloading = true;
  bool get enableAudioPreloading => _enableAudioPreloading;

  // Downloads / Offline
  AudioQuality _downloadQuality = AudioQuality.high;
  AudioQuality get downloadQuality => _downloadQuality;

  bool _downloadOverWifiOnly = false;
  bool get downloadOverWifiOnly => _downloadOverWifiOnly;

  bool _autoDeleteFailedDownloads = true;
  bool get autoDeleteFailedDownloads => _autoDeleteFailedDownloads;

  String _storageLocation = 'Default';
  String get storageLocation => _storageLocation;

  // Library
  bool _autoScanLocalMusic = false;
  bool get autoScanLocalMusic => _autoScanLocalMusic;

  SortOrder _sortOrder = SortOrder.recentlyAdded;
  SortOrder get sortOrder => _sortOrder;

  bool _hideUnavailableTracks = false;
  bool get hideUnavailableTracks => _hideUnavailableTracks;

  // Import & Services
  bool _autoSearchYouTubeForImports = true;
  bool get autoSearchYouTubeForImports => _autoSearchYouTubeForImports;

  // Notifications
  bool _lockScreenControls = true;
  bool get lockScreenControls => _lockScreenControls;

  // Developer Options
  bool _developerModeEnabled = false;
  bool get developerModeEnabled => _developerModeEnabled;

  bool _enableDebugLogs = false;
  bool get enableDebugLogs => _enableDebugLogs;

  SettingsProvider() {
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSettings();
  }

  void _loadSettings() {
    if (_prefs == null) return;
    
    _themeMode = ThemeModeOption.values[_prefs!.getInt('themeMode') ?? 0];
    _enableAnimations = _prefs!.getBool('enableAnimations') ?? true;
    _blurIntensity = _prefs!.getDouble('blurIntensity') ?? 8.0;

    _gaplessPlayback = _prefs!.getBool('gaplessPlayback') ?? false;
    _crossfadeDuration = _prefs!.getDouble('crossfadeDuration') ?? 0.0;
    _normalizeVolume = _prefs!.getBool('normalizeVolume') ?? false;
    _autoPlayNext = _prefs!.getBool('autoPlayNext') ?? true;
    _pauseOnHeadphoneDisconnect = _prefs!.getBool('pauseOnHeadphoneDisconnect') ?? true;

    _audioQuality = AudioQuality.values[_prefs!.getInt('audioQuality') ?? 2];
    _bufferSize = _prefs!.getDouble('bufferSize') ?? 2.0;
    _preferCache = _prefs!.getBool('preferCache') ?? true;
    _enableAudioPreloading = _prefs!.getBool('enableAudioPreloading') ?? true;

    _downloadQuality = AudioQuality.values[_prefs!.getInt('downloadQuality') ?? 2];
    _downloadOverWifiOnly = _prefs!.getBool('downloadOverWifiOnly') ?? false;
    _autoDeleteFailedDownloads = _prefs!.getBool('autoDeleteFailedDownloads') ?? true;
    _storageLocation = _prefs!.getString('storageLocation') ?? 'Default';

    _autoScanLocalMusic = _prefs!.getBool('autoScanLocalMusic') ?? false;
    _sortOrder = SortOrder.values[_prefs!.getInt('sortOrder') ?? 2];
    _hideUnavailableTracks = _prefs!.getBool('hideUnavailableTracks') ?? false;

    _autoSearchYouTubeForImports = _prefs!.getBool('autoSearchYouTubeForImports') ?? true;

    _lockScreenControls = _prefs!.getBool('lockScreenControls') ?? true;

    _developerModeEnabled = _prefs!.getBool('developerModeEnabled') ?? false;
    _enableDebugLogs = _prefs!.getBool('enableDebugLogs') ?? false;
    
    notifyListeners();
  }

  // --- Setters with persistence ---

  void setThemeMode(ThemeModeOption value) {
    if (_themeMode == value) return;
    _themeMode = value;
    _prefs?.setInt('themeMode', value.index);
    notifyListeners();
  }

  void setEnableAnimations(bool value) {
    if (_enableAnimations == value) return;
    _enableAnimations = value;
    _prefs?.setBool('enableAnimations', value);
    notifyListeners();
  }

  void setBlurIntensity(double value) {
    if (_blurIntensity == value) return;
    _blurIntensity = value;
    _prefs?.setDouble('blurIntensity', value);
    notifyListeners();
  }

  void setGaplessPlayback(bool value) {
    if (_gaplessPlayback == value) return;
    _gaplessPlayback = value;
    _prefs?.setBool('gaplessPlayback', value);
    notifyListeners();
  }

  void setCrossfadeDuration(double value) {
    if (_crossfadeDuration == value) return;
    _crossfadeDuration = value;
    _prefs?.setDouble('crossfadeDuration', value);
    notifyListeners();
  }

  void setNormalizeVolume(bool value) {
    if (_normalizeVolume == value) return;
    _normalizeVolume = value;
    _prefs?.setBool('normalizeVolume', value);
    notifyListeners();
  }

  void setAutoPlayNext(bool value) {
    if (_autoPlayNext == value) return;
    _autoPlayNext = value;
    _prefs?.setBool('autoPlayNext', value);
    notifyListeners();
  }

  void setPauseOnHeadphoneDisconnect(bool value) {
    if (_pauseOnHeadphoneDisconnect == value) return;
    _pauseOnHeadphoneDisconnect = value;
    _prefs?.setBool('pauseOnHeadphoneDisconnect', value);
    notifyListeners();
  }

  void setAudioQuality(AudioQuality value) {
    if (_audioQuality == value) return;
    _audioQuality = value;
    _prefs?.setInt('audioQuality', value.index);
    notifyListeners();
  }

  void setBufferSize(double value) {
    if (_bufferSize == value) return;
    _bufferSize = value;
    _prefs?.setDouble('bufferSize', value);
    notifyListeners();
  }

  void setPreferCache(bool value) {
    if (_preferCache == value) return;
    _preferCache = value;
    _prefs?.setBool('preferCache', value);
    notifyListeners();
  }

  void setEnableAudioPreloading(bool value) {
    if (_enableAudioPreloading == value) return;
    _enableAudioPreloading = value;
    _prefs?.setBool('enableAudioPreloading', value);
    notifyListeners();
  }

  void setDownloadQuality(AudioQuality value) {
    if (_downloadQuality == value) return;
    _downloadQuality = value;
    _prefs?.setInt('downloadQuality', value.index);
    notifyListeners();
  }

  void setDownloadOverWifiOnly(bool value) {
    if (_downloadOverWifiOnly == value) return;
    _downloadOverWifiOnly = value;
    _prefs?.setBool('downloadOverWifiOnly', value);
    notifyListeners();
  }

  void setAutoDeleteFailedDownloads(bool value) {
    if (_autoDeleteFailedDownloads == value) return;
    _autoDeleteFailedDownloads = value;
    _prefs?.setBool('autoDeleteFailedDownloads', value);
    notifyListeners();
  }

  void setStorageLocation(String value) {
    if (_storageLocation == value) return;
    _storageLocation = value;
    _prefs?.setString('storageLocation', value);
    notifyListeners();
  }

  void setAutoScanLocalMusic(bool value) {
    if (_autoScanLocalMusic == value) return;
    _autoScanLocalMusic = value;
    _prefs?.setBool('autoScanLocalMusic', value);
    notifyListeners();
  }

  void setSortOrder(SortOrder value) {
    if (_sortOrder == value) return;
    _sortOrder = value;
    _prefs?.setInt('sortOrder', value.index);
    notifyListeners();
  }

  void setHideUnavailableTracks(bool value) {
    if (_hideUnavailableTracks == value) return;
    _hideUnavailableTracks = value;
    _prefs?.setBool('hideUnavailableTracks', value);
    notifyListeners();
  }

  void setAutoSearchYouTubeForImports(bool value) {
    if (_autoSearchYouTubeForImports == value) return;
    _autoSearchYouTubeForImports = value;
    _prefs?.setBool('autoSearchYouTubeForImports', value);
    notifyListeners();
  }

  void setLockScreenControls(bool value) {
    if (_lockScreenControls == value) return;
    _lockScreenControls = value;
    _prefs?.setBool('lockScreenControls', value);
    notifyListeners();
  }

  void toggleDeveloperMode() {
    _developerModeEnabled = !_developerModeEnabled;
    _prefs?.setBool('developerModeEnabled', _developerModeEnabled);
    notifyListeners();
  }

  void setEnableDebugLogs(bool value) {
    if (_enableDebugLogs == value) return;
    _enableDebugLogs = value;
    _prefs?.setBool('enableDebugLogs', value);
    notifyListeners();
  }
}
