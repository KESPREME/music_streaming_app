import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/equalizer_service.dart';
import '../providers/music_provider.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';

class MaterialYouEqualizerScreen extends StatefulWidget {
  const MaterialYouEqualizerScreen({super.key});

  @override
  State<MaterialYouEqualizerScreen> createState() => _MaterialYouEqualizerScreenState();
}

class _MaterialYouEqualizerScreenState extends State<MaterialYouEqualizerScreen> {
  final EqualizerService _eqService = EqualizerService();
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _eqService.addListener(_onEQChanged);
    
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
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: MaterialYouTokens.surfaceDark,
      appBar: AppBar(
        backgroundColor: MaterialYouTokens.surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Equalizer',
          style: MaterialYouTypography.headlineSmall(colorScheme.onSurface),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: colorScheme.onSurfaceVariant),
            onPressed: () {
              HapticFeedback.mediumImpact();
              _eqService.reset();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: _buildEnableSwitch(colorScheme),
          ),
          
          const Spacer(),

          Expanded(
            flex: 4,
            child: _buildEQSliders(colorScheme),
          ),
          
          const Spacer(),

          SizedBox(
            height: 180,
            child: _buildPresetsList(colorScheme),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildEnableSwitch(ColorScheme colorScheme) {
    bool isEnabled = _eqService.isEnabled;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _eqService.setEnabled(!isEnabled);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: MaterialYouTokens.surfaceContainerDark,
          borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
          border: Border.all(
            color: isEnabled 
                ? MaterialYouTokens.primaryVibrant.withOpacity(0.3) 
                : colorScheme.surfaceVariant,
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
                  style: MaterialYouTypography.titleMedium(colorScheme.onSurface),
                ),
                Text(
                  isEnabled ? 'Active' : 'Disabled',
                  style: MaterialYouTypography.bodySmall(
                    isEnabled ? MaterialYouTokens.primaryVibrant : colorScheme.onSurfaceVariant
                  ),
                ),
              ],
            ),
            Switch.adaptive(
              value: isEnabled,
              activeColor: MaterialYouTokens.primaryVibrant,
              activeTrackColor: MaterialYouTokens.primaryVibrant.withOpacity(0.3),
              inactiveTrackColor: colorScheme.surfaceVariant,
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

  Widget _buildEQSliders(ColorScheme colorScheme) {
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
              colorScheme,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSlider(int index, double gain, String label, bool isEnabled, ColorScheme colorScheme) {
    double normalized = (gain + 12) / 24;
    
    return Column(
      children: [
        Text(
          '${gain > 0 ? '+' : ''}${gain.toInt()}dB',
          style: MaterialYouTypography.bodySmall(
            isEnabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant
          ),
        ),
        const SizedBox(height: 12),
        
        Expanded(
          child: GestureDetector(
            onVerticalDragUpdate: isEnabled ? (details) {
              final height = 300.0;
              final sensitivity = 1.0;
              final delta = -details.delta.dy / height * 24 * sensitivity;
              _eqService.setBandGain(index, (gain + delta).clamp(-12.0, 12.0));
            } : null,
            child: Container(
              width: 40,
              color: Colors.transparent,
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    width: 2,
                    color: colorScheme.surfaceVariant,
                  ),
                  
                  FractionallySizedBox(
                    heightFactor: normalized,
                    child: Container(
                      width: 2,
                      color: isEnabled ? MaterialYouTokens.primaryVibrant : colorScheme.surfaceVariant,
                    ),
                  ),
                  
                  Align(
                    alignment: Alignment(0, 1.0 - (normalized * 2.0)),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isEnabled ? colorScheme.onSurface : MaterialYouTokens.surfaceContainerDark,
                        border: Border.all(
                          color: isEnabled ? MaterialYouTokens.primaryVibrant : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        Text(
          label,
          style: MaterialYouTypography.bodySmall(
            isEnabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant
          ),
        ),
      ],
    );
  }

  Widget _buildPresetsList(ColorScheme colorScheme) {
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
              width: 100,
              height: 140,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected 
                    ? MaterialYouTokens.primaryVibrant 
                    : MaterialYouTokens.surfaceContainerDark,
                borderRadius: BorderRadius.circular(MaterialYouTokens.shapeMedium),
                border: Border.all(
                  color: isSelected ? Colors.transparent : colorScheme.surfaceVariant,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getPresetIcon(preset.id),
                    color: isSelected ? Colors.black : colorScheme.onSurface,
                    size: 28,
                  ),
                  const Spacer(),
                  Text(
                    preset.name,
                    style: MaterialYouTypography.bodyMedium(
                      isSelected ? Colors.black : colorScheme.onSurface
                    ).copyWith(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500),
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
