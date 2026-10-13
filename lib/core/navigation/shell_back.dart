// lib/core/navigation/shell_back.dart
// What the system back gesture does at the app shell, in order.

/// One answer to "back was pressed".
enum ShellBackAction {
  /// Close the topmost route on the PLAYER's own navigator: a provider sheet,
  /// the queue, an options sheet.
  popPlayerRoute,

  /// Bring the player panel down.
  collapsePlayer,

  /// Close the topmost detail screen on the shell's nested navigator.
  popDetail,

  /// Leave search.
  exitSearch,

  /// Go to the Home tab.
  goHome,

  /// Nothing to do: let the system leave the app.
  none,
}

/// The order back is answered in, as a pure function so it can be tested.
///
/// THE RULE: back closes the TOPMOST thing, and the topmost thing is whatever
/// was opened last. The player has a navigator of its own, and a sheet opened
/// from the player (the lyric provider switcher, a track's options) is a route
/// on it. Only the root navigator hears the system back, so the shell has to
/// forward it: the handler used to ask "is the player open?" and collapse it,
/// which closed the player UNDER a sheet that was still on screen.
ShellBackAction resolveShellBack({
  required bool isPanelOpen,
  required bool playerCanPop,
  required bool detailCanPop,
  required bool searchMode,
  required int tabIndex,
}) {
  if (isPanelOpen) {
    return playerCanPop
        ? ShellBackAction.popPlayerRoute
        : ShellBackAction.collapsePlayer;
  }
  if (detailCanPop) return ShellBackAction.popDetail;
  if (searchMode) return ShellBackAction.exitSearch;
  if (tabIndex != 0) return ShellBackAction.goHome;
  return ShellBackAction.none;
}
