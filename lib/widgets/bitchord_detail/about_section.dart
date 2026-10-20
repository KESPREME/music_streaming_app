import 'package:flutter/material.dart';
import '../../theme/app_font.dart';

/// Collapsible editorial blurb matching BitChord's AboutSection
class AboutSection extends StatefulWidget {
  final String title;
  final String text;
  final Color accentColor;

  const AboutSection({
    super.key,
    required this.title,
    required this.text,
    required this.accentColor,
  });

  static String cleanText(String raw) {
    return raw
        .replaceAll(RegExp(r'https?://[^\s)]+'), '')
        .replaceAll(RegExp(r'\s*\(from Wikipedia.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*From Wikipedia.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cleaned = AboutSection.cleanText(widget.text);
    if (cleaned.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: AppFont.style(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: Text(
              cleaned,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppFont.style(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
            secondChild: Text(
              cleaned,
              style: AppFont.style(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Text(
                _expanded ? 'Less' : 'More',
                style: AppFont.style(
                  color: widget.accentColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
