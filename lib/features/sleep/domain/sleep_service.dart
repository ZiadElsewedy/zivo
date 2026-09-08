import 'package:flutter/foundation.dart';

import 'sleep_night.dart';
import 'sleep_provenance.dart';
import 'sleep_repository.dart';
import 'sleep_resolver.dart';
import 'sleep_session.dart';
import 'sleep_sessionizer.dart';
import 'sleep_source.dart';
import 'sleep_targets.dart';

/// Drives the ingest pipeline and owns manual logging. Depends only on the two
/// `domain/` interfaces, so tests run it against fakes with no Firebase and no
/// platform channel — the same shape as `expenses_service.dart`.
///
/// ```
/// SleepSource.readRecords          raw platform records
///   → SleepSessionizer.sessionize  stitched, one provider at a time
///   → (+ the user's own sessions)  edits and manual logs, preserved
///   → SleepResolver.resolve        one night per sleep-day, conflicts settled
///   → SleepRepository.upsertNights keyed by sleep-day, so re-sync converges
/// ```
class SleepService {
  SleepService({
    required this.repository,
    required this.source,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SleepRepository repository;
  final SleepSource source;
  final DateTime Function() _now;

  /// How far back a first sync reaches.
  ///
  /// Ninety nights is what the longest window in `sleep_metrics.dart` needs
  /// (a trend wants a fortnight; a month of context makes the first week
  /// meaningful) with room over. On Android anything past thirty days needs
  /// `READ_HEALTH_DATA_HISTORY`, which is requested alongside read access and
  /// whose refusal costs history, not the feature.
  static const int backfillDays = 90;

  /// The window a routine refresh re-reads.
  ///
  /// Not just last night: a watch can sync a night hours late, an upstream
  /// record can be edited days after the fact, and the resolver has to see the
  /// whole picture for a day to settle it correctly.
  static const int refreshDays = 7;

  /// The shortest gap between two automatic syncs.
  ///
  /// Used by [syncIfStale], which is what the app's resume handler calls.
  /// Foregrounding is a frequent event — a notification glance, an app switch,
  /// unlocking the phone — and reading the whole health store on every one of
  /// them would spend battery re-deriving a night that has not changed. Ten
  /// minutes is short enough that coming back to ZIVO after waking up always
  /// re-reads, and long enough that flicking between apps does not.
  static const Duration minAutoSyncInterval = Duration(minutes: 10);

  /// Where the last sync got to.
  ///
  /// A [ValueNotifier] rather than a stream, and that is load-bearing. A
  /// broadcast stream wrapped in an `async*` generator has a window between
  /// `listen()` and the generator actually subscribing, and `sync()` is called
  /// **synchronously right after** the listener is attached — so a sync that
  /// settles quickly (no provider on this host, permission refused) emitted
  /// its terminal state straight into that window and the UI never saw it,
  /// leaving an "unavailable" host rendering the "nothing recorded yet"
  /// screen. A notifier has no such window: listeners read `.value`, which is
  /// always current. Same reason `MediaService.backupConnected` is one.
  final ValueNotifier<SleepSyncState> syncState =
      ValueNotifier<SleepSyncState>(const SleepSyncState.idle());

  /// The sync currently running, so concurrent callers join it. See [sync].
  Future<void>? _inFlight;

  /// When the last sync *started*. Drives [syncIfStale]'s throttle.
  DateTime? _lastSyncAt;

  /// Whether this process has already reached back [backfillDays].
  ///
  /// One deep read per launch is the budget: it is what fills the windows the
  /// longer metrics need, and repeating it on every refresh would re-read
  /// ninety nights to learn about one.
  bool _backfilled = false;

  /// How far back a routine `sync()` reaches.
  ///
  /// **This is the fix for a gate that could never open.** Every automatic
  /// sync passed no `days` and so read [refreshDays] — one week — while
  /// `SleepGates.minNightsForTrend` needs fourteen nights spread over
  /// twenty-one days, and the week-over-week comparison needs two full weeks.
  /// [backfillDays] was only ever reached from `requestAccess`, so a user who
  /// granted health access outside ZIVO (or granted it before an update)
  /// accumulated history a week at a time and the trend insight was
  /// unreachable in practice — not gated, *unreachable*, which looks from the
  /// outside exactly like a broken feature.
  ///
  /// So the first sync of each process reaches [backfillDays] whenever stored
  /// history is shorter than that window, and every sync after it is the cheap
  /// seven-day pass.
  int _routineWindowDays() {
    if (_backfilled) return refreshDays;
    _backfilled = true;
    final stored = repository.current;
    if (stored.isEmpty) return backfillDays;
    final oldest = stored
        .map((night) => night.sleepDay)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final covered = _now().difference(oldest).inDays;
    // A week of slack: history that reaches almost to the backfill horizon is
    // already as deep as a backfill would make it.
    return covered >= backfillDays - refreshDays ? refreshDays : backfillDays;
  }

  /// Reads the platform store and writes resolved nights.
  ///
  /// Never throws: every failure becomes a [SleepSyncState] the UI can render,
  /// because "we could not look" and "we looked and found nothing" are
  /// different sentences and only one of them is the user's problem to fix.
  ///
  /// **Concurrent calls join the sync already running** rather than returning
  /// immediately. They used to return a completed future the instant one was
  /// in flight, which meant pull-to-refresh dropped its spinner in the same
  /// frame it appeared and [SleepController.retryLoad] reported success before
  /// the read it was waiting on had started — both showing "done" for work
  /// that had not happened.
  Future<void> sync({int? days}) {
    final running = _inFlight;
    if (running != null) return running;
    final future = _sync(days: days);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  /// Syncs only if it has been at least [minAutoSyncInterval] since the last
  /// one — the entry point for automatic refreshes (app launch, app resume).
  ///
  /// This is what stops the rest of the app showing a night from three days
  /// ago. Today's sleep glance and the Hub's sleep card read the Firestore
  /// mirror directly, and *nothing outside the Sleep page ever triggered a
  /// read of the health store*, so a user who never opened Sleep saw whatever
  /// was written the last time they did — for as long as that took.
  Future<void> syncIfStale({int? days}) {
    final last = _lastSyncAt;
    if (last != null && _now().difference(last) < minAutoSyncInterval) {
      return Future.value();
    }
    return sync(days: days);
  }

  Future<void> _sync({int? days}) async {
    _emit(const SleepSyncState(status: SleepSyncStatus.syncing));

    final now = _now();
    _lastSyncAt = now;
    final window = Duration(days: days ?? _routineWindowDays());
    // An explicit deep read (the one `requestAccess` does) counts as the
    // process's backfill; otherwise the next routine sync would do it again.
    if (window.inDays >= backfillDays) _backfilled = true;
    final from = now.subtract(window);

    try {
      if (!await source.isAvailable()) {
        _emit(
          SleepSyncState(
            status: SleepSyncStatus.unavailable,
            authorization: SleepAuthorization.unavailable,
            at: now,
          ),
        );
        return;
      }

      final authorization = await source.authorizationStatus();
      if (authorization == SleepAuthorization.denied) {
        _emit(
          SleepSyncState(
            status: SleepSyncStatus.permissionDenied,
            authorization: authorization,
            at: now,
          ),
        );
        return;
      }

      final records = await source.readRecords(from: from, to: now);
      final platformSessions = SleepSessionizer.sessionize(
        records,
        ingestedAt: now,
      );

      await _resolveAndStore(
        platformSessions: platformSessions,
        windowStart: from,
        windowEnd: now,
        at: now,
      );

      _emit(
        SleepSyncState(
          status: SleepSyncStatus.idle,
          authorization: authorization,
          at: now,
          // An empty read under an unknowable authorization is the one case we
          // must not narrate as "no data" — on iOS a refusal looks exactly
          // like an empty store, and asserting emptiness would be a claim we
          // have no basis for.
          nothingVisible:
              records.isEmpty && authorization != SleepAuthorization.granted,
        ),
      );
    } on SleepSourceException catch (e) {
      _emit(
        SleepSyncState(
          status: switch (e.kind) {
            SleepSourceFailure.permissionDenied =>
              SleepSyncStatus.permissionDenied,
            SleepSourceFailure.providerUnavailable =>
              SleepSyncStatus.unavailable,
            SleepSourceFailure.historyWindowExceeded =>
              SleepSyncStatus.historyUnavailable,
            SleepSourceFailure.unknown => SleepSyncStatus.failed,
          },
          at: now,
        ),
      );
    } catch (_) {
      _emit(SleepSyncState(status: SleepSyncStatus.failed, at: now));
    }
  }

  /// "I'm going to sleep." Opens a mark; nothing becomes a night until the
  /// matching wake arrives.
  Future<void> markGoingToSleep({String? note}) async {
    final now = _now();
    await repository.openMark(
      SleepMark(
        id: 'open',
        atUtc: now.toUtc(),
        offsetMinutes: now.timeZoneOffset.inMinutes,
        note: note,
      ),
    );
  }

  /// "I'm awake." Closes the open mark into a night.
  ///
  /// The result is always [SleepMethod.userReported] — the user told us when
  /// they went to bed and got up, which is real information and is not a
  /// measurement. Returns false when there was no open mark, or when the wake
  /// is not after the sleep.
  Future<bool> markAwake({required String providerName}) async {
    final mark = repository.currentOpenMark;
    if (mark == null) return false;

    final now = _now();
    final session = sessionFromMarks(
      sleepMark: mark,
      wakeAtUtc: now.toUtc(),
      wakeOffsetMinutes: now.timeZoneOffset.inMinutes,
      ingestedAt: now,
      providerName: providerName,
    );
    if (session == null) return false;

    await _mergeUserSession(session, at: now);
    await repository.clearOpenMark();
    return true;
  }

  /// The user corrected a night by hand.
  ///
  /// Written as an override rather than an edit in place: the measured session
  /// it replaces stays in the night's alternates, so the record of what the
  /// device reported survives the user disagreeing with it.
  Future<void> editNight({
    required DateTime sleepDay,
    required DateTime startAtUtc,
    required DateTime endAtUtc,
    required String providerName,
  }) async {
    if (!endAtUtc.isAfter(startAtUtc)) return;
    final now = _now();
    final existing = _nightFor(sleepDay);

    final offset = now.timeZoneOffset.inMinutes;
    final session = SleepSession(
      id: 'manual:${startAtUtc.toUtc().toIso8601String()}',
      startAt: startAtUtc.toUtc(),
      endAt: endAtUtc.toUtc(),
      startOffsetMinutes: existing?.main?.startOffsetMinutes ?? offset,
      endOffsetMinutes: existing?.main?.endOffsetMinutes ?? offset,
      provenance: SleepProvenance.manual(
        ingestedAt: now,
        providerName: providerName,
      ),
      // Non-null even with nothing to supersede: it is what marks this session
      // as the user's own statement, which is what the resolver ranks above
      // every sensor.
      supersedes: existing?.main?.id ?? 'none',
    );

    await _mergeUserSession(session, at: now);
  }

  Future<void> saveTargets(SleepTargets targets) =>
      repository.saveTargets(targets);

  void dispose() => syncState.dispose();

  /// Folds one user-authored session into its night, keeping everything the
  /// night already knew as alternates.
  Future<void> _mergeUserSession(
    SleepSession session, {
    required DateTime at,
  }) async {
    final sleepDay = SleepResolver.sleepDayOf(session);
    final existing = _nightFor(sleepDay);
    final candidates = <SleepSession>[
      session,
      ...?existing?.alternates,
      if (existing?.main != null) existing!.main!,
      ...?existing?.naps,
    ];

    final resolved = SleepResolver.resolve(
      candidates,
      targets: existing?.targets ?? repository.currentTargets,
      updatedAt: at,
    );
    if (resolved.isEmpty) return;
    await repository.upsertNights(resolved);
  }

  /// Resolves the synced window and writes it, preserving anything the user
  /// authored.
  ///
  /// The preservation is the point. A plain overwrite would silently undo
  /// every manual correction on the next refresh — the user fixes a night,
  /// the app re-reads Health an hour later, and their fix is gone. So each
  /// day's stored user sessions are fed back in as candidates and the resolver
  /// ranks them where it always does: above the sensors.
  Future<void> _resolveAndStore({
    required List<SleepSession> platformSessions,
    required DateTime windowStart,
    required DateTime windowEnd,
    required DateTime at,
  }) async {
    final stored = repository.current;
    final targets = repository.currentTargets;

    final userSessions = <SleepSession>[
      for (final night in stored)
        if (_within(night.sleepDay, windowStart, windowEnd)) ...[
          if (night.main != null && _isUserAuthored(night.main!)) night.main!,
          for (final alt in night.alternates)
            if (_isUserAuthored(alt)) alt,
        ],
    ];

    final resolved = SleepResolver.resolve(
      [...platformSessions, ...userSessions],
      targets: targets,
      updatedAt: at,
    );

    if (resolved.isNotEmpty) await repository.upsertNights(resolved);

    // A night inside the window that now resolves to nothing has had every
    // record behind it deleted upstream. Withdrawing it here is what makes a
    // deletion in Apple Health or Health Connect propagate, rather than
    // leaving a night ZIVO alone still believes in.
    final resolvedDays = {
      for (final night in resolved) _dayKey(night.sleepDay),
    };
    for (final night in stored) {
      if (!_within(night.sleepDay, windowStart, windowEnd)) continue;
      if (resolvedDays.contains(_dayKey(night.sleepDay))) continue;
      if (!night.hasData) continue;
      await repository.removeNight(night.sleepDay);
    }
  }

  /// Whether the user, rather than a device, produced this session.
  static bool _isUserAuthored(SleepSession session) =>
      session.provenance.providerId == SleepProvenance.manualProviderId ||
      session.supersedes != null;

  SleepNight? _nightFor(DateTime sleepDay) {
    for (final night in repository.current) {
      if (_dayKey(night.sleepDay) == _dayKey(sleepDay)) return night;
    }
    return null;
  }

  static bool _within(DateTime day, DateTime from, DateTime to) =>
      !day.isBefore(DateTime(from.year, from.month, from.day)) &&
      !day.isAfter(DateTime(to.year, to.month, to.day));

  static String _dayKey(DateTime day) =>
      '${day.year}-${day.month}-${day.day}';

  void _emit(SleepSyncState state) => syncState.value = state;
}

/// Where the last sync got to. Every failure mode is a named state with its
/// own sentence on screen — none of them may render as a spinner that never
/// resolves, and none may render as a zero.
class SleepSyncState {
  const SleepSyncState({
    required this.status,
    this.authorization,
    this.at,
    this.nothingVisible = false,
  });

  const SleepSyncState.idle() : this(status: SleepSyncStatus.idle);

  final SleepSyncStatus status;
  final SleepAuthorization? authorization;
  final DateTime? at;

  /// The read came back empty **and** we cannot confirm we were allowed to
  /// look. Distinct from "no data": on iOS a refusal is indistinguishable from
  /// an empty store, so this is the flag that keeps the UI from asserting one
  /// when it might be the other.
  final bool nothingVisible;

  bool get isSyncing => status == SleepSyncStatus.syncing;
}

enum SleepSyncStatus {
  idle,
  syncing,

  /// No health provider on this host — manual logging still works.
  unavailable,

  /// The platform said no. Android only; iOS never says.
  permissionDenied,

  /// Android refused history beyond thirty days.
  historyUnavailable,

  failed,
}
