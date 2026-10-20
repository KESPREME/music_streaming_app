import 'package:flutter/material.dart';
import '../../theme/app_font.dart';
import '../jelly_press.dart';

/// In-page search input pill matching BitChord DetailSearchField
class DetailSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final String hintText;
  final Color accentColor;

  const DetailSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClose,
    this.hintText = 'Search this list',
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: Colors.white.withValues(alpha: 0.6),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                onChanged: onChanged,
                style: AppFont.style(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: accentColor,
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: AppFont.style(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            JellyPress(
              profile: JellyProfile.circle,
              haptic: JellyHaptic.none,
              onTap: () {
                if (controller.text.isNotEmpty) {
                  controller.clear();
                  onChanged('');
                } else {
                  onClose();
                }
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
