// lib/presentation/home/home_shelf_plan.dart
//
// ONE SHELF PER JOB.
//
// Home is built from two kinds of shelf: the ones YouTube Music sends (the feed)
// and the ones this app makes itself from what you play here ("Jump back in",
// and the Quick picks its recommendation engine ranks). For a signed-in account
// the feed carries its OWN "Quick picks" and "Listen again" - the very same jobs
// - and the screen drew both. Nothing compared them: the composer collapses
// duplicate titles inside the feed, and the local shelves are added outside it.
// So Home showed two "Quick picks", and a "Jump back in" beside a "Listen
// again", whenever the feed happened to include them - which depends on the
// account and on the response, hence "sometimes".
//
// The rule, stated once and tested:
//
//   * A job (quick picks, play history) is done by ONE shelf.
//   * If YouTube Music sent a shelf for the job, that is the shelf - it keeps its
//     place in the feed, because native order is truth - and the app's own
//     shelf does not also appear.
//   * The app does not throw its own knowledge away: what you played HERE is
//     folded into the front of "Listen again", because this app does not report
//     plays to YouTube Music and the shelf could never contain them otherwise.
//   * A job the feed did not send is filled by the app's shelf, as before.
//   * If two shelves in the feed claim one job ("Listen again" and "Recents"),
//     the first stays.
//   * A track is not shown twice in the opening stretch of the page: what the
//     hero carousel already shows is not repeated as the Quick picks below it.
//
// Pure functions over plain data, so each of those is a test and none is a
// property of a widget tree.

import '../../models/track.dart';
import '../../services/home/home_models.dart';

/// A job a Home shelf does.
enum HomeShelfRole { quickPicks, history }

/// The job [section] does, or null when it is just a shelf.
HomeShelfRole? shelfRoleOf(HomeSection section) {
  if (SectionIdentity.semanticSlug(section) == 'recent') {
    return HomeShelfRole.history;
  }
  final name = SectionIdentity.normalizedTitle(section.title);
  if (name == 'quick picks' || name.startsWith('quick picks ')) {
    return HomeShelfRole.quickPicks;
  }
  return null;
}

/// Whether a recently played track can become a Home item the feed's grid and
/// rows know how to play: a real YouTube video id, not a local file or a
/// collection id.
bool isStreamableTrack(Track t) =>
    t.source != 'local' &&
    t.id.length == 11 &&
    !RegExp(r'^(MPREb|OLAK|VL|PL|UC)').hasMatch(t.id);

/// What Home should draw below the hero, in order.
class HomeShelfPlan {
  const HomeShelfPlan({
    required this.feedSections,
    required this.quickPicksSection,
    required this.historySection,
    required this.localQuickPicks,
    required this.localHistory,
  });

  /// The feed's shelves, in feed order, one per job, with the history shelf
  /// already carrying the listener's own plays.
  final List<HomeSection> feedSections;

  /// The feed's Quick picks shelf (an element of [feedSections]), if it sent one.
  final HomeSection? quickPicksSection;

  /// The feed's history shelf (an element of [feedSections]), if it sent one.
  final HomeSection? historySection;

  /// The app's own Quick picks, empty when the feed's does the job.
  final List<Track> localQuickPicks;

  /// The app's own "Jump back in" tracks. Everything played here when the feed
  /// has no history shelf, and then only streamable plays; never local files.
  final List<Track> localHistory;
}

/// How many of the listener's own plays are folded into a history shelf, and the
/// size the merged shelf is held to (the composer's per-shelf budget).
const int kHistoryLocalLead = 8;
const int kHistoryShelfCap = 12;

/// [native] with [mine] (streamable plays from this app, most recent first)
/// put in front, de-duplicated by video id, native items after, capped.
HomeSection mergeHistory(HomeSection native, List<Track> mine) {
  final seen = <String>{};
  final items = <HomeItem>[];
  for (final t in mine.take(kHistoryLocalLead)) {
    if (!seen.add(t.id)) continue;
    items.add(HomeItem(
      id: t.id,
      videoId: t.id,
      title: t.trackName,
      subtitle: t.artistName,
      artworkUrl: t.albumArtUrl,
      contentType: HomeContentType.song,
      artists: t.artistName.isEmpty ? const [] : [t.artistName],
    ));
  }
  for (final item in native.items) {
    final key = item.videoId ?? item.id;
    if (!seen.add(key)) continue;
    items.add(item);
  }
  return HomeSection(
    id: native.id,
    title: native.title,
    items: items.length > kHistoryShelfCap
        ? items.sublist(0, kHistoryShelfCap)
        : items,
    presentation: native.presentation,
    sourcePath: native.sourcePath,
    renderer: native.renderer,
    sourceSubtitle: native.sourceSubtitle,
    provenance: native.provenance,
  );
}

/// Decides which shelves Home draws.
///
/// [feed] is the composed feed's sections; [hero] is a feed shelf that was
/// promoted into the hero carousel (and so is not drawn below it); [heroTrackIds]
/// are the tracks the hero shows; [recents] and [quickPicks] are the app's own
/// shelves' tracks; [renders] says whether a feed shelf will actually draw
/// anything - a shelf that collapses to nothing does not do its job and must not
/// suppress the app's shelf that would.
HomeShelfPlan planHomeShelves({
  required List<HomeSection> feed,
  HomeSection? hero,
  Set<String> heroTrackIds = const {},
  required List<Track> recents,
  required List<Track> quickPicks,
  required bool Function(HomeSection) renders,
}) {
  // Jobs already done: by the hero carousel, then by the feed as it is walked.
  final done = <HomeShelfRole>{};
  final heroRole = hero == null ? null : shelfRoleOf(hero);
  if (heroRole != null) done.add(heroRole);

  final sections = <HomeSection>[];
  HomeSection? quickShelf;
  HomeSection? historyShelf;

  for (final section in feed) {
    if (hero != null && section.id == hero.id) continue;
    if (!renders(section)) continue;

    final role = shelfRoleOf(section);
    if (role != null) {
      // A second claim on the same job: the first stays.
      if (!done.add(role)) continue;
      if (role == HomeShelfRole.quickPicks) quickShelf = section;
      if (role == HomeShelfRole.history) historyShelf = section;
    }
    sections.add(section);
  }

  // History: fold what was played here into the feed's shelf.
  //
  // Local files never feed a Jump back in shelf of their own. That shelf is
  // hidden whenever the feed has a history shelf, and a local play used to
  // bring it back on its own (a file cannot live in a YouTube shelf, so it was
  // given a shelf instead). It stays hidden: local plays remain in Library and
  // Replay, which is where a file is looked for.
  var localHistory = recents.where(isStreamableTrack).toList();
  if (historyShelf != null) {
    final mine = recents.where(isStreamableTrack).toList(growable: false);
    final merged = mine.isEmpty ? historyShelf : mergeHistory(historyShelf, mine);
    final at = sections.indexWhere((s) => identical(s, historyShelf));
    if (at >= 0) sections[at] = merged;
    historyShelf = merged;
    localHistory = const [];
  } else if (heroRole == HomeShelfRole.history) {
    // The hero IS the history shelf.
    localHistory = const [];
  }

  // Quick picks: the feed's does the job when it sent one; otherwise the app's,
  // minus what the hero already shows.
  var localQuick = const <Track>[];
  if (quickShelf == null && heroRole != HomeShelfRole.quickPicks) {
    final unseen =
        quickPicks.where((t) => !heroTrackIds.contains(t.id)).toList();
    // Dropping what the hero shows may leave a thin shelf; a rail of one card
    // is not a shelf. Without any overlap, keep it as it always was.
    final enough = unseen.length == quickPicks.length
        ? unseen.isNotEmpty
        : unseen.length >= 3;
    if (enough) localQuick = unseen;
  }

  return HomeShelfPlan(
    feedSections: sections,
    quickPicksSection: quickShelf,
    historySection: historyShelf,
    localQuickPicks: localQuick,
    localHistory: localHistory,
  );
}
