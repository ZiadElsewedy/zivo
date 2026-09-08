import 'sleep_provenance.dart';
import 'sleep_session.dart';

/// The platform health seam: the one place iOS and Android differ, and the
/// last place anything above may know they do.
///
/// Kept behind a plain interface for the same reason every other hardware seam
/// in ZIVO is (`features/device/steps/step_counter.dart`, the recorder, the
/// music controller): widget tests inject a fake, and hosts with no health
/// provider — desktop, web, an Android phone with no Health Connect — get
/// [UnsupportedSleepSource] rather than a hard platform dependency.
///
/// ## The asymmetry this hides
///
/// Health Connect stores real `SleepSessionRecord`s. HealthKit stores a cloud
/// of overlapping interval samples and has **no session type at all**
/// (`docs/SLEEP_SYSTEM.md` §3). So an implementation emits [RawSleepRecord]s
/// with [RawSleepRecord.preSessionized] set accordingly, and
/// `sleep_sessionizer.dart` stitches only what needs stitching.
abstract interface class SleepSource {
  /// Whether this host has a health provider at all. False on desktop/web, and
  /// on Android below 14 where the Health Connect APK may simply be absent —
  /// in which case the feature degrades to manual logging rather than erroring.
  Future<bool> isAvailable();

  /// Current read authorization, as far as the platform will admit it.
  ///
  /// **On iOS the answer to "did they deny us?" is unknowable by design** —
  /// Apple does not report read denial, so a denied read and an empty store are
  /// indistinguishable. Implementations therefore return
  /// [SleepAuthorization.unknown] rather than inventing certainty, and the UI
  /// must never turn an empty result into "you have no sleep data".
  Future<SleepAuthorization> authorizationStatus();

  /// Asks for read access. Returns whether the platform reported success —
  /// which on iOS means only that the sheet was shown without error.
  Future<bool> requestAuthorization();

  /// Raw sleep records overlapping `[from, to)`, in whatever shape the platform
  /// keeps them.
  ///
  /// Throws [SleepSourceException] on a real failure (provider gone, history
  /// window exceeded). An empty list is **not** an error and must not be
  /// treated as one.
  Future<List<RawSleepRecord>> readRecords({
    required DateTime from,
    required DateTime to,
  });
}

/// What we are allowed to say about read access.
enum SleepAuthorization {
  /// Never asked.
  notDetermined,

  /// The platform confirmed access. Android can say this; iOS cannot.
  granted,

  /// The platform confirmed refusal. Android only.
  denied,

  /// Asked, and the platform will not say. **The normal iOS answer.**
  unknown,

  /// No health provider on this host.
  unavailable,
}

/// A read failed for a reason worth showing the user differently from "no
/// data" — because "we could not look" and "we looked and there was nothing"
/// are different sentences.
class SleepSourceException implements Exception {
  const SleepSourceException(this.kind, [this.message]);

  final SleepSourceFailure kind;
  final String? message;

  @override
  String toString() => 'SleepSourceException($kind, $message)';
}

enum SleepSourceFailure {
  /// No Health Connect / HealthKit on this device.
  providerUnavailable,

  /// The read was refused outright (Android reports this; iOS does not).
  permissionDenied,

  /// Android: reading past 30 days without `READ_HEALTH_DATA_HISTORY`.
  historyWindowExceeded,

  /// Anything else — a platform channel error, a provider crash.
  unknown,
}

/// One record as the platform kept it, already normalized in vocabulary but
/// **not** yet in shape. The sessionizer's input.
class RawSleepRecord {
  const RawSleepRecord({
    required this.id,
    required this.startAt,
    required this.endAt,
    required this.startOffsetMinutes,
    required this.endOffsetMinutes,
    required this.stage,
    required this.providerId,
    required this.providerName,
    required this.deviceKind,
    required this.recordingMethod,
    this.tzId,
    this.stages = const [],
    this.preSessionized = false,
  });

  /// The upstream id — a HealthKit uuid or a Health Connect record id. Carried
  /// into [SleepProvenance.rawRefs], where it is the dedup key on re-sync and
  /// the join key when the record is deleted upstream.
  final String id;

  /// UTC instants.
  final DateTime startAt;
  final DateTime endAt;

  final int startOffsetMinutes;
  final int endOffsetMinutes;
  final String? tzId;

  /// The stage this record represents. For a flat iOS sample that is the
  /// sample's own value; for a pre-sessionized Android record it summarises
  /// the span and the detail is in [stages].
  final SleepStage stage;

  /// Stage detail, when the platform supplied a breakdown. Empty is normal.
  final List<SleepStageSegment> stages;

  /// True when this record is already a whole sleep period and must be taken
  /// as-is (Health Connect). False for HealthKit samples, which are fragments
  /// and have to be stitched.
  final bool preSessionized;

  final String providerId;
  final String providerName;
  final SleepDeviceKind deviceKind;
  final SleepRecordingMethod recordingMethod;

  Duration get duration => endAt.difference(startAt);
}
