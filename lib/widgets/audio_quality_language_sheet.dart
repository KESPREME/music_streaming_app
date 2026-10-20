// lib/widgets/audio_quality_language_sheet.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_font.dart';
import 'glass_snackbar.dart';
import 'home_sections.dart' show PressableScale;

/// Modal sheet for Multi-Language Audio & Quality Control.
class AudioQualityLanguageSheet extends StatefulWidget {
  const AudioQualityLanguageSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      isScrollControlled: true,
      builder: (context) => const AudioQualityLanguageSheet(),
    );
  }

  @override
  State<AudioQualityLanguageSheet> createState() =>
      _AudioQualityLanguageSheetState();
}

class _AudioQualityLanguageSheetState extends State<AudioQualityLanguageSheet> {
  String _currentQuality = 'High Definition (320 kbps)';
  String _currentLanguage = 'Original Audio (Detected)';

  final List<Map<String, String>> _qualities = [
    {
      'title': 'High Definition',
      'bitrate': '320 kbps',
      'desc': 'Maximum fidelity & wide dynamic range',
      'badge': 'FHD+',
    },
    {
      'title': 'Balanced',
      'bitrate': '160 kbps',
      'desc': 'Optimized for smooth streaming & clarity',
      'badge': 'HQ',
    },
    {
      'title': 'Data Saver',
      'bitrate': '64 kbps',
      'desc': 'Ultra-efficient for cellular networks',
      'badge': 'ECO',
    },
  ];

  final List<Map<String, String>> _languages = [
    {
      'title': 'Original Audio',
      'tag': 'Detected',
      'desc': 'Default primary artist master recording',
    },
    {
      'title': 'English',
      'tag': 'EN',
      'desc': 'Localized English audio track if available',
    },
    {
      'title': 'Romaji & Phonetics',
      'tag': 'aあ',
      'desc': 'Synchronized pronunciation assist',
    },
    {
      'title': 'Instrumental',
      'tag': 'Karaoke',
      'desc': 'Backing tracks & karaoke mix',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _currentQuality = prefs.getString('audio_quality_preset') ??
            'High Definition';
        _currentLanguage = prefs.getString('audio_language_preset') ??
            'Original Audio';
      });
    }
  }

  Future<void> _setQuality(String title) async {
    HapticFeedback.selectionClick();
    setState(() => _currentQuality = title);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('audio_quality_preset', title);
    if (mounted) {
      GlassSnackBar.show(
        context,
        message: 'Audio Quality set to $title',
      );
    }
  }

  Future<void> _setLanguage(String title) async {
    HapticFeedback.selectionClick();
    setState(() => _currentLanguage = title);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('audio_language_preset', title);
    if (mounted) {
      GlassSnackBar.show(
        context,
        message: 'Audio Language set to $title',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xD916161A),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.16),
                width: 0.8,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pull Handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.translate_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Audio & Quality Control',
                              style: AppFont.style(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Multi-language audio stream & bitrate resolution',
                              style: AppFont.style(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Section 1: Quality Control
                  _buildSectionHeader('STREAMING QUALITY', Icons.speed_rounded),
                  const SizedBox(height: 10),
                  ..._qualities.map((q) => _buildQualityOption(q)),

                  const SizedBox(height: 24),

                  // Section 2: Multi-Language Audio
                  _buildSectionHeader('AUDIO STREAM LANGUAGE', Icons.language_rounded),
                  const SizedBox(height: 10),
                  ..._languages.map((l) => _buildLanguageOption(l)),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 15),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppFont.style(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildQualityOption(Map<String, String> item) {
    final title = item['title']!;
    final isSelected = _currentQuality == title;

    return PressableScale(
      onTap: () => _setQuality(title),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: AppFont.style(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item['badge']!,
                          style: AppFont.style(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item['bitrate']!} • ${item['desc']!}',
                    style: AppFont.style(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              )
            else
              Icon(
                Icons.radio_button_unchecked_rounded,
                color: Colors.white.withValues(alpha: 0.25),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageOption(Map<String, String> item) {
    final title = item['title']!;
    final isSelected = _currentLanguage == title;

    return PressableScale(
      onTap: () => _setLanguage(title),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: AppFont.style(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item['tag']!,
                          style: AppFont.style(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item['desc']!,
                    style: AppFont.style(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              )
            else
              Icon(
                Icons.radio_button_unchecked_rounded,
                color: Colors.white.withValues(alpha: 0.25),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
