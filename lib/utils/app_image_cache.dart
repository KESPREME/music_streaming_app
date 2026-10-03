
/// Centralized image cache sizing and memory bounds.
/// Downsamples decoded bitmaps in GPU/RAM memory to prevent high memory usage,
/// garbage collection pauses, and OOMs on low- and high-end devices.
abstract final class AppImageCache {
  /// Thumbnail size for miniplayer, search results, queue items, and compact list tiles.
  /// Decodes at 160x160 (~100 KB in RAM instead of full 5.76 MB raw bitmap).
  static const int thumbnailMemCache = 160;

  /// Card size for shelf carousels, home grids, and library album art.
  /// Decodes at 400x400 (~640 KB in RAM).
  static const int cardMemCache = 400;

  /// Hero size for Now Playing screen, explore full card artwork, and album headers.
  /// Decodes at 800x800 (~2.5 MB in RAM).
  static const int heroMemCache = 800;
}
