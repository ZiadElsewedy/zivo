import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/home/presentation/motivation_lines.dart';

void main() {
  test('holds one line for the whole hour', () {
    final start = DateTime(2026, 9, 25, 7);
    expect(
      motivationFor(start.add(const Duration(minutes: 59)), 'en'),
      motivationFor(start, 'en'),
    );
  });

  test('changes on the hour, and never repeats within a day', () {
    final day = DateTime(2026, 9, 25);
    final lines = [
      for (var h = 0; h < 24; h++)
        motivationFor(day.add(Duration(hours: h)), 'en'),
    ];
    expect(lines.toSet(), hasLength(24));
  });

  test('Arabic has its own lines, and the same rotation', () {
    final day = DateTime(2026, 9, 25);
    final ar = {
      for (var h = 0; h < 24; h++)
        motivationFor(day.add(Duration(hours: h)), 'ar'),
    };
    expect(ar, hasLength(24));
    expect(ar.intersection({motivationFor(day, 'en')}), isEmpty);
  });

  test('the next change is the top of the next hour', () {
    expect(
      nextMotivationChange(DateTime(2026, 9, 25, 7, 42, 13)),
      DateTime(2026, 9, 25, 8),
    );
  });
}
