// tool/release/src/commit_notes.dart
//
// RELEASE NOTES FROM COMMITS, written for the person who installs the update.
//
// The repo's commits are conventional (`feat(scope): ...`, `fix(scope): ...`) but
// written for developers: long, with several changes joined by `;` and detail
// after a ` - `. A user reading "What's new" on their phone wants one short line
// per change, in plain words, grouped as New / Improved / Fixed. This turns one
// into the other:
//
//   * `;` splits one commit into several bullets;
//   * a clause that runs long is cut at its first ` - ` (the headline survives,
//     the engineering detail does not);
//   * chore / docs / test / ci / build commits are left out - they change
//     nothing the listener can see;
//   * duplicates collapse, and each section is capped so a big release is still
//     readable on a phone.
//
// A hand-written `release/notes/<version>.md` replaces all of this (see
// [sectionsFromMarkdown]); this is what runs when nobody had time to write one.

class NoteSection {
  const NoteSection(this.title, this.icon, this.items);

  /// `New`, `Improved`, `Fixed` (or whatever a curated file calls it).
  final String title;

  /// `sparkle`, `improved`, `fix`, `perf`, `design`, `other` - matches the app.
  final String icon;
  final List<String> items;

  Map<String, Object> toJson() => {'title': title, 'icon': icon, 'items': items};
}

class ParsedCommit {
  const ParsedCommit(this.type, this.scope, this.subject, {this.breaking = false});

  final String type;
  final String? scope;
  final String subject;
  final bool breaking;
}

final RegExp _conventional =
    RegExp(r'^(\w+)(?:\(([^)]*)\))?(!)?:\s*(.+)$', dotAll: true);

/// Null for something that is not a conventional subject.
ParsedCommit? parseCommit(String subject) {
  final m = _conventional.firstMatch(subject.trim());
  if (m == null) return null;
  return ParsedCommit(
    m.group(1)!.toLowerCase(),
    m.group(2),
    m.group(4)!.trim(),
    breaking: m.group(3) != null,
  );
}

/// Types nobody using the app can see.
const Set<String> _invisible = {
  'chore', 'docs', 'test', 'tests', 'ci', 'build', 'style', 'revert', 'wip',
  'merge', 'deps', 'release', 'bump',
};

const Map<String, String> _bucketOf = {
  'feat': 'New',
  'feature': 'New',
  'add': 'New',
  'fix': 'Fixed',
  'bugfix': 'Fixed',
  'hotfix': 'Fixed',
  'perf': 'Improved',
  'refactor': 'Improved',
  'design': 'Improved',
  'ui': 'Improved',
  'ux': 'Improved',
  'improve': 'Improved',
  'polish': 'Improved',
};

const Map<String, String> _iconOf = {
  'New': 'sparkle',
  'Improved': 'improved',
  'Fixed': 'fix',
};

const int maxItemsPerSection = 10;
const int maxItemLength = 140;

/// Turns commit subjects (newest first) into sections. Order: New, Improved, Fixed.
List<NoteSection> sectionsFromCommits(Iterable<String> subjects) {
  final buckets = <String, List<String>>{'New': [], 'Improved': [], 'Fixed': []};
  final seen = <String>{};

  for (final raw in subjects) {
    final subject = raw.trim();
    if (subject.isEmpty) continue;
    final lower = subject.toLowerCase();
    if (lower.startsWith('merge ') ||
        lower.startsWith('bump ') ||
        lower.contains('[skip release]') ||
        lower.contains('[skip notes]')) {
      continue;
    }

    final parsed = parseCommit(subject);
    String bucket;
    String body;
    if (parsed != null) {
      if (_invisible.contains(parsed.type) && !parsed.breaking) continue;
      bucket = _bucketOf[parsed.type] ?? 'Improved';
      body = parsed.subject;
    } else {
      bucket = _guessBucket(lower);
      body = subject;
    }

    for (final clause in splitClauses(body)) {
      final line = tidy(clause);
      if (line.isEmpty) continue;
      if (!seen.add(line.toLowerCase())) continue;
      if (buckets[bucket]!.length < maxItemsPerSection) buckets[bucket]!.add(line);
    }
  }

  return [
    for (final e in buckets.entries)
      if (e.value.isNotEmpty) NoteSection(e.key, _iconOf[e.key]!, e.value),
  ];
}

String _guessBucket(String lower) {
  if (RegExp(r'^(fix|fixes|fixed|repair|resolve)\b').hasMatch(lower)) return 'Fixed';
  if (RegExp(r'^(add|adds|added|new|introduce|implement)\b').hasMatch(lower)) return 'New';
  return 'Improved';
}

/// `;` separates changes. A comma or "and" does not: that is one sentence.
List<String> splitClauses(String body) =>
    [for (final c in body.split(';')) c.trim()].where((c) => c.isNotEmpty).toList();

/// One short, plain sentence: capitalised, no trailing full stop, long ones cut
/// at their first ` - ` (or ` – `) so the headline survives and the detail goes.
String tidy(String clause) {
  var s = clause.trim().replaceAll(RegExp(r'\s+'), ' ');
  s = s.replaceAll(RegExp(r'`'), '');
  // The headline is what comes before the first  - ; the engineering detail
  // after it is for the commit log, not the person updating their music app.
  if (s.length > 90) {
    final dash = RegExp(r'\s[-\u2013\u2014]\s').firstMatch(s);
    if (dash != null && dash.start >= 12) s = s.substring(0, dash.start);
  }
  if (s.length > maxItemLength) {
    final cut = s.lastIndexOf(' ', maxItemLength - 1);
    s = '${s.substring(0, cut > 40 ? cut : maxItemLength - 1)}\u2026';
  }
  s = s.replaceAll(RegExp(r'[.\s]+$'), '');
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

// ── Curated markdown ───────────────────────────────────────────────────────

final RegExp _emoji = RegExp(
  r'^[\s\u200d\ufe0f\u2600-\u27bf\u{1F000}-\u{1FAFF}\u2b00-\u2bff\u2190-\u21ff]+',
  unicode: true,
);

String _iconFor(String title) {
  final t = title.toLowerCase();
  if (RegExp(r'\b(new|added|feature)').hasMatch(t)) return 'sparkle';
  if (RegExp(r'\b(fix|bug)').hasMatch(t)) return 'fix';
  if (RegExp(r'\b(perf|faster|speed|battery)').hasMatch(t)) return 'perf';
  if (RegExp(r'\b(design|look|visual|ui)').hasMatch(t)) return 'design';
  if (RegExp(r'\b(improv|better|polish|change)').hasMatch(t)) return 'improved';
  return 'other';
}

/// Reads a hand-written notes file: `## ✨ New` headings with `- bullets`.
/// Returns the sections, the optional `# Title`, and the first free paragraph.
({String? title, String? summary, List<NoteSection> sections}) sectionsFromMarkdown(
    String markdown) {
  String? title;
  String? summary;
  final out = <NoteSection>[];
  String? current;
  var items = <String>[];

  void flush() {
    final c = current;
    if (c != null && items.isNotEmpty) out.add(NoteSection(c, _iconFor(c), items));
    items = <String>[];
  }

  for (final line in markdown.replaceAll('\r\n', '\n').split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (t.startsWith('# ') && title == null && out.isEmpty && current == null) {
      title = t.substring(2).trim();
      continue;
    }
    final h = RegExp(r'^#{2,3}\s+(.+)$').firstMatch(t);
    if (h != null) {
      flush();
      current = h.group(1)!.replaceFirst(_emoji, '').trim();
      continue;
    }
    final b = RegExp(r'^(?:[-*+]|\d+[.)])\s+(.+)$').firstMatch(t);
    if (b != null && current != null) {
      items.add(b.group(1)!.trim());
      continue;
    }
    if (current == null && summary == null && !t.startsWith('!') && !t.startsWith('<')) {
      summary = t.length > 160 ? '${t.substring(0, 159)}\u2026' : t;
    }
  }
  flush();
  return (title: title, summary: summary, sections: out);
}

// ── Rendering ───────────────────────────────────────────────────────────────

const Map<String, String> _heading = {
  'New': '\u2728 New',
  'Improved': '\ud83d\udee0\ufe0f Improved',
  'Fixed': '\ud83d\udc1e Fixed',
};

class GalleryImage {
  const GalleryImage(this.url, this.caption);
  final String url;
  final String caption;
}

/// The GitHub release body. The app parses this same markdown when a release has
/// no `update.json`, so the layout is the contract: banner first, then a title,
/// then `##` sections, then screenshots.
String renderReleaseBody({
  required String appName,
  required String version,
  String? title,
  String? summary,
  required List<NoteSection> sections,
  String? bannerUrl,
  List<GalleryImage> gallery = const [],
  String? compareUrl,
  String? sha256,
}) {
  final b = StringBuffer();
  if (bannerUrl != null) {
    b.writeln('![$appName $version]($bannerUrl)');
    b.writeln();
  }
  b.writeln('# ${title ?? '$appName $version'}');
  b.writeln();
  if (summary != null && summary.isNotEmpty) {
    b.writeln(summary);
    b.writeln();
  }
  if (sections.isEmpty) {
    b.writeln('Maintenance release: small fixes and polish.');
    b.writeln();
  }
  for (final s in sections) {
    b.writeln('## ${_heading[s.title] ?? s.title}');
    b.writeln();
    for (final item in s.items) {
      b.writeln('- $item');
    }
    b.writeln();
  }
  if (gallery.isNotEmpty) {
    b.writeln('## Screenshots');
    b.writeln();
    for (final g in gallery) {
      b.writeln('![${g.caption}](${g.url})');
    }
    b.writeln();
  }
  b.writeln('---');
  if (sha256 != null) b.writeln('SHA-256: `$sha256`');
  if (compareUrl != null) b.writeln('[Full changelog]($compareUrl)');
  return b.toString();
}
