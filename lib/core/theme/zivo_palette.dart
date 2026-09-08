import 'package:flutter/widgets.dart';

/// **The two dressings of the one design system.**
///
/// ZIVO shipped dark-only for its whole life, and every colour it owns lived
/// as a `static const` on `TrainColors` (ADR-006: one palette, no second
/// system to fall back to). This file is what that palette becomes once the
/// app has to be legible in daylight too: the *values* move here as two
/// immutable instances — [dark] and [light] — and `TrainColors` stays exactly
/// where it was, as the name every screen still calls.
///
/// The two are not inverses of each other, and shouldn't be. Three rules keep
/// them one system rather than two:
///
/// * **Hue ownership survives the flip.** Green is still state and progress,
///   ember is still the single committing action, amber is still money,
///   violet is still system/meta (ADR-006 §2). What changes is *luminance*:
///   the dark set is tuned to sit on a near-black ground, so every hue in it
///   is too light to carry text on paper. Each one walks down to a value that
///   holds ~4.5:1 on [light]'s base without leaving its hue family.
/// * **Ink ramps are not mirrored alphas.** White-on-black stays legible far
///   further down the alpha ramp than black-on-white does, so light's
///   secondary/tertiary inks sit higher (.62/.55/.42) than dark's
///   (.45/.40/.32) rather than matching them.
/// * **Elevation still comes from light, not shadow** (identity §5). On dark
///   that means a raised surface is the base lifted toward white; on light it
///   means a raised surface *is* white, and the step above it (chip fills,
///   active rows) goes grey instead — which is the only place the two skins
///   move in opposite directions.
///
/// See `docs/DECISIONS/ADR-011-light-mode.md` for why the tokens are resolved
/// through a swapped active palette rather than a `ThemeExtension`.
@immutable
class ZivoPalette {
  const ZivoPalette({
    required this.brightness,
    required this.base,
    required this.green,
    required this.ember,
    required this.violet,
    required this.violetGlyph,
    required this.amber,
    required this.ink,
    required this.inkPlain,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.voiceInk,
    required this.hairline,
    required this.hairlineStrong,
    required this.glass,
    required this.glassSoft,
    required this.glassStrong,
    required this.sectionFill,
    required this.raised,
    required this.raisedStrong,
    required this.emberWash,
    required this.violetWash,
    required this.greenWash,
    required this.amberWash,
    required this.neutralMark,
    required this.tabInactive,
    required this.cardGradient,
    required this.cardGradientTight,
    required this.sessionGradient,
    required this.todayTint,
    required this.setTint,
    required this.restTint,
    required this.askTint,
    required this.youTint,
    required this.hubTint,
    required this.playerTint,
    required this.expensesTint,
    required this.momentsTint,
    required this.sleepTint,
    required this.settingsTint,
    required this.sleepAccent,
    required this.sleepGlyph,
    required this.sleepOnAccent,
    required this.sleepWash,
    required this.sleepStageDeep,
    required this.sleepStageRem,
    required this.sleepStageLight,
    required this.sleepStageUnknown,
    required this.macroCarbs,
    required this.macroFat,
    required this.actionGlowAlpha,
  });

  /// Which skin this is. The one thing screens may branch on — and they should
  /// need to almost never: a token that differs between the two belongs in
  /// this class, not in an `if` at the call site.
  final Brightness brightness;

  final Color base;

  // ---- Hues (ADR-006 §2 — one hue, one meaning) ----
  final Color green;
  final Color ember;
  final Color violet;
  final Color violetGlyph;
  final Color amber;

  // ---- Ink ----
  final Color ink;
  final Color inkPlain;
  final Color ink2;
  final Color ink3;
  final Color ink4;

  /// The ink the assistant's serif speaks in — a hair brighter than [ink] on
  /// dark, and its own value on light.
  final Color voiceInk;

  // ---- Surfaces ----
  final Color hairline;
  final Color hairlineStrong;
  final Color glass;
  final Color glassSoft;
  final Color glassStrong;

  /// The fill behind an inset-grouped settings card.
  final Color sectionFill;

  // ---- Floating chrome ----
  final Color raised;
  final Color raisedStrong;

  // ---- Hue washes ----
  final Color emberWash;
  final Color violetWash;
  final Color greenWash;
  final Color amberWash;

  final Color neutralMark;
  final Color tabInactive;

  // ---- Gradients ----
  final LinearGradient cardGradient;
  final LinearGradient cardGradientTight;
  final LinearGradient sessionGradient;

  // ---- Screen washes ----
  final RadialGradient todayTint;
  final RadialGradient setTint;
  final RadialGradient restTint;
  final RadialGradient askTint;
  final RadialGradient youTint;
  final RadialGradient hubTint;
  final RadialGradient playerTint;
  final RadialGradient expensesTint;
  final RadialGradient momentsTint;
  final RadialGradient sleepTint;
  final RadialGradient settingsTint;

  // ---- Sleep ----
  final Color sleepAccent;
  final Color sleepGlyph;
  final Color sleepOnAccent;
  final Color sleepWash;
  final Color sleepStageDeep;
  final Color sleepStageRem;
  final Color sleepStageLight;
  final Color sleepStageUnknown;

  // ---- Diet macros ----
  final Color macroCarbs;
  final Color macroFat;

  /// How hard the bloom under a primary pill burns. A coloured glow on paper
  /// reads as a smudge at the strength it reads as light on near-black, so
  /// light dials it back rather than dropping it.
  final double actionGlowAlpha;

  /// [inkPlain] at an arbitrary opacity — the ramp between [ink2], [ink3] and
  /// [ink4] for the handful of places that need a step the ladder doesn't
  /// name. Prefer a named step; reach for this only when none of them is the
  /// value the design actually calls for.
  Color inkAt(double opacity) => inkPlain.withValues(alpha: opacity);

  /// **The near-black skin** — the one ZIVO shipped with, unchanged. Every
  /// value here is the literal that used to sit on `TrainColors`, so dark
  /// renders byte-identically to how it did before light mode existed.
  static const dark = ZivoPalette(
    brightness: Brightness.dark,
    base: _darkBase,
    green: Color(0xFF1FE08A),
    ember: Color(0xFFFF5C1A),
    violet: Color(0xFF8F8BFF),
    violetGlyph: Color(0xFFA8A4FF),
    amber: Color(0xFFE6BE3C),
    ink: Color(0xFFF7F7F3),
    inkPlain: Color(0xFFF4F4F0),
    ink2: Color(0x73F4F4F0),
    ink3: Color(0x66F4F4F0),
    ink4: Color(0x52F4F4F0),
    voiceInk: Color(0xFFF9F9F5),
    hairline: Color(0x12FFFFFF),
    hairlineStrong: Color(0x1FFFFFFF),
    glass: Color(0x0BFFFFFF),
    glassSoft: Color(0x09FFFFFF),
    glassStrong: Color(0x0FFFFFFF),
    sectionFill: Color(0x08FFFFFF),
    raised: Color(0xF0141514),
    raisedStrong: Color(0xFF1D1E1D),
    emberWash: Color(0x24FF5C1A),
    violetWash: Color(0x248F8BFF),
    greenWash: Color(0x241FE08A),
    amberWash: Color(0x24E6BE3C),
    neutralMark: Color(0xFFF4F4F0),
    tabInactive: Color(0xB2F4F4F0),
    cardGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x0EFFFFFF), Color(0x05FFFFFF)],
    ),
    cardGradientTight: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x0EFFFFFF), Color(0x04FFFFFF)],
    ),
    sessionGradient: LinearGradient(
      begin: Alignment(-0.7, -1),
      end: Alignment(0.7, 1),
      colors: [Color(0xFF0F5F3F), Color(0xFF0A3A29), Color(0xFF0B2A20)],
      stops: [0.0, 0.58, 1.0],
    ),
    todayTint: RadialGradient(
      center: Alignment(-0.7, -1),
      radius: 1.25,
      colors: [Color(0xFF12251C), Color(0xFF0A0B0A), _darkBase],
      stops: [0.0, 0.55, 1.0],
    ),
    setTint: RadialGradient(
      center: Alignment(0, 1),
      radius: 1.15,
      colors: [Color(0xFF1A0D06), Color(0xFF0A0908), _darkBase],
      stops: [0.0, 0.6, 1.0],
    ),
    restTint: RadialGradient(
      center: Alignment(0, -0.16),
      radius: 1.0,
      colors: [Color(0xFF0D2B21), Color(0xFF0A0F0D), _darkBase],
      stops: [0.0, 0.55, 1.0],
    ),
    askTint: RadialGradient(
      center: Alignment(0, -0.56),
      radius: 1.1,
      colors: [Color(0xFF1A1834), Color(0xFF0B0B12), _darkBase],
      stops: [0.0, 0.52, 1.0],
    ),
    youTint: RadialGradient(
      center: Alignment(0, -1),
      radius: 1.1,
      colors: [Color(0xFF1C1410), Color(0xFF0B0A09), _darkBase],
      stops: [0.0, 0.55, 1.0],
    ),
    hubTint: RadialGradient(
      center: Alignment(0, -0.94),
      radius: 1.1,
      colors: [Color(0xFF10261D), Color(0xFF0A0D0B), _darkBase],
      stops: [0.0, 0.55, 1.0],
    ),
    playerTint: RadialGradient(
      center: Alignment(0, 0.76),
      radius: 1.1,
      colors: [Color(0xFF0E2A1F), Color(0xFF0A0C0B), _darkBase],
      stops: [0.0, 0.55, 1.0],
    ),
    expensesTint: RadialGradient(
      center: Alignment(0.6, -0.96),
      radius: 1.1,
      colors: [Color(0xFF241D0C), Color(0xFF0C0B09), _darkBase],
      stops: [0.0, 0.55, 1.0],
    ),
    momentsTint: RadialGradient(
      center: Alignment(0, -0.96),
      radius: 1.1,
      colors: [Color(0xFF1B1610), Color(0xFF0B0A09), _darkBase],
      stops: [0.0, 0.55, 1.0],
    ),
    sleepTint: RadialGradient(
      center: Alignment(0, -0.96),
      radius: 1.1,
      colors: [Color(0xFF111A31), Color(0xFF090B11), _darkBase],
      stops: [0.0, 0.55, 1.0],
    ),
    settingsTint: RadialGradient(
      center: Alignment(0, -0.96),
      radius: 1.1,
      colors: [Color(0xFF151520), Color(0xFF0A0A0C), _darkBase],
      stops: [0.0, 0.55, 1.0],
    ),
    sleepAccent: Color(0xFF7C9CFF),
    sleepGlyph: Color(0xFF9FB6FF),
    sleepOnAccent: Color(0xFF080C1A),
    sleepWash: Color(0x247C9CFF),
    sleepStageDeep: Color(0xFF4E6BDE),
    sleepStageRem: Color(0xFF8AA4FF),
    sleepStageLight: Color(0xFFB9C9FF),
    sleepStageUnknown: Color(0xFF5C6478),
    macroCarbs: Color(0xFF6BE3AE),
    macroFat: Color(0xFFA9EDCE),
    actionGlowAlpha: 0.32,
  );

  /// **The paper skin.**
  ///
  /// Not white — a faintly cool off-white, because a true `#FFFFFF` ground
  /// under a page of near-black type is the one thing that makes a light UI
  /// read as a document rather than as a product. The dark base carries a
  /// green-neutral cast (`#080908`); this carries the same cast at the other
  /// end of the ramp, which is what keeps the two skins recognisably the same
  /// app.
  static const light = ZivoPalette(
    brightness: Brightness.light,
    base: _lightBase,

    // The four hues, walked down until each holds its own on paper. Same
    // families, same meanings — a training green that reads as mint on
    // near-black is simply invisible on white, so it goes deep instead.
    green: Color(0xFF0C9A60),
    ember: Color(0xFFE2500F),
    violet: Color(0xFF5A54DB),
    violetGlyph: Color(0xFF4841C4),
    amber: Color(0xFFA0710E),

    // Ink, at the higher alphas black-on-white needs (see the class doc).
    ink: Color(0xFF0E100E),
    inkPlain: Color(0xFF141614),
    ink2: Color(0x9E141614),
    ink3: Color(0x8C141614),
    ink4: Color(0x6B141614),
    voiceInk: Color(0xFF101410),

    // Hairlines and glass invert: on paper a separator is ink laid down, not
    // light lifted off. Tinted with the ink base rather than pure black so a
    // rule doesn't read colder than the type beside it.
    hairline: Color(0x1A141614),
    hairlineStrong: Color(0x2E141614),
    glass: Color(0x0D141614),
    glassSoft: Color(0x0A141614),
    glassStrong: Color(0x14141614),

    // ...with one deliberate exception. An inset-grouped card and a floating
    // object are the two things that must read as *above* the page, and on
    // paper the only direction left is white. This is the iOS grouped-list
    // pattern, and it is why `raisedStrong` then has to go grey: once
    // `raised` is white, a step further from the page can only be darker.
    sectionFill: Color(0xC7FFFFFF),
    raised: Color(0xF5FFFFFF),
    raisedStrong: Color(0xFFEBEDEA),

    emberWash: Color(0x1FE2500F),
    violetWash: Color(0x1F5A54DB),
    greenWash: Color(0x1F0C9A60),
    amberWash: Color(0x1FA0710E),

    neutralMark: Color(0xFF141614),
    tabInactive: Color(0xBF141614),

    cardGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xCCFFFFFF), Color(0x99FFFFFF)],
    ),
    cardGradientTight: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xCCFFFFFF), Color(0x8FFFFFFF)],
    ),

    // The Today session card stays a deep green slab carrying white ink.
    // Inverting it to a pale mint would have cost the screen its one hero
    // surface — "one hero per screen" is the handoff's first rule, and on
    // paper a saturated slab is how you say it.
    sessionGradient: LinearGradient(
      begin: Alignment(-0.7, -1),
      end: Alignment(0.7, 1),
      colors: [Color(0xFF0F7A52), Color(0xFF0C6344), Color(0xFF0A5238)],
      stops: [0.0, 0.58, 1.0],
    ),

    // The screen washes: each keeps its hue and its geometry, and gives up
    // almost all of its density. A radial that reads as a glow on near-black
    // reads as a stain on paper, so these land nearer the base than their
    // dark counterparts do.
    todayTint: RadialGradient(
      center: Alignment(-0.7, -1),
      radius: 1.25,
      colors: [Color(0xFFE4F2EA), Color(0xFFF2F6F2), _lightBase],
      stops: [0.0, 0.55, 1.0],
    ),
    setTint: RadialGradient(
      center: Alignment(0, 1),
      radius: 1.15,
      colors: [Color(0xFFFBEDE4), Color(0xFFF8F6F4), _lightBase],
      stops: [0.0, 0.6, 1.0],
    ),
    restTint: RadialGradient(
      center: Alignment(0, -0.16),
      radius: 1.0,
      colors: [Color(0xFFE2F1EA), Color(0xFFF1F6F3), _lightBase],
      stops: [0.0, 0.55, 1.0],
    ),
    askTint: RadialGradient(
      center: Alignment(0, -0.56),
      radius: 1.1,
      colors: [Color(0xFFEAE9F7), Color(0xFFF3F3F8), _lightBase],
      stops: [0.0, 0.52, 1.0],
    ),
    youTint: RadialGradient(
      center: Alignment(0, -1),
      radius: 1.1,
      colors: [Color(0xFFF7EFE9), Color(0xFFF8F5F2), _lightBase],
      stops: [0.0, 0.55, 1.0],
    ),
    hubTint: RadialGradient(
      center: Alignment(0, -0.94),
      radius: 1.1,
      colors: [Color(0xFFE6F2EB), Color(0xFFF2F6F3), _lightBase],
      stops: [0.0, 0.55, 1.0],
    ),
    playerTint: RadialGradient(
      center: Alignment(0, 0.76),
      radius: 1.1,
      colors: [Color(0xFFE4F1EA), Color(0xFFF2F6F3), _lightBase],
      stops: [0.0, 0.55, 1.0],
    ),
    expensesTint: RadialGradient(
      center: Alignment(0.6, -0.96),
      radius: 1.1,
      colors: [Color(0xFFF6EFDE), Color(0xFFF8F6F0), _lightBase],
      stops: [0.0, 0.55, 1.0],
    ),
    momentsTint: RadialGradient(
      center: Alignment(0, -0.96),
      radius: 1.1,
      colors: [Color(0xFFF6F0E8), Color(0xFFF8F5F1), _lightBase],
      stops: [0.0, 0.55, 1.0],
    ),
    sleepTint: RadialGradient(
      center: Alignment(0, -0.96),
      radius: 1.1,
      colors: [Color(0xFFE6EAF8), Color(0xFFF1F3F9), _lightBase],
      stops: [0.0, 0.55, 1.0],
    ),
    settingsTint: RadialGradient(
      center: Alignment(0, -0.96),
      radius: 1.1,
      colors: [Color(0xFFEFEFF4), Color(0xFFF5F5F8), _lightBase],
      stops: [0.0, 0.55, 1.0],
    ),

    // Sleep's three tones flip which end of the ramp carries the label: on
    // near-black the accent is light enough to take near-black ink, on paper
    // it is deep enough to take near-white. Same relationship, mirrored.
    sleepAccent: Color(0xFF3A5CD4),
    sleepGlyph: Color(0xFF2E4CBE),
    sleepOnAccent: Color(0xFFF4F6FF),
    sleepWash: Color(0x1F3A5CD4),

    // The stage ramp keeps its direction — deeper sleep is denser ink — which
    // happens to be the one part of the palette that needed no rethinking,
    // because "denser" already meant "more ink" rather than "more light".
    sleepStageDeep: Color(0xFF2B45B8),
    sleepStageRem: Color(0xFF5876E0),
    sleepStageLight: Color(0xFF93A9F0),
    sleepStageUnknown: Color(0xFF8A90A0),

    macroCarbs: Color(0xFF3FB77F),
    macroFat: Color(0xFF77CFA4),

    actionGlowAlpha: 0.20,
  );
}

const _darkBase = Color(0xFF080908);
const _lightBase = Color(0xFFF7F8F6);

/// **Which skin is on right now.**
///
/// The app's colour tokens are read by name (`TrainColors.ink`) at ~1,700 call
/// sites, most of them without a `BuildContext` anywhere near them, so the
/// active palette is held here and swapped at the root rather than looked up
/// per widget. [ZivoApp] sets it in the builder that wraps `MaterialApp`,
/// above every route, and rebuilds that whole subtree on a change — so a
/// token read during `build` is always the palette of the frame being built.
/// The trade-off, and what it forbids, is written up in
/// `docs/DECISIONS/ADR-011-light-mode.md`.
abstract final class ZivoTheme {
  static ZivoPalette _palette = ZivoPalette.dark;

  /// The active palette. Never cache this in a field or a `static final` —
  /// read it (or the `TrainColors` token that wraps it) inside `build`.
  static ZivoPalette get palette => _palette;

  static Brightness get brightness => _palette.brightness;

  /// Swaps the active skin. Called by the root, and by tests that need to
  /// render a screen in a chosen brightness.
  static void use(Brightness brightness) {
    _palette = brightness == Brightness.dark
        ? ZivoPalette.dark
        : ZivoPalette.light;
  }
}
