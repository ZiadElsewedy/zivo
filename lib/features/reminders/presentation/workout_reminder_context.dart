import '../../workout/domain/workout_plan.dart';
import '../domain/notification_scheduler.dart';
import '../domain/workout_motivations.dart';

/// Builds the live text a workout-synced reminder should carry from the active
/// [plan]: the next-up day's name and a short list of its exercises, plus
/// today's [motivations] line per tone for reminders in motivational mode.
///
/// The day text is empty when there is no plan or no next day — a synced
/// reminder then falls back to its own label — but [motivations] is still
/// carried so a motivational reminder shows encouragement even before a plan
/// resolves.
///
/// Shared by the app root (which bakes it into the OS schedule) and the edit
/// sheet's live preview, so the two can never drift on what a synced workout
/// reminder will say. Kept out of the reminders *domain* on purpose: that layer
/// depends on no other feature, which is exactly why [ReminderContext] exists.
ReminderContext workoutReminderContext(
  WorkoutPlan? plan, {
  Map<MotivationTone, String> motivations = const {},
}) {
  final day = plan?.nextDay;
  if (day == null) {
    return ReminderContext(workoutMotivations: motivations);
  }
  final names = [
    for (final e in (day.exercises.toList()
          ..sort((a, b) => a.order.compareTo(b.order))))
      if (e.name.trim().isNotEmpty) e.name.trim(),
  ];
  const maxNames = 3;
  String? body;
  if (names.length <= maxNames) {
    body = names.isEmpty ? null : names.join(' · ');
  } else {
    body = '${names.take(maxNames).join(' · ')} +${names.length - maxNames}';
  }
  final label = day.label.trim();
  return ReminderContext(
    workoutTitle: label.isEmpty ? null : label,
    workoutBody: body,
    workoutMotivations: motivations,
  );
}
