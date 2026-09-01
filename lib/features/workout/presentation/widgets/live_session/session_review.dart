import 'package:flutter/material.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/util/parse.dart';
import '../../../../../core/widgets/zivo_sheet.dart';
import '../../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../domain/logged_set.dart';
import '../../../domain/session_exercise.dart';
import '../../../../../l10n/l10n.dart';
import 'live_session_format.dart';
import 'set_input.dart';

/// One exercise's card in the end-of-workout review — its name plus every
/// resolved (done or skipped) set, each tappable to fix before Finish.
class ReviewExerciseGroup extends StatelessWidget {
  const ReviewExerciseGroup({
    required this.exercise,
    required this.onEditSet,
    super.key,
  });

  final SessionExercise exercise;
  final void Function(LoggedSet set, int position) onEditSet;

  @override
  Widget build(BuildContext context) {
    final resolved = <(int, LoggedSet)>[];
    for (final (i, set) in exercise.sets.indexed) {
      if (!set.pending) resolved.add((i + 1, set));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: TrainColors.raisedStrong,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairlineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exercise.name,
            style: AppText.rowTitle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: TrainColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          for (final (position, set) in resolved)
            ReviewSetRow(
              position: position,
              set: set,
              onTap: () => onEditSet(set, position),
            ),
        ],
      ),
    );
  }
}

/// One reviewable set row — flags a skip distinctly (muted dash icon, "Skipped"
/// label) from a done set (Pulse check, its actual reps/weight). The whole row
/// is the tap target, opening [SetReviewSheet] either way.
class ReviewSetRow extends StatelessWidget {
  const ReviewSetRow({
    required this.position,
    required this.set,
    required this.onTap,
    super.key,
  });

  final int position;
  final LoggedSet set;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skipped = set.skipped;
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Icon(
                skipped
                    ? Icons.remove_circle_outline_rounded
                    : Icons.check_circle_rounded,
                size: 16,
                color: skipped ? TrainColors.ink3 : TrainColors.green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l(context).liveSetNumber(position),
                  style: AppText.body.copyWith(
                    fontSize: 14,
                    color: TrainColors.ink2,
                  ),
                ),
              ),
              Text(
                skipped ? l(context).liveSkipped : formatSetActuals(set),
                style: AppText.meta.copyWith(
                  color: skipped ? TrainColors.ink3 : TrainColors.ink2,
                  fontWeight: skipped ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: TrainColors.ink3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The review-edit sheet: lets the reviewer type real reps/weight for a
/// skipped set ("Mark done") or correct an already-logged one ("Save").
/// Pops `(reps, weight)` on save, `null` on dismiss/cancel — mirrors the
/// running screen's own reps/weight inputs ([StepperField]) so editing here
/// feels like the same control, not a different one.
class SetReviewSheet extends StatefulWidget {
  const SetReviewSheet({
    required this.title,
    required this.wasSkipped,
    this.initialReps,
    this.initialWeight,
    super.key,
  });

  final String title;
  final bool wasSkipped;
  final int? initialReps;
  final double? initialWeight;

  @override
  State<SetReviewSheet> createState() => _SetReviewSheetState();
}

class _SetReviewSheetState extends State<SetReviewSheet> {
  late final TextEditingController _reps = TextEditingController(
    text: widget.initialReps?.toString() ?? '',
  );
  late final TextEditingController _weight = TextEditingController(
    text: widget.initialWeight != null ? trimWeight(widget.initialWeight!) : '',
  );

  @override
  void dispose() {
    _reps.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _save() {
    final reps = parseWhole(_reps.text);
    final weight = parseDecimal(_weight.text);
    Navigator.of(context).pop((reps, weight));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: const ZivoSheetHandle()),
          const SizedBox(height: 16),
          Text(
            widget.title,
            style: AppText.cardTitle.copyWith(
              fontSize: 18,
              color: TrainColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.wasSkipped
                ? l(context).liveCorrectSkipped
                : l(context).liveCorrectLogged,
            style: AppText.meta.copyWith(color: TrainColors.ink3),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              StepperField(
                label: l(context).liveRepsField,
                controller: _reps,
                step: 1,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(width: AppSpacing.m),
              StepperField(
                label: l(context).liveWeightField,
                controller: _weight,
                step: 2.5,
                hint: '—',
                onChanged: () => setState(() {}),
              ),
            ],
          ),
          const SizedBox(height: 20),
          PillButton(
            label: widget.wasSkipped
                ? l(context).liveMarkDone
                : l(context).actionSave,
            icon: Icons.check_rounded,
            enabled: true,
            onTap: _save,
          ),
        ],
      ),
    );
  }
}
