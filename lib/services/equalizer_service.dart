import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_service.dart';

/// Equalizer preset definitions
class EQPreset {
  final String name;
  final String id;
  final List<double> bandGains; // Gains for each frequency band (-12 to +12 dB)

  const EQPreset({
    required this.name,
    required this.id,
    required this.bandGains,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'id': id,
    'bandGains': bandGains,
  };

  factory EQPreset.fromJson(Map<String, dynamic> json) => EQPreset(
    name: json['name'] as String,
    id: json['id'] as String,
    bandGains: (json['bandGains'] as List).cast<double>(),
  );
}

/// Equalizer service with presets and custom settings
/// Connects directly to AudioService's AndroidEqualizer for real audio processing
class EqualizerService {
  static final EqualizerService _instance = EqualizerService._internal();
  factory EqualizerService() => _instance;
  EqualizerService._internal();

  // Reference to AudioService (set during initialization)
  AudioService? _audioService;
  AndroidEqualizerParameters? _eqParams;
  
  // Current settings
  bool _isEnabled = false;
  String _currentPresetId = 'flat';
  List<double> _customBandGains = [];
  int _bandCount = 5; // Default, will be updated from device
  
  // Callbacks for UI updates
  final List<VoidCallback> _listeners = [];

  // Built-in presets (5-band EQ: 60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz)
  static List<EQPreset> get presets => [
    const EQPreset(
      name: 'Flat',
      id: 'flat',
      bandGains: [0, 0, 0, 0, 0],
    ),
    const EQPreset(
      name: 'Bass Boost',
      id: 'bass_boost',
      bandGains: [6, 4, 0, 0, 0],
    ),
    const EQPreset(
      name: 'Treble Boost',
      id: 'treble_boost',
      bandGains: [0, 0, 0, 4, 6],
    ),
    const EQPreset(
      name: 'Vocal',
      id: 'vocal',
      bandGains: [-2, 0, 4, 3, 0],
    ),
    const EQPreset(
      name: 'Rock',
      id: 'rock',
      bandGains: [5, 3, -1, 3, 5],
    ),
    const EQPreset(
      name: 'Electronic',
      id: 'electronic',
      bandGains: [6, 4, 0, 2, 4],
    ),
    const EQPreset(
      name: 'Hip Hop',
      id: 'hiphop',
      bandGains: [5, 4, 0, 1, 3],
    ),
    const EQPreset(
      name: 'Podcast',
      id: 'podcast',
      bandGains: [-2, 0, 4, 4, 0],
    ),
    const EQPreset(
      name: 'Custom',
      id: 'custom',
      bandGains: [0, 0, 0, 0, 0],
    ),
  ];

  // Static band labels (may be updated from device)
  static List<String> bandLabels = ['60', '230', '910', '3.6k', '14k'];
  static int get bandCount => 5;

  // Getters
  bool get isEnabled => _isEnabled;
  String get currentPresetId => _currentPresetId;
  List<double> get currentBandGains {
    if (_currentPresetId == 'custom') {
      return List.from(_customBandGains);
    }
    final preset = presets.firstWhere(
      (p) => p.id == _currentPresetId,
      orElse: () => presets.first,
    );
    // Scale to match actual band count if different
    if (preset.bandGains.length != _bandCount && _bandCount > 0) {
      return _scaleBands(preset.bandGains, _bandCount);
    }
    return List.from(preset.bandGains);
  }
  
  EQPreset get currentPreset => presets.firstWhere(
    (p) => p.id == _currentPresetId,
    orElse: () => presets.first,
  );

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Initialize and load saved settings
  /// Call this AFTER AudioService is created
  Future<void> initialize([AudioService? audioService]) async {
    _audioService = audioService;
    await _loadSettings();
    
    // Get actual EQ parameters from device
    if (_audioService != null && Platform.isAndroid) {
      try {
        _eqParams = await _audioService!.equalizer.parameters;
        _bandCount = _eqParams?.bands.length ?? 5;
        
        // Update band labels from device
        if (_eqParams != null) {
          bandLabels = _eqParams!.bands.map((band) {
            final freq = band.centerFrequency;
            if (freq >= 1000) {
              return '${(freq / 1000).toStringAsFixed(1)}k';
            }
            return freq.toStringAsFixed(0);
          }).toList();
        }
        
        // Initialize custom gains to correct size
        if (_customBandGains.length != _bandCount) {
          _customBandGains = List.filled(_bandCount, 0.0);
        }
        
        if (kDebugMode) {
          print('EqualizerService: Initialized with $_bandCount bands');
          print('EqualizerService: Band frequencies: $bandLabels');
        }
      } catch (e) {
        if (kDebugMode) print('EqualizerService: Error getting EQ params: $e');
      }
    }
    
    // Apply saved settings
    if (_isEnabled) {
      await _applyEQ();
    }
    
    if (kDebugMode) {
      print('EqualizerService: Initialized with preset=$_currentPresetId, enabled=$_isEnabled');
    }
  }

  /// Set the audio service reference (for late binding)
  void setAudioService(AudioService audioService) {
    _audioService = audioService;
    // Re-initialize if needed
    if (_isEnabled) {
      _applyEQ();
    }
  }

  /// Scale preset bands to match device's actual band count
  List<double> _scaleBands(List<double> source, int targetCount) {
    if (source.length == targetCount) return List.from(source);
    
    final result = <double>[];
    for (int i = 0; i < targetCount; i++) {
      final sourceIndex = (i * source.length / targetCount).floor();
      result.add(source[sourceIndex.clamp(0, source.length - 1)]);
    }
    return result;
  }

  /// Enable/disable the equalizer
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    
    // Enable/disable the Android equalizer
    if (_audioService != null && Platform.isAndroid) {
      try {
        await _audioService!.equalizer.setEnabled(enabled);
        if (enabled) {
          await _applyEQ();
        }
        if (kDebugMode) print('EqualizerService: EQ ${enabled ? "enabled" : "disabled"}');
      } catch (e) {
        if (kDebugMode) print('EqualizerService: Error setting enabled: $e');
      }
    }
    
    await _saveSettings();
    _notifyListeners();
  }

  /// Select a preset by ID
  Future<void> selectPreset(String presetId) async {
    _currentPresetId = presetId;
    await _applyEQ();
    await _saveSettings();
    _notifyListeners();
  }

  /// Set a custom band gain (switches to custom preset)
  Future<void> setBandGain(int bandIndex, double gain) async {
    if (bandIndex < 0 || bandIndex >= _bandCount) return;
    
    // Clamp gain to valid range
    gain = gain.clamp(-12.0, 12.0);
    
    // Switch to custom mode if not already
    if (_currentPresetId != 'custom') {
      _customBandGains = List.from(currentBandGains);
      _currentPresetId = 'custom';
    }
    
    // Ensure custom gains list is correct size
    while (_customBandGains.length < _bandCount) {
      _customBandGains.add(0.0);
    }
    
    _customBandGains[bandIndex] = gain;
    await _applyEQ();
    await _saveSettings();
    _notifyListeners();
  }

  /// Apply EQ settings to the actual Android equalizer
  Future<void> _applyEQ() async {
    if (!_isEnabled || _audioService == null || !Platform.isAndroid) {
      return;
    }

    final gains = currentBandGains;
    if (kDebugMode) {
      print('EqualizerService: Applying EQ - Preset=$_currentPresetId, Gains=$gains');
    }

    try {
      // Get equalizer parameters
      _eqParams ??= await _audioService!.equalizer.parameters;
      
      if (_eqParams == null) {
        if (kDebugMode) print('EqualizerService: No EQ params available');
        return;
      }
      
      final bands = _eqParams!.bands;
      final minGain = _eqParams!.minDecibels;
      final maxGain = _eqParams!.maxDecibels;
      
      // Apply gains to each band
      for (int i = 0; i < bands.length && i < gains.length; i++) {
        // Map our -12 to +12 dB range to device's range
        final normalizedGain = (gains[i] + 12) / 24; // 0 to 1
        final deviceGain = minGain + (normalizedGain * (maxGain - minGain));
        
        await bands[i].setGain(deviceGain);
        if (kDebugMode) {
          print('EqualizerService: Band ${i} (${bands[i].centerFrequency}Hz) set to ${deviceGain.toStringAsFixed(1)}dB');
        }
      }
    } catch (e) {
      if (kDebugMode) print('EqualizerService: Error applying EQ: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool('eq_enabled') ?? false;
      _currentPresetId = prefs.getString('eq_preset') ?? 'flat';
      
      final customGainsStr = prefs.getStringList('eq_custom_gains');
      if (customGainsStr != null) {
        _customBandGains = customGainsStr.map((s) => double.tryParse(s) ?? 0.0).toList();
      } else {
        _customBandGains = List.filled(_bandCount, 0.0);
      }
    } catch (e) {
      if (kDebugMode) print('EqualizerService: Error loading settings: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('eq_enabled', _isEnabled);
      await prefs.setString('eq_preset', _currentPresetId);
      await prefs.setStringList(
        'eq_custom_gains',
        _customBandGains.map((g) => g.toString()).toList(),
      );
    } catch (e) {
      if (kDebugMode) print('EqualizerService: Error saving settings: $e');
    }
  }

  /// Reset to default settings
  Future<void> reset() async {
    _currentPresetId = 'flat';
    _customBandGains = List.filled(_bandCount, 0.0);
    await _applyEQ();
    await _saveSettings();
    _notifyListeners();
  }
}
