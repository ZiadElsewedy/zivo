import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import 'zivo_palette.dart';

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
/// Scope: **the whole app.** These began as the dress for the eleven handoff
/// screens, with capture flows, plan editing, auth and the import wizards left
/// on the warm v2 palette. That split was the "two systems on one screen"
/// problem the design audit named, so the rest of the app was rolled onto
/// these tokens and the v2 colour/elevation files were deleted. There is no
/// second palette to fall back to — if something needs a colour, it belongs
/// here. See `docs/DECISIONS/ADR-006-one-design-system.md` for the decision and
/// the rules any new colour work has to follow.
///
/// The design intent worth protecting (from the handoff, verbatim in spirit):
/// **one hero number per screen**, everything else demoted to a mono caption;
/// units and decimals always smaller and dimmer than the value they belong to;
/// **ember is reserved for the single committing action** on a screen, green
/// means state and progress.
abstract final class TrainColors {
  static ZivoPalette get _p => ZivoTheme.palette;

  /// Screen base — every handoff screen paints its own radial tint over this.
  static Color get base => _p.base;

  /// State + progress: done, resting, on-track.
  static Color get green => _p.green;

  /// The single committing action on a screen (Start Workout, Log set) and
  /// the "current" marker. Never decoration.
  static Color get ember => _p.ember;

  /// The violet the Today header's do-not-disturb/night chip carries.
  /// System/meta only — theme, calendar, assistant chrome.
  static Color get violet => _p.violet;
  static Color get violetGlyph => _p.violetGlyph;

  /// Money, and nothing else — the wallet card, expense amounts, the
  /// Expenses FAB. Never a training or system signal (identity §2).
  static Color get amber => _p.amber;

  // ---- Ink ----
  static Color get ink => _p.ink;
  static Color get inkPlain => _p.inkPlain;
  static Color get ink2 => _p.ink2;
  static Color get ink3 => _p.ink3;
  static Color get ink4 => _p.ink4;

  /// The ink ZIVO's serif voice speaks in.
  static Color get voiceInk => _p.voiceInk;

  /// [inkPlain] at an opacity the named ladder doesn't have a step for.
  /// Prefer [ink2]/[ink3]/[ink4]; this exists for the handful of surfaces
  /// whose spec lands between them.
  static Color inkAt(double opacity) => _p.inkAt(opacity);

  // ---- Surfaces ----
  /// 1px separators and card edges.
  static Color get hairline => _p.hairline;

  /// Flat glass fill for chips and the Spotify strip.
  static Color get glass => _p.glass;
  static Color get glassSoft => _p.glassSoft;
  static Color get glassStrong => _p.glassStrong;

  /// The fill behind an inset-grouped settings card.
  static Color get sectionFill => _p.sectionFill;

  /// A surface step the named tokens don't name — white on the dark skin,
  /// ink on the light one. See [hairline], [glass] and friends first.
  static Color liftAt(double opacity) => _p.liftAt(opacity);

  // ---- Ink on a filled hue ----
  /// The label on a filled green surface.
  static Color get onGreen => _p.onGreen;

  /// The label on a filled amber surface (a chip, a wallet card).
  static Color get onAmber => _p.onAmber;

  /// A step denser than [onAmber] — the glyph on the amber FAB.
  static Color get onAmberDeep => _p.onAmberDeep;

  // ---- Hue gradients ----
  /// The lit end of a two-stop ember gradient.
  static Color get emberLift => _p.emberLift;

  /// The lit end of a two-stop green gradient.
  static Color get greenLift => _p.greenLift;

  /// The palest ember the app draws — a chip label, never a fill.
  static Color get emberPale => _p.emberPale;

  // ---- On the session slab ----
  /// Ink on the Today session card, which stays deep green in both skins.
  static Color get sessionInk => _p.sessionInk;

  /// The quieter of the two inks on that slab.
  static Color get sessionInkMuted => _p.sessionInkMuted;

  /// The capture FAB's neutral gradient — the one floating object that
  /// deliberately carries no hue.
  static LinearGradient get fabGradient => _p.fabGradient;

  // ---- Floating chrome ----
  // The bottom nav island, the Ask composer, the voice sheet: objects that
  // float ABOVE a screen rather than sitting on it.

  /// A floating surface. Elevation here comes from light, not shadow
  /// (identity §5). Near-opaque on purpose: page content blurs underneath
  /// these, and anything more translucent lets text read through the blur.
  static Color get raised => _p.raised;

  /// A step further from the page than [raised] — chip fills and active rows
  /// inside floating chrome.
  static Color get raisedStrong => _p.raisedStrong;

  /// The opaque ground of a modal bottom sheet — [raised]'s tone with no
  /// translucency, because a sheet has the live launching screen right behind
  /// it and any bleed-through makes it read as see-through. Every sheet surface
  /// paints this; cards keep [raised].
  static Color get sheetSurface => _p.sheetSurface;

  /// The edge of a floating object, where [hairline] is the edge of a flat
  /// one.
  static Color get hairlineStrong => _p.hairlineStrong;

  /// Translucent washes of the chrome hues — the nav capsule, tinted glyph
  /// tiles.
  static Color get emberWash => _p.emberWash;
  static Color get violetWash => _p.violetWash;
  static Color get greenWash => _p.greenWash;
  static Color get amberWash => _p.amberWash;

  /// The neutral mark for a grid tile or list row that differentiates by
  /// **icon**, not colour.
  ///
  /// "One hue = one meaning" is a core identity pillar, and the four hues are
  /// semantic — green is state, ember is the one committing action, amber is
  /// money, violet is system/meta. None of them means "Diet" or "Moments", so
  /// a module grid that colours its tiles is spending meaning on decoration.
  /// Tiles lead with this instead and let the glyph say which one they are.
  static Color get neutralMark => _p.neutralMark;

  /// Inactive tab labels and icons on the nav island: present, not shouting.
  /// More present than [ink2] because these are the primary way you navigate.
  static Color get tabInactive => _p.tabInactive;

  /// The top-lit gradient every metric card carries, in place of a shadow.
  static LinearGradient get cardGradient => _p.cardGradient;

  /// The same, a touch tighter — the goal card and the up-next card.
  static LinearGradient get cardGradientTight => _p.cardGradientTight;

  /// The Today session card's green slab.
  static LinearGradient get sessionGradient => _p.sessionGradient;

  /// Screen washes — the one soft radial glow each screen is allowed.
  static RadialGradient get todayTint => _p.todayTint;
  static RadialGradient get setTint => _p.setTint;
  static RadialGradient get restTint => _p.restTint;

  /// The assistant's violet wash.
  static RadialGradient get askTint => _p.askTint;

  /// You / profile, warmed toward ember.
  static RadialGradient get youTint => _p.youTint;

  /// The Workout hub and Diet share one green wash.
  static RadialGradient get hubTint => _p.hubTint;

  /// Diet reads on the same wash as the hub (identity §2).
  static RadialGradient get dietTint => _p.hubTint;

  /// The Player, lit from below.
  static RadialGradient get playerTint => _p.playerTint;

  /// Expenses, the one amber-lit screen.
  static RadialGradient get expensesTint => _p.expensesTint;

  static RadialGradient get momentsTint => _p.momentsTint;

  /// Sleep, the night screen.
  ///
  /// The **blue end of the violet hue**, by the owner's decision (ADR-010,
  /// amended 2026-09-07). `violet` is documented above as what "the Today
  /// header's do-not-disturb/night chip carries", and Sleep is the full
  /// expression of that association rather than a new meaning — the
  /// alternative was a fifth hue, which ADR-006's four-hue system does not
  /// have room for. Sleep sits at ~225° where Ask sits at ~242°, so the two
  /// screens on this hue read as night and assistant rather than as each
  /// other. See [sleepAccent].
  static RadialGradient get sleepTint => _p.sleepTint;

  /// Settings, the coolest of the set.
  static RadialGradient get settingsTint => _p.settingsTint;

  // ---- Sleep ----
  // Sleep's own three tones, rather than the bare `violet`/`violetGlyph` the
  // screen used to borrow. Same hue family, walked toward blue: a night
  // screen dressed in lavender read as "assistant", and the one green control
  // on it (the header's targets button, on `TrainHeaderAction`'s default
  // accent) read as "training" on a screen that measures neither.
  //
  // Not a fifth hue — a *shade* of the fourth, which is why it lives here as
  // three named tones instead of a new entry in the hue table. Anything on
  // the Sleep screen that carries the hue takes one of these; nothing on it
  // takes `violet` directly.

  /// The Sleep accent: fills, the primary pill, a measured night's bar.
  static Color get sleepAccent => _p.sleepAccent;

  /// A step further from the page than [sleepAccent] — glyphs, links, chip
  /// text, and any hue-carrying mark that sits on the page rather than on the
  /// accent.
  static Color get sleepGlyph => _p.sleepGlyph;

  /// The label ink on a filled [sleepAccent] surface.
  static Color get sleepOnAccent => _p.sleepOnAccent;

  /// The wash behind a tinted Sleep chip or icon tile.
  static Color get sleepWash => _p.sleepWash;

  // The stage ramp. Deep, REM, light and undifferentiated sleep, drawn as one
  // **luminance ramp inside the sleep hue** rather than as four separate
  // colours — deeper sleep is denser ink. Four unrelated hues would read as
  // four categories of equal standing and would also import three colours the
  // palette does not own (ADR-006), where a ramp says "these are degrees of
  // one thing", which is exactly what sleep stages are.

  /// Deep sleep — the densest tone on the ramp.
  static Color get sleepStageDeep => _p.sleepStageDeep;

  /// REM.
  static Color get sleepStageRem => _p.sleepStageRem;

  /// Light (Apple's "core").
  static Color get sleepStageLight => _p.sleepStageLight;

  /// Asleep, kind unknown — off the ramp on purpose. A source that declined to
  /// grade the sleep must not be shown in a tone that implies it did, so this
  /// is the neutral one.
  static Color get sleepStageUnknown => _p.sleepStageUnknown;

  // ---- Diet macros ----
  // Protein, carbs and fat, drawn as one **luminance ramp inside the training
  // green** for the same reason the sleep stages are a ramp inside the sleep
  // hue: they are three parts of one day's food, not three categories of
  // equal standing that happen to share a card.

  /// Protein — the macro the coaching engine actually reasons about, so it
  /// keeps the full training green.
  static Color get macroProtein => _p.green;

  /// Carbohydrate.
  static Color get macroCarbs => _p.macroCarbs;

  /// Fat — the palest step on the ramp.
  static Color get macroFat => _p.macroFat;

  /// The colored bloom under a primary pill — the only shadow the handoff
  /// allows. [alpha] defaults to the active skin's strength, because a glow
  /// that reads as light on near-black reads as a smudge on paper.
  static List<BoxShadow> actionGlow(Color accent, {double? alpha}) => [
    BoxShadow(
      color: accent.withValues(alpha: alpha ?? _p.actionGlowAlpha),
      blurRadius: 32,
      offset: const Offset(0, 12),
    ),
  ];
}

/// **The app's three type families — the only place ZIVO names a typeface.**
///
/// * [mono] — **Azeret Mono**, for every number, timer and micro-caption.
///   Always tabular so a running value never shifts width.
/// * [ui] — **Manrope**, for names, titles, prose and button labels.
/// * [serif] — **Instrument Serif** italic, for the assistant's voice.
///
/// These began as the handoff's families, scoped to eleven workout screens,
/// while the rest of the app ran on Brand v2's Bricolage Grotesque / Hanken
/// Grotesk / Fraunces. ADR-006 collapsed the two *palettes* and left the two
/// *type systems* standing — five families meeting on fourteen screens, with
/// Hanken and Manrope doing the identical job. `ADR-009` finished the job:
/// v2's three faces are gone and [AppText]'s named ladder is built from these
/// builders. Do not add a fourth family, and do not call `GoogleFonts`
/// anywhere else — if a surface needs type, it comes from here.
///
/// [mono] and [ui] are builders rather than a fixed scale: the handoff
/// specifies a size per element (54/34/27/20/13…) rather than a ladder, so
/// pinning named steps would just make every call site fight them. Prose and
/// chrome want the opposite, and get it from `AppText`.
abstract final class TrainType {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Azeret Mono. [tracking] is in **ems** (the handoff's `letter-spacing`),
  /// converted to logical pixels here so call sites read like the spec.
  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w400,
    double tracking = 0,
    Color? color,
    double height = 1,
  }) => GoogleFonts.azeretMono(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: tracking * size,
    height: height,
    color: color ?? TrainColors.ink,
    fontFeatures: _tabular,
  );

  /// Manrope.
  static TextStyle ui({
    required double size,
    FontWeight weight = FontWeight.w700,
    double tracking = 0,
    Color? color,
    double height = 1.2,
  }) => GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: tracking * size,
    height: height,
    color: color ?? TrainColors.inkPlain,
  );

  /// **Instrument Serif, italic — ZIVO speaking, and nothing else** (identity
  /// §3).
  ///
  /// This is the one place the app speaks rather than reports, so it gets the
  /// one typeface neither of the other two families can imitate. Using it for
  /// anything else — a section header, a marketing line, a headline that
  /// isn't ZIVO talking — would spend the distinction and leave the assistant
  /// sounding like the rest of the UI.
  ///
  /// The rule used to be true only on paper: `AppText.aside` was a *second*
  /// italic serif (Fraunces) doing the same job at 24 call sites while this
  /// one was used at exactly one. `AppText.aside` is now this face, so the
  /// per-screen quiet line and ZIVO's own greeting are one voice.
  /// **Prefer [serifVoice]**, which asks the language whether the italic is
  /// even a thing. Use this directly only where there is no [BuildContext] and
  /// the script is known to be Latin.
  static TextStyle serif({
    required double size,
    Color? color,
    double height = 1.25,
    double tracking = -0.01,
    bool italic = true,
  }) => GoogleFonts.instrumentSerif(
    fontSize: size,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    letterSpacing: tracking * size,
    height: height,
    color: color ?? TrainColors.voiceInk,
  );

  /// [serif], with the italic dropped where the script has no such thing.
  ///
  /// Instrument Serif covers Latin only. Asking it for italic over Arabic text
  /// does not fall back to an Arabic italic — there is no such face, and no
  /// such tradition — so the shaper takes the system's upright Arabic fallback
  /// and **slants it synthetically**. ZIVO's greeting rendered as an obliqued
  /// أهلًا، which is not a voice: it is the artefact a Latin styling rule
  /// leaves behind on a script that never had the distinction. Every RTL script
  /// the app could reach (Arabic, Hebrew, Farsi, Urdu) is in the same position,
  /// so the gate is the paragraph's direction rather than a list of languages.
  ///
  /// What the voice keeps in Arabic is the serif itself — still one reserved
  /// face, still used only where ZIVO speaks, just upright. Giving Arabic a
  /// voice marker of its own means an Arabic display face, which is a fourth
  /// family and therefore an ADR (see ADR-009).
  static TextStyle serifVoice(
    BuildContext context, {
    required double size,
    Color? color,
    double height = 1.25,
    double tracking = -0.01,
  }) => serif(
    size: size,
    color: color,
    height: height,
    tracking: tracking,
    italic: Directionality.of(context) != TextDirection.rtl,
  );

  /// The handoff's caption pattern: 9–10px mono, uppercase, wide tracking.
  /// Used for every label on these screens (`TODAY`, `NEXT SESSION`, `NOW`,
  /// `LAST TIME`, `EXERCISE 4 / 10`…).
  static TextStyle caption({
    double size = 9.5,
    double tracking = 0.2,
    Color? color,
    FontWeight weight = FontWeight.w500,
  }) => mono(
    size: size,
    weight: weight,
    tracking: tracking,
    color: color ?? TrainColors.ink4,
  );
}
