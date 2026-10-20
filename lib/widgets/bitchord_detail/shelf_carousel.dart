import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../theme/app_font.dart';

import '../../models/bitchord_page_models.dart';
import '../../utils/app_image_cache.dart';
import '../themed_album_detail_screen.dart';
import '../themed_artist_detail_screen.dart';
import '../themed_playlist_detail_screen.dart';

/// Horizontal carousel shelf for artist discography, featured playlists, and related artists
/// matching BitChord DetailScreen.kt and Screenshots 4, 5, 6.
class ShelfCarousel extends StatelessWidget {
  final DetailShelf shelf;
  final String? artistNameHint;

  /// More items than the row shows at a glance: a "Show all" grid.
  static const int showAllThreshold = 5;

  const ShelfCarousel({
    super.key,
    required this.shelf,
    this.artistNameHint,
  });

  @override
  Widget build(BuildContext context) {
    if (shelf.items.isEmpty) return const SizedBox.shrink();
    final canShowAll = shelf.items.length > showAllThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 12.0, top: 22.0, bottom: 10.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  shelf.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.style(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (canShowAll)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ShelfGridScreen(shelf: shelf, artistNameHint: artistNameHint),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.72),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    'Show all',
                    style: AppFont.style(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 228,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            itemCount: shelf.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final item = shelf.items[index];
              return _ShelfCard(
                item: item,
                artistNameHint: artistNameHint,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ShelfCard extends StatelessWidget {
  final DetailShelfItem item;
  final String? artistNameHint;

  const _ShelfCard({
    required this.item,
    this.artistNameHint,
  });

  @override
  Widget build(BuildContext context) {
    return _ShelfCardBody(item: item, width: 154.0, artistNameHint: artistNameHint);
  }
}

/// Opens what a shelf card points at: an artist, a playlist, or a release.
void openDetailShelfItem(BuildContext context, DetailShelfItem item, {String? artistNameHint}) {
        final nav = Navigator.of(context);
        if (item.type == 'artist') {
          nav.push(
            MaterialPageRoute(
              builder: (_) => ThemedArtistDetailScreen(
                artistId: item.browseId,
                artistName: item.title,
                artistImage: item.imageUrl,
              ),
            ),
          );
        } else if (item.type == 'playlist') {
          nav.push(
            MaterialPageRoute(
              builder: (_) => ThemedPlaylistDetailScreen(
                playlistId: item.browseId,
                playlistName: item.title,
                playlistImage: item.imageUrl,
                artistNameHint: artistNameHint,
              ),
            ),
          );
        } else {
          // Album or Single
          nav.push(
            MaterialPageRoute(
              builder: (_) => ThemedAlbumDetailScreen(
                albumId: item.browseId,
                albumName: item.title,
                artistName: artistNameHint,
                albumImage: item.imageUrl,
              ),
            ),
          );
        }
}

class _ShelfCardBody extends StatelessWidget {
  final DetailShelfItem item;
  final double width;
  final String? artistNameHint;

  const _ShelfCardBody({required this.item, required this.width, this.artistNameHint});

  @override
  Widget build(BuildContext context) {
    final cardWidth = width;
    return GestureDetector(
      onTap: () => openDetailShelfItem(context, item, artistNameHint: artistNameHint),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artwork / Thumbnail (Squircle for all, matching BitChord's 10dp radius)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: cardWidth,
                height: cardWidth,
                color: Colors.white.withValues(alpha: 0.08),
                child: item.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: item.imageUrl,
                        memCacheWidth: AppImageCache.cardMemCache,
                        memCacheHeight: AppImageCache.cardMemCache,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(
                          Icons.album_rounded,
                          color: Colors.white38,
                          size: 40,
                        ),
                      )
                    : const Icon(
                        Icons.album_rounded,
                        color: Colors.white38,
                        size: 40,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFont.style(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            // Subtitle
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFont.style(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every item of a shelf as a two-column grid ("Show all").
class ShelfGridScreen extends StatelessWidget {
  final DetailShelf shelf;
  final String? artistNameHint;

  const ShelfGridScreen({super.key, required this.shelf, this.artistNameHint});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          shelf.title,
          style: AppFont.style(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const gutter = 20.0;
          const gap = 14.0;
          final cardW = (constraints.maxWidth - gutter * 2 - gap) / 2;
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 120),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: gap,
              mainAxisSpacing: 18,
              // Square art + 8 gap + two caption lines.
              childAspectRatio: cardW / (cardW + 56),
            ),
            itemCount: shelf.items.length,
            itemBuilder: (context, i) => _ShelfCardBody(
              item: shelf.items[i],
              width: cardW,
              artistNameHint: artistNameHint,
            ),
          );
        },
      ),
    );
  }
}