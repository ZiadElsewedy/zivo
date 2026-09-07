import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../domain/sleep_provenance.dart';
import '../domain/sleep_session.dart';
import '../domain/sleep_source.dart';

/// The real [SleepSource]: HealthKit on iOS, Health Connect on Android, via
/// the `health` package.
///
/// Everything platform-shaped stops here. Above this file nothing knows that
/// iOS hands back a cloud of loose samples while Android hands back sessions
/// with stages attached, or that the two use different words for the same
/// sleep stage (`docs/SLEEP_SYSTEM.md` §17).
///
/// ## Known limits of this implementation
///
/// Two things the package does not surface, both recorded here because they
/// are the trigger for the native-channel migration in ADR-010, not silent
/// shortcomings:
///
/// * **No Health Connect `Metadata.device.type`.** So on Android a record's
///   [SleepDeviceKind] is [SleepDeviceKind.unknown] and tiering falls to the
///   writing package name plus `recordingMethod` — which is why
///   `kWearableProviderPrefixes` exists and why it lists Android packages.
/// * **No stored zone offsets.** Health Connect keeps the offset the sleep was
///   *recorded* in; the package returns plain `DateTime`s, so we record the
///   offset this device would apply to that instant. Correct for anyone
///   sleeping in their own time zone; a night slept abroad and reviewed at home
///   renders in home time until the native layer lands.
class HealthSleepSource implements SleepSource {
  HealthSleepSource({Health? health}) : _health = health ?? Health();

  final Health _health;
  bool _configured = false;

  /// The sleep types worth asking for, per platform.
  ///
  /// Requesting a type the platform does not have makes the package throw, so
  /// the two lists are separate rather than one filtered list — iOS has no
  /// `SLEEP_SESSION` (HealthKit has no session type at all) and no
  /// out-of-bed/awake-in-bed values.
  static const List<HealthDataType> _iosTypes = [
    HealthDataType.SLEEP_IN_BED,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];

  static const List<HealthDataType> _androidTypes = [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_AWAKE_IN_BED,
    HealthDataType.SLEEP_OUT_OF_BED,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_UNKNOWN,
  ];

  /// The types this host can actually be asked about.
  static List<HealthDataType> get types {
    if (kIsWeb) return const [];
    if (Platform.isIOS) return _iosTypes;
    if (Platform.isAndroid) return _androidTypes;
    return const [];
  }

  /// Whether this host could have a health provider at all. Cheap, synchronous,
  /// and the thing `app.dart` branches on when deciding whether to build a real
  /// source or [UnsupportedSleepSource].
  static bool get isSupportedHost =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  Future<bool> isAvailable() async {
    if (!isSupportedHost) return false;
    if (Platform.isIOS) return true;
    // Android below 14 needs the Health Connect APK, which may simply not be
    // installed. Reporting that honestly lets the feature degrade to manual
    // logging instead of throwing at the first read.
    try {
      await _ensureConfigured();
      final status = await _health.getHealthConnectSdkStatus();
      return status == HealthConnectSdkStatus.sdkAvailable;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SleepAuthorization> authorizationStatus() async {
    if (!isSupportedHost) return SleepAuthorization.unavailable;
    if (!await isAvailable()) return SleepAuthorization.unavailable;
    await _ensureConfigured();

    final granted = await _health.hasPermissions(
      types,
      permissions: List.filled(types.length, HealthDataAccess.READ),
    );

    // `null` is the normal iOS answer and is not a bug: Apple refuses to
    // disclose read denial, so "denied" and "we never asked" are the same
    // observation. Anything downstream that turns this into "you have no
    // sleep data" is telling the user something we do not know.
    if (granted == null) return SleepAuthorization.unknown;
    return granted ? SleepAuthorization.granted : SleepAuthorization.denied;
  }

  @override
  Future<bool> requestAuthorization() async {
    if (!isSupportedHost) return false;
    await _ensureConfigured();
    try {
      final ok = await _health.requestAuthorization(
        types,
        permissions: List.filled(types.length, HealthDataAccess.READ),
      );
      // A backfill reaches past 30 days, which Android refuses without this
      // extra grant. Asked separately and best-effort: a refusal costs the
      // user their history, not the feature.
      if (ok && Platform.isAndroid) {
        try {
          if (await _health.isHealthDataHistoryAvailable() &&
              !await _health.isHealthDataHistoryAuthorized()) {
            await _health.requestHealthDataHistoryAuthorization();
          }
        } catch (_) {
          // Non-fatal — reads inside 30 days still work.
        }
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<RawSleepRecord>> readRecords({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!isSupportedHost) {
      throw const SleepSourceException(SleepSourceFailure.providerUnavailable);
    }
    await _ensureConfigured();

    final List<HealthDataPoint> points;
    try {
      points = await _health.getHealthDataFromTypes(
        types: types,
        startTime: from,
        endTime: to,
      );
    } on Exception catch (e) {
      throw SleepSourceException(_classify(e), e.toString());
    }

    return Platform.isAndroid ? _mapAndroid(points) : _mapIos(points);
  }

  /// iOS: every point is a flat interval sample. They are fragments of nights,
  /// so none is [RawSleepRecord.preSessionized] and all of them go through the
  /// stitcher.
  List<RawSleepRecord> _mapIos(List<HealthDataPoint> points) {
    final records = <RawSleepRecord>[];
    for (final point in points) {
      final stage = _stageForType(point.type);
      if (stage == null) continue;
      records.add(_rawFrom(point, stage: stage, providerId: point.sourceId));
    }
    return records;
  }

  /// Android: `SLEEP_SESSION` points are whole nights; the stage points are
  /// their contents.
  ///
  /// They are joined by **uuid**, not by time containment — the plugin stamps
  /// each stage with its parent session's `metadata.id`, which is an exact key
  /// where overlap arithmetic would only be a good guess. Stage points also
  /// arrive with an empty `sourceId`, so the provider is taken from the parent.
  ///
  /// A stage point whose parent is missing (an app that wrote stages without a
  /// session) is not dropped — it falls through to the stitcher as a sample,
  /// exactly like an iOS fragment.
  List<RawSleepRecord> _mapAndroid(List<HealthDataPoint> points) {
    final sessions = points
        .where((p) => p.type == HealthDataType.SLEEP_SESSION)
        .toList();
    final stagePoints = points
        .where((p) => p.type != HealthDataType.SLEEP_SESSION)
        .toList();

    final stagesByUuid = <String, List<SleepStageSegment>>{};
    final orphans = <HealthDataPoint>[];
    final sessionUuids = {for (final s in sessions) s.uuid};

    for (final point in stagePoints) {
      final stage = _stageForType(point.type);
      if (stage == null) continue;
      if (!sessionUuids.contains(point.uuid)) {
        orphans.add(point);
        continue;
      }
      stagesByUuid.putIfAbsent(point.uuid, () => []).add(
        SleepStageSegment(
          startAt: point.dateFrom.toUtc(),
          endAt: point.dateTo.toUtc(),
          stage: stage,
        ),
      );
    }

    return [
      for (final session in sessions)
        _rawFrom(
          session,
          stage: SleepStage.asleepUnspecified,
          providerId: session.sourceId,
          stages: stagesByUuid[session.uuid] ?? const [],
          preSessionized: true,
        ),
      for (final orphan in orphans)
        _rawFrom(
          orphan,
          stage: _stageForType(orphan.type)!,
          // Stage points carry an empty sourceId; the writing package's name
          // is the only handle we have on an orphan.
          providerId: orphan.sourceId.isEmpty
              ? orphan.sourceName
              : orphan.sourceId,
        ),
    ];
  }

  RawSleepRecord _rawFrom(
    HealthDataPoint point, {
    required SleepStage stage,
    required String providerId,
    List<SleepStageSegment> stages = const [],
    bool preSessionized = false,
  }) {
    final start = point.dateFrom;
    final end = point.dateTo;
    return RawSleepRecord(
      id: point.uuid,
      startAt: start.toUtc(),
      endAt: end.toUtc(),
      // `timeZoneOffset` on a local DateTime resolves that instant's own
      // offset, so a night either side of a DST change gets the offset that
      // was actually in force at each end rather than today's.
      startOffsetMinutes: start.isUtc ? 0 : start.timeZoneOffset.inMinutes,
      endOffsetMinutes: end.isUtc ? 0 : end.timeZoneOffset.inMinutes,
      stage: stage,
      stages: stages,
      preSessionized: preSessionized,
      providerId: providerId.isEmpty ? point.sourceName : providerId,
      providerName: point.sourceName,
      deviceKind: _deviceKindFor(point),
      recordingMethod: _recordingMethodFor(point.recordingMethod),
    );
  }

  /// Which hardware wrote this, as far as the platform will say.
  ///
  /// iOS gives `deviceModel` (`Watch6,1`, `iPhone14,2`), which is decisive.
  /// Android gives nothing usable here, so the answer is honestly
  /// [SleepDeviceKind.unknown] and `methodFor` tiers on the package name
  /// instead — see the class doc.
  SleepDeviceKind _deviceKindFor(HealthDataPoint point) {
    final model = point.deviceModel?.toLowerCase();
    if (model == null || model.isEmpty) return SleepDeviceKind.unknown;
    if (model.startsWith('watch')) return SleepDeviceKind.watch;
    if (model.startsWith('iphone') || model.startsWith('ipad')) {
      return SleepDeviceKind.phone;
    }
    return SleepDeviceKind.unknown;
  }

  /// The platform's measured-or-typed flag, preserved verbatim. This is the
  /// single most important field in the ingest: it is what stops a hand-typed
  /// night arriving through Apple Health from being promoted to a measurement
  /// (`docs/SLEEP_SYSTEM.md` §8).
  SleepRecordingMethod _recordingMethodFor(RecordingMethod method) =>
      switch (method) {
        RecordingMethod.manual => SleepRecordingMethod.manual,
        RecordingMethod.automatic => SleepRecordingMethod.automatic,
        RecordingMethod.active => SleepRecordingMethod.active,
        RecordingMethod.unknown => SleepRecordingMethod.unknown,
      };

  /// Both platforms' stage vocabularies, normalized onto [SleepStage].
  ///
  /// Apple's "core" and Google's "light" are the same stage under two names;
  /// `SLEEP_ASLEEP` is the honest landing place for a source that says "asleep"
  /// without saying which kind, including every pre-iOS-16 sample.
  SleepStage? _stageForType(HealthDataType type) => switch (type) {
    HealthDataType.SLEEP_IN_BED => SleepStage.inBed,
    HealthDataType.SLEEP_AWAKE_IN_BED => SleepStage.inBed,
    HealthDataType.SLEEP_OUT_OF_BED => SleepStage.outOfBed,
    HealthDataType.SLEEP_AWAKE => SleepStage.awake,
    HealthDataType.SLEEP_LIGHT => SleepStage.light,
    HealthDataType.SLEEP_DEEP => SleepStage.deep,
    HealthDataType.SLEEP_REM => SleepStage.rem,
    HealthDataType.SLEEP_ASLEEP => SleepStage.asleepUnspecified,
    HealthDataType.SLEEP_UNKNOWN => SleepStage.asleepUnspecified,
    _ => null,
  };

  SleepSourceFailure _classify(Exception e) {
    final message = e.toString().toLowerCase();
    if (message.contains('history')) {
      return SleepSourceFailure.historyWindowExceeded;
    }
    if (message.contains('permission') || message.contains('denied')) {
      return SleepSourceFailure.permissionDenied;
    }
    if (message.contains('health connect') || message.contains('unavailable')) {
      return SleepSourceFailure.providerUnavailable;
    }
    return SleepSourceFailure.unknown;
  }

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }
}

/// The no-provider [SleepSource] — desktop, web, and Android phones with no
/// Health Connect.
///
/// Not an error path: sleep still works here through manual logging, which is
/// the whole reason `authorizationStatus` reports [SleepAuthorization
/// .unavailable] rather than throwing. Half the feature working is the correct
/// outcome for a host with no health store.
class UnsupportedSleepSource implements SleepSource {
  const UnsupportedSleepSource();

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
