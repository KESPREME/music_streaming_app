import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  const ShelfCarousel({
    super.key,
    required this.shelf,
    this.artistNameHint,
  });

  @override
  Widget build(BuildContext context) {
    if (shelf.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 22.0, bottom: 10.0),
          child: Text(
            shelf.title,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
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
    const cardWidth = 154.0;
    final isArtist = item.type == 'artist';

    return GestureDetector(
      onTap: () {
        final nav = Navigator.of(context);
        if (isArtist) {
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
      },
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
              style: GoogleFonts.plusJakartaSans(
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
              style: GoogleFonts.plusJakartaSans(
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
