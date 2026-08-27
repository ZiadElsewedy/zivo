import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../domain/live_session.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';

/// The result of picking from the change-workout sheet: the [day] to train
/// instead, plus the plan's active [resumable] session when that day is
/// actually the one already under way.
class ChangeWorkoutSelection {
  const ChangeWorkoutSelection({required this.day, this.resumable});

  final WorkoutDay day;
  final LiveSession? resumable;
}

/// "Change Workout" — every day of the split in one sheet, so the user can
/// train something other than today's scheduled rotation entry. The cursor's
/// day is marked "Next up"; a day with an active/paused session reads as
/// "Resume". Popping with a [ChangeWorkoutSelection] lets the caller start
/// that session directly.
Future<ChangeWorkoutSelection?> showChangeWorkoutSheet(
  BuildContext context, {
  required WorkoutPlan plan,
  LiveSession? activeSession,
}) {
  return showModalBottomSheet<ChangeWorkoutSelection>(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ChangeWorkoutSheet(plan: plan, activeSession: activeSession),
  );
}

class _ChangeWorkoutSheet extends StatelessWidget {
  const _ChangeWorkoutSheet({required this.plan, this.activeSession});

  final WorkoutPlan plan;
  final LiveSession? activeSession;

  @override
  Widget build(BuildContext context) {
    final days = [...plan.days]..sort((a, b) => a.order.compareTo(b.order));
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'Change workout',
                style: AppText.cardTitle.copyWith(fontSize: 19),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                plan.name,
                style: AppText.meta.copyWith(color: AppColors.ink3),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: days.length,
                itemBuilder: (context, i) {
                  final day = days[i];
                  final resumable =
                      activeSession != null && activeSession!.dayId == day.id
                      ? activeSession
                      : null;
                  final isNext = plan.nextDay?.id == day.id;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: PressableScale(
                      child: Material(
                        color: isNext ? AppColors.surfaceRaised : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(
                            ChangeWorkoutSelection(day: day, resumable: resumable),
                          ),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    day.label,
                                    style: AppText.rowTitle.copyWith(
                                      color: AppColors.ink,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (isNext)
                                  const _Badge(label: 'Next up', color: AppColors.pulse)
                                else if (resumable != null)
                                  const _Badge(label: 'In progress', color: AppColors.solar),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: AppText.meta.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color == AppColors.pulse ? AppColors.pulseText : AppColors.solarText,
        ),
      ),
    );
  }
}
