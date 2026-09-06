import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/bidi.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/workout_labels.dart';
import 'package:zivo/l10n/l10n.dart';

/// What a planned set *says*, in each language.
///
/// Two things are being protected here, and only one of them is translation.
///
/// The other is direction. `3 × 8–10 · rest 1:30` is digits, an ×, an en dash
/// and a colon — every character in it is either a digit or bidi-neutral — so
/// dropped into an Arabic paragraph the bidirectional algorithm laid it out
/// right-to-left and it rendered as `rest 1:30 · 10–8 × 3`. The rep range came
/// out as **10–8**. That is not a cosmetic complaint: the screen was
/// advertising a target no plan contains, and no amount of translating the
/// word "rest" fixes it. `ltr()` pins each numeric run, and the Arabic cases
/// below are what stop that pinning from being quietly removed later.
PlannedSet _set({
  int order = 0,
  RepTarget repTarget = const RepTarget.fixed(10),
  int restSeconds = 90,
  double? targetWeightKg,
}) => PlannedSet(
  order: order,
  repTarget: repTarget,
  restSeconds: restSeconds,
  targetWeightKg: targetWeightKg,
  type: SetType.working,
);

/// Renders [build] inside a real localized app and returns what it produced.
Future<T> _inLocale<T>(
  WidgetTester tester,
  Locale locale,
  T Function(BuildContext) build,
) async {
  late T result;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          result = build(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

const _en = Locale('en');
const _ar = Locale('ar');

void main() {
  group('English wording is unchanged by the move out of domain/', () {
    testWidgets('a set summary omits the weight when unset', (tester) async {
      final out = await _inLocale(
        tester,
        _en,
        (c) => setSummaryText(
          c,
          _set(repTarget: const RepTarget.fixed(10), restSeconds: 90),
        ),
      );
      expect(stripBidi(out), '10 reps · rest 1:30');
    });

    testWidgets('a set summary keeps a fractional weight', (tester) async {
      final out = await _inLocale(
        tester,
        _en,
        (c) => setSummaryText(
          c,
          _set(
            repTarget: const RepTarget.fixed(8),
            restSeconds: 90,
            targetWeightKg: 22.5,
          ),
        ),
      );
      expect(stripBidi(out), '8 reps · 22.5kg · rest 1:30');
    });

    testWidgets('a to-failure set drops the "reps" suffix', (tester) async {
      final out = await _inLocale(
        tester,
        _en,
        (c) => setSummaryText(
          c,
          _set(repTarget: const RepTarget.toFailure(), restSeconds: 45),
        ),
      );
      expect(stripBidi(out), 'To failure · rest 0:45');
    });

    testWidgets('identical sets collapse to one "N ×" line', (tester) async {
      final sets = [
        _set(order: 0, repTarget: const RepTarget.range(8, 10)),
        _set(order: 1, repTarget: const RepTarget.range(8, 10)),
        _set(order: 2, repTarget: const RepTarget.range(8, 10)),
      ];
      final out = await _inLocale(
        tester,
        _en,
        (c) => collapsedSetSummaryTexts(c, sets),
      );
      expect(out.map(stripBidi), ['3 × 8–10 · rest 1:30']);
    });

    testWidgets('a heavier last set gets its own line', (tester) async {
      final sets = [
        _set(order: 0, repTarget: const RepTarget.range(8, 10), targetWeightKg: 40),
        _set(order: 1, repTarget: const RepTarget.range(8, 10), targetWeightKg: 40),
        _set(order: 2, repTarget: const RepTarget.range(6, 8), targetWeightKg: 45),
      ];
      final out = await _inLocale(
        tester,
        _en,
        (c) => collapsedSetSummaryTexts(c, sets),
      );
      expect(out.map(stripBidi), [
        '2 × 8–10 · 40kg · rest 1:30',
        '1 × 6–8 · 45kg · rest 1:30',
      ]);
    });

    testWidgets('exercise and day metas pluralise', (tester) async {
      final e = PlannedExercise(
        id: 'e1',
        name: 'Bench Press',
        order: 0,
        muscleGroup: 'Chest',
        defaultRestSeconds: 90,
        sets: [_set(order: 0), _set(order: 1), _set(order: 2), _set(order: 3)],
      );
      final plank = PlannedExercise(
        id: 'e2',
        name: 'Plank',
        order: 1,
        defaultRestSeconds: 60,
        sets: [_set()],
      );
      expect(
        stripBidi(await _inLocale(tester, _en, (c) => plannedExerciseMetaText(c, e))),
        '4 sets · Chest',
      );
      expect(
        stripBidi(await _inLocale(tester, _en, (c) => plannedExerciseMetaText(c, plank))),
        '1 set',
      );
      final day = WorkoutDay(
        id: 'd1',
        slot: 'A',
        label: 'Push A',
        order: 0,
        exercises: [e, plank],
      );
      expect(
        stripBidi(await _inLocale(tester, _en, (c) => workoutDayMetaText(c, day))),
        '2 exercises',
      );
    });
  });

  group('Arabic', () {
    testWidgets('the words are Arabic, not English', (tester) async {
      final out = await _inLocale(
        tester,
        _ar,
        (c) => setSummaryText(
          c,
          _set(repTarget: const RepTarget.range(8, 10), restSeconds: 90),
        ),
      );
      expect(out, contains('راحة'));
      expect(out, contains('تكرار'));
      expect(out, isNot(contains('rest')));
      expect(out, isNot(contains('reps')));
    });

    testWidgets('a rep range keeps its ascending order and is isolated', (
      tester,
    ) async {
      final out = await _inLocale(
        tester,
        _ar,
        (c) => repTargetText(c, const RepTarget.range(8, 10)),
      );
      // The range itself must survive intact...
      expect(stripBidi(out), '8–10');
      expect(stripBidi(out), isNot('10–8'));
      // ...and must carry the isolate that keeps it that way on screen. This
      // is the assertion that fails if someone "simplifies" `ltr()` away.
      expect(
        out,
        isNot(stripBidi(out)),
        reason: 'the range must be wrapped in a directional isolate',
      );
    });

    testWidgets('every numeric run in a collapsed line is isolated', (
      tester,
    ) async {
      final sets = [
        _set(order: 0, repTarget: const RepTarget.range(8, 10), targetWeightKg: 60),
        _set(order: 1, repTarget: const RepTarget.range(8, 10), targetWeightKg: 60),
      ];
      final out = await _inLocale(
        tester,
        _ar,
        (c) => collapsedSetSummaryTexts(c, sets),
      );
      final line = out.single;
      expect(stripBidi(line), contains('8–10'));
      expect(stripBidi(line), contains('60kg'));
      expect(stripBidi(line), contains('1:30'));
      // Three isolated runs — the range, the weight and the clock.
      expect('\u2066'.allMatches(line).length, 3);
      expect('\u2069'.allMatches(line).length, 3);
    });

    testWidgets('to-failure reads as a word, not a pinned number', (
      tester,
    ) async {
      final out = await _inLocale(
        tester,
        _ar,
        (c) => repTargetText(c, const RepTarget.toFailure()),
      );
      expect(out, 'حتى الفشل');
      expect(out, stripBidi(out), reason: 'a word needs no isolate');
    });
  });
}
