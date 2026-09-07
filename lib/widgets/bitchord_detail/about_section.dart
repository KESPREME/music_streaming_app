import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: GoogleFonts.plusJakartaSans(
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
              widget.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 14.5,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
            secondChild: Text(
              widget.text,
              style: GoogleFonts.plusJakartaSans(
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
                style: GoogleFonts.plusJakartaSans(
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
