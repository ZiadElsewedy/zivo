import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/sleep/data/in_memory_sleep_repository.dart';
import 'package:zivo/features/sleep/domain/sleep_night.dart';
import 'package:zivo/features/sleep/domain/sleep_provenance.dart';
import 'package:zivo/features/sleep/domain/sleep_service.dart';
import 'package:zivo/features/sleep/domain/sleep_session.dart';
import 'package:zivo/features/sleep/domain/sleep_source.dart';
import 'package:zivo/features/sleep/domain/sleep_targets.dart';
import 'package:zivo/features/sleep/presentation/controllers/sleep_controller.dart';
import 'package:zivo/features/sleep/presentation/pages/sleep_week_page.dart';

import '../support/bidi_finders.dart';

/// Cover for the history view's claims.
///
/// The window figures moved here off the dashboard, and they brought their
/// rules with them: a figure below its gate shows what would open it rather
/// than an average over too few nights, a day with no record is a row that
/// says so rather than a missing row or a zero, and an empty week says it is
/// empty rather than rendering as a week of nothing.

class _IdleSource implements SleepSource {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<SleepAuthorization> authorizationStatus() async =>
      SleepAuthorization.unavailable;

  @override
  Future<bool> requestAuthorization() async => false;

  @override
  Future<List<RawSleepRecord>> readRecords({
    required DateTime from,
    required DateTime to,
  }) async => const [];
}

final _now = DateTime(2026, 9, 8, 9);

/// A user-reported night on [day], 23:00 → 23:00 + [hours].
SleepNight _night(DateTime day, {double hours = 7.5}) {
  final start = DateTime(day.year, day.month, day.day - 1, 23);
  return SleepNight(
    sleepDay: day,
    main: SleepSession(
      id: 'n-${day.month}-${day.day}',
      startAt: start.toUtc(),
      endAt: start.add(Duration(minutes: (hours * 60).round())).toUtc(),
      startOffsetMinutes: start.timeZoneOffset.inMinutes,
      endOffsetMinutes: start.timeZoneOffset.inMinutes,
      provenance: SleepProvenance.manual(ingestedAt: _now, providerName: 'You'),
    ),
    targets: SleepTargets.defaults,
  );
}

Future<SleepController> _pump(
  WidgetTester tester,
  List<SleepNight> nights,
) async {
  final repository = InMemorySleepRepository();
  await repository.saveTargets(SleepTargets.defaults);
  if (nights.isNotEmpty) await repository.upsertNights(nights);

  final controller = SleepController(
    repository: repository,
    service: SleepService(
      repository: repository,
      source: _IdleSource(),
      now: () => _now,
    ),
    now: () => _now,
  );
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(home: SleepWeekPage(controller: controller)),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  // The page is one long scroll and a ListView builds only what is visible,
  // so the default 800x600 surface would leave the lower sections unbuilt —
  // and "not rendered" reads exactly like "not found".
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1400, 4400);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('a full week reports its averages with the n behind them', (
    tester,
  ) async {
    await _pump(tester, [
      for (var day = 2; day <= 8; day++) _night(DateTime(2026, 9, day)),
    ]);

    expect(findTextIgnoringBidi('TYPICAL NIGHT'), findsOneWidget);
    expect(findTextIgnoringBidi('7 of 7 nights'), findsWidgets);
    // No gate has failed, so no column is showing an em dash.
    expect(findTextIgnoringBidi('—'), findsNothing);
  });

  testWidgets('figures below their gate show what would open them, not a '
      'number', (tester) async {
    // One night is below every window gate. The three duration figures and
    // the two clock figures must each say what would open them rather than
    // averaging a single night into a "typical night".
    await _pump(tester, [_night(DateTime(2026, 9, 8))]);

    expect(findTextIgnoringBidi('—'), findsNWidgets(6));
    // The *requirement*, not the coverage. These sit directly under a section
    // header reading "1 of 7 nights", and when they read "1 of 3 nights" the
    // card showed the same shape seven times for two different facts.
    expect(findTextIgnoringBidi('Needs 3 nights'), findsNWidgets(5));
    expect(findTextIgnoringBidi('Needs 5 nights'), findsOneWidget);
    expect(findTextIgnoringBidi('1 of 3 nights'), findsNothing);
  });

  testWidgets('a day with no record is a row that says so, never a zero', (
    tester,
  ) async {
    // Filtering the empty days out would turn a three-night week into a
    // three-day week and quietly delete the most actionable thing on the page.
    await _pump(tester, [
      _night(DateTime(2026, 9, 8)),
      _night(DateTime(2026, 9, 6)),
      _night(DateTime(2026, 9, 3)),
    ]);

    expect(findTextIgnoringBidi('Nothing recorded'), findsNWidgets(4));
    expect(findTextIgnoringBidi('0h 0m'), findsNothing);
    expect(findTextIgnoringBidi('3 of 7 nights'), findsWidgets);
  });

  testWidgets('an empty week says it is empty', (tester) async {
    await _pump(tester, const []);

    expect(
      findTextIgnoringBidi('No nights were recorded in this week.'),
      findsOneWidget,
    );
    // Nothing to average, so the sections that would average it are absent
    // rather than rendering seven gated columns.
    expect(findTextIgnoringBidi('TYPICAL NIGHT'), findsNothing);
    expect(findTextIgnoringBidi('EVERY NIGHT'), findsNothing);
  });

  testWidgets('a week with no staged night says so instead of a chart', (
    tester,
  ) async {
    // Manual entries carry no stages. A composition chart over them would be
    // invented, so the section states the absence and names nothing.
    await _pump(tester, [
      for (var day = 2; day <= 8; day++) _night(DateTime(2026, 9, day)),
    ]);

    expect(
      findTextIgnoringBidi('No night this week carried stage detail.'),
      findsOneWidget,
    );
  });

  testWidgets('the trend states its own gate rather than vanishing', (
    tester,
  ) async {
    // The gate could not open at all before the sync window was widened, and
    // a section that simply disappeared gave no way to notice. It now names
    // exactly what would open it.
    await _pump(tester, [
      for (var day = 2; day <= 8; day++) _night(DateTime(2026, 9, day)),
    ]);

    expect(findTextIgnoringBidi('LONGER RUN'), findsOneWidget);
    expect(
      findTextIgnoringBidi(
        'A trend needs 14 nights across 21 days. You have 7.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('paging back shows the earlier week, dated', (tester) async {
    await _pump(tester, [
      for (var day = 2; day <= 8; day++) _night(DateTime(2026, 9, day)),
    ]);

    expect(findTextIgnoringBidi('This week'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Earlier week'));
    await tester.pumpAndSettle();

    // The week before the seeded run has nothing in it — and says so, rather
    // than continuing to show the week we just left.
    expect(findTextIgnoringBidi('This week'), findsNothing);
    expect(
      findTextIgnoringBidi('No nights were recorded in this week.'),
      findsOneWidget,
    );
  });
}
