import 'notification_scheduler.dart';
import 'reminder.dart';
import 'reminder_sync.dart';

/// Resolves a reminder's notification title and body, folding in its sync:
/// a [MealSync] lists its customised items in the body; a [WorkoutSync] takes
/// the live next-up workout from [context] (and falls back to the reminder's own
/// label when no plan is resolved); a plain reminder is title-only.
///
/// A [WorkoutSync] with `motivational` on is the exception: it names the day but
/// swaps the exercise list for [ReminderContext.workoutMotivation] — one short
/// line of encouragement, never the lift details.
///
/// Pure and free of any platform or repository dependency — the reason it lives
/// in `domain/` rather than beside the scheduler: the real
/// `LocalNotificationScheduler` uses it to bake notifications, and the edit
/// sheet uses the *same* function to show a live preview, so the two can never
/// disagree on what a reminder will say.
({String title, String? body}) resolveReminderText(
  Reminder reminder, {
  required String fallbackTitle,
  ReminderContext context = ReminderContext.empty,
}) {
  final base = _resolveBody(reminder, fallbackTitle: fallbackTitle, context: context);
  // An emoji the user picked leads the title — the one place it surfaces in the
  // notification itself. Kept out of the body so the message copy stays clean.
  final emoji = reminder.emoji?.trim();
  if (emoji == null || emoji.isEmpty) return base;
  return (title: '$emoji ${base.title}', body: base.body);
}

({String title, String? body}) _resolveBody(
  Reminder reminder, {
  required String fallbackTitle,
  ReminderContext context = ReminderContext.empty,
}) {
  final labelled = reminder.label.trim();
  switch (reminder.sync) {
    case MealSync m:
      final title = labelled.isNotEmpty
          ? labelled
          : (m.mealLabel.isNotEmpty ? m.mealLabel : fallbackTitle);
      return (title: title, body: m.items.isEmpty ? null : m.items.join(' · '));
    case WorkoutSync w:
      final day = context.workoutTitle;
      if (w.motivational) {
        // Motivational mode: encouragement, not the exercise list. The day still
        // shows so the reminder is grounded ("Arm Day · Keep going"); with no day
        // resolved it is the motivational line alone. The line is picked by the
        // reminder's own tone.
        final motivation = context.workoutMotivations[w.tone]?.trim();
        final title = labelled.isNotEmpty ? labelled : (day ?? fallbackTitle);
        final String? body;
        if (motivation != null && motivation.isNotEmpty) {
          body = (day != null && labelled.isNotEmpty)
              ? '$day · $motivation'
              : motivation;
        } else {
          body = labelled.isNotEmpty ? day : null;
        }
        return (title: title, body: body);
      }
      if (day == null) {
        // No active plan / no next day resolved — behave like a plain reminder.
        return (
          title: labelled.isNotEmpty ? labelled : fallbackTitle,
          body: null,
        );
      }
      if (labelled.isNotEmpty) {
        final detail = context.workoutBody;
        return (title: labelled, body: detail == null ? day : '$day — $detail');
      }
      return (title: day, body: context.workoutBody);
    case null:
      return (title: labelled.isNotEmpty ? labelled : fallbackTitle, body: null);
  }
}
