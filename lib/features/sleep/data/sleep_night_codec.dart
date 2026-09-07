import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/sleep_night.dart';
import '../domain/sleep_provenance.dart';
import '../domain/sleep_repository.dart';
import '../domain/sleep_session.dart';
import '../domain/sleep_targets.dart';

/// The Firestore wire format for sleep. Split out of the repository because it
/// is the feature's **durability boundary**: a night written today has to be
/// readable by every build that comes after, and a boundary that big deserves
/// its own file and its own tests rather than living as private helpers.
///
/// ## Rules this codec keeps
///
/// * **Instants are `Timestamp`s; offsets are integers beside them.** Never a
///   local wall-clock string — a night decoded in a different time zone from
///   the one it was recorded in must still be the same instant.
/// * **Every enum is persisted by `name`.** Which is why none of them carries
///   copy: renaming a label must never rewrite stored data. Decoding is
///   tolerant — an unknown name falls back rather than throwing, so a document
///   written by a newer build cannot brick an older one.
/// * **Nullables stay null.** `inBedStartAt` absent means the source did not
///   track time in bed; substituting a default here would manufacture a sleep
///   efficiency for every night that has none.
abstract final class SleepNightCodec {
  /// Bumped whenever the shape below changes incompatibly.
  static const int schemaVersion = 1;

  /// Document id for a sleep-day: `2026-09-06`.
  ///
  /// The id is derived, not random, and that is what makes syncing idempotent:
  /// two of the user's devices resolving the same night write to the same
  /// document instead of racing to create two.
  static String docId(DateTime sleepDay) =>
      '${sleepDay.year.toString().padLeft(4, '0')}-'
      '${sleepDay.month.toString().padLeft(2, '0')}-'
      '${sleepDay.day.toString().padLeft(2, '0')}';

  static DateTime? sleepDayFromId(String id) {
    final parts = id.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  static Map<String, Object?> encodeNight(SleepNight night) => {
    'schemaVersion': schemaVersion,
    'sleepDay': Timestamp.fromDate(night.sleepDay),
    'main': night.main == null ? null : encodeSession(night.main!),
    'naps': [for (final nap in night.naps) encodeSession(nap)],
    'alternates': [for (final alt in night.alternates) encodeSession(alt)],
    'resolution': night.resolution.name,
    'targets': night.targets == null ? null : encodeTargets(night.targets!),
  };

  static SleepNight decodeNight(String id, Map<String, dynamic> data) {
    final sleepDay =
        _dateOrNull(data['sleepDay']) ?? sleepDayFromId(id) ?? DateTime(1970);
    return SleepNight(
      sleepDay: DateTime(sleepDay.year, sleepDay.month, sleepDay.day),
      main: _decodeSessionOrNull(data['main']),
      naps: _decodeSessionList(data['naps']),
      alternates: _decodeSessionList(data['alternates']),
      resolution: _enumByName(
        SleepResolution.values,
        data['resolution'],
        SleepResolution.none,
      ),
      targets: _decodeTargetsOrNull(data['targets']),
      createdAt: _dateOrNull(data['createdAt']),
      updatedAt: _dateOrNull(data['updatedAt']),
    );
  }

  static Map<String, Object?> encodeTargets(SleepTargets targets) => {
    'bedtimeMinutes': targets.bedtimeMinutes,
    'wakeMinutes': targets.wakeMinutes,
    'durationMinutes': targets.durationMinutes,
  };

  static SleepTargets decodeTargets(Map<String, dynamic> data) => SleepTargets(
    bedtimeMinutes:
        _int(data['bedtimeMinutes']) ?? SleepTargets.defaults.bedtimeMinutes,
    wakeMinutes: _int(data['wakeMinutes']) ?? SleepTargets.defaults.wakeMinutes,
    durationMinutes:
        _int(data['durationMinutes']) ?? SleepTargets.defaults.durationMinutes,
  );

  static Map<String, Object?> encodeMark(SleepMark mark) => {
    'id': mark.id,
    'atUtc': Timestamp.fromDate(mark.atUtc),
    'offsetMinutes': mark.offsetMinutes,
    'tzId': mark.tzId,
    'note': mark.note,
  };

  static SleepMark? decodeMarkOrNull(Map<String, dynamic>? data) {
    if (data == null) return null;
    final at = _dateOrNull(data['atUtc']);
    if (at == null) return null;
    return SleepMark(
      id: data['id'] as String? ?? 'open',
      atUtc: at.toUtc(),
      offsetMinutes: _int(data['offsetMinutes']) ?? 0,
      tzId: data['tzId'] as String?,
      note: data['note'] as String?,
    );
  }

  static Map<String, Object?> encodeSession(SleepSession session) => {
    'id': session.id,
    'startAt': Timestamp.fromDate(session.startAt),
    'endAt': Timestamp.fromDate(session.endAt),
    'startOffsetMinutes': session.startOffsetMinutes,
    'endOffsetMinutes': session.endOffsetMinutes,
    'tzId': session.tzId,
    'inBedStartAt': session.inBedStartAt == null
        ? null
        : Timestamp.fromDate(session.inBedStartAt!),
    'inBedEndAt': session.inBedEndAt == null
        ? null
        : Timestamp.fromDate(session.inBedEndAt!),
    'stages': [
      for (final stage in session.stages)
        {
          'startAt': Timestamp.fromDate(stage.startAt),
          'endAt': Timestamp.fromDate(stage.endAt),
          'stage': stage.stage.name,
        },
    ],
    'interruptions': [
      for (final i in session.interruptions)
        {
          'startAt': Timestamp.fromDate(i.startAt),
          'endAt': Timestamp.fromDate(i.endAt),
        },
    ],
    'supersedes': session.supersedes,
    'provenance': encodeProvenance(session.provenance),
  };

  static SleepSession? decodeSession(Map<String, dynamic> data) {
    final start = _dateOrNull(data['startAt']);
    final end = _dateOrNull(data['endAt']);
    if (start == null || end == null) return null;
    return SleepSession(
      id: data['id'] as String? ?? '',
      startAt: start.toUtc(),
      endAt: end.toUtc(),
      startOffsetMinutes: _int(data['startOffsetMinutes']) ?? 0,
      endOffsetMinutes: _int(data['endOffsetMinutes']) ?? 0,
      tzId: data['tzId'] as String?,
      inBedStartAt: _dateOrNull(data['inBedStartAt'])?.toUtc(),
      inBedEndAt: _dateOrNull(data['inBedEndAt'])?.toUtc(),
      stages: [
        for (final raw in _mapList(data['stages']))
          if (_dateOrNull(raw['startAt']) != null &&
              _dateOrNull(raw['endAt']) != null)
            SleepStageSegment(
              startAt: _dateOrNull(raw['startAt'])!.toUtc(),
              endAt: _dateOrNull(raw['endAt'])!.toUtc(),
              stage: _enumByName(
                SleepStage.values,
                raw['stage'],
                SleepStage.asleepUnspecified,
              ),
            ),
      ],
      interruptions: [
        for (final raw in _mapList(data['interruptions']))
          if (_dateOrNull(raw['startAt']) != null &&
              _dateOrNull(raw['endAt']) != null)
            SleepInterruption(
              startAt: _dateOrNull(raw['startAt'])!.toUtc(),
              endAt: _dateOrNull(raw['endAt'])!.toUtc(),
            ),
      ],
      supersedes: data['supersedes'] as String?,
      provenance: decodeProvenance(
        (data['provenance'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  static Map<String, Object?> encodeProvenance(SleepProvenance p) => {
    'method': p.method.name,
    'providerId': p.providerId,
    'providerName': p.providerName,
    'deviceKind': p.deviceKind.name,
    'recordingMethod': p.recordingMethod.name,
    'confidence': p.confidence.name,
    'completeness': p.completeness,
    'rawRefs': p.rawRefs,
    'ingestedAt': Timestamp.fromDate(p.ingestedAt),
  };

  /// Decoding falls back to the **most cautious** value at every step —
  /// `platformDerived`, `low`, `unknown` — so a document we cannot fully
  /// understand is under-claimed rather than over-claimed. Anywhere else that
  /// would be over-defensive; here it is the whole point.
  static SleepProvenance decodeProvenance(Map<String, dynamic> data) =>
      SleepProvenance(
        method: _enumByName(
          SleepMethod.values,
          data['method'],
          SleepMethod.platformDerived,
        ),
        providerId: data['providerId'] as String? ?? '',
        providerName: data['providerName'] as String? ?? '',
        deviceKind: _enumByName(
          SleepDeviceKind.values,
          data['deviceKind'],
          SleepDeviceKind.unknown,
        ),
        recordingMethod: _enumByName(
          SleepRecordingMethod.values,
          data['recordingMethod'],
          SleepRecordingMethod.unknown,
        ),
        confidence: _enumByName(
          SleepConfidence.values,
          data['confidence'],
          SleepConfidence.low,
        ),
        completeness: _double(data['completeness']) ?? 0,
        rawRefs: [
          for (final ref in (data['rawRefs'] as List? ?? const []))
            if (ref is String) ref,
        ],
        ingestedAt: _dateOrNull(data['ingestedAt'])?.toUtc() ?? DateTime(1970),
      );

  static SleepSession? _decodeSessionOrNull(Object? raw) {
    if (raw is! Map) return null;
    return decodeSession(raw.cast<String, dynamic>());
  }

  static List<SleepSession> _decodeSessionList(Object? raw) => [
    for (final entry in _mapList(raw)) ?decodeSession(entry),
  ];

  static SleepTargets? _decodeTargetsOrNull(Object? raw) {
    if (raw is! Map) return null;
    return decodeTargets(raw.cast<String, dynamic>());
  }

  static List<Map<String, dynamic>> _mapList(Object? raw) => [
    for (final entry in (raw as List? ?? const []))
      if (entry is Map) entry.cast<String, dynamic>(),
  ];

  /// Accepts a `Timestamp` (what Firestore returns) or a `DateTime` (what the
  /// in-memory fake and the tests hand over).
  static DateTime? _dateOrNull(Object? raw) => switch (raw) {
    Timestamp t => t.toDate(),
    DateTime d => d,
    _ => null,
  };

  static int? _int(Object? raw) => raw is num ? raw.toInt() : null;

  static double? _double(Object? raw) => raw is num ? raw.toDouble() : null;

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) {
    if (raw is! String) return fallback;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return fallback;
  }
}
