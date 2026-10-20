// lib/widgets/update/release_notes_view.dart
//
// A release's notes, laid out for a phone: the banner, a headline and a line of
// summary, grouped change lists with a coloured chip per group, and a gallery of
// screenshots you can swipe and tap to enlarge.
//
// It draws from the STRUCTURED notes (sections, gallery) the updater already
// parsed; only when a release has no sections does it fall back to the markdown
// text, rendered with a small inline renderer (**bold**, `code`, [links]) - not a
// markdown package, because release notes need nothing else.
//
// Images fail soft: a banner or screenshot that does not load simply is not
// there. Nothing on this screen may wait on, or break because of, a picture.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/update/update_models.dart';
import '../../theme/app_font.dart';
import '../jelly_press.dart';

/// Chip colour and icon for a section's icon key.
({IconData icon, Color color}) releaseSectionStyle(String? key, Color accent) {
  return switch (key) {
    'sparkle' => (icon: Icons.auto_awesome_rounded, color: const Color(0xFFFFD166)),
    'improved' => (icon: Icons.tune_rounded, color: const Color(0xFF7AD7F0)),
    'fix' => (icon: Icons.build_circle_rounded, color: const Color(0xFF7BE0A6)),
    'perf' => (icon: Icons.bolt_rounded, color: const Color(0xFFFFA45B)),
    'design' => (icon: Icons.palette_rounded, color: const Color(0xFFD59BFF)),
    _ => (icon: Icons.circle_notifications_rounded, color: accent),
  };
}

class ReleaseNotesView extends StatelessWidget {
  const ReleaseNotesView({
    super.key,
    required this.notes,
    this.showBanner = true,
    this.accent,
    this.maxSections,
  });

  final ReleaseNotes notes;
  final bool showBanner;
  final Color? accent;

  /// Cut the list for a compact sheet; null shows everything.
  final int? maxSections;

  @override
  Widget build(BuildContext context) {
    final tone = accent ?? Theme.of(context).colorScheme.primary;
    final sections = maxSections == null
        ? notes.sections
        : notes.sections.take(maxSections!).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBanner && notes.bannerUrl != null) ...[
          _NetworkPicture(
            url: notes.bannerUrl!,
            aspect: 2,
            radius: 24,
            semanticLabel: 'Release banner',
          ),
          const SizedBox(height: 18),
        ],
        if (notes.title != null && notes.title!.isNotEmpty)
          Text(
            notes.title!,
            style: AppFont.style(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.2,
            ),
          ),
        if (notes.summary != null && notes.summary!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            notes.summary!,
            style: AppFont.style(
                color: Colors.white.withValues(alpha: 0.65), fontSize: 14.5, height: 1.4),
          ),
        ],
        if (sections.isNotEmpty) const SizedBox(height: 18),
        for (final s in sections) ...[
          _SectionBlock(section: s, accent: tone),
          const SizedBox(height: 14),
        ],
        if (sections.isEmpty && notes.notesMarkdown.trim().isNotEmpty)
          _InlineMarkdown(text: notes.notesMarkdown, accent: tone),
        if (notes.gallery.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('SCREENSHOTS',
              style: AppFont.style(
                  color: tone.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6)),
          const SizedBox(height: 12),
          _Gallery(images: notes.gallery),
        ],
      ],
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section, required this.accent});

  final ReleaseSection section;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final style = releaseSectionStyle(section.icon, accent);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.icon, size: 16, color: style.color),
              ),
              const SizedBox(width: 10),
              Text(section.title,
                  style: AppFont.style(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in section.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 10),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(color: style.color, shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(child: _InlineText(text: item, accent: style.color)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// **bold**, `code` and [label](url), nothing more.
class _InlineText extends StatefulWidget {
  const _InlineText({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  State<_InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<_InlineText> {
  final List<TapGestureRecognizer> _taps = [];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final base = AppFont.style(
        color: Colors.white.withValues(alpha: 0.86), fontSize: 14.5, height: 1.42);
    return Text.rich(TextSpan(style: base, children: inlineSpans(widget.text, base, widget.accent, _taps)));
  }
}

final RegExp _inline = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\((https?://[^)\s]+)\)');

/// Spans for the inline markdown in [text]. Link taps are registered in [taps]
/// so the caller can dispose them.
List<InlineSpan> inlineSpans(
  String text,
  TextStyle base,
  Color accent,
  List<TapGestureRecognizer> taps,
) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w800)));
    } else if (m.group(2) != null) {
      spans.add(TextSpan(
        text: m.group(2),
        style: TextStyle(
          fontFamily: 'monospace',
          backgroundColor: Colors.white.withValues(alpha: 0.1),
        ),
      ));
    } else {
      final url = Uri.tryParse(m.group(4)!);
      final tap = TapGestureRecognizer()
        ..onTap = () {
          if (url != null) launchUrl(url, mode: LaunchMode.externalApplication);
        };
      taps.add(tap);
      spans.add(TextSpan(
        text: m.group(3),
        style: TextStyle(color: accent, decoration: TextDecoration.underline),
        recognizer: tap,
      ));
    }
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

/// The markdown body when a release has no structured sections: paragraphs,
/// `#` headings and bullets, with inline formatting.
class _InlineMarkdown extends StatelessWidget {
  const _InlineMarkdown({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final h = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(line);
      if (h != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(h.group(1)!,
              style: AppFont.style(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        ));
        continue;
      }
      final b = RegExp(r'^(?:[-*+]|\d+[.)])\s+(.+)$').firstMatch(line);
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: b == null
            ? _InlineText(text: line, accent: accent)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 10),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(child: _InlineText(text: b.group(1)!, accent: accent)),
                ],
              ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.images});

  final List<ReleaseGalleryImage> images;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 330,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final g = images[i];
          return JellyPress(
            borderRadius: 22,
            haptic: JellyHaptic.selection,
            onTap: () => _enlarge(context, g),
            child: SizedBox(
              width: 158,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _NetworkPicture(
                      url: g.url,
                      aspect: null,
                      radius: 22,
                      semanticLabel: g.caption ?? 'Screenshot ${i + 1}',
                    ),
                  ),
                  if (g.caption != null && g.caption!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(g.caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.style(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _enlarge(BuildContext context, ReleaseGalleryImage g) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _NetworkPicture(
                url: g.url,
                aspect: null,
                radius: 18,
                fit: BoxFit.contain,
                semanticLabel: g.caption ?? 'Screenshot',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An image that fades in, shows a quiet placeholder, and disappears if it fails.
class _NetworkPicture extends StatelessWidget {
  const _NetworkPicture({
    required this.url,
    required this.radius,
    this.aspect,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });

  final String url;
  final double radius;
  final double? aspect;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget img = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        fadeInDuration: const Duration(milliseconds: 320),
        placeholder: (_, __) => Container(color: Colors.white.withValues(alpha: 0.05)),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
    if (aspect != null) img = AspectRatio(aspectRatio: aspect!, child: img);
    return Semantics(image: true, label: semanticLabel, child: img);
  }
}
