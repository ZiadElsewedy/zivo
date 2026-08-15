import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// ZIVO Brand System v2 typography.
///
/// - Bricolage Grotesque — display: greeting, screen & card titles, hero numbers.
/// - Hanken Grotesk — text: rows, labels, buttons, and all data/numbers.
/// - Fraunces italic — one warm aside line per screen.
///
/// No monospace: numeric alignment comes from tabular figures on Hanken.
abstract final class AppText {
  static const _tabular = [FontFeature.tabularFigures()];

  // ---- Display (Bricolage Grotesque) ----
  static TextStyle greeting = GoogleFonts.bricolageGrotesque(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.05,
    letterSpacing: -0.68,
    color: AppColors.ink,
  );

  static TextStyle cardTitle = GoogleFonts.bricolageGrotesque(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: -0.36,
    color: AppColors.ink,
  );

  static TextStyle heroNumber = GoogleFonts.bricolageGrotesque(
    fontSize: 66,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -1.98,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  // ---- Text (Hanken Grotesk) ----
  static TextStyle dateLabel = GoogleFonts.hankenGrotesk(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.44, // 0.12em
    color: AppColors.ink3,
  );

  static TextStyle sectionLabel = GoogleFonts.hankenGrotesk(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.32, // 0.11em
    color: AppColors.ink3,
  );

  static TextStyle hueLabel = GoogleFonts.hankenGrotesk(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1, // 0.1em
  );

  static TextStyle rowTitle = GoogleFonts.hankenGrotesk(
    fontSize: 16.5,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.ink,
  );

  static TextStyle body = GoogleFonts.hankenGrotesk(
    fontSize: 14.5,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.ink2,
  );

  static TextStyle meta = GoogleFonts.hankenGrotesk(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.ink2,
    fontFeatures: _tabular,
  );

  static TextStyle amount = GoogleFonts.hankenGrotesk(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  static TextStyle button = GoogleFonts.hankenGrotesk(
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  static TextStyle tabLabel = GoogleFonts.hankenGrotesk(
    fontSize: 9.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  // ---- Aside (Fraunces italic) ----
  static TextStyle aside = GoogleFonts.fraunces(
    fontSize: 21,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    height: 1.32,
    color: AppColors.ink2,
  );
}
