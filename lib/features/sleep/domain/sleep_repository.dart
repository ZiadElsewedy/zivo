import 'sleep_night.dart';
import 'sleep_provenance.dart';
import 'sleep_session.dart';
import 'sleep_targets.dart';

/// The seam between the app and sleep storage — Firestore in production, the
/// in-memory implementation offline and in tests. Presentation depends on this
/// interface and never on either implementation.
abstract interface class SleepRepository {
  /// Latest snapshot, newest night first (synchronous, for initial paint).
  List<SleepNight> get current;

  /// Emits the current nights immediately, then again on every change.
  Stream<List<SleepNight>> watchNights();

  /// The user's targets, or null until they have set them. Null is meaningful:
  /// adherence is not computed against a goal nobody chose.
  Stream<SleepTargets?> watchTargets();

  SleepTargets? get currentTargets;

  Future<void> saveTargets(SleepTargets targets);

  /// Writes [nights], replacing each by its sleep-day.
  ///
  /// Idempotent by construction: the sleep-day is the document id, so
  /// re-syncing the same night converges on one document instead of racing to
  /// create two — which is also what makes two of the user's phones agree.
  Future<void> upsertNights(List<SleepNight> nights);

  /// Removes the night for [sleepDay] entirely — used when every upstream
  /// record behind it has been deleted.
  Future<void> removeNight(DateTime sleepDay);

  /// The open sleep mark, if the user has tapped "I'm going to sleep" and not
  /// yet said they are awake. Null otherwise.
  Stream<SleepMark?> watchOpenMark();

  SleepMark? get currentOpenMark;

  /// Records "I'm going to sleep". Replaces any existing open mark.
  Future<void> openMark(SleepMark mark);

  /// Clears the open mark without producing a night — the user tapped by
  /// mistake, or changed their mind.
  Future<void> clearOpenMark();
}

/// A user-reported sleep boundary — one half of a manual log, held open
/// between "I'm going to sleep" and "I'm awake".
///
/// Stored separately from nights because it is not yet a night: until the
/// second tap arrives there is a start and no end, and writing a half-night
/// into the nights collection would mean either an open-ended session or a
/// guessed wake time. Both are worse than an explicitly pending state.
class SleepMark {
  const SleepMark({
    required this.id,
    required this.atUtc,
    required this.offsetMinutes,
    this.tzId,
    this.note,
  });

  final String id;

  /// UTC instant, as everywhere in this feature.
  final DateTime atUtc;

  /// The local offset when the user tapped, so a night logged before a flight
  /// renders in the time zone it was lived in.
  final int offsetMinutes;

  final String? tzId;
  final String? note;

  /// The mark rendered in its own recorded offset. Display only.
  DateTime get localAt => atUtc.add(Duration(minutes: offsetMinutes));
}

/// Builds the [SleepSession] a closed pair of marks describes.
///
/// The result is always [userReported]: the user told us when they went to bed
/// and when they got up, which is real information and is not a measurement.
/// Presenting it as one — "Asleep 11:30 PM" rather than "You logged 11:30 PM" —
/// is the exact failure this feature is built to avoid.
SleepSession? sessionFromMarks({
  required SleepMark sleepMark,
  required DateTime wakeAtUtc,
  required int wakeOffsetMinutes,
  required DateTime ingestedAt,
  required String providerName,
  String? supersedes,
}) {
  if (!wakeAtUtc.isAfter(sleepMark.atUtc)) return null;
  return SleepSession(
    id: 'manual:${sleepMark.atUtc.toUtc().toIso8601String()}',
    startAt: sleepMark.atUtc,
    endAt: wakeAtUtc,
    startOffsetMinutes: sleepMark.offsetMinutes,
    endOffsetMinutes: wakeOffsetMinutes,
    tzId: sleepMark.tzId,
    provenance: SleepProvenance.manual(
      ingestedAt: ingestedAt,
      providerName: providerName,
    ),
    supersedes: supersedes,
  );
}
