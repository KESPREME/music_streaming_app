// lib/widgets/library/library_shelves.dart
//
// The Library's building blocks below the listening card:
//
//   * LibraryQuickTile   - a destination (Liked Songs, Downloaded...): a tinted
//                          glass squircle, its name, and a live count.
//   * LibraryShelfHeader - a shelf title with a "See all" that leads somewhere.
//   * LibraryRail        - a horizontal shelf of artwork.
//   * LibraryArtCard / LibraryArtistCard / LibraryPlaylistCard / LibraryNewPlaylistCard
//
// Artwork is the content, so cards are artwork first: no plate behind them, no
// border, the image itself carries the edge. Every card presses with the same
// spring as Home (PressableScale) so the app has one touch language.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/playlist.dart';
import '../../utils/app_image_cache.dart';
import '../../utils/image_quality_utils.dart';
import '../home_sections.dart' show PressableScale;
import '../playlist/playlist_cover.dart';

const double kLibraryCardRadius = 18;

TextStyle _title() => GoogleFonts.plusJakartaSans(
      color: Colors.white,
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
    );

TextStyle _meta() => GoogleFonts.plusJakartaSans(
      color: Colors.white.withValues(alpha: 0.52),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );

// ── Quick access ───────────────────────────────────────────────────────────

class LibraryQuickTile extends StatelessWidget {
  const LibraryQuickTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  static const double width = 86;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: PressableScale(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: width,
                height: 78,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.30),
                      color.withValues(alpha: 0.08),
                    ],
                  ),
                  border: Border.all(
                    color: Color.lerp(color, Colors.white, 0.3)!
                        .withValues(alpha: 0.28),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                // The glass catches light along its top edge.
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.white.withValues(alpha: 0.10),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Icon(
                  icon,
                  size: 30,
                  color: Color.lerp(color, Colors.white, 0.18),
                ),
              ),
              const SizedBox(height: 9),
              Text(title,
                  style: _title().copyWith(fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 1),
              Text(subtitle,
                  style: _meta().copyWith(fontSize: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shelves ────────────────────────────────────────────────────────────────

class LibraryShelfHeader extends StatelessWidget {
  const LibraryShelfHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.horizontalPadding = 20,
  });

  final String title;
  final VoidCallback? onSeeAll;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 30, horizontalPadding - 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          if (onSeeAll != null)
            Semantics(
              button: true,
              label: 'See all $title',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSeeAll!();
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('See all',
                            style: _meta().copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.62))),
                        Icon(Icons.chevron_right_rounded,
                            size: 20,
                            color: Colors.white.withValues(alpha: 0.62)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A horizontal shelf. [height] is the card's full height including its text.
class LibraryRail extends StatelessWidget {
  const LibraryRail({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.horizontalPadding = 20,
    this.gap = 14,
  });

  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double horizontalPadding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        itemCount: itemCount,
        separatorBuilder: (_, __) => SizedBox(width: gap),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

// ── Cards ──────────────────────────────────────────────────────────────────

class _Art extends StatelessWidget {
  const _Art({required this.url, required this.size, this.icon = Icons.music_note_rounded, this.circle = false});

  final String url;
  final double size;
  final IconData icon;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: const Color(0xFF15171D),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white24, size: size * 0.3),
    );
    final image = url.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: ImageQualityUtils.getHighResArtwork(url),
            fit: BoxFit.cover,
            width: size,
            height: size,
            memCacheWidth: AppImageCache.cardMemCache,
            fadeInDuration: const Duration(milliseconds: 220),
            placeholder: (_, __) => placeholder,
            errorWidget: (_, __, ___) => placeholder,
          );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(kLibraryCardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: circle
          ? ClipOval(child: image)
          : ClipRRect(
              borderRadius: BorderRadius.circular(kLibraryCardRadius),
              child: image,
            ),
    );
  }
}

/// Square artwork, title, one line of meta.
class LibraryArtCard extends StatelessWidget {
  const LibraryArtCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.size = 148,
    this.icon = Icons.music_note_rounded,
    this.playing = false,
  });

  final String imageUrl;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double size;
  final IconData icon;
  final bool playing;

  /// Card height for a rail of these at [size].
  static double heightFor(double size) => size + 48;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: playing,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: PressableScale(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        onLongPress: onLongPress,
        child: SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Art(url: imageUrl, size: size, icon: icon),
              const SizedBox(height: 9),
              Text(title,
                  style: _title().copyWith(color: playing ? accent : null),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: _meta(), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class LibraryArtistCard extends StatelessWidget {
  const LibraryArtistCard({
    super.key,
    required this.imageUrl,
    required this.name,
    required this.onTap,
    this.size = 112,
  });

  final String imageUrl;
  final String name;
  final VoidCallback onTap;
  final double size;

  static double heightFor(double size) => size + 34;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$name, artist',
      excludeSemantics: true,
      child: PressableScale(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          width: size,
          child: Column(
            children: [
              _Art(url: imageUrl, size: size, icon: Icons.person_rounded, circle: true),
              const SizedBox(height: 10),
              Text(name,
                  style: _title().copyWith(fontSize: 13),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// A playlist: its cover, or a 2x2 of its first four distinct covers.
class LibraryPlaylistCard extends StatelessWidget {
  const LibraryPlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.onLongPress,
    this.size = 148,
  });

  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final n = playlist.tracks.length;
    final art = PlaylistCover(
        playlist: playlist, size: size, radius: kLibraryCardRadius, shadow: true);

    return Semantics(
      button: true,
      label: '${playlist.name}, ${n == 1 ? '1 song' : '$n songs'}',
      excludeSemantics: true,
      child: PressableScale(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        onLongPress: onLongPress,
        child: SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              art,
              const SizedBox(height: 9),
              Text(playlist.name,
                  style: _title(), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(n == 1 ? '1 song' : '$n songs',
                  style: _meta(), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// The first card of the playlists shelf: always there, so an empty library
/// still has somewhere to start.
class LibraryNewPlaylistCard extends StatelessWidget {
  const LibraryNewPlaylistCard({super.key, required this.onTap, this.size = 148});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: 'New playlist',
      excludeSemantics: true,
      child: PressableScale(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kLibraryCardRadius),
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.16),
                      border: Border.all(color: accent.withValues(alpha: 0.4)),
                    ),
                    child: Icon(Icons.add_rounded, color: accent, size: 28),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text('New playlist', style: _title(), maxLines: 1),
              const SizedBox(height: 2),
              Text('Start from scratch', style: _meta(), maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }
}
