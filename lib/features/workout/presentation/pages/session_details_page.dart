import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/zivo_confirm.dart';
import '../../domain/live_session.dart';
import '../../domain/logged_set.dart';
import '../../domain/progression.dart';
import '../../domain/rep_target.dart';
import '../../domain/session_exercise.dart';
import '../../domain/session_status.dart';
import '../../domain/set_outcome.dart';
import '../widgets/staggered_reveal.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../workout_format.dart';

/// The full detail view of one logged/live session — a designed screen, not
/// a table: a hero header (day, date, status, duration, time range,
/// exercise/set counts) followed by one card per exercise, each set shown as
/// its own row with actual reps/weight, RPE, and a clear completed/skipped
/// marker. Reads only the [LiveSession] handed to it — no streams, no
/// repository access; the session is already resolved by whoever pushed
/// this page.
class SessionDetailsPage extends StatelessWidget {
  const SessionDetailsPage({required this.session, super.key});

  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    return TrainScreen(
      tint: TrainColors.hubTint,
      child: ListView(
        padding: EdgeInsets.fromLTRB(22, 12, 22, TrainBottomInset.of(context)),
        children: [
          _DetailsHeader(
            onDelete: () async {
              final repo = AppScope.of(context).workoutSessions;
              final confirmed = await confirmDeleteSession(
                context,
                session.dayLabel,
              );
              if (!confirmed || !context.mounted) return;
              await repo.deleteSession(session.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 22),
          _SessionHeroHeader(session: session),
          const SizedBox(height: 26),
          if (session.exercises.isEmpty)
            Text(
              l(context).sessionNoExercises,
              style: AppText.aside(context).copyWith(color: TrainColors.ink2),
            )
          else
            for (final (i, exercise) in session.exercises.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StaggeredReveal(
                  index: i,
                  child: _ExerciseDetailCard(exercise: exercise),
                ),
              ),
        ],
      ),
    );
  }
}

/// The pushed-page header — back chip, title, and the delete action.
/// The pushed-page header: the shared back circle and title, with this
/// page's one action — deleting the session — as the trailing chip.
class _DetailsHeader extends StatelessWidget {
  const _DetailsHeader({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return TrainPageHeader(
      title: l(context).sessionDetailsTitle,
      action: TrainHeaderAction(
        icon: AppIcons.trash,
        semanticLabel: l(context).sessionDeleteAction,
        // Neutral, not ember: destructive, but already gated behind its own
        // confirm — it doesn't get to be the loudest thing in the bar.
        accent: TrainColors.inkPlain,
        onTap: onDelete,
      ),
    );
  }
}

/// Confirms deleting a logged session — destructive and irreversible, so it
/// always asks first. Returns true only on an explicit Delete tap. Shared by
/// [SessionDetailsPage]'s delete action and History's swipe-to-delete so both
/// use the exact same wording and guard.
Future<bool> confirmDeleteSession(BuildContext context, String dayLabel) async {
  return confirmDestructive(
    context,
    title: l(context).sessionDeleteTitle,
    body: l(context).sessionDeleteBody(dayLabel),
  );
}

class _SessionHeroHeader extends StatelessWidget {
  const _SessionHeroHeader({required this.session});

  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (session.status) {
      SessionStatus.completed => (
        l(context).sessionStatusCompleted,
        TrainColors.green,
      ),
      SessionStatus.active => (
        l(context).sessionStatusActive,
        TrainColors.amber,
      ),
      SessionStatus.abandoned => (
        l(context).sessionStatusAbandoned,
        TrainColors.ink4,
      ),
    };
    final duration = session.status == SessionStatus.active
        ? session.activeElapsed(now: DateTime.now())
        : session.elapsed;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TrainColors.sectionFill,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.09),
            color.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.28),
                      color.withValues(alpha: 0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  switch (session.status) {
                    SessionStatus.completed => AppIcons.trendUp,
                    SessionStatus.active => AppIcons.bolt,
                    SessionStatus.abandoned => AppIcons.minus,
                  },
                  size: 18,
                  color: color == TrainColors.ink4 ? TrainColors.ink2 : color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.dayLabel,
                      style: AppText.cardTitle.copyWith(
                        color: TrainColors.ink,
                        fontSize: 21,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatWeekdayDate(context, session.startedAt),
                      style: AppText.meta.copyWith(color: TrainColors.ink4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  label,
                  style: AppText.meta.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  value: formatDurationShort(context, duration),
                  label: l(context).sessionStatDuration,
                ),
              ),
              Expanded(
                child: _HeroStat(
                  value: _timeRange(context, session),
                  label: l(context).sessionStatTime,
                ),
              ),
              Expanded(
                child: _HeroStat(
                  value: ltrFor(context, '${session.exercises.length}'),
                  label: l(context).sessionStatExercises,
                ),
              ),
              Expanded(
                child: _HeroStat(
                  // A ratio is digits around a neutral slash: pinned, or
                  // Arabic renders "12/15" as "15/12".
                  value: ltrFor(
                    context,
                    '${session.completedSetCount}/${session.totalSets}',
                  ),
                  label: l(context).sessionStatSetsDone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _timeRange(BuildContext context, LiveSession s) {
    final start = formatClockTime(context, s.startedAt);
    if (s.completedAt == null) return start;
    return ltrFor(
      context,
      l(context).sessionTimeRange(
        start,
        formatClockTime(context, s.completedAt!),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.rowTitle.copyWith(
            fontWeight: FontWeight.w700,
            color: TrainColors.ink,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppText.meta.copyWith(color: TrainColors.ink4, fontSize: 11),
        ),
      ],
    );
  }
}

class _ExerciseDetailCard extends StatelessWidget {
  const _ExerciseDetailCard({required this.exercise});

  final SessionExercise exercise;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TrainColors.sectionFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: TrainColors.ink,
                  ),
                ),
              ),
              if (exercise.muscleGroup != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: TrainColors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    exercise.muscleGroup!,
                    style: AppText.meta.copyWith(
                      color: TrainColors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          for (final (i, set) in exercise.sets.indexed) ...[
            if (i > 0)
              Container(
                margin: const EdgeInsetsDirectional.only(start: 26, bottom: 10),
                height: 1,
                color: TrainColors.hairline,
              ),
            _SetRow(index: i + 1, set: set),
          ],
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({required this.index, required this.set});

  final int index;
  final LoggedSet set;

  @override
  Widget build(BuildContext context) {
    final resolved = set.outcome != SetOutcome.pending;
    final weight = set.actualWeightKg ?? (resolved ? set.targetWeightKg : null);
    final reps =
        set.actualReps ?? (resolved ? _targetRepsFallback(set.target) : null);
    final toFailure = set.target.kind == RepTargetKind.toFailure;
    // `kAmrapLabel` is a sentinel value, not copy — the progression engine
    // compares against it, so it must not be translated (see AGENTS.md).
    final repsText = reps != null
        ? '$reps'
        : (toFailure ? kAmrapLabel : '—');
    final mainText = weight != null
        ? ltrFor(
            context,
            l(context).sessionSetWeightByReps(
              '${_trimNumber(weight)}kg',
              repsText,
            ),
          )
        : reps != null
        ? l(context).sessionSetRepsOnly(reps)
        : l(context).sessionSetRepsUnknown(repsText);

    final (icon, iconColor) = switch (set.outcome) {
      SetOutcome.completed => (Icons.check_circle_rounded, TrainColors.green),
      SetOutcome.skipped => (
        Icons.remove_circle_outline_rounded,
        TrainColors.ink4,
      ),
      SetOutcome.pending => (
        Icons.radio_button_unchecked_rounded,
        TrainColors.ink4,
      ),
    };

    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 10),
        Text(
          l(context).sessionSetNumber(index),
          style: AppText.meta.copyWith(
            color: TrainColors.ink4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            mainText,
            style: AppText.body.copyWith(
              fontSize: 14,
              color: set.outcome == SetOutcome.skipped
                  ? TrainColors.ink4
                  : TrainColors.ink2,
            ),
          ),
        ),
        if (set.outcome == SetOutcome.skipped) ...[
          Text(
            l(context).sessionSetSkipped,
            style: AppText.meta.copyWith(color: TrainColors.ink4, fontSize: 11),
          ),
          const SizedBox(width: 8),
        ],
        if (set.rpe != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: TrainColors.amber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              l(context).sessionSetRpe(
                ltrFor(context, _trimNumber(set.rpe!)),
              ),
              style: AppText.meta.copyWith(
                color: TrainColors.amber,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

int? _targetRepsFallback(RepTarget target) =>
    target.kind == RepTargetKind.toFailure ? null : target.min;

String _trimNumber(double v) =>
    v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

