import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a Home section lays its items out.
enum HomeSectionViewMode {
  /// Compact paging columns of dense rows.
  list,

  /// A rail of large artwork cards.
  card;

  HomeSectionViewMode get toggled =>
      this == HomeSectionViewMode.list
          ? HomeSectionViewMode.card
          : HomeSectionViewMode.list;
}

/// Which section a stored view mode belongs to.
///
/// An enum rather than a bare string so a section cannot be renamed without the
/// persisted preference silently orphaning itself under a key nothing reads.
enum HomeViewSection {
  /// The listening-history shelf.
  jumpBackIn,

  /// The deterministic recommendation shelf.
  quickPicks,

  /// The source's own history shelf ("Listen again", "Recents", …).
  ///
  /// A separate entry from [jumpBackIn] on purpose: one is our local overlay over
  /// play history and the other is a shelf the feed parser returns, and they
  /// arrive under different titles on different accounts. Sharing one key would
  /// make toggling one silently re-lay-out the other.
  listenAgain;

  String get storageKey => 'home_view_$name';
}

/// Per-section layout preference, persisted across restarts.
///
/// Deliberately one store for every section rather than a bool on each widget:
/// the preference has to outlive the widget that shows it, and a section that is
/// not currently built must not lose its choice because it scrolled away.
///
/// A section that has never been touched returns [defaultMode] for that section,
/// so the defaults live in one place instead of being spread across call sites
/// that would inevitably disagree.
class HomeViewModeStore extends ChangeNotifier {
  HomeViewModeStore({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;
  final Map<HomeViewSection, HomeSectionViewMode> _modes = {};
  bool _initialized = false;

  /// Defaults chosen per section, not globally.
  ///
  /// Quick picks opens as cards because it is a discovery shelf: a dense list of
  /// 52dp rows reads as a queue to work through rather than as things to pick
  /// from. Jump back in opens as cards too, matching what it has always been -
  /// history you are returning to is easier to recognise by artwork.
  static HomeSectionViewMode defaultFor(HomeViewSection section) =>
      switch (section) {
        // Both open on cards. A user who prefers compact rows taps once and the
        // choice sticks; a user who does not is never served a layout they did
        // not ask for first.
        HomeViewSection.jumpBackIn => HomeSectionViewMode.card,
        HomeViewSection.quickPicks => HomeSectionViewMode.card,
        // Cards, because that is how this shelf has always rendered. Defaulting
        // it to rows would silently restyle the feed on upgrade for a user who
        // never asked for a change.
        HomeViewSection.listenAgain => HomeSectionViewMode.card,
      };

  HomeSectionViewMode modeOf(HomeViewSection section) =>
      _modes[section] ?? defaultFor(section);

  bool isCard(HomeViewSection section) =>
      modeOf(section) == HomeSectionViewMode.card;

  Future<void> toggle(HomeViewSection section) async {
    final next = modeOf(section).toggled;
    _modes[section] = next;
    notifyListeners();
    // Write through the live instance if one is cached, otherwise resolve it
    // now. Awaiting the write rather than fire-and-forget: the tap that
    // changed the layout should not be able to outrun its own persistence, or a
    // kill straight after loses the choice with no way back.
    //
    // A store that cannot be written is not an error worth surfacing. The
    // layout already changed in memory and the screen already moved; throwing
    // here would leave the tap looking broken over a preference the user never
    // asked about. The choice simply resets to the default next launch.
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      await prefs.setString(section.storageKey, next.name);
    } catch (e) {
      debugPrint('HomeViewModeStore: could not persist $section: $e');
    }
  }

  /// Load persisted choices.
  ///
  /// Called once from main() alongside the other controllers that own a
  /// preference key. Until it runs, every section reports its default, which is
  /// why the UI is usable rather than blank on a cold start.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      for (final section in HomeViewSection.values) {
        final stored = _prefs!.getString(section.storageKey);
        if (stored == null) continue;
        // An unrecognised value means a downgrade or a rename. Falling back to
        // the default is correct; refusing to load would leave it stuck.
        final parsed = HomeSectionViewMode.values
            .where((m) => m.name == stored)
            .firstOrNull;
        if (parsed != null) _modes[section] = parsed;
      }
      _initialized = true;
      notifyListeners();
    } catch (e) {
      // A preference store that cannot be read must not stop the screen from
      // building. Defaults are a perfectly good answer here.
      debugPrint('HomeViewModeStore: could not read preferences: $e');
    }
  }

  @visibleForTesting
  void debugSet(HomeViewSection section, HomeSectionViewMode mode) {
    _modes[section] = mode;
    notifyListeners();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}