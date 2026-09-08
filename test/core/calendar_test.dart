import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/calendar.dart';

/// The transitions the ambient zone actually has in [year], found by scanning
/// for a day whose UTC offset differs from the previous day's.
///
/// Written this way rather than against hard-coded Cairo dates so the DST
/// group is meaningful in ANY zone the suite happens to run in: under
/// `TZ=Africa/Cairo` it finds late April and late October, under
/// `TZ=America/New_York` it finds March and November, and under `TZ=UTC` it
/// finds nothing and the group skips.
List<DateTime> _transitionsIn(int year) {
  final found = <DateTime>[];
  var previous = DateTime(year, 1, 1).timeZoneOffset;
  for (var day = 2; day <= 366; day++) {
    final date = DateTime(year, 1, day);
    if (date.year != year) break;
    final offset = date.timeZoneOffset;
    if (offset != previous) found.add(date);
    previous = offset;
  }
  return found;
}

bool get _zoneHasDst => _transitionsIn(2026).isNotEmpty;

void main() {
  group('startOfDay', () {
    test('strips the time of day', () {
      expect(
        startOfDay(DateTime(2026, 3, 14, 18, 42, 9)),
        DateTime(2026, 3, 14),
      );
    });

    test('is idempotent', () {
      final once = startOfDay(DateTime(2026, 3, 14, 18, 42));
      expect(startOfDay(once), once);
    });
  });

  group('addCalendarDays', () {
    test('walks forward and backward within a month', () {
      expect(addCalendarDays(DateTime(2026, 3, 14), 3), DateTime(2026, 3, 17));
      expect(addCalendarDays(DateTime(2026, 3, 14), -3), DateTime(2026, 3, 11));
    });

    test('crosses month and year boundaries', () {
      expect(addCalendarDays(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
      expect(addCalendarDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      expect(addCalendarDays(DateTime(2026, 1, 1), -1), DateTime(2025, 12, 31));
    });

    test('crosses a leap day', () {
      expect(addCalendarDays(DateTime(2028, 2, 28), 1), DateTime(2028, 2, 29));
      expect(addCalendarDays(DateTime(2028, 3, 1), -1), DateTime(2028, 2, 29));
    });

    test('zero is the identity on a day key', () {
      expect(addCalendarDays(DateTime(2026, 3, 14), 0), DateTime(2026, 3, 14));
    });
  });

  group('calendarDaysBetween', () {
    test('counts dates, signed', () {
      expect(
        calendarDaysBetween(DateTime(2026, 3, 14), DateTime(2026, 3, 17)),
        3,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 3, 17), DateTime(2026, 3, 14)),
        -3,
      );
    });

    test('ignores the time of day on both ends', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 3, 14, 23, 59),
          DateTime(2026, 3, 15, 0, 1),
        ),
        1,
      );
    });

    test('is zero within one day', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 3, 14, 0, 5),
          DateTime(2026, 3, 14, 23, 55),
        ),
        0,
      );
    });
  });

  group('startOfWeek', () {
    test('resolves every weekday to its Monday', () {
      // 2026-03-09 is a Monday.
      for (var i = 0; i < 7; i++) {
        expect(startOfWeek(DateTime(2026, 3, 9 + i)), DateTime(2026, 3, 9));
      }
    });

    test('a Sunday belongs to the week that started six days earlier', () {
      expect(DateTime(2026, 3, 15).weekday, DateTime.sunday);
      expect(startOfWeek(DateTime(2026, 3, 15)), DateTime(2026, 3, 9));
    });
  });

  group('dayKey', () {
    test('zero-pads to yyyy-MM-dd', () {
      expect(dayKey(DateTime(2026, 3, 4, 22)), '2026-03-04');
      expect(dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('round-trips through dayFromKey', () {
      final day = DateTime(2026, 3, 4);
      expect(dayFromKey(dayKey(day)), day);
    });

    test('rejects a malformed or impossible key instead of guessing', () {
      expect(dayFromKey('nonsense'), isNull);
      expect(dayFromKey('2026-13-01'), isNull);
      expect(dayFromKey('2026-02-31'), isNull);
      expect(dayFromKey('2026-03'), isNull);
      expect(dayFromKey(''), isNull);
    });
  });

  // The regression this whole library exists for. `Duration(days: 1)` is 24
  // absolute hours; a calendar day on a transition date is 23 or 25. These
  // assertions are only *capable* of failing in a zone that shifts, so the
  // group skips elsewhere and the suite stays green on any machine.
  group('daylight saving', () {
    test('the ambient zone shifts at least once in 2026', () {
      expect(
        _transitionsIn(2026),
        isNotEmpty,
        reason:
            'This group is a no-op outside a DST zone. Run the real check '
            'with: TZ=Africa/Cairo flutter test test/core/calendar_test.dart',
      );
    }, skip: _zoneHasDst ? false : 'ambient zone has no DST transition');

    test('stepping across a transition lands on the adjacent calendar day', () {
      for (final transition in _transitionsIn(2026)) {
        final dayAfter = startOfDay(addCalendarDays(transition, 1));
        expect(
          addCalendarDays(dayAfter, -1),
          startOfDay(transition),
          reason: 'walking back from $dayAfter across $transition',
        );
        expect(
          addCalendarDays(startOfDay(transition), -1),
          startOfDay(addCalendarDays(transition, -1)),
          reason: 'walking back onto the eve of $transition',
        );
      }
    }, skip: _zoneHasDst ? false : 'ambient zone has no DST transition');

    test('a transition day is exactly one calendar day wide', () {
      for (final transition in _transitionsIn(2026)) {
        expect(
          calendarDaysBetween(
            addCalendarDays(transition, -1),
            transition,
          ),
          1,
          reason: 'the eve of $transition',
        );
        expect(
          calendarDaysBetween(transition, addCalendarDays(transition, 1)),
          1,
          reason: 'the morning after $transition',
        );
      }
    }, skip: _zoneHasDst ? false : 'ambient zone has no DST transition');

    test('an unbroken walk across a transition visits every date once', () {
      for (final transition in _transitionsIn(2026)) {
        final visited = <DateTime>{};
        var cursor = startOfDay(addCalendarDays(transition, 3));
        for (var i = 0; i < 7; i++) {
          expect(
            visited.add(cursor),
            isTrue,
            reason: 'revisited $cursor while walking past $transition',
          );
          cursor = addCalendarDays(cursor, -1);
        }
        expect(visited.length, 7);
        // The naive version this replaced skipped a date entirely.
        expect(
          visited.contains(startOfDay(transition)),
          isTrue,
          reason: 'the walk stepped over $transition itself',
        );
      }
    }, skip: _zoneHasDst ? false : 'ambient zone has no DST transition');

    test('week keys stay 7 calendar days apart across a transition', () {
      for (final transition in _transitionsIn(2026)) {
        final week = startOfWeek(transition);
        expect(calendarDaysBetween(addCalendarWeeks(week, -1), week), 7);
        expect(calendarDaysBetween(week, addCalendarWeeks(week, 1)), 7);
      }
    }, skip: _zoneHasDst ? false : 'ambient zone has no DST transition');
  });
}
