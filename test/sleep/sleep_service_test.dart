import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/sleep/data/in_memory_sleep_repository.dart';
import 'package:zivo/features/sleep/domain/sleep_provenance.dart';
import 'package:zivo/features/sleep/domain/sleep_service.dart';
import 'package:zivo/features/sleep/domain/sleep_session.dart';
import 'package:zivo/features/sleep/domain/sleep_source.dart';

/// Cover for the ingest pipeline's behaviour over time — the failures that
/// only appear on the *second* sync.
class _FakeSleepSource implements SleepSource {
  // Mutable fields rather than constructor arguments: every test here sets
  // them mid-flight, to change what the platform reports BETWEEN two syncs.
  List<RawSleepRecord> records = const [];
  bool available = true;
  SleepAuthorization authorization = SleepAuthorization.granted;
  SleepSourceFailure? failure;
  int readCount = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<SleepAuthorization> authorizationStatus() async => authorization;

  @override
  Future<bool> requestAuthorization() async => true;

  @override
  Future<List<RawSleepRecord>> readRecords({
    required DateTime from,
    required DateTime to,
  }) async {
    readCount++;
    final f = failure;
    if (f != null) throw SleepSourceException(f);
    return records;
  }
}

RawSleepRecord _watchNight({
  required DateTime start,
  required DateTime end,
  String providerId = 'com.apple.health',
}) => RawSleepRecord(
  id: '$providerId:${start.toIso8601String()}',
  startAt: start,
  endAt: end,
  startOffsetMinutes: 0,
  endOffsetMinutes: 0,
  stage: SleepStage.asleepUnspecified,
  providerId: providerId,
  providerName: 'Apple Health',
  deviceKind: SleepDeviceKind.watch,
  recordingMethod: SleepRecordingMethod.automatic,
);

void main() {
  late InMemorySleepRepository repository;
  late _FakeSleepSource source;
  late SleepService service;

  // Pinned so the sync window is deterministic.
  final now = DateTime(2026, 9, 7, 12);

  setUp(() {
    repository = InMemorySleepRepository();
    source = _FakeSleepSource();
    service = SleepService(
      repository: repository,
      source: source,
      now: () => now,
    );
  });

  tearDown(() {
    service.dispose();
    repository.dispose();
  });

  test('a synced night is stored under the day it was woken from', () async {
    source.records = [
      _watchNight(
        start: DateTime.utc(2026, 9, 6, 23),
        end: DateTime.utc(2026, 9, 7, 7),
      ),
    ];

    await service.sync();

    expect(repository.current, hasLength(1));
    expect(repository.current.single.sleepDay, DateTime(2026, 9, 7));
    expect(
      repository.current.single.main!.provenance.method,
      SleepMethod.measuredWearable,
    );
  });

  test('a user edit survives the next sync', () async {
    // The regression this exists for: a plain overwrite would silently undo
    // every manual correction an hour later, when the app re-reads Health.
    source.records = [
      _watchNight(
        start: DateTime.utc(2026, 9, 6, 23, 47),
        end: DateTime.utc(2026, 9, 7, 7),
      ),
    ];
    await service.sync();

    await service.editNight(
      sleepDay: DateTime(2026, 9, 7),
      startAtUtc: DateTime.utc(2026, 9, 6, 22, 30),
      endAtUtc: DateTime.utc(2026, 9, 7, 7),
      providerName: 'You',
    );
    expect(
      repository.current.single.main!.startAt,
      DateTime.utc(2026, 9, 6, 22, 30),
    );

    await service.sync();

    final night = repository.current.single;
    expect(night.main!.startAt, DateTime.utc(2026, 9, 6, 22, 30));
    expect(night.main!.provenance.method, SleepMethod.userReported);
    // And the measurement it overrode is still on record.
    expect(
      night.alternates.any(
        (a) => a.startAt == DateTime.utc(2026, 9, 6, 23, 47),
      ),
      isTrue,
    );
  });

  test('a night deleted upstream is withdrawn here too', () async {
    source.records = [
      _watchNight(
        start: DateTime.utc(2026, 9, 6, 23),
        end: DateTime.utc(2026, 9, 7, 7),
      ),
    ];
    await service.sync();
    expect(repository.current, hasLength(1));

    // The user deleted the night in Apple Health.
    source.records = [];
    await service.sync();

    expect(repository.current, isEmpty);
  });

  test('manual logging produces a user-reported night, never a measured one',
      () async {
    final logger = SleepService(
      repository: repository,
      source: source,
      now: () => DateTime(2026, 9, 6, 23),
    );
    await logger.markGoingToSleep();
    expect(repository.currentOpenMark, isNotNull);
    logger.dispose();

    final waker = SleepService(
      repository: repository,
      source: source,
      now: () => DateTime(2026, 9, 7, 7),
    );
    final closed = await waker.markAwake(providerName: 'You');
    waker.dispose();

    expect(closed, isTrue);
    expect(repository.currentOpenMark, isNull);

    final night = repository.current.single;
    expect(night.main!.provenance.method, SleepMethod.userReported);
    expect(night.main!.provenance.confidence, SleepConfidence.low);
    expect(night.main!.asleepDuration, const Duration(hours: 8));
  });

  test('waking with no open mark changes nothing', () async {
    expect(await service.markAwake(providerName: 'You'), isFalse);
    expect(repository.current, isEmpty);
  });

  test('a missing provider is a named state, not an exception', () async {
    source.available = false;
    await service.sync();

    expect(service.syncState.value.status, SleepSyncStatus.unavailable);
    expect(repository.current, isEmpty);
  });

  test('a denied read is distinguished from an empty store', () async {
    source.authorization = SleepAuthorization.denied;
    await service.sync();

    expect(service.syncState.value.status, SleepSyncStatus.permissionDenied);
    expect(source.readCount, 0);
  });

  test('an empty read under unknowable authorization is flagged, not asserted',
      () async {
    // The iOS case: Apple never reports read denial, so an empty result may
    // mean "refused". ZIVO must not turn that into "you have no sleep data".
    source.authorization = SleepAuthorization.unknown;
    source.records = [];
    await service.sync();

    expect(service.syncState.value.status, SleepSyncStatus.idle);
    expect(service.syncState.value.nothingVisible, isTrue);
  });

  test('an empty read under confirmed access is genuinely empty', () async {
    source.authorization = SleepAuthorization.granted;
    source.records = [];
    await service.sync();

    expect(service.syncState.value.nothingVisible, isFalse);
  });

  test('a source failure becomes a state rather than throwing', () async {
    source.failure = SleepSourceFailure.historyWindowExceeded;
    await service.sync();

    expect(service.syncState.value.status, SleepSyncStatus.historyUnavailable);
  });

  test('a second sync while one is running is dropped', () async {
    source.records = [
      _watchNight(
        start: DateTime.utc(2026, 9, 6, 23),
        end: DateTime.utc(2026, 9, 7, 7),
      ),
    ];
    await Future.wait([service.sync(), service.sync()]);
    expect(source.readCount, 1);
  });
}
