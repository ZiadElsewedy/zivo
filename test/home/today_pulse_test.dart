import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/theme/train_tokens.dart';
import 'package:zivo/features/expenses/domain/expense.dart';
import 'package:zivo/features/home/domain/today_pulse.dart';
import 'package:zivo/features/home/presentation/widgets/today_pulse_card.dart'
    show formatSteps;
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/l10n/app_localizations_en.dart';
import 'package:zivo/l10n/app_localizations_ar.dart';
import 'package:zivo/l10n/app_localizations.dart';

/// A minimal day [LiveSession.start] needs — no exercises, it only reads
/// id/label.
const WorkoutDay _day = WorkoutDay(
  id: 'd',
  slot: 'A',
  label: 'Pull',
  order: 0,
  exercises: [],
);

/// Builds a COMPLETED session on [day] (at [hour], default 18:00).
LiveSession _done(DateTime day, {int hour = 18, String id = 's'}) {
  final start = DateTime(day.year, day.month, day.day, hour);
  return LiveSession.start(_day, id: id, planId: 'p', now: start).complete(
    now: start.add(const Duration(minutes: 45)),
  );
}

void main() {
  final now = DateTime(2026, 8, 26, 20); // a Wednesday evening

  group('formatSteps', () {
    test('compacts thousands, keeps small counts exact', () {
      expect(formatSteps(12400), '12.4k');
      expect(formatSteps(8000), '8k');
      expect(formatSteps(999), '999');
    });
  });

  group('weekActivity', () {
    test('buckets completed sessions per day over the trailing 7 days', () {
      final sessions = [
        _done(now.subtract(const Duration(days: 1))),
        _done(now.subtract(const Duration(days: 1)), hour: 7, id: 'b'),
        _done(now), // today
        // Outside the window entirely:
        _done(now.subtract(const Duration(days: 9)), id: 'old'),
      ];
      final week = weekActivity(sessions, now);

      expect(week.length, 7);
      expect(week.last.workouts, 1, reason: 'today');
      expect(week[5].workouts, 2, reason: 'yesterday got two');
      expect(
        week.first.day,
        DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6)),
      );
    });

    test('abandoned and still-active sessions are not history', () {
      final active = LiveSession.start(
        _day,
        id: 'live',
        planId: 'p',
        now: now,
      );
      expect(weekActivity([active], now).last.workouts, 0);
    });
  });

  group('trainingStreakDays', () {
    test('counts consecutive days ending today', () {
      final sessions = [
        _done(now),
        _done(now.subtract(const Duration(days: 1))),
        _done(now.subtract(const Duration(days: 2))),
        _done(now.subtract(const Duration(days: 5))), // gap breaks it
      ];
      expect(trainingStreakDays(sessions, now), 3);
    });

    test("today's missing workout doesn't break yesterday's streak", () {
      final sessions = [
        _done(now.subtract(const Duration(days: 1))),
        _done(now.subtract(const Duration(days: 2))),
      ];
      expect(
        trainingStreakDays(sessions, now),
        2,
        reason: 'the day is not over yet',
      );
    });

    test('a rest day before an unstarted today ends the streak honestly', () {
      final sessions = [
        _done(now.subtract(const Duration(days: 2))),
        _done(now.subtract(const Duration(days: 3))),
      ];
      // The streak ran two days ago; yesterday had nothing → done growing.
      expect(trainingStreakDays(sessions, now), 0);
    });
  });

  group('weightTrend', () {
    test('delta spans the window and samples stay bounded', () {
      final entries = <(DateTime, double)>[
        for (var i = 0; i < 30; i++)
          (now.subtract(Duration(days: 29 - i)), 80.0 + i * 0.1),
      ];
      final trend = weightTrend(entries)!;
      expect(trend.spanDays, 14);
      // Window covers indices 16..29 (days 13..0 ago): 81.6 → 82.9.
      expect(trend.deltaKg, closeTo(1.3, 0.01));
      expect(trend.samples.length, lessThanOrEqualTo(15));
      expect(trend.samples.first.$2, lessThan(trend.samples.last.$2));
    });

    test('needs at least two points', () {
      expect(weightTrend([(now, 80.0)]), isNull);
    });
  });

  group('spendBetween', () {
    Expense e(int amountMinor, DateTime at) => Expense(
          id: '$amountMinor-${at.millisecondsSinceEpoch}',
          amountMinor: amountMinor,
          currency: 'EGP',
          categoryId: 'x',
          spentAt: at,
        );

    test('this-week vs last-week windows are disjoint', () {
      final items = [
        e(100, now.subtract(const Duration(days: 1))), // this week
        e(400, now.subtract(const Duration(days: 8))), // last week
      ];
      final thisWeek =
          spendBetween(items, now, ago: const Duration(days: 7));
      final lastWeek = spendBetween(
        items,
        now.subtract(const Duration(days: 7)),
        ago: const Duration(days: 7),
      );
      expect(thisWeek, 100);
      expect(lastWeek, 400);
    });
  });

  group('buildInsights', () {
    List<PulseInsight> build({
      List<LiveSession> sessions = const [],
      List<Expense> expenses = const [],
      int? kcalLeft,
      int? mealsLeft,
      int? stepsToday,
    }) =>
        buildInsights(
          strings: AppLocalizationsEn(),
          sessions: sessions,
          expenses: expenses,
          kcalLeft: kcalLeft,
          mealsLeft: mealsLeft,
          stepsToday: stepsToday,
          weight: null,
          now: now,
        );

    test('a live streak speaks first', () {
      final insights = build(
        sessions: [
          for (var i = 0; i < 4; i++) _done(now.subtract(Duration(days: i))),
        ],
      );
      expect(insights.first.title, contains('streak'));
      expect(insights.first.hue, TrainColors.green);
    });

    test('a long rest nudges without guilt', () {
      final insights = build(
        sessions: [_done(now.subtract(const Duration(days: 4)))],
      );
      expect(insights.any((i) => i.body.contains('No guilt')), isTrue);
    });

    test('evening meals-left nudge only fires late in the day', () {
      expect(
        build(mealsLeft: 1, kcalLeft: 640)
            .any((i) => i.title == 'Evening check-in'),
        isTrue,
      );

      final morningInsights = buildInsights(
        strings: AppLocalizationsEn(),
        sessions: const [],
        expenses: const [],
        kcalLeft: 640,
        mealsLeft: 1,
        stepsToday: null,
        weight: null,
        now: DateTime(2026, 8, 26, 9),
      );
      expect(
        morningInsights.any((i) => i.title == 'Evening check-in'),
        isFalse,
      );
    });

    test('hot spending is flagged against the same span last week', () {
      Expense at(int daysAgo, int minor) => Expense(
            id: 'e$daysAgo-$minor',
            amountMinor: minor,
            currency: 'EGP',
            categoryId: 'x',
            spentAt: now.subtract(Duration(days: daysAgo)),
          );
      // This week: 500 vs the same span last week: 200 → well past 125%.
      final insights = build(
        expenses: [at(1, 300), at(2, 200), at(8, 200)],
      );
      expect(insights.any((i) => i.title.contains('% hot')), isTrue);
    });

    test('late-day step shortfall suggests the easy close', () {
      final stepLine =
          build(stepsToday: 6500).firstWhere((i) => i.hue == TrainColors.violet);
      expect(stepLine.title, contains('Steps'));
      expect(stepLine.body, contains('1500'));
    });

    test('never more than three rows — attention is the scarce resource', () {
      final insights = build(
        sessions: [
          for (var i = 0; i < 5; i++)
            _done(now.subtract(Duration(days: i))),
        ],
        mealsLeft: 2,
        kcalLeft: 900,
        stepsToday: 1200,
      );
      expect(insights.length, lessThanOrEqualTo(3));
    });

    test('a quiet life stays quiet', () {
      expect(build(), isEmpty);
    });
  });

  group('buildInsights speaks the app\'s language', () {
    test('the same signals produce Arabic copy under the Arabic strings', () {
      List<PulseInsight> build(AppLocalizations strings) => buildInsights(
        strings: strings,
        sessions: [
          for (var i = 0; i < 4; i++) _done(now.subtract(Duration(days: i))),
        ],
        expenses: const [],
        kcalLeft: null,
        mealsLeft: null,
        stepsToday: null,
        weight: null,
        now: now,
      );

      final english = build(AppLocalizationsEn());
      final arabic = build(AppLocalizationsAr());

      // Same nudge, same hue, same order — only the words differ.
      expect(english.length, arabic.length);
      expect(english.first.hue, arabic.first.hue);
      expect(english.first.title, '4-day training streak');
      expect(arabic.first.title, 'سلسلة تمرين 4 أيام');
      expect(arabic.first.body, isNot(english.first.body));
    });
  });
}
