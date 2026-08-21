import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/body_weight_entry.dart';
import 'package:zivo/features/workout/domain/weight_trend.dart';

final _now = DateTime(2026, 8, 19);

BodyWeightEntry _entry(String id, DateTime loggedAt, double kg) =>
    BodyWeightEntry(id: id, weightKg: kg, loggedAt: loggedAt);

void main() {
  group('computeWeightTrend', () {
    test('no entries yields nulls and an empty series', () {
      final trend = computeWeightTrend(entries: const [], now: _now);
      expect(trend.latest, isNull);
      expect(trend.changeKgOverWindow, isNull);
      expect(trend.series, isEmpty);
    });

    test('a single entry is the latest, but there is no change to report', () {
      final entry = _entry('e1', DateTime(2026, 8, 15), 80.0);
      final trend = computeWeightTrend(entries: [entry], now: _now);
      expect(trend.latest, entry);
      expect(trend.changeKgOverWindow, isNull);
      expect(trend.series, [entry]);
    });

    test('change is latest-in-window minus oldest-in-window, series sorted oldest-first', () {
      final oldest = _entry('e1', DateTime(2026, 8, 1), 82.0);
      final middle = _entry('e2', DateTime(2026, 8, 10), 81.0);
      final newest = _entry('e3', DateTime(2026, 8, 18), 79.5);
      final trend = computeWeightTrend(
        entries: [newest, oldest, middle], // deliberately out of order
        now: _now,
      );
      expect(trend.latest, newest);
      expect(trend.changeKgOverWindow, closeTo(-2.5, 0.001));
      expect(trend.series, [oldest, middle, newest]);
    });

    test('entries older than the window are excluded from series/change but latest still wins', () {
      final tooOld = _entry('old', DateTime(2026, 6, 1), 90.0);
      final inWindow = _entry('recent', DateTime(2026, 8, 15), 80.0);
      final trend = computeWeightTrend(
        entries: [tooOld, inWindow],
        now: _now,
        window: const Duration(days: 30),
      );
      expect(trend.latest, inWindow); // globally most recent, window-independent
      expect(trend.series, [inWindow]);
      expect(trend.changeKgOverWindow, isNull); // only one entry inside the window
    });
  });
}
