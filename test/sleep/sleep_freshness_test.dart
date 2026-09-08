import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/sleep/data/in_memory_sleep_repository.dart';
import 'package:zivo/features/sleep/domain/sleep_night.dart';
import 'package:zivo/features/sleep/domain/sleep_provenance.dart';
import 'package:zivo/features/sleep/domain/sleep_service.dart';
import 'package:zivo/features/sleep/domain/sleep_session.dart';
import 'package:zivo/features/sleep/domain/sleep_source.dart';
import 'package:zivo/features/sleep/domain/sleep_window.dart';
import 'package:zivo/features/sleep/presentation/controllers/sleep_controller.dart';

/// Cover for **is the number on screen the current one** — the half of this
/// feature that has nothing to do with whether the arithmetic is right.
///
/// Every failure guarded here produces a screen full of real, correctly
/// computed figures that are simply not about now: a five-day-old night under
/// the words "last night", a trend gate that no automatic sync could ever open,
/// a pull-to-refresh that reports success without reading anything. None of
/// them is visible as a bug from inside the data layer, and all of them are
/// indistinguishable from "the app has stopped working" from outside it.

/// Records the windows it was asked for, so a test can assert how far back a
/// sync actually reached.
class _RecordingSource implements SleepSource {
  final reads = <Duration>[];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<SleepAuthorization> authorizationStatus() async =>
      SleepAuthorization.granted;

  @override
  Future<bool> requestAuthorization() async => true;

  @override
  Future<List<RawSleepRecord>> readRecords({
    required DateTime from,
    required DateTime to,
  }) async {
    reads.add(to.difference(from));
    return const [];
  }
}

SleepNight _night(DateTime day) => SleepNight(
  sleepDay: day,
  main: SleepSession(
    id: 'n${day.day}',
    startAt: DateTime.utc(day.year, day.month, day.day - 1, 23),
    endAt: DateTime.utc(day.year, day.month, day.day, 7),
    startOffsetMinutes: 0,
    endOffsetMinutes: 0,
    provenance: SleepProvenance.manual(
      ingestedAt: DateTime.utc(2026, 9, 8),
      providerName: 'You',
    ),
  ),
);

void main() {
  group('SleepWindow', () {
    final nights = [
      _night(DateTime(2026, 9, 8)),
      _night(DateTime(2026, 9, 6)),
      _night(DateTime(2026, 9, 4)),
    ];

    test('fills absent days rather than closing the week up', () {
      // The fill is the whole reason the raster can draw a gap. Dropping the
      // missing days would make a three-night week look like three
      // consecutive nights, hiding the one thing a history view exists for.
      final week = SleepWindow.daysEndingOn(
        nights,
        lastDay: DateTime(2026, 9, 8),
        count: 7,
      );

      expect(week.length, 7);
      expect(week.first.sleepDay, DateTime(2026, 9, 2));
      expect(week.last.sleepDay, DateTime(2026, 9, 8));
      expect(week.where((night) => night.hasData).length, 3);
      expect(week[5].hasData, isFalse); // the 7th, absent
    });

    test('latestWithData scans rather than trusting list order', () {
      // The Firestore mirror emits newest-first and the in-memory repository
      // sorts on write, so "take the first row" happened to work. It is not a
      // property either interface promises, and taking the first row of a
      // list that arrives oldest-first silently headlines the oldest night.
      expect(
        SleepWindow.latestWithData(nights.reversed.toList())!.sleepDay,
        DateTime(2026, 9, 8),
      );
    });

    test('latestWithData skips a stored night that has no data', () {
      final withEmpty = [
        SleepNight.empty(DateTime(2026, 9, 9)),
        ...nights,
      ];
      expect(
        SleepWindow.latestWithData(withEmpty)!.sleepDay,
        DateTime(2026, 9, 8),
      );
    });

    test('ageInDays counts whole sleep-days', () {
      expect(
        SleepWindow.ageInDays(_night(DateTime(2026, 9, 4)),
            DateTime(2026, 9, 8, 22, 30)),
        4,
      );
    });
  });

  group('SleepController freshness', () {
    SleepController controllerAt(
      DateTime now,
      InMemorySleepRepository repository,
    ) => SleepController(
      repository: repository,
      service: SleepService(
        repository: repository,
        source: _RecordingSource(),
        now: () => now,
      ),
      now: () => now,
    );

    test('a night from this morning is last night, not stale', () async {
      final repository = InMemorySleepRepository();
      await repository.upsertNights([_night(DateTime(2026, 9, 8))]);
      final controller = controllerAt(DateTime(2026, 9, 8, 9), repository);
      await Future<void>.delayed(Duration.zero);

      expect(controller.latestNightAgeDays, 0);
      expect(controller.isLatestNightStale, isFalse);
      controller.dispose();
    });

    test('a night four days old is stale', () async {
      // The screen may still show it — it is the most recent thing we have —
      // but it may not call it last night.
      final repository = InMemorySleepRepository();
      await repository.upsertNights([_night(DateTime(2026, 9, 4))]);
      final controller = controllerAt(DateTime(2026, 9, 8, 9), repository);
      await Future<void>.delayed(Duration.zero);

      expect(controller.latestNightAgeDays, 4);
      expect(controller.isLatestNightStale, isTrue);
      controller.dispose();
    });

    test('the headline baseline excludes the night it describes', () async {
      // Comparing a night against an average it is part of pulls the average
      // toward the night and shrinks every difference — most severely on the
      // sparse weeks where a reader is least able to notice.
      final repository = InMemorySleepRepository();
      await repository.upsertNights([
        for (var day = 2; day <= 8; day++) _night(DateTime(2026, 9, day)),
      ]);
      final controller = controllerAt(DateTime(2026, 9, 8, 9), repository);
      await Future<void>.delayed(Duration.zero);

      expect(controller.week.where((n) => n.hasData).length, 7);
      // Six: the seven stored nights less the one being described.
      expect(controller.baselineMetrics.nightCount, 6);
      controller.dispose();
    });
  });

  group('SleepService sync windows', () {
    test('the first sync of a process backfills, later ones do not', () async {
      // The bug this pins: every automatic sync passed no `days` and so read
      // one week, while the trend gate needs fourteen nights across
      // twenty-one days. `backfillDays` was reachable only from
      // `requestAccess`, so a user who granted health access outside ZIVO
      // accumulated history a week at a time and the trend was not gated —
      // it was unreachable.
      final source = _RecordingSource();
      final service = SleepService(
        repository: InMemorySleepRepository(),
        source: source,
        now: () => DateTime(2026, 9, 8),
      );

      await service.sync();
      await service.sync();

      expect(source.reads.first.inDays, SleepService.backfillDays);
      expect(source.reads[1].inDays, SleepService.refreshDays);
      service.dispose();
    });

    test('a store that already holds deep history skips the backfill',
        () async {
      final repository = InMemorySleepRepository();
      await repository.upsertNights([_night(DateTime(2026, 5, 20))]);
      final source = _RecordingSource();
      final service = SleepService(
        repository: repository,
        source: source,
        now: () => DateTime(2026, 9, 8),
      );

      await service.sync();

      expect(source.reads.single.inDays, SleepService.refreshDays);
      service.dispose();
    });

    test('concurrent syncs join the one in flight instead of returning early',
        () async {
      // A second caller used to get a completed future the instant a sync was
      // running — so pull-to-refresh dropped its spinner in the frame it
      // appeared, and `retryLoad` reported success before the read it was
      // waiting on had begun. Both showed "done" for work that had not
      // happened.
      final source = _RecordingSource();
      final service = SleepService(
        repository: InMemorySleepRepository(),
        source: source,
        now: () => DateTime(2026, 9, 8),
      );

      await Future.wait([service.sync(), service.sync()]);

      expect(source.reads.length, 1);
      service.dispose();
    });

    test('syncIfStale reads once inside the throttle window', () async {
      // Today, the Hub and the Sleep page all ask for a refresh on the way in.
      // They share one budget, so waking up and tapping through to Sleep costs
      // one read of the health store, not three.
      var now = DateTime(2026, 9, 8, 7);
      final source = _RecordingSource();
      final service = SleepService(
        repository: InMemorySleepRepository(),
        source: source,
        now: () => now,
      );

      await service.syncIfStale();
      await service.syncIfStale();
      expect(source.reads.length, 1);

      now = now.add(SleepService.minAutoSyncInterval * 2);
      await service.syncIfStale();
      expect(source.reads.length, 2);
      service.dispose();
    });
  });
}
