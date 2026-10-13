import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/accent_controller.dart';
import '../providers/music_provider.dart';
import '../services/lyrics/lyrics_service.dart';
import '../theme/material_you_tokens.dart';
import '../theme/material_you_typography.dart';
import 'liquid_switch.dart';

/// Reports where a drag handle's finger is, without claiming the gesture.
///
/// `ReorderableDragStartListener` starts the reorder on its own; this only
/// observes. A [Listener] rather than a [GestureDetector] on purpose - a
/// GestureDetector here would enter the arena and can win it, and the reorder
/// would stop starting.
class _DragPositionReporter extends StatelessWidget {
  const _DragPositionReporter({
    required this.onMove,
    required this.onEnd,
    required this.child,
  });

  final void Function(Offset globalPosition) onMove;
  final VoidCallback onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerMove: (event) => onMove(event.position),
        onPointerUp: (_) => onEnd(),
        onPointerCancel: (_) => onEnd(),
        child: child,
      );
}

/// What the sheet is for.
///
/// Two different jobs that look alike and must not be merged. Settings asks
/// "which sources should this app use, and in what order" - a standing preference
/// with drags and toggles. The live sheet asks "show me this song's words from
/// somewhere else instead" - a one-off, showing what the lookup actually just
/// did. Mixing them puts a reorder handle next to a spinner and makes both
/// unreadable.
enum LyricProvidersMode { settings, live }

/// Modal sheet for choosing where lyrics come from.
///
/// [LyricProvidersMode.settings] customizes the provider priority order and the
/// enabled sources; [LyricProvidersMode.live] switches the loaded song's lyrics
/// to another source that has (or can fetch) them.
class LyricProvidersSheet extends StatelessWidget {
  const LyricProvidersSheet({
    super.key,
    this.isMaterialYou = false,
    this.mode = LyricProvidersMode.settings,
    this.changed,
  });

  final bool isMaterialYou;
  final LyricProvidersMode mode;

  /// Set to true by the settings sheet whenever the enabled set or the order
  /// changes, so the caller can re-run the lookup once the sheet closes - not
  /// once per drag.
  final ValueNotifier<bool>? changed;

  /// Enter 260ms, exit 180ms (BitChord `PlayerDrawer`).
  static const AnimationStyle _sheetAnimation = AnimationStyle(
    duration: Duration(milliseconds: 260),
    reverseDuration: Duration(milliseconds: 180),
    curve: Curves.fastOutSlowIn,
    reverseCurve: Curves.fastOutSlowIn,
  );

  /// The settings sheet.
  ///
  /// Shown on the ROOT navigator. The settings page lives in the shell's nested
  /// navigator, and a sheet pushed there is laid out underneath the floating tab
  /// bar and the mini player: the list believed it fitted, had no scroll extent,
  /// and its last rows sat behind the bar where nothing could reach them. The
  /// mini player is drawn above the root navigator by the global overlay, so it
  /// is hidden for the duration (the same arrangement the options sheets use).
  static Future<void> show(
    BuildContext context, {
    bool isMaterialYou = false,
  }) async {
    HapticFeedback.lightImpact();
    final music = Provider.of<MusicProvider>(context, listen: false);
    final hidMini = !music.isPlayerExpanded && !music.hideMiniPlayer;
    if (hidMini) music.setHideMiniPlayer(true);
    final changed = ValueNotifier<bool>(false);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        constraints: BoxConstraints(maxHeight: maxHeight),
        sheetAnimationStyle: _sheetAnimation,
        builder: (_) => LyricProvidersSheet(
          isMaterialYou: isMaterialYou,
          changed: changed,
        ),
      );
    } finally {
      if (hidMini) music.setHideMiniPlayer(false);
      // Once, when the sheet is gone: a drag across five rows is one change.
      if (changed.value) music.refreshLyricsForSourceChange();
      changed.dispose();
    }
  }

  /// The per-track switcher, opened from the "Lyrics by ..." caption on the deck.
  ///
  /// Shown on the PLAYER's navigator (the default), not the root one: the
  /// player panel is drawn above the root navigator by the global overlay, so a
  /// root-navigator sheet would open underneath the card it was opened from.
  /// Back is therefore the shell's job (see `resolveShellBack`): it pops the
  /// player's own routes before it closes the player.
  ///
  /// Rows that the automatic lookup already completed are entirely local: a hit
  /// applies immediately and a miss is not requestable twice.
  static Future<void> showLive(
    BuildContext context, {
    bool isMaterialYou = false,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: false,
      // Dragging is the sheet's own (see _LiveProvidersSheet): the built-in drag
      // sits behind the list's scroll recognizer and never wins.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: _sheetAnimation,
      builder: (_) => LyricProvidersSheet(
        isMaterialYou: isMaterialYou,
        mode: LyricProvidersMode.live,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mode == LyricProvidersMode.live) return const _LiveProvidersSheet();
    return _SettingsProvidersSheet(
      isMaterialYou: isMaterialYou,
      changed: changed,
    );
  }
}

// =============================================================================
// Live switcher
// =============================================================================

/// What the live sheet draws, compared by value so a position tick (which makes
/// the provider notify many times a second) does not rebuild it.
@immutable
class _LiveData {
  const _LiveData({
    required this.current,
    required this.states,
    required this.loading,
  });

  final LyricsProvider? current;
  final Map<LyricsProvider, ProviderState> states;
  final bool loading;

  @override
  bool operator ==(Object other) =>
      other is _LiveData &&
      other.current == current &&
      other.loading == loading &&
      mapEquals(other.states, states);

  @override
  int get hashCode => Object.hash(current, loading, states.length);
}

class _LiveProvidersSheet extends StatefulWidget {
  const _LiveProvidersSheet();

  @override
  State<_LiveProvidersSheet> createState() => _LiveProvidersSheetState();
}

class _LiveProvidersSheetState extends State<_LiveProvidersSheet> {
  final LyricsService _lyricsService = LyricsService();

  /// The provider a selection is waiting on.
  ///
  /// Held so the sheet can dismiss itself once the requested source actually
  /// becomes the loaded one. Dismissing on the tap instead would close the sheet
  /// while the request was still in flight, leaving the listener staring at the
  /// same lyrics wondering whether anything happened.
  LyricsProvider? _requested;

  /// Set the moment the sheet starts to leave, and never cleared: the route is
  /// going and this State with it.
  ///
  /// The old sheet scheduled a pop on EVERY rebuild once the request had landed,
  /// and it rebuilds on every provider notification - so one selection popped
  /// the sheet and then, on the next notification, popped whatever was under it
  /// (the player's own page, and with it the player).
  bool _closing = false;

  static const double _rowExtent = 66; // 6 margin + 12*2 padding + 40 disc ~ 66
  static const double _headerExtent = 112;

  void _close() {
    if (_closing) return;
    _closing = true;
    // Never from inside a build or a gesture callback.
    scheduleMicrotask(() {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _maybeDismissOnLand(LyricsProvider? current) {
    if (_closing || _requested == null || current != _requested) return;
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Provider.of<AccentController>(context, listen: false).accent;
    final providers = [
      for (final p in _lyricsService.providerOrder)
        if (_lyricsService.isEnabled(p)) p,
    ];

    // Content-fit height, capped. The sheet opens exactly as tall as its rows
    // need up to 75% of the screen, and can be pulled taller when there are
    // more than that.
    final screen = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final contentHeight =
        _headerExtent + providers.length * _rowExtent + bottomInset + 16;
    final initial = (contentHeight / screen).clamp(0.3, 0.75);
    final maxSize = contentHeight / screen > 0.75 ? 0.92 : initial;

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        // `snap` carries a released drag to either end; reaching the bottom end
        // is the dismissal. Popped exactly once.
        if (n.extent <= 0.02) _close();
        return false;
      },
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: initial,
        minChildSize: 0,
        maxChildSize: maxSize,
        snap: true,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF14151C).withValues(alpha: 0.95),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.8,
              ),
            ),
            child: Selector<MusicProvider, _LiveData>(
              selector: (_, p) => _LiveData(
                current: p.lyricsSourceProvider,
                states: Map.of(p.lyricsProviderStates),
                loading: p.isLoadingLyrics,
              ),
              builder: (context, data, _) {
                _maybeDismissOnLand(data.current);
                return CustomScrollView(
                  controller: scrollController,
                  // Clamping: this is a translucent lens, and a stretch
                  // overscroll under one renders black at both edges on Android.
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _header(accent, data)),
                    if (providers.isEmpty)
                      SliverToBoxAdapter(child: _empty())
                    else
                      SliverList.builder(
                        itemCount: providers.length,
                        itemBuilder: (context, index) =>
                            _row(context, providers[index], data),
                      ),
                    SliverToBoxAdapter(child: SizedBox(height: bottomInset + 16)),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        child: Text(
          'No lyric sources are enabled.',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 13,
          ),
        ),
      );

  /// The grabber is purely visual. The whole sheet is the drag target, because
  /// the header is part of the scroll view the sheet drags.
  Widget _header(Color accent, _LiveData data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose lyrics provider',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.current == null
                          ? (data.loading ? 'Searching\u2026' : 'No source yet')
                          : 'Showing ${data.current!.displayName}',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (data.loading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The 20dp status glyph for a live row.
  ///
  /// [isCurrent] is checked FIRST, and it has to be: a source whose lyrics came
  /// from the disk cache never ran in this lookup at all, so its state is
  /// "not searched" and matching on state alone would put a magnifying glass
  /// next to the source actually on screen.
  Widget _glyph(ProviderState state, bool isCurrent) {
    if (state == ProviderState.fetching) {
      return SizedBox(
        key: const ValueKey('fetching'),
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(
            Colors.white.withValues(alpha: 0.85),
          ),
        ),
      );
    }
    if (isCurrent || state == ProviderState.found) {
      return Icon(
        Icons.check_rounded,
        key: const ValueKey('found'),
        size: 21,
        color: Colors.white.withValues(alpha: isCurrent ? 1 : 0.75),
      );
    }
    if (state == ProviderState.notFound) {
      return Icon(
        Icons.close_rounded,
        key: const ValueKey('missing'),
        size: 20,
        color: Colors.white.withValues(alpha: 0.4),
      );
    }
    return Icon(
      Icons.search_rounded,
      key: const ValueKey('search'),
      size: 20,
      color: Colors.white.withValues(alpha: 0.7),
    );
  }

  Widget _row(BuildContext context, LyricsProvider provider, _LiveData data) {
    final isCurrent = data.current == provider;
    final state = data.states[provider] ?? ProviderState.notFetched;
    final needsKey = provider.requiresApiKey && !_lyricsService.hasPaxSenixKey;

    final status = needsKey
        ? 'API key required'
        : switch (state) {
            ProviderState.fetching => 'Fetching\u2026',
            ProviderState.found => 'Found',
            ProviderState.notFound => 'Not found',
            ProviderState.notFetched => 'Tap to search',
          };

    // A source with nothing is not selectable - tapping it would spend a request
    // to arrive at the answer already on screen - and neither is one that
    // cannot be asked.
    final enabled = !needsKey && !isCurrent && state != ProviderState.notFound;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                setState(() => _requested = provider);
                // The sheet watches the provider for the result.
                unawaited(context
                    .read<MusicProvider>()
                    .selectLyricsProvider(provider));
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: isCurrent ? 0.10 : 0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      Colors.white.withValues(alpha: isCurrent ? 0.16 : 0.08),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _glyph(state, isCurrent),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white
                            .withValues(alpha: enabled || isCurrent ? 1 : 0.55),
                        fontSize: 15,
                        fontWeight:
                            isCurrent ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white
                            .withValues(alpha: isCurrent ? 0.7 : 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Settings
// =============================================================================

class _SettingsProvidersSheet extends StatefulWidget {
  const _SettingsProvidersSheet({
    required this.isMaterialYou,
    required this.changed,
  });

  final bool isMaterialYou;
  final ValueNotifier<bool>? changed;

  @override
  State<_SettingsProvidersSheet> createState() =>
      _SettingsProvidersSheetState();
}

class _SettingsProvidersSheetState extends State<_SettingsProvidersSheet> {
  final LyricsService _lyricsService = LyricsService();
  late List<LyricsProvider> _providers;
  late Set<LyricsProvider> _enabled;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  @override
  void dispose() {
    _edgeTicker?.dispose();
    super.dispose();
  }

  void _loadProviders() {
    _providers = [
      for (final p in _lyricsService.providerOrder)
        if (p.isOffered) p,
    ];
    _enabled = Set.from(_lyricsService.enabledProviders);
  }

  void _markChanged() => widget.changed?.value = true;

  final GlobalKey<State<StatefulWidget>> _reorderListKey = GlobalKey();

  /// The list being reordered, captured when a row builds inside it.
  ///
  /// Driving the list's OWN position rather than injecting a ScrollController:
  /// `ReorderableListView` owns its controller, and reaching in from outside
  /// means fighting it for the same scroll activity.
  ScrollPosition? _reorderPosition;

  Ticker? _edgeTicker;
  double _edgeSpeed = 0;

  /// How close to an edge a dragged row has to be before the list moves.
  static const double _edgeZone = 28.0;

  /// List travel per second while the finger is inside the band.
  ///
  /// Constant rather than proportional to how far into the band it is: a list
  /// that accelerates under a still finger is hard to aim with, and the band's
  /// only job is to say "there is more this way".
  ///
  /// The reference does the same (`LyricsSourcesDialog.kt:596-597`), and it is
  /// what makes the last row reachable at all - with this many providers the
  /// finger runs out of list long before the row runs out of finger. KEPT: it
  /// could only be dropped if `ReorderableListView`'s own autoscroll reaches the
  /// ends on a device, which has not been checked.
  static const double _edgeSpeedPerSecond = 220.0;

  /// Moves the list under a finger held near its edge.
  void _updateEdgeScroll(Offset globalPosition) {
    final position = _reorderPosition;
    if (position == null || !position.hasPixels) return;
    final context = position.context;
    final render = context.notificationContext?.findRenderObject();
    if (render is! RenderBox) return;

    final local = render.globalToLocal(globalPosition);
    final height = render.size.height;
    final speed = local.dy - _edgeZone < 0
        ? -_edgeSpeedPerSecond
        : height - local.dy - _edgeZone < 0
            ? _edgeSpeedPerSecond
            : 0.0;

    if (speed == _edgeSpeed) return;
    _edgeSpeed = speed;
    if (_edgeSpeed == 0) {
      _edgeTicker?.dispose();
      _edgeTicker = null;
    } else {
      _edgeTicker ??= Ticker(_onEdgeTick)..start();
    }
  }

  void _stopEdgeScroll() {
    if (_edgeSpeed == 0) return;
    _edgeSpeed = 0;
    _edgeTicker?.dispose();
    _edgeTicker = null;
  }

  void _onEdgeTick(Duration elapsed) {
    final position = _reorderPosition;
    if (position == null || !position.hasPixels || _edgeSpeed == 0) return;
    final next = (position.pixels + _edgeSpeed * elapsed.inMicroseconds / 1e6)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (next != position.pixels) position.jumpTo(next);
  }

  void _onReorder(int oldIndex, int newIndex) {
    HapticFeedback.selectionClick();
    // `onReorderItem` hands over the index AFTER the removal has been accounted
    // for; the deprecated `onReorder` did not, and needed `newIndex -= 1`.
    setState(() {
      final item = _providers.removeAt(oldIndex);
      _providers.insert(newIndex, item);
    });
    _lyricsService.updateProviderOrder(_providers);
    _markChanged();
  }

  bool _isLastEnabled(LyricsProvider provider) =>
      _enabled.where((p) => p.isOffered).length <= 1 &&
      _enabled.contains(provider);

  void _onToggle(LyricsProvider provider, bool value) {
    if (!value && _isLastEnabled(provider)) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least one lyric provider must remain active.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      if (value) {
        _enabled.add(provider);
      } else {
        _enabled.remove(provider);
      }
    });
    _lyricsService.setProviderEnabled(provider, value);
    _markChanged();
  }

  void _onReset() {
    HapticFeedback.mediumImpact();
    final music = Provider.of<MusicProvider>(context, listen: false);
    unawaited(music.setPrioritizeSyllableSync(
      LyricsService.prioritizeSyllableDefault,
    ));
    _lyricsService.resetProvidersToDefault().then((_) {
      _markChanged();
      if (mounted) {
        setState(() {
          _loadProviders();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accentController =
        Provider.of<AccentController>(context, listen: false);
    final accentColor = accentController.accent;

    if (widget.isMaterialYou) {
      return _buildMaterialYouLayout(context, accentColor);
    }
    return _buildLiquidGlassLayout(context, accentColor);
  }

  /// The bottom padding that keeps the last row clear of the gesture bar and
  /// anything drawn over the sheet's foot.
  double _footPadding(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom + 12;

  Widget _buildLiquidGlassLayout(BuildContext context, Color accentColor) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF14151C).withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 32,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, _footPadding(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pull handle - visual only; the built-in sheet drag owns the
            // gesture.
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title and Reset action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lyric Providers',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sources are tried in this order. Drag to reorder them. '
                        'The first source with lyrics wins unless syllable '
                        'lyrics are prioritized.',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _onReset,
                  icon: Icon(Icons.restart_alt_rounded,
                      size: 16, color: accentColor),
                  label: Text(
                    'Reset',
                    style: GoogleFonts.plusJakartaSans(
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    backgroundColor: accentColor.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // The word-sync preference, HERE rather than only in Settings.
            //
            // It is a property of how this list is consulted, so it belongs next to
            // the list - and the reference puts it inside its sources dialog
            // (`LyricsSourcesDialog.kt:194`). A reader who has just spent effort
            // ordering these sources is exactly the person deciding whether to
            // spend more network time per track to get better timings, and the
            // Settings copy cannot see the list it is talking about.
            _buildPrioritizeRow(context, accentColor),
            _buildApiKeyRow(context, accentColor),
            const SizedBox(height: 12),

            // Reorderable list
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                      width: 0.6,
                    ),
                  ),
                  child: ReorderableListView.builder(
                    key: _reorderListKey,
                    // Natural height up to the sheet's cap, then it scrolls.
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: _providers.length,
                    onReorderItem: _onReorder,
                    proxyDecorator: (child, index, animation) => Material(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      elevation: 6,
                      child: child,
                    ),
                    itemBuilder: (context, index) {
                      _reorderPosition ??= Scrollable.maybeOf(context)?.position;
                      return _glassRow(context, index, accentColor);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassRow(BuildContext context, int index, Color accentColor) {
    final provider = _providers[index];
    final isEnabled = _enabled.contains(provider);
    final needsKey = provider.requiresApiKey && !_lyricsService.hasPaxSenixKey;

    return GestureDetector(
      key: ValueKey(provider),
      behavior: HitTestBehavior.opaque,
      // Tapping the row toggles it, as in the reference.
      onTap: () => _onToggle(provider, !isEnabled),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: index < _providers.length - 1
              ? Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.05),
                    width: 0.6,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            // Drag Handle
            ReorderableDragStartListener(
              index: index,
              // Feeds the edge scroll: the finger's position is what tells the
              // list whether there is more this way. Without it, dragging the
              // last row up is impossible - the finger reaches the top of the
              // viewport long before the row does.
              child: _DragPositionReporter(
                onMove: _updateEdgeScroll,
                onEnd: _stopEdgeScroll,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: Colors.white.withValues(alpha: 0.4),
                    size: 22,
                  ),
                ),
              ),
            ),

            // Provider Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          provider.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: isEnabled
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (index == 0 && isEnabled) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'PRIMARY',
                            style: GoogleFonts.plusJakartaSans(
                              color: accentColor,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    needsKey
                        ? '${provider.description} \u00b7 API key required'
                        : provider.description,
                    style: GoogleFonts.plusJakartaSans(
                      color: isEnabled
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.25),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Enable/Disable Toggle. The last enabled source is shown dimmed:
            // it cannot be switched off, and the dim says so before the tap
            // does.
            Opacity(
              opacity: _isLastEnabled(provider) ? 0.5 : 1,
              child: LiquidSwitch(
                value: isEnabled,
                onChanged: (val) => _onToggle(provider, val),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Prioritize syllable lyrics", shared by both sheet layouts.
  ///
  /// One builder for both, because a control that exists in one theme and not the
  /// other is a control that is missing for whoever uses that theme.
  Widget _buildPrioritizeRow(
    BuildContext context,
    Color accentColor, {
    bool materialYou = false,
  }) {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        provider.setPrioritizeSyllableSync(!provider.prioritizeSyllableSync);
        _markChanged();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prioritize syllable lyrics',
                    style: materialYou
                        ? MaterialYouTypography.titleMedium(
                            colorScheme.onSurface,
                          )
                        : GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Keep searching past a line-synced match for '
                    'word-by-word lyrics',
                    style: materialYou
                        ? MaterialYouTypography.bodySmall(
                            colorScheme.onSurfaceVariant,
                          )
                        : GoogleFonts.plusJakartaSans(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Watched, so a tap on the row and a tap on the switch both show.
            Selector<MusicProvider, bool>(
              selector: (_, p) => p.prioritizeSyllableSync,
              builder: (context, value, _) => Switch(
                value: value,
                onChanged: (v) {
                  provider.setPrioritizeSyllableSync(v);
                  _markChanged();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "PaxSenix API key - optional", shared by both layouts.
  ///
  /// The keyed Spotify and Musixmatch sources need the listener's own key; with
  /// none they are listed, disabled and never asked. The key lives in the
  /// platform keystore and is never shown back: the dialog opens empty.
  Widget _buildApiKeyRow(
    BuildContext context,
    Color accentColor, {
    bool materialYou = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<bool>(
      valueListenable: _lyricsService.paxSenixKeyConfigured,
      builder: (context, configured, _) {
        return InkWell(
          onTap: () => _editApiKey(context, configured),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PaxSenix API key',
                        style: materialYou
                            ? MaterialYouTypography.titleMedium(
                                colorScheme.onSurface,
                              )
                            : GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Optional \u00b7 ${configured ? 'configured' : 'not configured'}',
                        style: materialYou
                            ? MaterialYouTypography.bodySmall(
                                colorScheme.onSurfaceVariant,
                              )
                            : GoogleFonts.plusJakartaSans(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  configured ? Icons.key_rounded : Icons.key_off_rounded,
                  size: 20,
                  color: materialYou
                      ? colorScheme.onSurfaceVariant
                      : Colors.white.withValues(alpha: configured ? 0.8 : 0.4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editApiKey(BuildContext context, bool configured) async {
    HapticFeedback.selectionClick();
    final result = await showDialog<_ApiKeyAction>(
      context: context,
      builder: (_) => _ApiKeyDialog(configured: configured),
    );
    if (result == null) return;
    switch (result) {
      case _SaveKey(:final key):
        await _lyricsService.setPaxSenixKey(key);
        // Saving a key switches the two keyed sources on.
        if (mounted) setState(_loadProviders);
      case _ClearKey():
        await _lyricsService.setPaxSenixKey('');
    }
    _markChanged();
  }

  Widget _buildMaterialYouLayout(BuildContext context, Color accentColor) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: const BoxDecoration(
        color: MaterialYouTokens.surfaceContainerDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, _footPadding(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lyric Providers',
                        style: MaterialYouTypography.headlineMedium(
                            colorScheme.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sources are tried in this order. Drag to reorder them. '
                        'The first source with lyrics wins unless syllable '
                        'lyrics are prioritized.',
                        style: MaterialYouTypography.bodySmall(
                            colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _onReset,
                  child: Text('Reset',
                      style: TextStyle(color: colorScheme.primary)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildPrioritizeRow(
              context,
              colorScheme.primary,
              materialYou: true,
            ),
            _buildApiKeyRow(
              context,
              colorScheme.primary,
              materialYou: true,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ReorderableListView.builder(
                  key: _reorderListKey,
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: _providers.length,
                  onReorderItem: _onReorder,
                  itemBuilder: (context, index) {
                    _reorderPosition ??= Scrollable.maybeOf(context)?.position;
                    final provider = _providers[index];
                    final isEnabled = _enabled.contains(provider);
                    final needsKey = provider.requiresApiKey &&
                        !_lyricsService.hasPaxSenixKey;

                    return ListTile(
                      key: ValueKey(provider),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      onTap: () => _onToggle(provider, !isEnabled),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: _DragPositionReporter(
                          onMove: _updateEdgeScroll,
                          onEnd: _stopEdgeScroll,
                          child: Icon(Icons.drag_indicator_rounded,
                              color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      title: Text(
                        provider.displayName,
                        style: TextStyle(
                          color: isEnabled
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withValues(alpha: 0.38),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        needsKey
                            ? '${provider.description} \u00b7 API key required'
                            : provider.description,
                        style: TextStyle(
                          color: isEnabled
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.38),
                          fontSize: 12,
                        ),
                      ),
                      trailing: Switch(
                        value: isEnabled,
                        activeThumbColor: MaterialYouTokens.primaryVibrant,
                        onChanged: (val) => _onToggle(provider, val),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// API key dialog
// =============================================================================

sealed class _ApiKeyAction {
  const _ApiKeyAction();
}

class _SaveKey extends _ApiKeyAction {
  const _SaveKey(this.key);
  final String key;
}

class _ClearKey extends _ApiKeyAction {
  const _ClearKey();
}

/// A password-style field for the PaxSenix key: Save / Cancel / Clear.
///
/// Opens EMPTY even when a key is stored. A secret that can be read back out of
/// a settings screen is a secret over a shoulder; to replace it, type the new
/// one, and to remove it, Clear.
class _ApiKeyDialog extends StatefulWidget {
  const _ApiKeyDialog({required this.configured});

  final bool configured;

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PaxSenix API key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Optional. Unlocks the PaxSenix Spotify and Musixmatch sources. '
            'It is kept in the device keystore and never shown again.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.configured ? 'Replace the saved key' : 'API key',
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show key' : 'Hide key',
                icon: Icon(_obscure
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        if (widget.configured)
          TextButton(
            onPressed: () => Navigator.of(context).pop(const _ClearKey()),
            child: const Text('Clear'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(_SaveKey(key));
  }
}
