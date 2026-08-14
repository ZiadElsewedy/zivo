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
    required this.nowNext,
    required this.focus,
    required this.training,
    required this.spending,
  });

  final String dateLabel; // e.g. "Saturday · 15 August"
  final String greeting; // e.g. "Morning, Ziad"
  final String aside; // one warm line

  final NowNext? nowNext;
  final List<FocusItem> focus;
  final TrainingToday? training;
  final SpendingGlance? spending;
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
  });

  final String title;
  final ZHue hue;
  final String? meta; // "overdue", "due today"
  final bool done;
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

class SpendingGlance {
  const SpendingGlance({
    required this.today,
    required this.week,
    required this.currency,
  });

  final int today;
  final int week;
  final String currency; // "EGP"
}
