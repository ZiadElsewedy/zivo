import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the **workout-tracking surfaces** — Today, the live
/// session's logging phase, and rest — from the owner's design handoff in
/// `assets/design_handoff_workout_tracking/` (`PROMPT.md` +
/// `Workout Tracking.dc.html`).
///
/// This is a deliberate, owner-signed departure from two v2 rules in
/// [`docs/ZIVO-brand-system.md`](../../../docs/ZIVO-brand-system.md):
///
/// * **Monospace is back**, for numeric data only. v2 removed it to kill a
///   "coding tool" feel; the handoff brings it back for the opposite reason —
///   a running timer that reflows its own width every tick is the single most
///   unpolished thing a training app can do. Azeret Mono with tabular figures
///   fixes that, and it is scoped to numbers and micro-captions, never prose.
/// * **A cooler, darker base** (`#080908`) with a brighter training green,
///   because these screens are looked at in a gym, mid-set, at arm's length.
///
/// Scope: these tokens dress the three handoff screens. The rest of the app
/// still runs on [AppColors]'s warm v2 surfaces and [AppText]'s Bricolage /
/// Hanken pairing — rolling this further is a separate pass.
///
/// The design intent worth protecting (from the handoff, verbatim in spirit):
/// **one hero number per screen**, everything else demoted to a mono caption;
/// units and decimals always smaller and dimmer than the value they belong to;
/// **ember is reserved for the single committing action** on a screen, green
/// means state and progress.
abstract final class TrainColors {
  /// Screen base — every handoff screen paints its own radial tint over this.
  static const base = Color(0xFF080908);

  /// State + progress: done, resting, on-track.
  static const green = Color(0xFF1FE08A);

  /// The single committing action on a screen (Start Workout, Log set) and
  /// the "current" marker. Never decoration.
  static const ember = Color(0xFFFF5C1A);

  /// The violet the Today header's do-not-disturb/night chip carries.
  static const violet = Color(0xFF8F8BFF);
  static const violetGlyph = Color(0xFFA8A4FF);

  // ---- Ink ----
  static const ink = Color(0xFFF7F7F3);
  static const inkPlain = Color(0xFFF4F4F0);
  static const ink2 = Color(0x73F4F4F0); // .45
  static const ink3 = Color(0x66F4F4F0); // .40
  static const ink4 = Color(0x52F4F4F0); // .32

  // ---- Surfaces ----
  /// 1px separators and card edges — `rgba(255,255,255,.07)`.
  static const hairline = Color(0x12FFFFFF);

  /// Flat glass fill for chips and the Spotify strip.
  static const glass = Color(0x0BFFFFFF); // .045
  static const glassSoft = Color(0x09FFFFFF); // .035
  static const glassStrong = Color(0x0FFFFFFF); // .06

  /// The top-lit gradient every metric card carries, in place of a shadow.
  static const cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0EFFFFFF), Color(0x05FFFFFF)],
  );

  /// The same, a touch tighter — the goal card and the up-next card.
  static const cardGradientTight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0EFFFFFF), Color(0x04FFFFFF)],
  );

  /// The Today session card's green slab.
  static const sessionGradient = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.7, 1),
    colors: [Color(0xFF0F5F3F), Color(0xFF0A3A29), Color(0xFF0B2A20)],
    stops: [0.0, 0.58, 1.0],
  );

  /// Screen washes — the one soft radial glow each screen is allowed.
  static const todayTint = RadialGradient(
    center: Alignment(-0.7, -1),
    radius: 1.25,
    colors: [Color(0xFF12251C), Color(0xFF0A0B0A), base],
    stops: [0.0, 0.55, 1.0],
  );

  static const setTint = RadialGradient(
    center: Alignment(0, 1),
    radius: 1.15,
    colors: [Color(0xFF1A0D06), Color(0xFF0A0908), base],
    stops: [0.0, 0.6, 1.0],
  );

  static const restTint = RadialGradient(
    center: Alignment(0, -0.16),
    radius: 1.0,
    colors: [Color(0xFF0D2B21), Color(0xFF0A0F0D), base],
    stops: [0.0, 0.55, 1.0],
  );

  /// The colored bloom under a primary pill — the only shadow the handoff
  /// allows (`0 12px 32px <accent>/.3`).
  static List<BoxShadow> actionGlow(Color accent, {double alpha = 0.32}) => [
    BoxShadow(
      color: accent.withValues(alpha: alpha),
      blurRadius: 32,
      offset: const Offset(0, 12),
    ),
  ];
}

/// The handoff's two type families.
///
/// * [mono] — **Azeret Mono**, for every number, timer and micro-caption.
///   Always tabular so a running value never shifts width.
/// * [ui] — **Manrope**, for names, titles and button labels.
///
/// Both are builders rather than a fixed scale: the handoff specifies a size
/// per element (54/34/27/20/13…) rather than a ladder, so pinning named steps
/// would just make every call site fight them.
abstract final class TrainType {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Azeret Mono. [tracking] is in **ems** (the handoff's `letter-spacing`),
  /// converted to logical pixels here so call sites read like the spec.
  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w400,
    double tracking = 0,
    Color color = TrainColors.ink,
    double height = 1,
  }) => GoogleFonts.azeretMono(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: tracking * size,
    height: height,
    color: color,
    fontFeatures: _tabular,
  );

  /// Manrope.
  static TextStyle ui({
    required double size,
    FontWeight weight = FontWeight.w700,
    double tracking = 0,
    Color color = TrainColors.inkPlain,
    double height = 1.2,
  }) => GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: tracking * size,
    height: height,
    color: color,
  );

  /// The handoff's caption pattern: 9–10px mono, uppercase, wide tracking.
  /// Used for every label on these screens (`TODAY`, `NEXT SESSION`, `NOW`,
  /// `LAST TIME`, `EXERCISE 4 / 10`…).
  static TextStyle caption({
    double size = 9.5,
    double tracking = 0.2,
    Color color = TrainColors.ink4,
    FontWeight weight = FontWeight.w500,
  }) => mono(size: size, weight: weight, tracking: tracking, color: color);
}
