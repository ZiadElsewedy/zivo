import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/live_session.dart';
import '../../domain/logged_set.dart';
import '../../domain/rep_target.dart';
import '../../domain/session_exercise.dart';
import '../../domain/session_status.dart';
import '../../domain/set_outcome.dart';
import '../widgets/staggered_reveal.dart';
import 'workout_dashboard_page.dart' show formatClockTime, formatDurationShort;

/// The full detail view of one logged/live session — a designed screen, not
/// a table: a hero header (day, date, status, duration, time range,
/// exercise/set counts) followed by one card per exercise, each set shown as
/// its own row with actual reps/weight, RPE, and a clear completed/skipped
/// marker. Reads only the [LiveSession] handed to it — no streams, no
/// repository access; the session is already resolved by whoever pushed
/// this page (`_RecentSessionRow` on the Workout Dashboard).
class SessionDetailsPage extends StatelessWidget {
  const SessionDetailsPage({required this.session, super.key});

  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.ink2),
        title: Text('Session details', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
        actions: [
          IconButton(
            tooltip: 'Delete session',
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.ink2),
            onPressed: () async {
              final repo = AppScope.of(context).workoutSessions;
              final confirmed = await confirmDeleteSession(context, session.dayLabel);
              if (!confirmed || !context.mounted) return;
              await repo.deleteSession(session.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
        children: [
          _SessionHeroHeader(session: session),
          const SizedBox(height: 26),
          if (session.exercises.isEmpty)
            Text('No exercises logged.', style: AppText.aside.copyWith(color: AppColors.ink2))
          else
            for (final (i, exercise) in session.exercises.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StaggeredReveal(index: i, child: _ExerciseDetailCard(exercise: exercise)),
              ),
        ],
      ),
    );
  }
}

/// Confirms deleting a logged session — destructive and irreversible, so it
/// always asks first. Returns true only on an explicit Delete tap. Shared by
/// [SessionDetailsPage]'s delete action and History's swipe-to-delete so both
/// use the exact same wording and guard.
Future<bool> confirmDeleteSession(BuildContext context, String dayLabel) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Delete this session?', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
      content: Text(
        'This permanently removes your "$dayLabel" session and everything '
        "logged in it. This can't be undone.",
        style: AppText.body.copyWith(color: AppColors.ink2),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: AppText.button.copyWith(color: AppColors.ink3)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Delete', style: AppText.button.copyWith(color: AppColors.flare)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _SessionHeroHeader extends StatelessWidget {
  const _SessionHeroHeader({required this.session});

  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (session.status) {
      SessionStatus.completed => ('Completed', AppColors.pulse),
      SessionStatus.active => ('In progress', AppColors.solar),
      SessionStatus.abandoned => ('Not completed', AppColors.ink3),
    };
    final duration = session.status == SessionStatus.active
        ? session.activeElapsed(now: DateTime.now())
        : session.elapsed;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  session.dayLabel,
                  style: AppText.cardTitle.copyWith(color: AppColors.ink, fontSize: 22),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  label,
                  style: AppText.meta.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_formatFullDate(session.startedAt), style: AppText.meta.copyWith(color: AppColors.ink3)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _HeroStat(value: formatDurationShort(duration), label: 'Duration')),
              Expanded(child: _HeroStat(value: _timeRange(session), label: 'Time')),
              Expanded(child: _HeroStat(value: '${session.exercises.length}', label: 'Exercises')),
              Expanded(
                child: _HeroStat(
                  value: '${session.completedSetCount}/${session.totalSets}',
                  label: 'Sets done',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _timeRange(LiveSession s) {
    final start = formatClockTime(_minutesSinceMidnight(s.startedAt));
    if (s.completedAt == null) return start;
    return '$start–${formatClockTime(_minutesSinceMidnight(s.completedAt!))}';
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
          style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 16),
        ),
        const SizedBox(height: 2),
        Text(label, style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 11)),
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
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline2),
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
                  style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
              ),
              if (exercise.muscleGroup != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.pulse.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    exercise.muscleGroup!,
                    style: AppText.meta.copyWith(color: AppColors.pulse, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          for (final (i, set) in exercise.sets.indexed)
            Padding(
              padding: EdgeInsets.only(bottom: i == exercise.sets.length - 1 ? 0 : 10),
              child: _SetRow(index: i + 1, set: set),
            ),
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
    final reps = set.actualReps ?? (resolved ? _targetRepsFallback(set.target) : null);
    final toFailure = set.target.kind == RepTargetKind.toFailure;
    final repsText = reps != null ? '$reps' : (toFailure ? 'AMRAP' : '—');
    final mainText = weight != null
        ? '${_trimNumber(weight)}kg × $repsText'
        : '$repsText rep${reps == 1 ? '' : 's'}';

    final (icon, iconColor) = switch (set.outcome) {
      SetOutcome.completed => (Icons.check_circle_rounded, AppColors.pulse),
      SetOutcome.skipped => (Icons.remove_circle_outline_rounded, AppColors.ink3),
      SetOutcome.pending => (Icons.radio_button_unchecked_rounded, AppColors.ink3),
    };

    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 10),
        Text('Set $index', style: AppText.meta.copyWith(color: AppColors.ink3, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            mainText,
            style: AppText.body.copyWith(
              fontSize: 14,
              color: set.outcome == SetOutcome.skipped ? AppColors.ink3 : AppColors.ink2,
            ),
          ),
        ),
        if (set.outcome == SetOutcome.skipped) ...[
          Text('Skipped', style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 11)),
          const SizedBox(width: 8),
        ],
        if (set.rpe != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.solar.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              'RPE ${_trimNumber(set.rpe!)}',
              style: AppText.meta.copyWith(color: AppColors.solar, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

int? _targetRepsFallback(RepTarget target) =>
    target.kind == RepTargetKind.toFailure ? null : target.min;

double _minutesSinceMidnight(DateTime dt) => (dt.hour * 60 + dt.minute).toDouble();

String _trimNumber(double v) => v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatFullDate(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}';
