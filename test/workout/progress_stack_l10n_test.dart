import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/presentation/pages/bodyweight_history_page.dart';
import 'package:zivo/features/workout/presentation/pages/workout_analysis_page.dart';
import 'package:zivo/features/workout/presentation/pages/workout_history_page.dart';
import 'package:zivo/features/workout/presentation/pages/workout_progress_page.dart';
import 'package:zivo/features/workout/presentation/widgets/progress_status_style.dart';
import 'package:zivo/features/workout/domain/analytics/exercise_analysis.dart';
import 'package:zivo/features/workout/domain/analytics/workout_analytics.dart';
import 'package:zivo/l10n/l10n.dart';

import '../support/test_app.dart';

/// The whole point of moving this stack's copy into the `.arb` files: an
/// Arabic reader gets an Arabic screen. These tests pump each surface under
/// `Locale('ar')` and assert the English is gone — a plain "does it render"
/// test would pass just as happily on hardcoded English, so it would not have
/// caught the bug this change fixes.
///
/// The chrome each page is asserted on is its *empty* state, which is what a
/// page renders with the in-memory repositories' seed data. That is enough:
/// the strings under test are the page's own labels, not its data.
Future<void> _pumpArabic(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(wrapWithScope(page, locale: const Locale('ar')));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Every latin word the progress stack used to hardcode. None may survive on
/// an Arabic screen. (Deliberately excludes strings that stay latin by design
/// — "ZIVO", "kg", the D/F set markers — none of which are listed here.)
const _englishCopy = <String>[
  'Progress',
  'Analysis',
  'History',
  'Bodyweight',
  'This week',
  'Day streak',
  'Total sessions',
  'Avg length',
  'Current split',
  'Recent activity',
  'Go deeper',
  'Full analysis',
  'All history',
  'Splits',
  'Sessions',
  'Trained',
  'Completed',
  'In progress',
  'Not completed',
  'Recent PRs',
  'Focus next',
  'Training volume',
  'All exercises',
  'OVERALL',
  'THIS WEEK',
  'LAST WEEK',
  'SEE ALL',
  'SEE FULL ANALYSIS',
];

void _expectNoEnglish(WidgetTester tester) {
  for (final word in _englishCopy) {
    expect(
      find.text(word),
      findsNothing,
      reason: '"$word" is still hardcoded English on an Arabic screen',
    );
  }
}

void main() {
  group('the progress stack renders in Arabic', () {
    testWidgets('WorkoutProgressPage', (tester) async {
      await _pumpArabic(tester, const WorkoutProgressPage());
      _expectNoEnglish(tester);
      expect(find.text('التقدم'), findsWidgets);
    });

    testWidgets('WorkoutAnalysisPage', (tester) async {
      await _pumpArabic(tester, const WorkoutAnalysisPage());
      _expectNoEnglish(tester);
      expect(find.text('التحليل'), findsWidgets);
    });

    testWidgets('WorkoutHistoryPage', (tester) async {
      await _pumpArabic(tester, const WorkoutHistoryPage());
      _expectNoEnglish(tester);
      expect(find.text('السجل'), findsWidgets);
    });

    testWidgets('BodyweightHistoryPage', (tester) async {
      await _pumpArabic(tester, const BodyweightHistoryPage());
      _expectNoEnglish(tester);
      expect(find.text('وزن الجسم'), findsWidgets);
    });
  });

  group('the shared progression vocabulary is localized', () {
    testWidgets('every ProgressStatus and ExerciseTrendTone reads Arabic', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exhaustive: a new enum value that forgets its key shows up here as
      // latin text rather than silently shipping English.
      for (final status in ProgressStatus.values) {
        final label = progressStatusStyle(ctx, status).label;
        expect(
          RegExp(r'[A-Za-z]').hasMatch(label),
          isFalse,
          reason: 'ProgressStatus.${status.name} still reads "$label"',
        );
      }
      for (final tone in ExerciseTrendTone.values) {
        final label = trendToneStyle(ctx, tone).label;
        expect(
          RegExp(r'[A-Za-z]').hasMatch(label),
          isFalse,
          reason: 'ExerciseTrendTone.${tone.name} still reads "$label"',
        );
      }
    });
  });

  group('English is unchanged', () {
    testWidgets('the same surfaces still read English under Locale("en")', (tester) async {
      await tester.pumpWidget(
        wrapWithScope(const WorkoutProgressPage(), locale: const Locale('en')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Progress'), findsWidgets);
      // The Arabic runs above assert the same surface, so this one only has to
      // prove the English side did not regress into Arabic (or into a key).
      expect(find.text('التقدم'), findsNothing);
    });
  });
}
