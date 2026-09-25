import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/calendar.dart';
import '../../../../core/util/deferred_write.dart';
import '../../../../core/widgets/async_action.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/live_session.dart';
import '../../domain/training_day_mark.dart';
import '../../domain/training_days.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../pages/live_session_page.dart';
import '../pages/workout_day_details_page.dart';
import '../workout_labels.dart';
import 'up_next_workout_card.dart';

/// Today's training, as the day actually stands — the ONE card Today and the
/// Workout tab show for the active plan.
///
/// [UpNextWorkoutCard] answers "what's next in the rotation"; this answers
/// "what is today" first, from `training_days.dart`:
///
/// * a session under way → the workout card, resuming it;
/// * the plan scheduled rest → [RestDayCard] (never an empty workout);
/// * the user chose rest → [RestDayCard], with the way back;
/// * otherwise → the workout card, with "Take a rest day" while it is still
///   untouched today.
///
/// Choosing rest writes a day mark and nothing else — the plan is never
/// edited, so the rotation still says the same workout tomorrow.
class TrainingDayCard extends StatelessWidget {
  const TrainingDayCard({
    required this.plan,
    required this.day,
    required this.resumable,
    this.now,
    super.key,
  });

  final WorkoutPlan plan;

  /// The rotation's next workout (`resolveUpNext`).
  final WorkoutDay day;
  final LiveSession? resumable;

  /// The clock "today" is judged against; wall time when null.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final marksRepo = scope.trainingDayMarks;
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, sessionsSnap) {
        return StreamBuilder<List<TrainingDayMark>>(
          stream: marksRepo?.watchAll() ?? const Stream.empty(),
          initialData: marksRepo?.current ?? const <TrainingDayMark>[],
          builder: (context, marksSnap) {
            final marks = marksSnap.data ?? const <TrainingDayMark>[];
            final today = (now ?? DateTime.now)();
            final record = resumable != null
                ? null
                : todayTrainingRecord(
                    plan: plan,
                    sessions: sessionsSnap.data ?? const <LiveSession>[],
                    marks: marks,
                    now: today,
                  );
            final Widget card = switch (record?.outcome) {
              DayOutcome.plannedRest => RestDayCard(
                key: const ValueKey('rest-planned'),
                plan: plan,
                next: day,
                chosen: false,
              ),
              DayOutcome.userRest => RestDayCard(
                key: const ValueKey('rest-chosen'),
                plan: plan,
                next: day,
                chosen: true,
                onResume: marksRepo == null
                    ? null
                    : () => _setRest(context, marks, today, rest: false),
              ),
              _ => UpNextWorkoutCard(
                key: const ValueKey('workout'),
                plan: plan,
                day: day,
                resumable: resumable,
                onTakeRest:
                    record?.outcome == DayOutcome.pending && marksRepo != null
                    ? () => _setRest(context, marks, today, rest: true)
                    : null,
              ),
            };
            return AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              child: card,
            );
          },
        );
      },
    );
  }

  /// Records (or withdraws) the user's choice to rest today. Local-first: the
  /// marks stream already carries it, so the card flips on this frame.
  void _setRest(
    BuildContext context,
    List<TrainingDayMark> marks,
    DateTime now, {
    required bool rest,
  }) {
    final repo = AppScope.of(context).trainingDayMarks;
    if (repo == null) return;
    rest ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
    final today = startOfDay(now);
    final existing = marks.where((m) => startOfDay(m.day) == today).firstOrNull;
    final failure = l(context).trainingDayMarkSaveFailed;
    if (rest) {
      deferWrite(
        repo.saveMark(chooseRest(existing, day: today, now: now)),
        failureMessage: failure,
      );
      return;
    }
    if (existing == null) return;
    final remaining = withdrawRest(existing);
    deferWrite(
      remaining == null ? repo.deleteMark(today) : repo.saveMark(remaining),
      failureMessage: failure,
    );
  }
}

/// A rest day — planned by the split, or chosen by the user — on the same
/// quiet glass surface as Today's other cards: no stats, no Start, nothing
/// that reads as a workout with zero in it.
///
/// The next workout rides underneath so the day still points somewhere.
/// A planned rest offers to train anyway (which the history then records as
/// an extra session); a chosen rest offers the way back to today's workout.
class RestDayCard extends StatefulWidget {
  const RestDayCard({
    required this.plan,
    required this.next,
    required this.chosen,
    this.onResume,
    super.key,
  });

  final WorkoutPlan plan;

  /// The rotation's next workout.
  final WorkoutDay next;

  /// Whether the user chose this rest (vs. the plan scheduling it).
  final bool chosen;

  /// Withdraws a chosen rest. Null hides "Resume today's workout".
  final VoidCallback? onResume;

  @override
  State<RestDayCard> createState() => _RestDayCardState();
}

class _RestDayCardState extends State<RestDayCard>
    with AsyncAction<RestDayCard> {
  void _viewNext() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            WorkoutDayDetailsPage(plan: widget.plan, day: widget.next),
      ),
    );
  }

  /// Guarded like the workout card's Start: it pushes, and a double tap would
  /// stack two live sessions.
  Future<void> _trainAnyway() => runAction(#start, () async {
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveSessionPage(day: widget.next, plan: widget.plan),
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final next = widget.next;
    return Container(
      key: widget.chosen
          ? const Key('rest-day-chosen')
          : const Key('rest-day-planned'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      decoration: BoxDecoration(
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TrainIconTile(
                icon: AppIcons.sleep,
                accent: TrainColors.green,
                size: 40,
                iconSize: 21,
              ),
              const SizedBox(width: 12),
              Expanded(child: TrainCaption(strings.restDayCaps)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.chosen ? strings.restDayChosenTitle : strings.restDayTitle,
            style: TrainType.ui(
              size: 26,
              weight: FontWeight.w800,
              tracking: -0.02,
              height: 1.1,
              color: TrainColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.chosen ? strings.restDayChosenBody : strings.restDayBody,
            style: AppText.aside(context).copyWith(color: TrainColors.ink2),
          ),
          const SizedBox(height: 20),
          Divider(height: 1, thickness: 1, color: TrainColors.hairline),
          const SizedBox(height: 14),
          TrainCaption(strings.restDayNextSession),
          const SizedBox(height: 6),
          Text(
            strings.restDayNextLine(
              isolate(next.label),
              workoutDayMetaText(context, next),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.rowTitle.copyWith(color: TrainColors.ink),
          ),
          const SizedBox(height: 16),
          TrainGhostButton(
            key: const Key('rest-view-next'),
            label: strings.restDayViewNext,
            mono: false,
            onTap: _viewNext,
          ),
          Center(
            child: PressableScale(
              child: TextButton(
                key: widget.chosen
                    ? const Key('rest-resume-workout')
                    : const Key('rest-train-anyway'),
                onPressed: widget.chosen
                    ? (widget.onResume == null
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              widget.onResume!();
                            })
                    : (actionInFlight ? null : _trainAnyway),
                child: Text(
                  widget.chosen
                      ? strings.restDayResume
                      : strings.restDayTrainAnyway,
                  style: AppText.meta.copyWith(color: TrainColors.ink2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
