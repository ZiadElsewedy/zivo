import 'package:flutter/painting.dart';

/// The live workout session's dark, immersive palette — Phase 5A.
///
/// Scoped to the live session screens (running/rest/completed + their top
/// bar) only; the rest of the app stays on [AppColors] (light) this round,
/// so this is a deliberately separate token set rather than a global
/// dark-mode [AppColors] variant.
///
/// Warm charcoal, not cold gray — a near-black with a warm (not blue) cast,
/// staying on-brand with ZIVO's warm light palette. [ember]/[pulse] keep the
/// exact same vivid hues as light mode (already saturated enough to pop on
/// dark); only the neutrals below are new.
abstract final class SessionColors {
  // Surfaces — each a step lighter than the last, for real elevation.
  static const ground = Color(0xFF15110D); // screen background
  static const surface = Color(0xFF211A14); // elevated cards (Goal/Warm-up block)
  static const surfaceRaised = Color(0xFF2C231A); // further-elevated (current-set chip fill)

  // Text — near-white warm primary, muted warm-gray secondary/tertiary.
  static const ink = Color(0xFFF6F1E9);
  static const ink2 = Color(0xFFC7BCAC);
  static const ink3 = Color(0xFF8C8171);

  static const hairline = Color(0x14F6F1E9); // rgba(246,241,233,0.08)
  static const hairline2 = Color(0x22F6F1E9); // rgba(246,241,233,0.13)
}
