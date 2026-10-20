// lib/services/update/release_notes.dart
//
// Turns a release into something a sheet can lay out: a title, one summary
// line, three highlight bullets, sections with icons, a banner and a gallery.
//
// Two sources feed it. `update.json` (CI) hands the pieces over already split;
// a plain GitHub release only has a markdown `body`, so [parseReleaseBody]
// recovers the same pieces from conventions people actually write:
//
//     ![banner](https://…)            <- first image before any heading: banner
//     # Glass that behaves            <- leading H1: title
//     A calmer player and an EQ.      <- first paragraph: summary
//     ## ✨ New                       <- headings: sections (emoji stripped)
//     - Ten-band equalizer            <- bullets: items
//     ### 🐛 Fixed
//     1. Seek bar jumping
//     ![eq](https://…)                <- any later image: gallery
//
// Everything here is a pure function of its input and TOTAL: any string -
// empty, CRLF, binary-looking, 100 KB on one line - returns a [ReleaseNotes]
// and never throws. Work is bounded (input is capped, overlong lines skip the
// regex-heavy steps) so a hostile release body cannot hang the app.

import 'update_json.dart';
import 'update_models.dart';

/// Bodies longer than this are cut (GitHub's own limit is 125,000).
const int _maxBodyChars = 120000;

/// Lines longer than this skip inline parsing (images, HTML, emphasis), which
/// keeps every regex pass linear in practice.
const int _maxInlineLine = 2000;

const int _summaryMax = 160;
const int _highlightCount = 3;
const int _maxSections = 40;
const int _maxItemsPerSection = 200;

/// Parses a GitHub-style markdown release body. Total; never throws.
ReleaseNotes parseReleaseBody(String markdown) => _parseTotal(markdown, takeTitle: true);

ReleaseNotes _parseTotal(String markdown, {required bool takeTitle}) {
  try {
    return _parseBody(markdown, takeTitle: takeTitle);
  } catch (_) {
    return ReleaseNotes(notesMarkdown: _safeTail(markdown));
  }
}

/// Builds notes from the `update.json` shape. A key that is *present* (even
/// empty/null) is authoritative; a key that is absent is derived from the
/// markdown in `notes`. Total; never throws.
ReleaseNotes releaseNotesFromManifest(Map<String, dynamic> m) {
  try {
    return _fromManifest(m);
  } catch (_) {
    return ReleaseNotes.empty;
  }
}

// ---------------------------------------------------------------------------
// Icons and titles
// ---------------------------------------------------------------------------

/// The icon keys the UI knows. Anything else is `other`.
const Set<String> kNoteIconKeys = {
  'sparkle',
  'improved',
  'fix',
  'perf',
  'design',
  'other',
};

const Map<String, String> _iconSynonyms = {
  'sparkle': 'sparkle',
  'sparkles': 'sparkle',
  'new': 'sparkle',
  'star': 'sparkle',
  'feature': 'sparkle',
  'added': 'sparkle',
  'improved': 'improved',
  'improvement': 'improved',
  'improve': 'improved',
  'update': 'improved',
  'changed': 'improved',
  'wrench': 'improved',
  'fix': 'fix',
  'fixed': 'fix',
  'bug': 'fix',
  'bugfix': 'fix',
  'perf': 'perf',
  'performance': 'perf',
  'speed': 'perf',
  'bolt': 'perf',
  'design': 'design',
  'ui': 'design',
  'palette': 'design',
  'other': 'other',
};

/// A published icon name mapped onto a key the UI knows; null if unrecognised.
String? normalizeIconKey(String? raw) {
  if (raw == null) return null;
  return _iconSynonyms[raw.trim().toLowerCase()];
}

const Map<String, String> _wordIcons = {
  // new
  'new': 'sparkle', 'added': 'sparkle', 'add': 'sparkle', 'feature': 'sparkle',
  'features': 'sparkle', 'introducing': 'sparkle', 'introduced': 'sparkle',
  'highlights': 'sparkle',
  // improved
  'improved': 'improved', 'improvements': 'improved', 'improvement': 'improved',
  'improve': 'improved', 'changed': 'improved', 'changes': 'improved',
  'change': 'improved', 'updated': 'improved', 'updates': 'improved',
  'enhanced': 'improved', 'enhancements': 'improved', 'polish': 'improved',
  'refined': 'improved', 'tweaks': 'improved', 'better': 'improved',
  // fix
  'fix': 'fix', 'fixed': 'fix', 'fixes': 'fix', 'bug': 'fix', 'bugs': 'fix',
  'bugfix': 'fix', 'bugfixes': 'fix', 'hotfix': 'fix', 'resolved': 'fix',
  // perf
  'performance': 'perf', 'perf': 'perf', 'faster': 'perf', 'speed': 'perf',
  'optimized': 'perf', 'optimised': 'perf', 'optimizations': 'perf',
  'optimisations': 'perf', 'optimization': 'perf', 'battery': 'perf',
  'memory': 'perf',
  // design
  'design': 'design', 'ui': 'design', 'ux': 'design', 'visual': 'design',
  'visuals': 'design', 'look': 'design', 'theme': 'design', 'themes': 'design',
  'style': 'design', 'styling': 'design', 'animation': 'design',
  'animations': 'design', 'interface': 'design',
};

/// Emoji that decide an icon when the title words do not. Written as escapes
/// so the file's encoding can never matter.
const Map<String, String> _emojiIcons = {
  '\u2728': 'sparkle', // sparkles
  '\u{1F31F}': 'sparkle', // glowing star
  '\u2B50': 'sparkle', // star
  '\u{1F195}': 'sparkle', // NEW
  '\u{1F389}': 'sparkle', // party popper
  '\u{1F680}': 'sparkle', // rocket
  '\u{1F527}': 'improved', // wrench
  '\u{1F6E0}': 'improved', // hammer and wrench
  '\u{1F4AA}': 'improved', // flexed biceps
  '\u{1F4C8}': 'improved', // chart increasing
  '\u2B06': 'improved', // up arrow
  '\u{1F504}': 'improved', // counterclockwise arrows
  '\u267B': 'improved', // recycling
  '\u{1F41B}': 'fix', // bug
  '\u{1F41E}': 'fix', // lady beetle
  '\u{1FA79}': 'fix', // adhesive bandage
  '\u{1F528}': 'fix', // hammer
  '\u{1F691}': 'fix', // ambulance
  '\u26A1': 'perf', // high voltage
  '\u{1F3CE}': 'perf', // racing car
  '\u23F1': 'perf', // stopwatch
  '\u{1F50B}': 'perf', // battery
  '\u{1F3A8}': 'design', // artist palette
  '\u{1F484}': 'design', // lipstick
  '\u{1F48E}': 'design', // gem
  '\u{1F5BC}': 'design', // framed picture
  '\u{1F308}': 'design', // rainbow
};

final RegExp _wordToken = RegExp(r"[a-z']+");

/// The icon key for a section heading: its words first ("Bug fixes" -> `fix`),
/// then any emoji in it, else `other`.
String iconForHeading(String heading) {
  final lower = heading.toLowerCase();
  for (final m in _wordToken.allMatches(lower)) {
    final hit = _wordIcons[m.group(0)!.replaceAll("'", '')] ?? _wordIcons[m.group(0)!];
    if (hit != null) return hit;
  }
  for (final e in _emojiIcons.entries) {
    if (heading.contains(e.key)) return e.value;
  }
  return 'other';
}

final RegExp _leadingSymbols = RegExp(r'^[^\p{L}\p{N}]+', unicode: true);
// \uFE0E/\uFE0F are the emoji variation selectors that trail a pictograph.
final RegExp _trailingSymbols =
    RegExp(r'[\s:\p{S}\p{Cf}\uFE0E\uFE0F]+$', unicode: true);

/// A heading as display text: emphasis markers, leading emoji/symbols and
/// trailing colons removed. Empty becomes `Other`.
String cleanSectionTitle(String heading) {
  var t = heading.replaceAll(RegExp(r'[*_`~]'), '');
  t = t.replaceFirst(_leadingSymbols, '');
  t = t.replaceFirst(_trailingSymbols, '');
  t = t.trim();
  return t.isEmpty ? 'Other' : t;
}

// ---------------------------------------------------------------------------
// Plain text
// ---------------------------------------------------------------------------

final RegExp _mdLink = RegExp(r'\[([^\]\n]*)\]\([^)\n]*\)');
final RegExp _autoLink = RegExp(r'<(https?://[^>\s]+)>');
final RegExp _htmlTag = RegExp(r'</?[a-zA-Z][^>\n]*>');
final RegExp _inlineCode = RegExp(r'`([^`\n]+)`');
final RegExp _bold = RegExp(r'\*\*(.+?)\*\*|__(.+?)__');
final RegExp _strike = RegExp(r'~~(.+?)~~');
final RegExp _italicStar = RegExp(r'\*([^*\n]+?)\*');
final RegExp _italicUnder = RegExp(r'(?<![A-Za-z0-9_])_([^_\n]+?)_(?![A-Za-z0-9_])');
final RegExp _spaces = RegExp(r'\s+');

/// [md] with inline markdown reduced to its words (links keep their text,
/// emphasis and code lose their markers, images and tags vanish). Only the
/// first ~600 characters are looked at - this is for one-line previews.
String plainFromMarkdown(String md) {
  var s = md.length > 600 ? md.substring(0, 600) : md;
  s = s.replaceAll(_mdImage, '');
  s = s.replaceAllMapped(_mdLink, (m) => m[1] ?? '');
  s = s.replaceAllMapped(_autoLink, (m) => m[1] ?? '');
  s = s.replaceAll(_htmlTag, '');
  s = s.replaceAllMapped(_inlineCode, (m) => m[1] ?? '');
  s = s.replaceAllMapped(_bold, (m) => m[1] ?? m[2] ?? '');
  s = s.replaceAllMapped(_strike, (m) => m[1] ?? '');
  s = s.replaceAllMapped(_italicStar, (m) => m[1] ?? '');
  s = s.replaceAllMapped(_italicUnder, (m) => m[1] ?? '');
  return sanitizeText(s.replaceAll(_spaces, ' ').trim());
}

String _truncate(String s, int max) {
  if (s.length <= max) return s;
  var end = max - 1;
  // Never split a surrogate pair.
  if (end > 0 && s.codeUnitAt(end - 1) >= 0xD800 && s.codeUnitAt(end - 1) <= 0xDBFF) {
    end--;
  }
  return '${s.substring(0, end).trimRight()}\u2026';
}

String _safeTail(String s) {
  final cut = s.length > _maxBodyChars ? s.substring(0, _maxBodyChars) : s;
  return sanitizeText(cut).trim();
}

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

/// `[![alt](img)](link)` - an image wrapped in a link; the link is dropped.
final RegExp _linkedImage =
    RegExp(r'\[\s*(!\[[^\]\n]*\]\([^)\n]*\))\s*\]\([^)\n]*\)');

/// `![alt](url "title")`, with the url optionally in angle brackets.
final RegExp _mdImage =
    RegExp(r'!\[([^\]\n]*)\]\(\s*<?([^)\s>]*)>?(?:\s+"[^"\n]*")?\s*\)');
final RegExp _htmlImg = RegExp(r'<img\b[^>\n]*>', caseSensitive: false);
final RegExp _attrSrc =
    RegExp(r'''\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)')''', caseSensitive: false);
final RegExp _attrAlt =
    RegExp(r'''\balt\s*=\s*(?:"([^"]*)"|'([^']*)')''', caseSensitive: false);
final RegExp _onlyTags = RegExp(r'^(?:</?[a-zA-Z][^>\n]*>\s*)+$');

class _Img {
  const _Img(this.start, this.end, this.url, this.alt);
  final int start;
  final int end;
  final String url;
  final String alt;
}

/// More images than this on one line means it is not a line of prose.
const int _maxImagesPerLine = 20;

/// Occurrences of [needle] in [s], counting stops one past [limit].
int _countAtMost(String s, String needle, int limit) {
  var count = 0;
  var from = 0;
  while (count <= limit) {
    final i = s.indexOf(needle, from);
    if (i < 0) break;
    count++;
    from = i + needle.length;
  }
  return count;
}

/// Splits a line into its remaining text and the images it contained, in
/// reading order. Markdown and HTML images are both recognised.
({String line, List<_Img> images}) _pullImages(String line) {
  // A real line carries a handful of images. Thousands of unclosed `![` make
  // each regex start rescan the whole line (quadratic), so such a line is
  // treated as plain text instead.
  final hasMd = line.contains('![') && _countAtMost(line, '![', _maxImagesPerLine) <= _maxImagesPerLine;
  final lower = line.length >= 4 ? line.toLowerCase() : '';
  final hasHtml = lower.contains('<img') && _countAtMost(lower, '<img', _maxImagesPerLine) <= _maxImagesPerLine;
  if (!hasMd && !hasHtml) return (line: line, images: const <_Img>[]);

  final work = hasMd ? line.replaceAllMapped(_linkedImage, (m) => m[1]!) : line;
  final found = <_Img>[];
  if (hasMd) {
    for (final m in _mdImage.allMatches(work)) {
      found.add(_Img(m.start, m.end, (m[2] ?? '').trim(), (m[1] ?? '').trim()));
    }
  }
  if (hasHtml) {
    for (final m in _htmlImg.allMatches(work)) {
      final tag = m[0]!;
      final src = _attrSrc.firstMatch(tag);
      final alt = _attrAlt.firstMatch(tag);
      found.add(_Img(
        m.start,
        m.end,
        (src?.group(1) ?? src?.group(2) ?? '').trim(),
        (alt?.group(1) ?? alt?.group(2) ?? '').trim(),
      ));
    }
  }
  found.sort((a, b) => a.start.compareTo(b.start));

  final out = StringBuffer();
  var pos = 0;
  for (final img in found) {
    if (img.start < pos) continue; // overlapping match; already consumed
    out.write(work.substring(pos, img.start));
    pos = img.end;
  }
  out.write(work.substring(pos));
  return (line: out.toString(), images: found);
}

// ---------------------------------------------------------------------------
// The body parser
// ---------------------------------------------------------------------------

final RegExp _bullet = RegExp(r'^(\s*)(?:[-*+]|\d{1,3}[.)])[ \t]+(\S.*)$');
final RegExp _checkbox = RegExp(r'^\[[ xX]\][ \t]+');
final RegExp _hr = RegExp(r'^\s*([-*_])(?:\s*\1){2,}\s*$');
final RegExp _fullChangelog = RegExp(r'^\W*full changelog', caseSensitive: false);
final RegExp _bareUrl = RegExp(r'^<?https?://\S+>?$');
final RegExp _controlChars = RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]');
final RegExp _blankRun = RegExp(r'\n{3,}');

class _Section {
  _Section(this.heading);
  final String heading;
  final List<String> items = [];
}

ReleaseNotes _parseBody(String input, {required bool takeTitle}) {
  var text = input.length > _maxBodyChars ? input.substring(0, _maxBodyChars) : input;
  text = sanitizeText(text)
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(_controlChars, '');
  final lines = text.split('\n');

  final kept = <String>[];
  final sections = <_Section>[];
  _Section? current;
  String? title;
  String? summary;
  String? banner;
  final gallery = <ReleaseGalleryImage>[];
  final seenUrls = <String>{};
  // Banner rule: the first image seen before any section heading. A leading
  // `# Title` is the document's name, not a section, so it does not end that
  // window.
  var inLead = true;
  var inFence = false;
  String fenceMark = '';
  final para = <String>[];
  var paraOk = true;
  var lastItemSection = -1;
  var lastItemIndex = -1;

  void endParagraph() {
    if (summary == null && para.isNotEmpty && paraOk) {
      final s = plainFromMarkdown(para.join(' '));
      if (s.isNotEmpty) summary = _truncate(s, _summaryMax);
    }
    para.clear();
    paraOk = true;
  }

  void endItem() {
    lastItemSection = -1;
    lastItemIndex = -1;
  }

  for (final rawLine in lines) {
    var line = rawLine;
    final trimmed = line.trimLeft();

    // Code fences are opaque: kept verbatim, never parsed.
    if (inFence) {
      kept.add(line);
      if (trimmed.startsWith(fenceMark)) inFence = false;
      continue;
    }
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      endParagraph();
      endItem();
      inFence = true;
      fenceMark = trimmed.substring(0, 3);
      kept.add(line);
      continue;
    }

    final long = line.length > _maxInlineLine;

    // Images come out of the line first, wherever they sit.
    if (!long) {
      final pulled = _pullImages(line);
      if (pulled.images.isNotEmpty) {
        for (final img in pulled.images) {
          final url = asHttpsUrl(img.url);
          if (url == null || !seenUrls.add(url)) continue;
          final caption = img.alt.isEmpty ? null : sanitizeText(img.alt);
          if (banner == null && inLead && gallery.isEmpty) {
            banner = url;
          } else {
            gallery.add(ReleaseGalleryImage(url: url, caption: caption));
          }
        }
        line = pulled.line.trimRight();
        if (line.trim().isEmpty) continue; // the line was only images
      }
      // Layout-only HTML (`<p align="center">`, `</div>`) means nothing to a
      // markdown view.
      if (_onlyTags.hasMatch(line.trim())) continue;
    }

    final stripped = line.trim();

    // Blank line: ends a paragraph and any wrapped bullet.
    if (stripped.isEmpty) {
      endParagraph();
      endItem();
      kept.add('');
      continue;
    }

    // Headings.
    final heading = long ? null : _heading(line);
    if (heading != null) {
      endParagraph();
      endItem();
      if (takeTitle && heading.level == 1 && title == null && current == null) {
        title = _truncate(plainFromMarkdown(heading.text), 120);
        if (title.isEmpty) title = null;
        continue; // surfaced as `title`; not repeated in the body
      }
      inLead = false;
      current = _Section(heading.text);
      if (sections.length < _maxSections) sections.add(current);
      kept.add(line);
      continue;
    }

    // Horizontal rules just separate.
    if (stripped.length <= 100 && _hr.hasMatch(stripped)) {
      endParagraph();
      endItem();
      kept.add(line);
      continue;
    }

    // Bullets.
    final b = _bullet.firstMatch(line);
    if (b != null) {
      endParagraph();
      final itemText = b.group(2)!.trim().replaceFirst(_checkbox, '');
      if (itemText.isNotEmpty) {
        final owner = current ??= _newImplicit(sections);
        if (owner.items.length < _maxItemsPerSection) {
          owner.items.add(itemText);
          lastItemSection = sections.indexOf(owner);
          lastItemIndex = owner.items.length - 1;
        } else {
          endItem();
        }
      }
      kept.add(line);
      continue;
    }

    // An indented line right under a bullet continues it.
    final indented = line.startsWith('  ') || line.startsWith('\t');
    if (indented && lastItemIndex >= 0 && lastItemSection >= 0 && lastItemSection < sections.length) {
      final items = sections[lastItemSection].items;
      if (lastItemIndex < items.length) {
        items[lastItemIndex] = '${items[lastItemIndex]} $stripped';
      }
      kept.add(line);
      continue;
    }

    // Plain text: a candidate for the summary paragraph.
    endItem();
    kept.add(line);
    if (summary == null) {
      if (stripped.startsWith('>') ||
          stripped.startsWith('|') ||
          stripped.startsWith('<') ||
          _fullChangelog.hasMatch(stripped) ||
          _bareUrl.hasMatch(stripped)) {
        paraOk = false;
      }
      para.add(stripped);
    }
  }
  endParagraph();

  final built = <ReleaseSection>[
    for (final s in sections)
      if (s.items.isNotEmpty)
        ReleaseSection(
          title: cleanSectionTitle(s.heading),
          icon: iconForHeading(s.heading),
          items: List.unmodifiable(s.items),
        ),
  ];

  return ReleaseNotes(
    title: title,
    summary: summary,
    highlights: _highlightsOf(built),
    sections: built,
    notesMarkdown: _tidy(kept),
    bannerUrl: banner,
    gallery: gallery,
  );
}

/// The section bullets land in when the body has bullets but no heading.
_Section _newImplicit(List<_Section> sections) {
  final s = _Section('Changes');
  if (sections.length < _maxSections) sections.add(s);
  return s;
}

({int level, String text})? _heading(String line) {
  // Up to three spaces of indent, 1-6 hashes, then a space.
  var i = 0;
  while (i < line.length && i < 4 && line.codeUnitAt(i) == 0x20) {
    i++;
  }
  if (i > 3) return null;
  var level = 0;
  while (i < line.length && line.codeUnitAt(i) == 0x23) {
    level++;
    i++;
  }
  if (level < 1 || level > 6) return null;
  if (i >= line.length || (line.codeUnitAt(i) != 0x20 && line.codeUnitAt(i) != 0x09)) {
    return null;
  }
  var text = line.substring(i).trim();
  // Optional closing hashes: `## Fixed ##`.
  var end = text.length;
  while (end > 0 && text.codeUnitAt(end - 1) == 0x23) {
    end--;
  }
  if (end < text.length && (end == 0 || text.codeUnitAt(end - 1) == 0x20)) {
    text = text.substring(0, end).trimRight();
  }
  if (text.isEmpty) return null;
  return (level: level, text: text);
}

List<String> _highlightsOf(List<ReleaseSection> sections) {
  final out = <String>[];
  for (final s in sections) {
    for (final item in s.items) {
      final plain = plainFromMarkdown(item);
      if (plain.isEmpty) continue;
      out.add(plain);
      if (out.length == _highlightCount) return out;
    }
  }
  return out;
}

String _tidy(List<String> kept) =>
    kept.join('\n').replaceAll(_blankRun, '\n\n').trim();

// ---------------------------------------------------------------------------
// The manifest reader
// ---------------------------------------------------------------------------

ReleaseNotes _fromManifest(Map<String, dynamic> m) {
  final body = asTrimmed(m['notes']) ?? '';
  // When the manifest declares a title, a `# heading` inside `notes` is just
  // content - re-reading our own cached output must not eat it a second time.
  final parsed = body.isEmpty
      ? ReleaseNotes.empty
      : _parseTotal(body, takeTitle: !m.containsKey('title'));

  final title = m.containsKey('title') ? asTrimmed(m['title']) : parsed.title;
  final summaryRaw = m.containsKey('summary') ? asTrimmed(m['summary']) : parsed.summary;
  final summary = summaryRaw == null ? null : _truncate(summaryRaw, _summaryMax);

  final List<ReleaseSection> sections;
  if (m.containsKey('sections')) {
    sections = _manifestSections(m['sections']);
  } else {
    sections = parsed.sections;
  }

  final List<String> highlights;
  if (m.containsKey('highlights')) {
    highlights = asStringList(m['highlights']);
  } else if (m.containsKey('sections')) {
    highlights = _highlightsOf(sections);
  } else {
    highlights = parsed.highlights;
  }

  final images = asMap(m['images']);
  final declaredBanner = images == null ? null : asHttpsUrl(images['banner']);
  final seen = <String>{};
  final gallery = <ReleaseGalleryImage>[];
  void addGallery(ReleaseGalleryImage g) {
    if (seen.add(g.url)) gallery.add(g);
  }

  if (declaredBanner != null) seen.add(declaredBanner);
  for (final raw in asList(images?['gallery'])) {
    final g = ReleaseGalleryImage.tryParse(raw);
    if (g != null) addGallery(g);
  }
  // Images that were written into the markdown rather than declared.
  String? banner = declaredBanner;
  if (banner == null && parsed.bannerUrl != null && !seen.contains(parsed.bannerUrl)) {
    banner = parsed.bannerUrl;
    seen.add(banner!);
  } else if (parsed.bannerUrl != null) {
    addGallery(ReleaseGalleryImage(url: parsed.bannerUrl!));
  }
  parsed.gallery.forEach(addGallery);

  return ReleaseNotes(
    title: title,
    summary: summary,
    highlights: highlights,
    sections: sections,
    notesMarkdown: parsed.notesMarkdown,
    bannerUrl: banner,
    gallery: gallery,
  );
}

List<ReleaseSection> _manifestSections(Object? raw) {
  final out = <ReleaseSection>[];
  for (final e in asList(raw)) {
    final m = asMap(e);
    if (m == null) continue;
    final items = asStringList(m['items']);
    if (items.isEmpty) continue;
    final title = asTrimmed(m['title']) ?? 'Other';
    out.add(ReleaseSection(
      title: title,
      icon: normalizeIconKey(asTrimmed(m['icon'])) ?? iconForHeading(title),
      items: items,
    ));
    if (out.length >= _maxSections) break;
  }
  return out;
}
