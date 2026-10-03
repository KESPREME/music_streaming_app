
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

  /// The shared-element artwork on its way between the hero and the mini pill.
  ///
  /// This is the size that actually matters for smoothness. The pill is 46dp,
  /// but it used to render an [heroMemCache] (800px) bitmap and let the GPU
  /// resample it down on every frame of the flight - 120 times a second - while
  /// a second 800px copy for the hero was alive at the same time. 256 keeps the
  /// smallest copy sharp at pill scale and roughly 10x cheaper to sample.
  static const int morphMemCache = 256;
}
