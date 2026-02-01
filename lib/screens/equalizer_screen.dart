import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../services/equalizer_service.dart';
import '../providers/music_provider.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  final EqualizerService _eqService = EqualizerService();
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _eqService.addListener(_onEQChanged);
    
    // Connect to AudioService from MusicProvider after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeEQ();
    });
  }
  
  Future<void> _initializeEQ() async {
    if (_isInitialized) return;
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    await _eqService.initialize(musicProvider.audioService);
    _isInitialized = true;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _eqService.removeListener(_onEQChanged);
    super.dispose();
  }

  void _onEQChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A), // Solid dark background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Equalizer',
          style: GoogleFonts.splineSans(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () {
               HapticFeedback.mediumImpact();
              _eqService.reset();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Enable Switch
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: _buildEnableSwitch(),
          ),
          
          const Spacer(),

          // 2. Main Visualizer / Sliders
          Expanded(
            flex: 4,
            child: _buildEQSliders(),
          ),
          
          const Spacer(),

          // 3. Presets
          SizedBox(
            height: 180,
            child: _buildPresetsList(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildEnableSwitch() {
    bool isEnabled = _eqService.isEnabled;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _eqService.setEnabled(!isEnabled);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEnabled 
                ? const Color(0xFF00B4D8).withOpacity(0.3) // Light blue
                : Colors.white.withOpacity(0.05),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audio Tuner',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  isEnabled ? 'Active' : 'Disabled',
                  style: GoogleFonts.outfit(
                    color: isEnabled ? const Color(0xFF00B4D8) : Colors.white54, // Light blue
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            Switch.adaptive(
              value: isEnabled,
              activeColor: const Color(0xFF00B4D8), // Light blue
              activeTrackColor: const Color(0xFF00B4D8).withOpacity(0.3),
              inactiveTrackColor: Colors.grey.withOpacity(0.2),
              onChanged: (val) {
                HapticFeedback.selectionClick();
                _eqService.setEnabled(val);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEQSliders() {
    final gains = _eqService.currentBandGains;
    final isEnabled = _eqService.isEnabled;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(EqualizerService.bandCount, (index) {
          return Expanded(
            child: _buildSlider(
              index,
              gains[index],
              EqualizerService.bandLabels[index],
              isEnabled,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSlider(int index, double gain, String label, bool isEnabled) {
    // Normalize gain -12..12 -> 0..1
    double normalized = (gain + 12) / 24;
    
    return Column(
      children: [
        // Gain Text
        Text(
          '${gain > 0 ? '+' : ''}${gain.toInt()}dB',
          style: GoogleFonts.outfit(
            color: isEnabled ? Colors.white70 : Colors.white24,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        
        // Slider Track
        Expanded(
          child: GestureDetector(
            onVerticalDragUpdate: isEnabled ? (details) {
              final box = context.findRenderObject() as RenderBox;
              final height = 300.0; // Approximate
              final sensitivity = 1.0; 
              final delta = -details.delta.dy / height * 24 * sensitivity;
              _eqService.setBandGain(index, (gain + delta).clamp(-12.0, 12.0));
            } : null,
            child: Container(
              width: 40, // Touch target
              color: Colors.transparent,
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // Track Line
                  Container(
                    width: 2,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  
                  // Active Line
                  FractionallySizedBox(
                    heightFactor: normalized,
                    child: Container(
                      width: 2,
                      color: isEnabled ? const Color(0xFF00B4D8) : Colors.white12, // Light blue
                    ),
                  ),
                  
                  // Thumb
                  Align(
                    alignment: Alignment(0, 1.0 - (normalized * 2.0)), 
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isEnabled ? Colors.white : const Color(0xFF2A2A2A),
                        border: Border.all(
                          color: isEnabled ? const Color(0xFF00B4D8) : Colors.transparent, // Light blue
                          width: 2,
                        ),
                        boxShadow: isEnabled ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ] : [],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Frequency Label
        Text(
          label,
          style: GoogleFonts.outfit(
            color: isEnabled ? Colors.white : Colors.white38,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ).animate().fadeIn(delay: (100 * index).ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildPresetsList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      scrollDirection: Axis.horizontal,
      itemCount: EqualizerService.presets.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final preset = EqualizerService.presets[index];
        final isSelected = _eqService.currentPresetId == preset.id;
        
        return Center(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _eqService.selectPreset(preset.id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 100, // Fixed width for cleaner look
              height: 140,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF00B4D8) : const Color(0xFF141414), // Light blue
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.05),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getPresetIcon(preset.id),
                    color: isSelected ? Colors.white : Colors.white54,
                    size: 28,
                  ),
                  const Spacer(),
                  Text(
                    preset.name,
                    style: GoogleFonts.outfit(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getPresetIcon(String presetId) {
    switch (presetId) {
      case 'flat': return Icons.horizontal_rule_rounded;
      case 'bass_boost': return Icons.speaker_rounded;
      case 'treble_boost': return Icons.music_note_rounded;
      case 'vocal': return Icons.mic_rounded;
      case 'rock': return Icons.electric_bolt_rounded;
      case 'electronic': return Icons.waves_rounded;
      case 'hiphop': return Icons.headphones_rounded;
      case 'podcast': return Icons.podcasts_rounded;
      case 'custom': return Icons.tune_rounded;
      default: return Icons.equalizer_rounded;
    }
  }
}
