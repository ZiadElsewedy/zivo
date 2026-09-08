import 'sleep_night.dart';
import 'sleep_targets.dart';

/// **Window arithmetic — the one place a range of sleep-days is built.**
///
/// Three screens now ask the same question with different anchors: the Today
/// dashboard wants the latest night, the weekly page wants the seven days
/// ending on a chosen Sunday, and the comparison wants the seven before that.
/// Each of them needs the same two things done exactly the same way — days
/// keyed to a local calendar date, and absent days materialised as empty
/// nights — and re-deriving that per caller is how two screens end up
/// disagreeing about which day is missing.
///
/// The fill is load-bearing, not a convenience. Dropping absent days would
/// close a week up and hide the gap, which is the single most important thing
/// a sleep history has to show.
abstract final class SleepWindow {
  /// A local calendar-date key. Sleep-days are dates, never instants, so this
  /// compares them the way the resolver files them (`sleep_resolver.dart`).
  static String dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// Midnight of [at] in the local zone — the canonical form of a sleep-day.
  static DateTime dayOf(DateTime at) => DateTime(at.year, at.month, at.day);

  /// [count] consecutive sleep-days ending on [lastDay] (inclusive), oldest
  /// first, with days absent from [nights] present as [SleepNight.empty].
  ///
  /// [targets] is stamped onto the empty days only. A night that has data
  /// keeps the targets it was resolved with, because a goal changed in March
  /// must not retroactively rewrite whether January's nights hit it.
  static List<SleepNight> daysEndingOn(
    List<SleepNight> nights, {
    required DateTime lastDay,
    required int count,
    SleepTargets? targets,
  }) {
    final byDay = {for (final night in nights) dayKey(night.sleepDay): night};
    final end = dayOf(lastDay);

    return [
      for (var i = count - 1; i >= 0; i--)
        () {
          final day = end.subtract(Duration(days: i));
          return byDay[dayKey(day)] ?? SleepNight.empty(day, targets: targets);
        }(),
    ];
  }

  /// The night for [day] if we have one with data, else null.
  ///
  /// Distinct from "the row exists": an empty night is stored so a week can
  /// draw its gap, and treating that as a night would put a headline on
  /// nothing.
  static SleepNight? withDataOn(List<SleepNight> nights, DateTime day) {
    final key = dayKey(dayOf(day));
    for (final night in nights) {
      if (dayKey(night.sleepDay) == key) return night.hasData ? night : null;
    }
    return null;
  }

  /// The most recent night that has data, or null.
  ///
  /// Scans rather than trusting the list's order: the Firestore mirror emits
  /// newest-first and the in-memory repository sorts on write, but a caller
  /// holding a filtered or re-ordered list would otherwise silently get the
  /// oldest night as "latest".
  static SleepNight? latestWithData(List<SleepNight> nights) {
    SleepNight? latest;
    for (final night in nights) {
      if (!night.hasData) continue;
      if (latest == null || night.sleepDay.isAfter(latest.sleepDay)) {
        latest = night;
      }
    }
    return latest;
  }

  /// Whole days between [night]'s sleep-day and [today].
  ///
  /// `0` is this morning's night, `1` is the night before. This is what lets a
  /// screen stop calling a five-day-old record "last night" — see
  /// `SleepController.latestNightAgeDays`.
  static int ageInDays(SleepNight night, DateTime today) =>
      dayOf(today).difference(dayOf(night.sleepDay)).inDays;
}
