/// Spacing scale — 4pt base. Do not invent odd values (13/17/19/23/27)
/// unless there is a specific optical justification documented inline.
abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
  static const double massive = 48;
  static const double section = 64;

  /// Horizontal screen padding for immersive content (Home, Player).
  static const double screenX = 20;

  /// Horizontal screen padding for dense screens (Library, Search, Queue).
  static const double screenDense = 16;
}

/// Semantic corner radii. Different surfaces need different geometry —
/// never give every object the same radius.
abstract final class Radii {
  /// Chips, small controls, thumbnails.
  static const double small = 10;

  /// Cards, compact tiles, artwork thumbs.
  static const double medium = 16;

  /// Hero cards, large artwork, mini-player.
  static const double large = 24;

  /// Bottom sheets.
  static const double sheet = 28;

  /// Full capsules (nav pill, search field).
  static const double pill = 999;

  /// Perfect circles (player controls, artist avatars).
  static const double circle = 999;
}

/// Semantic elevation. Depth comes primarily from transparency, blur,
/// edge definition and sharpness contrast — shadow is supplementary.
abstract final class Elevation {
  static const double grounded = 0;
  static const double card = 1;
  static const double floating = 3;
  static const double sheet = 6;
  static const double overlay = 12;
}

/// Screen-level density budgets (0–10). Tune spacing per screen against
/// these rather than forcing one spacing system everywhere.
abstract final class Density {
  static const int home = 5;
  static const int discover = 4;
  static const int library = 7;
  static const int search = 7;
  static const int queue = 8;
  static const int settings = 6;
  static const int player = 3;
  static const int lyrics = 3;
}
