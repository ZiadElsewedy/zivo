import 'package:flutter/painting.dart';

/// ZIVO Brand System v2 — dark & warm palette.
///
/// Surfaces are warm charcoal, not cold gray — a near-black with a warm
/// (not blue) cast. Each surface step is a step *lighter* than the last,
/// which is how elevation reads in a dark UI (no drop shadows doing the
/// work). Each hue owns one area of life and carries meaning, never
/// decoration: a vivid tone for dots/fills/text (already saturated enough
/// to pop on dark) and a translucent wash of the same hue for soft fills.
abstract final class AppColors {
  // Surfaces — each a step lighter than the last, for real elevation.
  static const ground = Color(0xFF15110D); // screen background
  static const card = Color(0xFF211A14); // elevated cards, sheets
  static const surfaceRaised = Color(0xFF2C231A); // further-elevated (chip fills, active rows)

  // Text — near-white warm primary, muted warm-gray secondary/tertiary.
  static const ink = Color(0xFFF6F1E9);
  static const ink2 = Color(0xFFC7BCAC);
  static const ink3 = Color(0xFF8C8171);

  static const hairline = Color(0x14F6F1E9); // rgba(246,241,233,0.08)
  static const hairline2 = Color(0x22F6F1E9); // rgba(246,241,233,0.13)

  // Hues — dot/fill/text tone (same vivid value does both; it already pops
  // on dark) + a translucent wash for soft tinted fills.
  static const ember = Color(0xFFFF5A1F); // now / next / primary action
  static const emberText = ember;
  static const emberWash = Color(0x24FF5A1F);

  static const pulse = Color(0xFF12C48A); // training / health
  static const pulseText = pulse;
  static const pulseWash = Color(0x2412C48A);

  static const solar = Color(0xFFF6B300); // money / expenses
  static const solarText = solar;
  static const solarWash = Color(0x24F6B300);

  static const iris = Color(0xFF6E5BFF); // university / study / focus
  static const irisText = iris;
  static const irisWash = Color(0x246E5BFF);

  static const flare = Color(0xFFFF3D6E); // overdue / alert
  static const flareText = flare;
  static const flareWash = Color(0x24FF3D6E);

  // Tab bar inactive
  static const tabInactive = Color(0xFFB4AEA4);
}
