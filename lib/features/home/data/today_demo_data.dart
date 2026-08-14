import '../domain/today_snapshot.dart';
import '../presentation/widgets/hue.dart';

/// Demo content for the Today screen. Placeholder until a real `GetToday`
/// use case wires schedule / tasks / workout / expenses. Swap for Ziad's
/// actual data once the direction is locked.
const todayDemoSnapshot = TodaySnapshot(
  dateLabel: 'Saturday · 15 August',
  greeting: 'Morning, Ziad',
  aside: 'One deadline today, and a push session waiting.',
  nowNext: NowNext(
    kind: 'Lecture',
    time: '09:30 · in 2h',
    title: 'Data Structures',
    detail: 'Hall B · Dr. Naguib · bring assignment 2',
  ),
  // Tasks are read live from the task repository; the university deadline
  // stays demo until the University feature exists.
  focus: [
    FocusItem(
      title: 'Assignment 2 — Algorithms',
      hue: ZHue.iris,
      meta: 'due today',
      done: true,
    ),
  ],
  training: TrainingToday(
    label: 'Push',
    title: 'Chest · Shoulders · Triceps',
    detail: 'Bench · Incline DB · Cable Fly · Dips · Rope Pushdown',
    meta: '5 exercises · last: +2.5kg bench',
    duration: '~50 min',
  ),
);
