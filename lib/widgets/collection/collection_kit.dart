// lib/widgets/collection/collection_kit.dart
//
// THE COLLECTION KIT - the pieces every "list of songs / playlists" screen in
// the Library is made of, so Liked Songs, Your Playlists, a playlist and
// History look and behave as one family:
//
//   nav bar with a collapsing title and a selection mode, glass pills, search
//   field, sort row, filter chips, the song row (tap to play, swipe to queue or
//   remove, long-press to select, equalizer on the playing song), the selection
//   action bar, empty / no-match states, a fade-in for changing results, and
//   the toast + bottom clearance that keep feedback above the mini player.
//
// Everything here is presentation. What a row does is decided by the screen.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../jelly_icon_button.dart';
import 'package:flutter/services.dart';
import '../../theme/app_font.dart';

import '../../models/track.dart';
import '../../theme/glass_tokens.dart';
import '../../utils/app_image_cache.dart';
import '../../utils/image_quality_utils.dart';
import '../glass_circle_button.dart';
import '../glass_surface.dart';
import '../jelly_press.dart';
import '../home_sections.dart' show PressableScale;

/// Tokens shared by the collection screens.
abstract final class CollectionStyle {
  /// The one crimson: "what is playing", destructive remove, pins.
  static const Color accent = Color(0xFFFF3B5C);
  static const Color accentDeep = Color(0xFFB0193D);
  static const double gutter = 20;
  static const double art = 56;
  static const double heroArt = 124;
  static const double pill = 52;

  static TextStyle title(double size, {FontWeight w = FontWeight.w800}) =>
      AppFont.style(
        color: Colors.white,
        fontSize: size,
        fontWeight: w,
        letterSpacing: -size * 0.02,
      );

  static TextStyle meta({double size = 13.5, double alpha = 0.55, FontWeight w = FontWeight.w500}) =>
      AppFont.style(
        color: Colors.white.withValues(alpha: alpha),
        fontSize: size,
        fontWeight: w,
      );
}

/// Space to leave under a scrolling list so the last row clears the mini player
/// and the nav bar.
double collectionBottomClearance(BuildContext context) =>
    GlassTokens.playerBottomInset +
    GlassTokens.playerPillHeight +
    20 +
    MediaQuery.paddingOf(context).bottom;

/// A floating confirmation that sits above the mini player. With an [action]
/// (Undo) it stays long enough to use.
void showCollectionToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_rounded,
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.fromLTRB(16, 0, 16, collectionBottomClearance(context) - 8),
    duration: Duration(milliseconds: action == null ? 1600 : 5000),
    content: Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: CollectionStyle.meta(size: 14, alpha: 0.95, w: FontWeight.w600)),
        ),
      ],
    ),
    action: action,
  ));
}

/// A modal bottom sheet in the app's glass: handle, then [children].
Future<T?> showCollectionSheet<T>(
  BuildContext context,
  List<Widget> Function(BuildContext sheet) children, {
  bool scrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: scrollControlled,
    builder: (sheet) => GlassSurface(
      tier: GlassTier.chrome,
      borderRadius: 24,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHandle(),
                const SizedBox(height: 14),
                ...children(sheet),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// One 52 dp row of a sheet: icon, label, optional check.
class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.checked = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool checked;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? CollectionStyle.accent : Colors.white;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 52,
      leading: Icon(icon, color: color.withValues(alpha: checked ? 1 : 0.75)),
      title: Text(label,
          style: CollectionStyle.meta(size: 15, alpha: checked ? 1 : 0.88, w: checked ? FontWeight.w700 : FontWeight.w500)
              .copyWith(color: destructive ? CollectionStyle.accent : null)),
      trailing: checked ? const Icon(Icons.check_rounded, color: Colors.white) : null,
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}

// ── Nav bar ────────────────────────────────────────────────────────────────

/// The top bar: back + breadcrumb that becomes the title as the page scrolls,
/// optional [actions], an overflow button, and a selection mode.
class CollectionNavBar extends StatelessWidget {
  const CollectionNavBar({
    super.key,
    required this.scroll,
    required this.topInset,
    required this.title,
    required this.onBack,
    this.backLabel = 'Library',
    this.onMore,
    this.actions = const [],
    this.selecting = false,
    this.selectedCount = 0,
    this.allSelected = false,
    this.onEndSelection,
    this.onSelectAll,
    this.titleAppearsAt = 70,
  });

  final ScrollController scroll;
  final double topInset;
  final String title;
  final String backLabel;
  final VoidCallback onBack;
  final VoidCallback? onMore;
  final List<Widget> actions;
  final bool selecting;
  final int selectedCount;
  final bool allSelected;
  final VoidCallback? onEndSelection;
  final VoidCallback? onSelectAll;

  /// Scroll offset at which the small title starts to arrive.
  final double titleAppearsAt;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, _) {
        final offset = scroll.hasClients ? scroll.offset : 0.0;
        final scrim = (offset / 60).clamp(0.0, 1.0);
        final titleIn = ((offset - titleAppearsAt) / 50).clamp(0.0, 1.0);
        return Container(
          padding: EdgeInsets.fromLTRB(12, topInset + 8, 12, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.92 * scrim),
                Colors.black.withValues(alpha: 0.75 * scrim),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06 * scrim), width: 0.6),
            ),
          ),
          child: SizedBox(
            height: 48,
            child: AnimatedSwitcher(
              duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
              child: selecting
                  ? Row(
                      key: const ValueKey('select'),
                      children: [
                        GlassCircleButton(
                          icon: Icons.close_rounded,
                          size: 44,
                          iconSize: 22,
                          semanticLabel: 'Done selecting',
                          onTap: onEndSelection ?? () {},
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text('$selectedCount selected',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(18)),
                          ),
                        ),
                        TextButton(
                          onPressed: onSelectAll,
                          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                          child: Text(allSelected ? 'Deselect all' : 'Select all',
                              style: CollectionStyle.meta(size: 14.5, alpha: 0.9, w: FontWeight.w700)),
                        ),
                      ],
                    )
                  : Row(
                      key: const ValueKey('nav'),
                      children: [
                        GlassCircleButton(
                          icon: Icons.arrow_back_rounded,
                          size: 44,
                          iconSize: 22,
                          semanticLabel: 'Back to $backLabel',
                          onTap: onBack,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              Opacity(
                                opacity: 1 - titleIn,
                                child: ExcludeSemantics(
                                  child: Text(backLabel,
                                      maxLines: 1, style: CollectionStyle.meta(size: 16, alpha: 0.6, w: FontWeight.w600)),
                                ),
                              ),
                              Opacity(
                                opacity: titleIn,
                                child: Transform.translate(
                                  offset: Offset(0, 6 * (1 - titleIn)),
                                  child: Text(title,
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.title(18)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (final a in actions) ...[a, const SizedBox(width: 8)],
                        if (onMore != null)
                          GlassCircleButton(
                            icon: Icons.more_vert_rounded,
                            size: 44,
                            iconSize: 22,
                            semanticLabel: 'More options',
                            onTap: onMore!,
                          ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

// ── Pills, search, sort, chips ─────────────────────────────────────────────

class CollectionPill extends StatelessWidget {
  const CollectionPill({
    super.key,
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.black : Colors.white;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          height: CollectionStyle.pill,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: filled
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFFFFF), Color(0xFFE6E6EA)],
                  )
                : null,
            color: filled ? null : Colors.white.withValues(alpha: 0.07),
            border: Border.all(color: Colors.white.withValues(alpha: filled ? 0 : 0.14), width: 0.8),
            boxShadow: filled
                ? [BoxShadow(color: Colors.white.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 6))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(icon, key: ValueKey(icon), color: fg, size: 24),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.style(color: fg, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CollectionSearchField extends StatelessWidget {
  const CollectionSearchField({
    super.key,
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.hint,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 0, CollectionStyle.gutter, 6),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.8),
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.6), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  cursorColor: CollectionStyle.accent,
                  style: CollectionStyle.meta(size: 15.5, alpha: 0.95),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: CollectionStyle.meta(size: 15.5, alpha: 0.45),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                JellyIconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.cancel_rounded, color: Colors.white.withValues(alpha: 0.55), size: 20),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              else
                const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Recently added ⌄" on the left, [trailing] (a filter or view toggle) on the
/// right.
class CollectionSortRow extends StatelessWidget {
  const CollectionSortRow({super.key, required this.label, required this.onSort, this.trailing});

  final String label;
  final VoidCallback onSort;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter - 8, 2, CollectionStyle.gutter - 4, 2),
      child: Row(
        children: [
          Flexible(
            child: Semantics(
            button: true,
            label: 'Sort: $label',
            excludeSemantics: true,
            // Opens a sheet, which is a navigation rather than a state change, so
            // it stays silent like the rest of the sheet openers.
            child: JellyPress(
              profile: JellyProfile.pill,
              haptic: JellyHaptic.none,
              onTap: onSort,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CollectionStyle.meta(size: 15.5, alpha: 0.8, w: FontWeight.w600)),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withValues(alpha: 0.7)),
                    ],
                  ),
                ),
              ),
            ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class CollectionChipData {
  const CollectionChipData({required this.id, required this.label, this.icon});

  final String id;
  final String label;
  final IconData? icon;
}

class CollectionChips extends StatelessWidget {
  const CollectionChips({super.key, required this.chips, required this.selectedId, required this.onTap});

  final List<CollectionChipData> chips;
  final String? selectedId;
  final ValueChanged<CollectionChipData> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 6, CollectionStyle.gutter, 6),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = chips[i];
          final on = c.id == selectedId;
          return Semantics(
            button: true,
            selected: on,
            label: 'Filter: ${c.label}',
            excludeSemantics: true,
            child: JellyPress(
              profile: JellyProfile.pill,
              haptic: JellyHaptic.selection,
              onTap: () => onTap(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? Colors.white : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: on ? 0 : 0.10), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.icon != null) ...[
                      Icon(c.icon, size: 16, color: on ? Colors.black : Colors.white70),
                      const SizedBox(width: 6),
                    ],
                    Text(c.label,
                        style: AppFont.style(
                          color: on ? Colors.black : Colors.white.withValues(alpha: 0.85),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── The song row ───────────────────────────────────────────────────────────

class CollectionTrackRow extends StatelessWidget {
  const CollectionTrackRow({
    super.key,
    required this.track,
    required this.current,
    required this.playing,
    required this.downloaded,
    required this.selecting,
    required this.selected,
    required this.last,
    required this.onTap,
    required this.onLongPress,
    required this.onOptions,
    required this.onQueue,
    required this.onRemove,
    this.removeLabel = 'Remove',
    this.reorderHandle,
    this.swipeEnabled = true,
    this.swipeRemoveEnabled = true,
    this.subtitleOverride,
    this.artOverride,
  });

  final Track track;
  final bool current;
  final bool playing;
  final bool downloaded;
  final bool selecting;
  final bool selected;
  final bool last;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onOptions;
  final VoidCallback onQueue;
  final VoidCallback onRemove;

  /// Word on the swipe-left background.
  final String removeLabel;

  /// When set (reorder mode) it replaces the ⋮ button, and swipes are off.
  final Widget? reorderHandle;
  final bool swipeEnabled;

  /// False when removing cannot be undone (a deleted download): only the
  /// swipe-right "Queue" remains, and removal goes through a confirmation.
  final bool swipeRemoveEnabled;

  /// Replaces the artist line (e.g. "Artist · 3:42").
  final String? subtitleOverride;

  /// Replaces the network artwork (a file's embedded cover).
  final Widget? artOverride;

  Widget _swipeBg({required bool left, required Color color, required IconData icon, required String label}) {
    return Container(
      color: color,
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!left) Text(label, style: CollectionStyle.meta(size: 15, alpha: 1, w: FontWeight.w700)),
          if (!left) const SizedBox(width: 8),
          Icon(icon, color: Colors.white),
          if (left) const SizedBox(width: 8),
          if (left) Text(label, style: CollectionStyle.meta(size: 15, alpha: 1, w: FontWeight.w700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final art = track.albumArtUrl;
    final placeholder = Container(
      color: Colors.white.withValues(alpha: 0.06),
      child: const Icon(Icons.music_note_rounded, color: Colors.white24),
    );

    final songArea = Semantics(
      button: true,
      selected: selecting ? selected : current,
      label: '${track.trackName}, ${track.artistName}'
          '${current ? (playing ? ', now playing' : ', paused') : ''}',
      hint: selecting ? (selected ? 'Selected' : 'Not selected') : null,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        onLongPress: selecting || reorderHandle != null ? null : onLongPress,
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.fromLTRB(CollectionStyle.gutter, 8, 0, 8),
          child: Row(
            children: [
              AnimatedContainer(
                duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: selecting ? 36 : 0,
                height: 24,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: 36,
                    child: AnimatedSwitcher(
                      duration: reduce ? Duration.zero : const Duration(milliseconds: 140),
                      child: Icon(
                        selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        key: ValueKey(selected),
                        color: selected ? CollectionStyle.accent : Colors.white38,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: CollectionStyle.art,
                height: CollectionStyle.art,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: artOverride ?? (art.isEmpty
                      ? placeholder
                      : CachedNetworkImage(
                          imageUrl: ImageQualityUtils.getHighResArtwork(art),
                          fit: BoxFit.cover,
                          memCacheWidth: AppImageCache.thumbnailMemCache,
                          fadeInDuration: const Duration(milliseconds: 160),
                          placeholder: (_, __) => placeholder,
                          errorWidget: (_, __, ___) => placeholder,
                        )),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.trackName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CollectionStyle.title(16, w: FontWeight.w700)
                            .copyWith(color: current ? CollectionStyle.accent : Colors.white)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (track.isExplicit) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('E',
                                style: AppFont.style(
                                    color: Colors.black, fontSize: 9.5, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (downloaded) ...[
                          const Icon(Icons.download_done_rounded, size: 15, color: Color(0xFF2EB15E)),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(subtitleOverride ?? track.artistName,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: CollectionStyle.meta()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (current) ...[
                const SizedBox(width: 8),
                CollectionEqualizer(playing: playing),
              ],
            ],
          ),
        ),
      ),
    );

    final row = DecoratedBox(
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 0.6)),
      ),
      position: DecorationPosition.foreground,
      child: Row(
        children: [
          Expanded(child: songArea),
          if (reorderHandle != null)
            reorderHandle!
          else if (!selecting)
            JellyIconButton(
              tooltip: 'More options for ${track.trackName}',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(Icons.more_vert_rounded, color: Colors.white.withValues(alpha: 0.7)),
              onPressed: onOptions,
            )
          else
            const SizedBox(width: 12),
          const SizedBox(width: 4),
        ],
      ),
    );

    if (selecting || !swipeEnabled || reorderHandle != null) return row;
    return Dismissible(
      key: ValueKey('dismiss_${track.id}'),
      direction: swipeRemoveEnabled ? DismissDirection.horizontal : DismissDirection.startToEnd,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.4,
      },
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onQueue();
          return false; // springs back
        }
        return true;
      },
      onDismissed: (_) => onRemove(),
      background: _swipeBg(
          left: true, color: const Color(0xFF1F3B63), icon: Icons.queue_music_rounded, label: 'Queue'),
      secondaryBackground: swipeRemoveEnabled
          ? _swipeBg(left: false, color: CollectionStyle.accentDeep, icon: Icons.heart_broken_rounded, label: removeLabel)
          : null,
      child: row,
    );
  }
}

/// Three bars that dance while [playing] and rest (static) otherwise.
class CollectionEqualizer extends StatefulWidget {
  const CollectionEqualizer({super.key, required this.playing});

  final bool playing;

  @override
  State<CollectionEqualizer> createState() => _CollectionEqualizerState();
}

class _CollectionEqualizerState extends State<CollectionEqualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.playing && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(CollectionEqualizer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static double _wave(double t) {
    final x = t * 2 - 1;
    return 1 - 2 * x * x;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.playing ? 'Now playing' : 'Paused',
      child: SizedBox(
        width: 20,
        height: 18,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            const phases = [0.0, 0.33, 0.66];
            const rest = [0.45, 0.8, 0.6];
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 4,
                    height: 18 *
                        (_c.isAnimating
                            ? 0.3 + 0.7 * (0.5 + 0.5 * _wave((_c.value + phases[i]) % 1))
                            : rest[i]),
                    decoration: BoxDecoration(
                      color: CollectionStyle.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Selection bar ──────────────────────────────────────────────────────────

class SelectionAction {
  const SelectionAction(this.icon, this.label, this.onTap, {this.destructive = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

class CollectionSelectionBar extends StatelessWidget {
  const CollectionSelectionBar({super.key, required this.visible, required this.actions});

  final bool visible;
  final List<SelectionAction> actions;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.4),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
          child: GlassSurface(
            tier: GlassTier.floating,
            borderRadius: 22,
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  for (final a in actions)
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: a.label,
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            a.onTap();
                          },
                          child: SizedBox(
                            height: 60,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(a.icon, color: a.destructive ? CollectionStyle.accent : Colors.white, size: 22),
                                const SizedBox(height: 3),
                                Text(a.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: CollectionStyle.meta(size: 11.5, alpha: 0.9, w: FontWeight.w600)
                                        .copyWith(color: a.destructive ? CollectionStyle.accent : null)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── States ─────────────────────────────────────────────────────────────────

class CollectionEmptyState extends StatelessWidget {
  const CollectionEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String message;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, textAlign: TextAlign.center, style: CollectionStyle.title(22)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center, style: CollectionStyle.meta(size: 15, alpha: 0.6)),
          const SizedBox(height: 22),
          SizedBox(
            width: 220,
            child: CollectionPill(label: actionLabel, icon: actionIcon, filled: true, onTap: onAction),
          ),
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: onSecondary,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(secondaryLabel!,
                  style: CollectionStyle.meta(size: 14.5, alpha: 0.85, w: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

class CollectionNoMatch extends StatelessWidget {
  const CollectionNoMatch({super.key, required this.query, required this.onClear, this.noun = 'songs'});

  final String query;
  final VoidCallback onClear;

  /// What was being searched ("songs", "playlists").
  final String noun;

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 20),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(q.isEmpty ? 'No $noun match this filter' : 'No $noun match "$q"',
              textAlign: TextAlign.center, style: CollectionStyle.title(18)),
          const SizedBox(height: 6),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text('Clear search and filters',
                style: CollectionStyle.meta(size: 14.5, alpha: 0.9, w: FontWeight.w700)
                    .copyWith(color: CollectionStyle.accent)),
          ),
        ],
      ),
    );
  }
}

/// Fades its sliver in on arrival. Keyed by the query, so a new sort, filter or
/// search reads as the list settling rather than a cut.
class FadeInSliver extends StatefulWidget {
  const FadeInSliver({super.key, required this.sliver});

  final Widget sliver;

  @override
  State<FadeInSliver> createState() => _FadeInSliverState();
}

class _FadeInSliverState extends State<FadeInSliver> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SliverFadeTransition(opacity: _a, sliver: widget.sliver);
}
