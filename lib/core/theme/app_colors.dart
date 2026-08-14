import 'package:flutter/painting.dart';

/// ZIVO Brand System v2 — light & warm palette.
///
/// Surfaces are a picked warm off-white (never stark white, never cream).
/// Each hue owns one area of life and carries meaning, never decoration:
/// a vivid tone for dots/fills and a darker, legible tone for text on white.
abstract final class AppColors {
  // Surfaces
  static const ground = Color(0xFFF6F4EF); // app background
  static const card = Color(0xFFFFFFFF); // cards, sheets
  static const ink = Color(0xFF1D1A16); // primary text (warm near-black)
  static const ink2 = Color(0xFF6B655C); // secondary text
  static const ink3 = Color(0xFFA49E93); // muted / tertiary

  static const hairline = Color(0x171D1A16); // rgba(29,26,22,0.09)
  static const hairline2 = Color(0x241D1A16); // rgba(29,26,22,0.14)

  // Hues — dot/fill + legible text tone
  static const ember = Color(0xFFFF5A1F); // now / next / primary action
  static const emberText = Color(0xFFDC490E);
  static const emberWash = Color(0xFFFFF3EB);

  static const pulse = Color(0xFF12C48A); // training / health
  static const pulseText = Color(0xFF0A8F63);
  static const pulseWash = Color(0xFFECFBF4);

  static const solar = Color(0xFFF6B300); // money / expenses
  static const solarText = Color(0xFFA9760A);
  static const solarWash = Color(0xFFFFF7E4);

  static const iris = Color(0xFF6E5BFF); // university / study / focus
  static const irisText = Color(0xFF5B49E6);

  static const flare = Color(0xFFFF3D6E); // overdue / alert
  static const flareText = Color(0xFFDE2C56);

  // Tab bar inactive
  static const tabInactive = Color(0xFFB4AEA4);
}
