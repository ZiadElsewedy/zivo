import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../theme/app_typography.dart';
import '../theme/train_tokens.dart';

/// The one way to ask "are you sure?" before something irreversible.
///
/// Seven screens each wrote this dialog out by hand — delete a moment, a
/// session, a split, a workout plan, a diet plan, discard a live session — and
/// they had drifted in both look and language.
///
/// **The look:** the background was `TrainColors.raised` in some and a nearly
/// invisible `Color(0x08FFFFFF)` in others, across four different title styles
/// and two different Cancel tints. The same question wore a different face
/// depending on which screen asked it.
///
/// **The language, which mattered more:** six of the seven hard-coded the
/// English strings `'Cancel'` and `'Delete'` — while `actionCancel` ("إلغاء")
/// and `actionDelete` ("حذف") had been sitting translated in both `.arb` files
/// the whole time. An Arabic user deleting a plan got English buttons. Reading
/// the labels from [l] by default is the point of this function; the shared
/// chrome is the bonus.
///
/// Returns true only on an explicit confirm — a dismissed dialog is a no.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String body,

  /// Defaults to the localized "Delete". Pass one for a destructive action
  /// that isn't a deletion (the live session's "Discard").
  String? confirmLabel,

  /// Defaults to the localized "Cancel". Pass one where the dismissal has its
  /// own meaning (the live session's "Keep going").
  String? cancelLabel,

  /// Keyed by the tests that drive a specific screen's confirm button.
  Key? confirmKey,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: TrainColors.raised,
      title: Text(title, style: AppText.cardTitle.copyWith(fontSize: 18)),
      content: Text(
        body,
        style: AppText.body.copyWith(color: TrainColors.ink2),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            cancelLabel ?? l(context).actionCancel,
            style: AppText.button.copyWith(color: TrainColors.ink3),
          ),
        ),
        TextButton(
          key: confirmKey,
          onPressed: () {
            // The moment commitment becomes certain — the same weight the
            // remove-row animations carry.
            HapticFeedback.mediumImpact();
            Navigator.pop(dialogContext, true);
          },
          child: Text(
            confirmLabel ?? l(context).actionDelete,
            style: AppText.button.copyWith(color: TrainColors.ember),
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
