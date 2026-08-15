import '../presentation/widgets/hue.dart';

/// A read-only aggregation of everything that matters on Today.
///
/// This is a plain immutable view model. In a later phase it will be produced
/// by a `GetToday` use case composing schedule / tasks / workout / expenses;
/// for now it is populated with demo data so the design can run.
class TodaySnapshot {
  const TodaySnapshot({
    required this.dateLabel,
    required this.greeting,
    required this.aside,
    required this.focus,
    required this.training,
  });

  final String dateLabel; // e.g. "Saturday · 15 August"
  final String greeting; // e.g. "Morning, Ziad"
  final String aside; // one warm line

  final List<FocusItem>
  focus; // unused — focus is built live, see _FocusSection
  final TrainingToday? training;
  // Now/Next comes live from the schedule repository; spending from expenses.
}

class NowNext {
  const NowNext({
    required this.kind,
    required this.time,
    required this.title,
    required this.detail,
  });

  final String kind; // "Lecture"
  final String time; // "09:30 · in 2h"
  final String title; // "Data Structures"
  final String detail; // "Hall B · Dr. Naguib · bring assignment 2"
}

class FocusItem {
  const FocusItem({
    required this.title,
    required this.hue,
    this.meta,
    this.done = false,
    this.taskId, // set for rows backed by a task (tap to complete)
  });

  final String title;
  final ZHue hue;
  final String? meta; // "overdue", "due today"
  final bool done;
  final String? taskId;
}

class TrainingToday {
  const TrainingToday({
    required this.label,
    required this.title,
    required this.detail,
    required this.meta,
    required this.duration,
  });

  final String label; // "Push"
  final String title; // "Chest · Shoulders · Triceps"
  final String detail; // exercise list
  final String meta; // "5 exercises · last: +2.5kg bench"
  final String duration; // "~50 min"
}
