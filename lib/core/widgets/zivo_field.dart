import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/train_tokens.dart';

/// The filled-box input decoration — ZIVO's standard text field chrome.
///
/// Eleven call sites across diet, workout, auth and ai had each written this
/// out by hand, and they had drifted apart in ways nobody chose: the corner
/// radius was 12 in six and 14 in five, the fill was `base` in some and
/// `raisedStrong` or a raw `Color(0x08FFFFFF)` in others, and only four drew a
/// focus ring at all — so on most screens a tapped field looked exactly like
/// an untapped one.
///
/// This is a decoration factory rather than a wrapper widget on purpose. The
/// call sites share their *chrome* and share almost nothing else: one is
/// six-line multiline prose, one is a numeric keypad with input formatters,
/// one has a 60-character counter, one autofocuses and submits on done. A
/// widget would have to proxy twenty [TextField] properties to cover them;
/// a decoration lets each keep its own [TextField] and drop twenty lines.
///
/// [accent] is the field's feature hue — Ember for auth, Pulse green for
/// training and diet, Violet for Ask. Per ADR-006 each area owns one colour,
/// so this takes it as an argument instead of picking one.
InputDecoration zivoFieldDecoration({
  String? hintText,
  TextStyle? hintStyle,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? suffixText,
  TextStyle? suffixStyle,
  TextStyle? counterStyle,
  Color fill = TrainColors.base,
  Color accent = TrainColors.green,
  double radius = AppRadius.field,
  EdgeInsets contentPadding = const EdgeInsets.symmetric(
    vertical: 10,
    horizontal: 12,
  ),
  bool isDense = false,
  bool focusRing = true,
}) {
  final shape = OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: hintStyle ?? AppText.rowTitle.copyWith(color: TrainColors.ink3),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    suffixText: suffixText,
    suffixStyle: suffixStyle,
    counterStyle: counterStyle,
    isDense: isDense,
    contentPadding: contentPadding,
    filled: true,
    fillColor: fill,
    border: shape,
    // The focused state is the one piece of this that isn't decoration: a
    // field the keyboard is pointed at should say so. Callers that sit inside
    // an already-outlined container pass `focusRing: false`.
    focusedBorder: focusRing
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide(color: accent, width: 1.4),
          )
        : shape,
  );
}
