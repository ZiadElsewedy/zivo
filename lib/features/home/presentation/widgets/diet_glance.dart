import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/bidi.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/theme/zivo_palette.dart';

/// One glance line, like [SpendingGlanceRow] — "2 of 5 meals eaten · 1400
/// kcal left". Values are live from the diet repository.
///
/// It measures against the same yardstick the Diet screen does: the user's own
/// daily target when they've set one ("of target"), the day's plan otherwise
/// ("of plan"). Two surfaces quoting the same phrase against different
/// baselines is exactly the kind of quiet disagreement that makes a number
/// untrustworthy, so the baseline is always named.
class DietGlanceRow extends StatelessWidget {
  const DietGlanceRow({
    required this.eaten,
    required this.total,
    required this.kcalLeft,
    required this.kcalEstimated,
    required this.againstTarget,
    super.key,
  });

  final int eaten;
  final int total;

  /// Calories left. Negative when a target has been passed — see
  /// [againstTarget].
  final int kcalLeft;

  /// Whether [kcalLeft] rests on AI-estimated figures — shown as the same "~"
  /// the Diet screen uses, so Today never states as fact what Diet marks as a
  /// guess.
  final bool kcalEstimated;

  /// True when [kcalLeft] is measured against the user's own target rather
  /// than the day's plan total.
  final bool againstTarget;

  /// "1,400 kcal left of target" / "200 kcal over target" / "1,400 kcal left
  /// of plan", with "~" when the figure rests on estimated values.
  ///
  /// The figure and its "~" are one composed run and are pinned together; the
  /// sentence around them is translated copy and is not.
  String _kcalText(BuildContext context) {
    final tilde = kcalEstimated ? '~' : '';
    final strings = l(context);
    if (againstTarget && kcalLeft < 0) {
      return strings.dietKcalOverTarget(ltrFor(context, '$tilde${-kcalLeft}'));
    }
    final kcal = ltrFor(context, '$tilde$kcalLeft');
    return againstTarget
        ? strings.dietKcalLeftOfTarget(kcal)
        : strings.dietKcalLeftOfPlan(kcal);
  }

  @override
  Widget build(BuildContext context) {
    final done = total > 0 && eaten >= total;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        gradient: TrainColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l(context).dietMealsEaten(eaten, total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.ui(
                    size: 15.5,
                    weight: FontWeight.w800,
                    tracking: -0.01,
                    height: 1.1,
                    color: TrainColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                _MealSegments(eaten: eaten, total: total, done: done),
                const SizedBox(height: 9),
                Text(
                  _kcalText(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: TrainColors.ink3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.chevron_right_rounded, size: 18, color: TrainColors.ink3),
        ],
      ),
    );
  }
}

/// One segment per planned meal, lit as it's eaten — the day's eating read
/// as a sequence rather than a fraction. A finished day glows. Past eight
/// meals the segments would be slivers, so it becomes one continuous bar.
class _MealSegments extends StatelessWidget {
  const _MealSegments({
    required this.eaten,
    required this.total,
    required this.done,
  });

  final int eaten;
  final int total;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final glow = done && ZivoTheme.brightness == Brightness.dark;
    Widget segment(bool lit, {int flex = 1}) => Expanded(
      flex: flex,
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          gradient: lit
              ? LinearGradient(
                  colors: [TrainColors.green, TrainColors.greenLift],
                )
              : null,
          color: lit ? null : TrainColors.liftAt(0.08),
          boxShadow: lit && glow
              ? [
                  BoxShadow(
                    color: TrainColors.green.withValues(alpha: 0.35),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
      ),
    );

    if (total <= 0) return const SizedBox(height: 6);
    if (total > 8) {
      final lit = (eaten.clamp(0, total) * 100 / total).round();
      return Row(
        children: [
          if (lit > 0) segment(true, flex: lit),
          if (lit < 100) segment(false, flex: 100 - lit),
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          segment(i < eaten),
        ],
      ],
    );
  }
}
