import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Home design tokens (spec #68): every dimension the Home UI uses, in one
/// place. Values are proportions of available content width where the
/// layout is responsive, and logical dp where fixed.
///
/// Usage:
///   final w = HomeTokens.contentWidth(MediaQuery.sizeOf(context).width);
///   final cardW = w * HomeTokens.heroCardFraction;
abstract final class HomeTokens {
  // ── Content grid (spec #3) ──────────────────────────────────────────────
  /// Horizontal outer margin for headers, rails, grids, lists.
  static const double contentPadding = 16.0;

  /// Available content width after insets.
  static double contentWidth(double screenWidth) =>
      screenWidth - contentPadding * 2;

  // ── Spacing (spec #21/#22/#43) ──────────────────────────────────────────
  /// Gap between section header and its content.
  static const double headerToContent = 10.0;

  /// Gap between consecutive sections.
  static const double sectionGap = 30.0;

  /// Gap between cards in a rail.
  static const double cardGap = 12.0;

  /// Compact list row height (thumbnail + padding).
  static const double compactRowHeight = 64.0;

  // ── Card geometry (spec #17/#36/#37) ────────────────────────────────────
  /// Card artwork corner radius.
  static const double cardRadius = 12.0;

  /// Hero card corner radius (larger, spec #10).
  static const double heroRadius = 20.0;

  // ── Rail width fractions (of contentWidth, spec #41) ────────────────────
  /// Hero carousel card: ~88% content width, next card peeks.
  static const double heroCardFraction = 0.88;

  /// Square rail card (recent / songs / new releases).
  static const double squareCardFraction = 0.46;

  /// Playlist / mood editorial card.
  static const double playlistCardFraction = 0.38;

  /// Artist circle card.
  static const double artistCardFraction = 0.28;

  /// 16:9 video card: ~78% content width for dominant card + peek.
  static const double videoCardFraction = 0.78;

  // ── Aspect ratios (spec #17 matrix) ─────────────────────────────────────
  static const double heroAspect = 4 / 5;
  static const double squareAspect = 1.0;
  static const double videoAspect = 16 / 9;
  static const double playlistCoverAspect = 16 / 9; // landscape covers
  static const double portraitAspect = 4 / 5;

  // ── Play button (spec #13) ──────────────────────────────────────────────
  static const double heroPlaySize = 56.0;
  static const double heroPlayIconSize = 30.0;

  // ── Compact list (spec #29/#30) ─────────────────────────────────────────
  static const double compactThumbSize = 52.0;

  // ── Colors (spec #49: artwork pops, background recedes) ─────────────────
  static Color titleColor(BuildContext context) => Colors.white;
  static Color mutedColor(BuildContext context) =>
      Colors.white.withValues(alpha: 0.55);
  static Color subtleColor(BuildContext context) =>
      Colors.white.withValues(alpha: 0.35);
  static Color placeholderColor(BuildContext context) =>
      Colors.white.withValues(alpha: 0.06);

  // ── Typography scale (spec #5/#6/#45) ───────────────────────────────────
  // Deliberate hierarchy: section title > card title > metadata.
  // Hero title > normal card title. Weights create contrast, not size.
  // All styles scale with the system textScaler (spec #61).

  /// Page header "Home".
  static TextStyle homeTitle(BuildContext context) => GoogleFonts.outfit(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.1,
        color: titleColor(context),
      );

  /// Hero card title (up to 2 lines).
  static TextStyle heroTitle(BuildContext context) => GoogleFonts.outfit(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.15,
        color: titleColor(context),
      );

  /// Hero contextual label (Picked for you / eyebrow).
  static TextStyle heroLabel(BuildContext context) => GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: Colors.white.withValues(alpha: 0.75),
      );

  /// Hero artist/subtitle.
  static TextStyle heroSubtitle(BuildContext context) => GoogleFonts.outfit(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: Colors.white.withValues(alpha: 0.8),
      );

  /// Section header title.
  static TextStyle sectionTitle(BuildContext context) => GoogleFonts.outfit(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.15,
        color: titleColor(context),
      );

  /// Section description (secondary, muted).
  static TextStyle sectionDescription(BuildContext context) =>
      GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: mutedColor(context),
      );

  /// Standard card title.
  static TextStyle cardTitle(BuildContext context) => GoogleFonts.outfit(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: titleColor(context),
      );

  /// Card metadata (artist, muted — never bold).
  static TextStyle cardMetadata(BuildContext context) => GoogleFonts.outfit(
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        height: 1.25,
        color: mutedColor(context),
      );

  /// Compact list row title.
  static TextStyle compactTitle(BuildContext context) => GoogleFonts.outfit(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: titleColor(context),
      );

  /// Compact list row metadata.
  static TextStyle compactMetadata(BuildContext context) => GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: mutedColor(context),
      );
}
