import 'package:flutter/material.dart';

import '../../design/tokens/space.dart';
import '../../design/tokens/type.dart' as type;

/// One searchable row in Settings.
class SettingsEntry {
  const SettingsEntry(this.id, this.keywords);

  final String id;

  /// Everything this row should be findable by: its title, its subtitle, and
  /// terms the user would actually type that are not on screen.
  ///
  /// Hidden keywords are the point of the feature. A row labelled "Cellular
  /// Quality" is what somebody looks for when they type "mobile data", and
  /// without a synonym the search looks broken even though it is working.
  final List<String> keywords;
}

/// Case-insensitive keyword index over Settings rows.
///
/// Pure and separate from the screen so the matching rules can be pinned by
/// tests. Substring rather than prefix, because people type fragments
/// ("qual") and expect to find things.
class SettingsSearchIndex {
  SettingsSearchIndex([this.query = '']);

  final String query;
  final Map<String, SettingsEntry> _entries = {};

  /// The trimmed query. An all-whitespace query is the same as no query, which
  /// is what stops a stray space from hiding the entire screen.
  String get needle => query.trim();

  bool get isFiltering => needle.isNotEmpty;

  /// Whether ANY registered row matched.
  ///
  /// Read only after every group has voted, so the empty state cannot claim
  /// "nothing matches" while a group further down the list has not voted yet.
  bool get anyMatch => _entries.values.any(_matches);

  void registerAll(Iterable<SettingsEntry> entries) {
    for (final entry in entries) {
      _entries[entry.id] = entry;
    }
  }

  /// Whether [id] should stay visible.
  ///
  /// An unregistered id stays VISIBLE. Failing open is deliberate: a row the
  /// index does not know about is a row we failed to annotate, and hiding every
  /// row we forgot is a much worse failure than showing one extra.
  bool matches(String id) {
    if (!isFiltering) return true;
    final entry = _entries[id];
    if (entry == null) return true;
    return _matches(entry);
  }

  /// Whether any of [ids] should stay visible.
  bool matchesAny(Iterable<String> ids) =>
      ids.isEmpty ? true : ids.any(matches);

  bool _matches(SettingsEntry entry) {
    final n = needle.toLowerCase();
    if (n.isEmpty) return true;
    return entry.keywords.any((k) => k.toLowerCase().contains(n));
  }
}

/// Makes the index available to the groups below it.
class SettingsSearchScope extends InheritedWidget {
  const SettingsSearchScope({
    super.key,
    required this.index,
    required super.child,
  });

  final SettingsSearchIndex index;

  static SettingsSearchIndex? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SettingsSearchScope>()
      ?.index;

  @override
  bool updateShouldNotify(SettingsSearchScope oldWidget) =>
      oldWidget.index.query != index.query;
}

/// Hides a group when nothing in it matches.
///
/// The group header is treated as a keyword for every row beneath it, which is
/// what makes searching "playback" return the whole Playback group rather than
/// the one row that happens to contain the word.
class SettingsSearchGate extends StatelessWidget {
  const SettingsSearchGate({
    super.key,
    required this.index,
    required this.entries,
    required this.child,
  });

  final SettingsSearchIndex index;

  /// The rows this group contains. [SettingsEntry.keywords] should already
  /// include the group header, so the caller decides that once per group.
  final List<SettingsEntry> entries;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!index.matchesAny(entries.map((e) => e.id))) {
      return const SizedBox.shrink();
    }
    return child;
  }
}

/// The search field, matching the Settings header in the reference app.
///
/// Plain text with no debounce: the index is a handful of entries, so filtering
/// is instant and a debounce would only add latency to a list that is already
/// on screen.
class SettingsSearchField extends StatefulWidget {
  const SettingsSearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search settings',
  });

  final ValueChanged<String> onChanged;
  final String hint;

  @override
  State<SettingsSearchField> createState() => _SettingsSearchFieldState();
}

class _SettingsSearchFieldState extends State<SettingsSearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.screenX),
      child: TextField(
        controller: _controller,
        // Rebuilds on every keystroke. Without it the clear affordance never
        // appears while typing, because nothing marks this subtree dirty - the
        // suffix is decided from _controller.text, which is not an input the
        // build system watches.
        onChanged: (value) {
          setState(() {});
          widget.onChanged(value);
        },
        textInputAction: TextInputAction.search,
        style: type.Type.body(context),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: type.Type.body(context)
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search_rounded,
              color: theme.colorScheme.onSurfaceVariant, size: 20),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                  // Clears the field AND the filter: leaving text behind while
                  // the list is unfiltered is a state that reads as broken.
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.5),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Honest "nothing found" state, with the query echoed back.
///
/// Echoing matters: "No settings match" with no query shown leaves the user
/// guessing whether the app broke or they typed something odd.
class SettingsSearchEmpty extends StatelessWidget {
  const SettingsSearchEmpty({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.screenX, vertical: Spacing.xxxl),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: Spacing.md),
          Text(
            'No settings match "$query"',
            textAlign: TextAlign.center,
            style: type.Type.body(context)
                .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}