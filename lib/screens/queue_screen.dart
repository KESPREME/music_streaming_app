import 'dart:io';
import 'package:flutter/material.dart' hide RepeatMode;
import '../widgets/song_sheet_plan.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../theme/app_font.dart';
import '../models/track.dart';
import '../providers/music_provider.dart';
import '../widgets/blurred_backdrop.dart';
import '../widgets/queue_transition_connector.dart';
import '../widgets/transition_chip.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/glass_options_sheet.dart';
import '../widgets/animated_equalizer_icon.dart';
import '../widgets/audio_quality_language_sheet.dart';
import '../widgets/bitchord_detail/bitchord_detail.dart';
import '../widgets/liquid_glass_pill.dart';
import '../widgets/jelly_press.dart';
import '../utils/color_utils.dart';
import '../utils/app_image_cache.dart';
import '../utils/image_quality_utils.dart';
import '../theme/amoled_theme.dart';

/// Queue / Playing Next Screen with Apple Music / Muzo liquid glass design (Image 4).
class QueueScreen extends StatelessWidget {
  final VoidCallback? onMinimize;
  final Function(int)? onTabTap;
  final bool isEmbedded;

  /// When false, the Playing Now block is omitted: the caller holds an
  /// equivalent header (the Now Playing shared-element morph overlay).
  final bool showPlayingNow;

  /// Renders the song header (art + title + star / a? / options) without the
  /// "Playing Now" label.
  ///
  /// This is the *resting* half of the queue shared-element. The morph overlay
  /// only flies the artwork and the title; when it lands it hands off to this
  /// header, which sits at the exact same rect and therefore carries the three
  /// track actions. Folding the buttons into the overlay instead would mean
  /// re-implementing them in a flying widget and would still lose them the
  /// moment the flight ends.
  final bool showMiniHeader;

  /// Wraps the header's cover, given that cover and a builder for the same
  /// image. The player uses it to let this cover dock into the mini player
  /// when it is closed from the queue.
  final Widget Function(Widget art, WidgetBuilder image)? headerArtWrapper;

  const QueueScreen({
    super.key,
    this.onMinimize,
    this.onTabTap,
    this.isEmbedded = false,
    this.showPlayingNow = true,
    this.headerArtWrapper,
    this.showMiniHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final currentTrack = musicProvider.currentTrack;
    final palette = musicProvider.paletteGenerator;
    final accentColor = ColorUtils.getVibrantAccent(
      palette,
      const Color(0xFFE89838), // Apple / Muzo gold-amber accent
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1. Blurred album art background (only when standalone)
          if (!isEmbedded) ...[
            const Positioned.fill(
              child: ColoredBox(color: Color(0xFF08080A)),
            ),
            if (currentTrack != null &&
                currentTrack.albumArtUrl.isNotEmpty &&
                backdropArtProvider(currentTrack.albumArtUrl) != null)
              Positioned.fill(
                // Baked once per track and drawn as one image - the same
                // cover-fit, blur 65 and 1.25x scale, without re-blurring the
                // screen on the GPU every frame. See blurred_backdrop.dart.
                child: BlurredBackdrop(
                  image: backdropArtProvider(currentTrack.albumArtUrl)!,
                  sigma: 65,
                  scale: 1.25,
                ),
              ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.65),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ],

          // 2. Queue content
          Positioned.fill(
            child: isEmbedded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mini header (art + title + star / a? / options).
                      // Standalone always shows it; embedded shows it only as
                      // the morph overlay's landing state.
                      if (currentTrack != null &&
                          (showPlayingNow || showMiniHeader)) ...[
                        if (showPlayingNow)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              MediaQuery.of(context).padding.top + 32.0,
                              20,
                              6,
                            ),
                            child: Text(
                              'Playing Now',
                              style: AppFont.style(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        _buildTopMiniTrackHeader(
                          context,
                          currentTrack,
                          musicProvider,
                          accentColor,
                        ),
                      ],

                      // Queue heading (BitChord parity): title + Clear.
                      _buildQueueHeadingRow(context, musicProvider),

                      // Now playing is NOT here: it is the first sliver, so it
                      // scrolls away with the queue instead of hanging above it.

                      const SizedBox(height: 8),

                      // Reorderable queue list
                      Expanded(
                        child: _buildQueueSections(
                          context,
                          currentTrack,
                          musicProvider,
                          accentColor,
                        ),
                      ),

                      const SizedBox(height: 10),
                    ],
                  )
                : SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pull handle
                        _buildPullHandle(context),

                        // Mini track card header (Image 4)
                        if (currentTrack != null)
                          _buildTopMiniTrackHeader(
                            context,
                            currentTrack,
                            musicProvider,
                            accentColor,
                          ),

                        // Queue heading (title + Clear); the mini above
                        // already covers now-playing here.
                        _buildQueueHeadingRow(context, musicProvider),

                        const SizedBox(height: 8),

                        // Reorderable queue list
                        Expanded(
                          child: _buildQueueSections(
                            context,
                            currentTrack,
                            musicProvider,
                            accentColor,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Standalone only: controls pill. The embedded page
                        // gets these from the persistent Now Playing bar.
                        _buildModePill(context, musicProvider),

                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Queue controls as one glass pill (shuffle | repeat | autoplay).
  ///
  /// Standalone sheet only: the embedded page gets these controls from the
  /// persistent Now Playing bar instead, so the queue screen never shows
  /// two control pills. Segment definitions are shared with that bar.
  Widget _buildModePill(
    BuildContext context,
    MusicProvider musicProvider,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: LiquidGlassSegmented(
        height: 44,
        segments: queueControlSegments(
          shuffleActive: musicProvider.shuffleEnabled,
          repeatActive: musicProvider.repeatMode != RepeatMode.off,
          repeatOne: musicProvider.repeatMode == RepeatMode.one,
          autoplayActive: musicProvider.autoplayEnabled,
          onShuffle: () {
            HapticFeedback.selectionClick();
            musicProvider.toggleShuffle();
          },
          onRepeat: () {
            HapticFeedback.selectionClick();
            musicProvider.cycleRepeatMode();
          },
          onAutoplay: () {
            HapticFeedback.selectionClick();
            musicProvider.toggleAutoplay();
          },
        ),
      ),
    );
  }
  /// Queue heading row (BitChord parity): big title left, Clear right.
  /// The top inset only has to clear the status bar when the page draws the
  /// landed header itself; when some host owns the header (older embedded
  /// callers) the heading sits below that floating mini instead.
  Widget _buildQueueHeadingRow(
    BuildContext context,
    MusicProvider musicProvider,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        showMiniHeader
            ? 14.0
            : (showPlayingNow
                ? 4.0
                : MediaQuery.of(context).padding.top + 90.0),
        20,
        6,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Queue',
            style: AppFont.style(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TransitionChip(settings: musicProvider.transitionSettings),
              if (musicProvider.canClearQueue) ...[
                const SizedBox(width: 8),
                JellyPress(
                  profile: JellyProfile.pill,
                  haptic: JellyHaptic.light,
                  onTap: () => _showClearDialog(context, musicProvider),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      'Clear',
                      style: AppFont.style(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Now-playing section (BitChord parity): gray label + the current row
  /// with equalizer + remove. Tap replays (same jump-to semantics as
  /// BitChord's row click); X removes like every other row.
  Widget _buildNowPlayingSection(
    BuildContext context,
    Track currentTrack,
    MusicProvider musicProvider,
    Color accentColor,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'Now playing',
              style: AppFont.style(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _buildTrackRowContent(
            context,
            currentTrack,
            currentTrack: currentTrack,
            musicProvider: musicProvider,
            accentColor: accentColor,
            showDragHandle: false,
            showEqualizer: false,
          ),
        ],
      ),
    );
  }

  Widget _buildPullHandle(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        HapticFeedback.lightImpact();
        if (onMinimize != null) {
          onMinimize!();
        } else if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: Center(
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 6),
          width: 38,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }

  Widget _buildTopMiniTrackHeader(
    BuildContext context,
    Track track,
    MusicProvider provider,
    Color accentColor,
  ) {
    final isLiked = provider.isSongLiked(track.id);
    // Landed-header geometry: the morph overlay flies the artwork to exactly
    // left 20 / statusBar + 32 / 46x46 radius 8, and the title to left 78 /
    // statusBar + 34. Reproducing those numbers here is what makes the handoff
    // invisible - anything else shows as a jump on the last frame of the flight.
    final landedHeader = showMiniHeader && isEmbedded;
    final topPadding = landedHeader
        ? MediaQuery.of(context).padding.top + 32.0
        : (isEmbedded ? 8.0 : 6.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, 4),
      child: Row(
        children: [
          // Album art thumbnail (tapping returns to normal album view)
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTabTap?.call(1);
            },
child: _wrapHeaderArt(
              ClipRRect(
                key: const ValueKey('queueHeaderArt'),
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: _buildAlbumArtImage(track),
                ),
              ),
              track,
            ),
          ),
          const SizedBox(width: 12),

          // Title & Artist (tapping returns to normal album view)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                onTabTap?.call(1);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.trackName,
                    style: AppFont.style(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artistName,
                    style: AppFont.style(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // Star button
          _buildCircleButton(
            icon: isLiked ? Icons.star_rounded : Icons.star_outline_rounded,
            iconColor: isLiked ? accentColor : Colors.white,
            semanticLabel: 'Favorite',
            onTap: () {
              HapticFeedback.lightImpact();
              provider.toggleLike(track);
            },
          ),

          const SizedBox(width: 8),

          // Multi-Language Audio & Quality Control button ("aあ")
          _buildCircleButtonWidget(
            semanticLabel: 'Pronunciation',
            child: Text(
              'aあ',
              style: AppFont.style(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              AudioQualityLanguageSheet.show(context);
            },
          ),

          const SizedBox(width: 8),

          // Options button (3 vertical dots matching Image 4)
          _buildCircleButton(
            icon: Icons.more_vert_rounded,
            iconColor: Colors.white,
            semanticLabel: 'Options',
            onTap: () {
              HapticFeedback.lightImpact();
              GlassOptionsSheet.show(
                context,
                track: track,
                isInQueueContext: true,
                origin: SongSheetOrigin.queue,
              );
            },
          ),
        ],
      ),
    );
  }


  /// The queue as sections, in the order they will actually play.
  ///
  /// Mirrors BitChord's queue: user picks, then the collection remainder, then
  /// a standalone Autoplay heading with the station. Each row carries a stable
  /// section-prefixed key (never a positional index), so when the head is
  /// consumed the surviving rows keep their identity instead of the whole list
  /// rebuilding - which is what made the old sheet flash on every track change.
  ///
  /// Motion follows the same rule as BitChord's queue: placement and
  /// insert/remove only, never cross-fades. A fading row draws its title over
  /// whatever slides through its slot, which reads as ghosting rather than
  /// movement. Drag-reorder stays inside the user section; the station is not
  /// reorderable because reordering suggestions is meaningless.
  Widget _buildQueueSections(
    BuildContext context,
    Track? currentTrack,
    MusicProvider musicProvider,
    Color accentColor,
  ) {
    final userPicks = musicProvider.queue;
    final collection = musicProvider.upcomingCollection;
    final station = musicProvider.autoplayQueue;

    final nothingQueued = userPicks.isEmpty &&
        collection.isEmpty &&
        station.isEmpty &&
        !musicProvider.autoplayEnabled;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Now playing first, and *inside* the list. BitChord emits it as
        // item(key = "header-now-playing") in the same LazyColumn (L294-320),
        // so it scrolls off with the queue; ours was pinned above the scroll
        // area and stayed put while rows slid underneath it.
        if (currentTrack != null)
          SliverToBoxAdapter(
            child: _buildNowPlayingSection(
              context,
              currentTrack,
              musicProvider,
              accentColor,
            ),
          ),

        // How the playing song will meet the next one: the join sits between
        // them. Says nothing while transitions are off.
        if (currentTrack != null)
          SliverToBoxAdapter(
            child: QueueTransitionConnector(
              upcoming: musicProvider.upcomingMix,
              settings: musicProvider.transitionSettings,
            ),
          ),

        // Empty state is a list item now, not an early return: returning it
        // would swallow the now-playing row that used to sit above the scroll
        // area. Honest either way - the song is playing, the queue is just
        // empty.
        if (nothingQueued)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(context),
          ),
        if (userPicks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeading(context, 'Next in queue'),
          ),
          _buildUserPicksSection(
            context,
            userPicks,
            currentTrack,
            musicProvider,
            accentColor,
          ),
        ],
        if (collection.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeading(
              context,
              'Next from ${musicProvider.queueSourceLabel}',
            ),
          ),
          _buildCollectionSection(
            context,
            collection,
            currentTrack,
            musicProvider,
            accentColor,
          ),
        ],
        if (station.isNotEmpty || musicProvider.autoplayEnabled)
          SliverToBoxAdapter(
            child: _buildAutoplayHeading(
              context,
              station.isNotEmpty,
              accentColor,
              musicProvider,
            ),
          ),
        if (station.isNotEmpty || musicProvider.autoplayEnabled)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverReorderableList(
              itemCount: station.length,
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                elevation: 8,
                child: child,
              ),
              itemBuilder: (context, index) {
                final track = station[index];
                return Dismissible(
                  key: ValueKey('auto_${track.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_outline,
                        color: Colors.white),
                  ),
                  onDismissed: (_) {
                    musicProvider.removeFromQueue(track);
                  },
                  child: _buildTrackRowContent(
                    context,
                    track,
                    currentTrack: currentTrack,
                    musicProvider: musicProvider,
                    accentColor: accentColor,
                    showDragHandle: true,
                    dragIndex: index,
                  ),
                );
              },
              // ignore: deprecated_member_use
              onReorder: (oldIndex, newIndex) {
                musicProvider.reorderAutoplayItem(oldIndex, newIndex);
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  /// A section divider (BitChord `QueueHeading`): titleMedium white at 75%,
  /// nothing else. Each section owns one, which is what tells the listener
  /// where the user's picks stop and the album's remaining tracks begin.
  Widget _buildSectionHeading(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: ExcludeSemantics(
        child: Text(
          title,
          style: AppFont.style(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// The curated collection still ahead of the current track.
  ///
  /// Reorderable within itself, like every other BitChord section: a drag
  /// never leaves the section, but the section is not read-only either. Rows
  /// that cannot move (no context, or only one left) fall back to plain rows
  /// so no handle is offered for a move that cannot happen.
  Widget _buildCollectionSection(
    BuildContext context,
    List<Track> collection,
    Track? currentTrack,
    MusicProvider musicProvider,
    Color accentColor,
  ) {
    final reorderable = collection.length > 1;

    Widget row(Track t, int index) {
      return Dismissible(
        key: ValueKey('ctx_${t.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        onDismissed: (_) {
          musicProvider.removeFromQueue(t);
        },
        child: _buildTrackRowContent(
          context,
          t,
          currentTrack: currentTrack,
          musicProvider: musicProvider,
          accentColor: accentColor,
          showDragHandle: reorderable,
          dragIndex: reorderable ? index : null,
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: reorderable
          ? SliverReorderableList(
              itemCount: collection.length,
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                elevation: 8,
                child: child,
              ),
              itemBuilder: (context, index) => row(collection[index], index),
              // ignore: deprecated_member_use
              onReorder: (oldIndex, newIndex) {
                musicProvider.reorderCollectionItem(oldIndex, newIndex);
              },
            )
          : SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => row(collection[index], index),
                childCount: collection.length,
              ),
            ),
    );
  }

  /// The listener's own picks. Indices map 1:1 onto the user queue (the list
  /// used to mix station rows in, so a reorder could corrupt the queue order),
  /// and a drag stays inside the section.
  Widget _buildUserPicksSection(
    BuildContext context,
    List<Track> userPicks,
    Track? currentTrack,
    MusicProvider musicProvider,
    Color accentColor,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      sliver: SliverReorderableList(
        itemCount: userPicks.length,
        proxyDecorator: (child, index, animation) => Material(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          elevation: 8,
          child: child,
        ),
        itemBuilder: (context, index) {
          final track = userPicks[index];
          return Dismissible(
            key: ValueKey('user_${track.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            onDismissed: (_) {
              musicProvider.removeFromQueue(track);
            },
            child: _buildTrackRowContent(
              context,
              track,
              currentTrack: currentTrack,
              musicProvider: musicProvider,
              accentColor: accentColor,
              showDragHandle: true,
              dragIndex: index,
            ),
          );
        },
        // ignore: deprecated_member_use
        onReorder: (oldIndex, newIndex) {
          musicProvider.reorderQueueItem(oldIndex, newIndex);
        },
      ),
    );
  }

/// The Autoplay heading as its own item with its own key - never glued onto
  /// the first station row. Previously it was rendered inside the first row's
  /// Column, which made it read as a label *for that song* instead of as the
  /// section divider it is.
  ///
  /// It is also the toggle. The pill in the player deck carries Autoplay too,
  /// but that deck is the first thing a finger-scroll collapses, so a queue that
  /// only offers Autoplay from down there is a queue where the station looks
  /// permanently switched off. Tapping here is the same
  /// [MusicProvider.toggleAutoplay] the pill calls - one state, two doors.
  Widget _buildAutoplayHeading(
    BuildContext context,
    bool hasTracks,
    Color accentColor,
    MusicProvider musicProvider,
  ) {
    final enabled = musicProvider.autoplayEnabled;
    final sublabel = enabled
        ? (hasTracks ? 'Similar tracks' : 'Finding similar tracks...')
        : 'Off - tap to turn on';

    return Padding(
      key: const ValueKey('autoplay-heading'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Semantics(
        label: 'Autoplay',
        button: true,
        toggled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            musicProvider.toggleAutoplay();
          },
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: enabled
                      ? accentColor.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.all_inclusive_rounded,
                  size: 14,
                  color: enabled ? accentColor : Colors.white54,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Autoplay',
                style: AppFont.style(
                  color: enabled ? Colors.white : Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  sublabel,
                  style: AppFont.style(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              // Explicit state, so the control does not rely on the icon tint
              // alone to say whether the station is running.
              Icon(
                enabled ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 16,
                color: enabled
                    ? accentColor
                    : Colors.white.withValues(alpha: 0.28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One queue row's content: art, equalizer when current, title, artist, and
  /// an optional drag handle. No key and no Dismissible here - the caller owns
  /// identity and swipe because user, collection and station rows differ.
  Widget _buildTrackRowContent(
    BuildContext context,
    Track track, {
    required Track? currentTrack,
    required MusicProvider musicProvider,
    required Color accentColor,
    required bool showDragHandle,
    int? dragIndex,
    // The equalizer is a perpetual animation. Only one instance may run at a
    // time (the held morph header owns it while embedded); extras hang
    // pumpAndSettle and cost a frame per bar forever.
    bool showEqualizer = true,
  }) {
    final bool isCurrent = currentTrack?.id == track.id;
    final bool isActuallyPlaying = isCurrent && musicProvider.isPlaying;
    final bool isAutoplay = musicProvider.isAutoplayTrack(track.id);

    return Container(
      key: ValueKey('container_${track.id}'),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      // No card, no fill, no border - not even for the current track. BitChord
      // keeps every row transparent and marks "now playing" with the title
      // colour plus the eq glyph alone (InlineQueueRow L711/L756/L766). A
      // highlight here read as a selected card and, because the row is a
      // duplicate of the one under the header, looked like a second selection.
      decoration: const BoxDecoration(),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 48,
              height: 48,
              child: _buildAlbumArtImage(track),
            ),
          ),
          const SizedBox(width: 12),
          if (isCurrent && showEqualizer) ...[
            AnimatedEqualizerIcon(
              isPlaying: isActuallyPlaying,
              color: accentColor,
              size: 16,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                try {
                  await musicProvider.playTrack(
                    track,
                    setContext: false,
                    clearQueue: false,
                  );
                } catch (error) {
                  if (context.mounted) {
                    showGlassSnackBar(
                      context,
                      'Could not play ${track.trackName}',
                    );
                  }
                }
              },
child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Explicit marker rides on the title line, same as search,
                    // album detail and playlist detail. A bare title here read
                    // as a clean song when it was not.
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.trackName,
                            style: AppFont.style(
                              // Current track: full white, matching BitChord's
                              // isCurrent branch rather than an accent tint.
                              color: isCurrent
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.92),
                              fontSize: 15,
                              fontWeight:
                                  isCurrent ? FontWeight.bold : FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (track.isExplicit) ...[
                          const SizedBox(width: 6),
                          const BitchordExplicitBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                  Row(
                    children: [
                      if (isAutoplay) ...[
                        Icon(
                          Icons.all_inclusive_rounded,
                          size: 12,
                          color: accentColor.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          track.artistName,
                          style: AppFont.style(
                            color: Colors.white.withValues(alpha: 0.60),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (showDragHandle && dragIndex != null)
            ReorderableDragStartListener(
              index: dragIndex,
              child: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: Color(0xB3FFFFFF),
                  size: 22,
                ),
              ),
            ),
          // Visible remove affordance (BitChord parity - the same op as
          // the swipe): every row carries its X, current included.
          Semantics(
            label: 'Remove from queue',
            button: true,
            child: JellyPress(
              profile: JellyProfile.icon,
              haptic: JellyHaptic.light,
              onTap: () => musicProvider.removeFromQueue(track),
              child: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Icon(
                  Icons.close_rounded,
                  color: Color(0x99FFFFFF),
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color iconColor,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      // The callers play their own haptic (as before); the jelly adds none.
      child: JellyPress(
        profile: JellyProfile.circle,
        haptic: JellyHaptic.none,
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }

  Widget _buildCircleButtonWidget({
    required Widget child,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: JellyPress(
        profile: JellyProfile.circle,
        haptic: JellyHaptic.none,
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _wrapHeaderArt(Widget art, Track track) {
    final wrap = headerArtWrapper;
    if (wrap == null) return art;
    return wrap(art, (_) => _buildAlbumArtImage(track));
  }

  Widget _buildAlbumArtImage(Track track) {
    final rawArt = track.albumArtUrl;
    if (rawArt.isEmpty) return _buildArtPlaceholder();
    final art = ImageQualityUtils.getHighResArtwork(rawArt);
    if (!art.contains('://')) {
      final f = File(art);
      // Decoded at the row's size: a 48dp thumbnail does not need the file's
      // full resolution in memory.
      if (f.existsSync()) {
        return Image.file(
          f,
          fit: BoxFit.cover,
          cacheWidth: AppImageCache.thumbnailMemCache,
        );
      }
    }
    return CachedNetworkImage(
      imageUrl: art,
      fit: BoxFit.cover,
      memCacheWidth: AppImageCache.thumbnailMemCache,
      memCacheHeight: AppImageCache.thumbnailMemCache,
      errorWidget: (_, __, ___) => _buildArtPlaceholder(),
    );
  }

  Widget _buildArtPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Icon(Icons.music_note, color: Colors.white30, size: 20),
      ),
    );
  }

  /// Honest empty state. It is only reachable when the station is off too:
  /// with autoplay enabled there is a real section to show, and swallowing it
  /// behind "Queue is empty" is exactly how the Autoplay block went missing
  /// for a queue whose station had not produced a track yet.
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.queue_music_rounded,
            size: 56,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Queue is empty',
            style: AppFont.style(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Songs you play next will appear here',
            style: AppFont.style(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context, MusicProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AmoledTheme.surfaceOf(ctx, const Color(0xFF1E1E1E)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: AmoledTheme.edge(ctx),
        ),
        title: Text(
          'Clear Queue?',
          style: AppFont.style(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to clear all upcoming songs?',
          style: AppFont.style(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: AppFont.style(color: Colors.white60),
            ),
          ),
          TextButton(
            onPressed: () {
              provider.clearQueue();
              Navigator.pop(ctx);
              showGlassSnackBar(context, 'Queue cleared');
            },
            child: Text(
              'Clear',
              style: AppFont.style(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
