import 'package:flutter/material.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/train_chrome.dart';
import '../../../../../core/util/parse.dart';
import '../../../domain/logged_set.dart';
import '../../../domain/progress_comparison.dart';
import '../../../domain/progression.dart';
import '../verdict_style.dart';
import '../../../../../l10n/l10n.dart';
import 'live_session_format.dart';
import 'session_header.dart';

/// The goal card — the hero of the logging screen.
///
/// One hero number per screen, and here it is **reps × weight**: reps at
/// 62px, weight at 42px beside it, with the units always smaller and dimmer
/// than the values they belong to. Both track the steppers live, so the card
/// is always showing what you are about to log — it starts at the
/// progression engine's suggestion (see [computeGoal], which seeds the
/// steppers) and follows every edit from there.
///
/// Under a hairline sit three supporting cells: what you did LAST TIME, the
/// plan's TARGET RANGE, and the REST this exercise prescribes.
///
/// (The handoff's third cell is RPE. ZIVO has no RPE anywhere in the domain —
/// no field, no capture, nothing to read — so rather than print a plausible
/// fiction the cell carries rest, which is real, is the other number you act
/// on between sets, and is otherwise buried in the plan.)
class GoalBlock extends StatelessWidget {
  const GoalBlock({
    required this.lastTimeLabel,
    required this.goal,
    required this.liveReps,
    required this.liveWeight,
    required this.restSeconds,
    this.targetText,
    this.intraSessionDelta,
    this.previous,
    this.accent,
    super.key,
  });

  /// Just the value ("5 × 30 kg", or "First time") — rendered inside the
  /// card's LAST TIME stat cell.
  final String lastTimeLabel;
  final ProgressionGoal goal;

  /// The live stepper values, as typed. Empty renders as a dash.
  final String liveReps;
  final String liveWeight;

  /// This exercise's prescribed rest, for the third stat cell.
  final int restSeconds;

  final String? targetText;

  /// How this set compares to this session's own previous set in the same
  /// exercise. Null only on the first set, where there is nothing to compare
  /// against yet — see
  /// [intraSessionDeltaLabel] for why it is NOT also null when unchanged.
  final ({String label, bool changed})? intraSessionDelta;

  /// The index-aligned set from last time — the "why" behind the goal's
  /// suggestion is derived from it.
  final LoggedSet? previous;

  /// The live track's accent color (whole-screen ambience) — tints the
  /// card's glow so the hero element breathes with the music too.
  final Color? accent;

  /// The one-line "why" under the goal — makes the progression engine's
  /// decision legible instead of a number appearing from nowhere.
  String? _hintFor(BuildContext context) {
    final prevWeight = previous?.actualWeightKg;
    if (goal.weightKg != null && prevWeight != null) {
      if (goal.weightKg! > prevWeight) {
        return l(context).liveWeightUp;
      }
      if (goal.weightKg! < prevWeight) {
        return l(context).liveWeightEased;
      }
    }
    final prevReps = previous?.actualReps;
    if (prevReps != null && goal.repsLabel != kAmrapLabel) {
      final suggested = int.tryParse(goal.repsLabel);
      if (suggested != null && suggested > prevReps) {
        return l(context).liveSameLoadMoreRep;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final glowColor = accent ?? TrainColors.green;
    return AnimatedContainer(
      key: const Key('goal-card'),
      duration: reducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        gradient: TrainColors.cardGradientTight,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: TrainColors.hairline),
        boxShadow: cardGlow(glowColor),
      ),
      // A +2.5 can add a whole row to this card (the intra-session delta
      // chip, the "why" hint). Without this the card — and everything the
      // Spacers position around it — jumped to its new height in one frame,
      // which reads as the screen refreshing rather than as the number you
      // just nudged.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TrainCaption(
            l(context).liveGoal,
            color: TrainColors.green.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 14),
          // ONE expression, read straight across: reps × weight. The two
          // numbers used to sit at opposite ends of the card — reps far left,
          // weight far right, nothing between them — which read as two
          // unrelated readouts that happened to share a row rather than as
          // the multiplication they are. `scaleDown` keeps a wide one
          // ("15 REPS × 102.5 KG") on a single line instead of letting the
          // operator wrap away from its operands.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                RollingNumber(
                  text: liveReps,
                  whole: true,
                  textKey: const Key('goal-reps'),
                  style: TrainType.mono(
                    size: 62,
                    weight: FontWeight.w300,
                    tracking: -0.06,
                    height: 0.9,
                    color: const Color(0xFFF9F9F5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l(context).liveReps,
                  style: TrainType.mono(
                    size: 12,
                    weight: FontWeight.w500,
                    tracking: 0.14,
                    color: const Color(0x59F4F4F0),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: Text(
                    '×',
                    style: TrainType.mono(
                      size: 22,
                      weight: FontWeight.w300,
                      color: const Color(0x4DF4F4F0),
                    ),
                  ),
                ),
                RollingNumber(
                  text: liveWeight,
                  textKey: const Key('goal-weight'),
                  style: TrainType.mono(
                    size: 42,
                    weight: FontWeight.w300,
                    tracking: -0.05,
                    height: 0.9,
                    color: const Color(0xFFF9F9F5),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'KG',
                  style: TrainType.mono(
                    size: 11,
                    weight: FontWeight.w500,
                    tracking: 0.14,
                    color: const Color(0x59F4F4F0),
                  ),
                ),
              ],
            ),
          ),
          if (_hintFor(context) != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  AppIcons.trendUp,
                  size: 12,
                  color: TrainColors.green,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _hintFor(context)!,
                    style: TrainType.ui(
                      size: 11.5,
                      weight: FontWeight.w600,
                      height: 1.2,
                      color: TrainColors.green.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ],
          Container(
            height: 1,
            margin: const EdgeInsets.fromLTRB(0, 18, 0, 14),
            color: const Color(0x14FFFFFF),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GoalStatCell(
                    label: l(context).liveLastTime,
                    value: lastTimeLabel,
                    valueKey: const Key('last-time-label'),
                  ),
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Color(0x14FFFFFF),
                ),
                Expanded(
                  child: GoalStatCell(
                    label: l(context).liveTargetRange,
                    value: targetText ?? '—',
                    valueKey: const Key('target-label'),
                    accent: TrainColors.green,
                    inset: true,
                  ),
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Color(0x14FFFFFF),
                ),
                Expanded(
                  child: GoalStatCell(
                    label: l(context).liveRest,
                    value: formatRest(restSeconds),
                    valueKey: const Key('rest-label'),
                    inset: true,
                  ),
                ),
              ],
            ),
          ),
          if (intraSessionDelta != null) ...[
            const SizedBox(height: AppSpacing.m),
            IntraSessionChip(
              key: const Key('intra-session-delta'),
              delta: intraSessionDelta!,
            ),
          ],
        ],
      ),
    );
  }
}

/// One of the goal card's two hero numerals, **rolled** to its new value
/// rather than replaced.
///
/// These mirror the steppers live, and a stepper is the one place a
/// cross-fade is the wrong motion: you pressed +2.5, so the number should
/// travel the 2.5 rather than dissolve into a different one. Tapping used to
/// repaint it in a single frame, which read as the screen refreshing instead
/// of as the value you just changed.
///
/// Falls back to a plain [Text] whenever there is nothing numeric to
/// interpolate — an empty field mid-edit, or a body-weight set with no load —
/// and under reduced motion.
class RollingNumber extends StatelessWidget {
  const RollingNumber({
    required this.text,
    required this.style,
    required this.textKey,
    this.whole = false,
    super.key,
  });

  /// The raw stepper text, exactly as typed.
  final String text;
  final TextStyle style;

  /// Kept on the rendered [Text] itself so the card's two numerals stay
  /// addressable (`goal-reps` / `goal-weight`) mid-roll.
  final Key textKey;

  /// Reps are counted, not measured — rounded every frame so the roll never
  /// shows "9.4 REPS". Weight keeps [trimWeight]'s single decimal.
  final bool whole;

  @override
  Widget build(BuildContext context) {
    final value = parseDecimal(text);
    if (value == null || reducedMotion(context)) {
      return Text(text.isEmpty ? '—' : text, key: textKey, style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        whole ? v.round().toString() : trimWeight(v),
        key: textKey,
        style: style,
      ),
    );
  }
}

/// One labelled value cell in the goal card's stat strip — the quiet
/// supporting numbers under the hero.
class GoalStatCell extends StatelessWidget {
  const GoalStatCell({
    required this.label,
    required this.value,
    this.valueKey,
    this.accent,
    this.inset = false,
    super.key,
  });

  final String label;
  final String value;
  final Key? valueKey;

  /// Tints the VALUE when this cell is the "pointing forward" one (TARGET).
  final Color? accent;

  /// Cells after the first sit off their divider.
  final bool inset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: inset ? 16 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TrainType.mono(
              size: 8.5,
              weight: FontWeight.w500,
              tracking: 0.16,
              color: const Color(0x52F4F4F0),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            key: valueKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TrainType.ui(
              size: 13,
              weight: FontWeight.w600,
              height: 1,
              color: accent ?? TrainColors.inkPlain,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Progress verdict callout (Feature B) — how today's in-progress set
/// stacks up against the same set from last time (see [compareToLastTime]):
/// reps %, weight delta, and volume % rolled into one verdict. Lives right
/// under "Last time" in the Goal card, since that's the number it's judged
/// against, and updates live on every keystroke/step. Punches (a small
/// spring scale) only when the verdict/label actually changes — the same
/// settle-in idiom as the numbered set chips — so it doesn't just flicker
/// on every unrelated rebuild.
class ProgressVerdictBadge extends StatefulWidget {
  const ProgressVerdictBadge({required this.comparison, super.key});

  final SetProgressComparison comparison;

  @override
  State<ProgressVerdictBadge> createState() => _ProgressVerdictBadgeState();
}

class _ProgressVerdictBadgeState extends State<ProgressVerdictBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController(
    vsync: this,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant ProgressVerdictBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final same =
        oldWidget.comparison.verdict == widget.comparison.verdict &&
        oldWidget.comparison.overallChangePercent.round() ==
            widget.comparison.overallChangePercent.round();
    if (same) return;
    if (reducedMotion(context)) {
      _scale.value = 1;
    } else {
      _scale.value = 0.9;
      _scale.springTo(1, spring: AppSprings.bounce);
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comparison = widget.comparison;
    final (icon, color, word) = verdictStyle(comparison.verdict);
    final pct = comparison.overallChangePercent.round();
    final label = comparison.verdict == ProgressVerdict.matched
        ? word
        : '$word ${pct > 0 ? '+' : ''}$pct%';

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: Container(
        key: const Key('progress-verdict'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppText.meta.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
