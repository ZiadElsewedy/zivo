import 'package:flutter/painting.dart';

import 'train_tokens.dart';

/// ZIVO's named type ladder.
///
/// Every style here is built from the **three** families in [TrainType] —
/// Manrope for text and display, Azeret Mono for numbers and micro-labels,
/// Instrument Serif for the assistant's voice. `app_typography.dart` names no
/// family of its own: [train_tokens.dart] is the only place a typeface is
/// chosen, exactly as `TrainColors` is the only place a colour is.
///
/// **This file used to carry a second type system.** Its styles were
/// Bricolage Grotesque / Hanken Grotesk / Fraunces — the display, text and
/// aside faces of Brand System v2's *light and warm* skin. ADR-006 deleted
/// that skin's palette and moved the whole app onto the handoff's cool
/// near-black, but left the typography behind, so five families from two
/// unreconciled systems met on fourteen screens. See
/// `docs/DECISIONS/ADR-009-one-type-system.md`.
///
/// [AppText] survives that consolidation because a **named ladder** is the
/// right API for prose and chrome: `AppText.rowTitle` says what a thing *is*.
/// [TrainType] stays the right API for the handoff's numeric surfaces, which
/// specify a size per element rather than a ladder. Two APIs, one type system.
abstract final class AppText {
  static const _tabular = [FontFeature.tabularFigures()];

  // ---- Display (Manrope, heavy + tight) ----
  // Bricolage's display weights carried more presence than Manrope's at the
  // same number, so the two display steps each go up one weight to hold the
  // hierarchy they had.

  static TextStyle greeting = TrainType.ui(
    size: 34,
    weight: FontWeight.w800,
    tracking: -0.02,
    height: 1.05,
    color: TrainColors.ink,
  );

  static TextStyle cardTitle = TrainType.ui(
    size: 24,
    weight: FontWeight.w700,
    tracking: -0.015,
    height: 1.1,
    color: TrainColors.ink,
  );

  /// The one hero number on a screen. Mono and *light* — the house pattern set
  /// by the rest ring and the goal block, where a big numeral earns its size
  /// from scale, not weight, and tabular figures keep it from reflowing as it
  /// counts or as digits are typed.
  static TextStyle heroNumber = TrainType.mono(
    size: 66,
    weight: FontWeight.w300,
    tracking: -0.05,
    height: 1.0,
    color: TrainColors.ink,
  );

  // ---- Text (Manrope) ----

  static TextStyle sectionLabel = TrainType.caption(
    size: 12,
    tracking: 0.11,
    weight: FontWeight.w600,
    color: TrainColors.ink3,
  );

  static TextStyle hueLabel = TrainType.caption(
    size: 11,
    tracking: 0.1,
    weight: FontWeight.w700,
  );

  static TextStyle tabLabel = TrainType.caption(
    size: 9.5,
    tracking: 0.063,
    weight: FontWeight.w600,
  );

  static TextStyle rowTitle = TrainType.ui(
    size: 16.5,
    weight: FontWeight.w500,
    height: 1.3,
    color: TrainColors.ink,
  );

  /// Body runs at 45% ink on a near-black ground, where Manrope's Regular is
  /// thinner than Hanken's was at the same number. w500 holds the old density.
  static TextStyle body = TrainType.ui(
    size: 14.5,
    weight: FontWeight.w500,
    height: 1.5,
    color: TrainColors.ink2,
  );

  static TextStyle meta = TrainType.ui(
    size: 13,
    weight: FontWeight.w600,
    height: 1.2,
    color: TrainColors.ink2,
  ).copyWith(fontFeatures: _tabular);

  /// Money. Mono because an amount is a number, and amounts sit in columns.
  static TextStyle amount = TrainType.mono(
    size: 16,
    weight: FontWeight.w500,
    tracking: -0.02,
    color: TrainColors.ink,
  );

  static TextStyle button = TrainType.ui(
    size: 14,
    weight: FontWeight.w700,
    color: TrainColors.ink,
  );

  // ---- Aside (Instrument Serif italic) ----

  /// One quiet line per screen. This is the same face as [TrainType.serif] on
  /// purpose: the italic serif is ZIVO's speaking voice, and it was split
  /// across two families (Fraunces here, Instrument Serif there) with the
  /// reserved one used *once* in the whole app. One voice, one face.
  static TextStyle aside = TrainType.serif(
    size: 21,
    height: 1.32,
    color: TrainColors.ink2,
  );
}
