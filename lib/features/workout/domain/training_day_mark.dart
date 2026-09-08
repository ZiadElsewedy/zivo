import '../../../core/util/calendar.dart';

/// Why a day had no training on it — context the user adds to a day they
/// didn't train, so history reads as a training life rather than a row of
/// holes.
///
/// Persisted by `name`, so these are **ids** and carry no copy; their labels
/// live in `presentation/workout_labels.dart` with every other persisted enum
/// (see `AGENTS.md` on the l10n seam).
enum MissedDayReason { rest, recovery, travel, illness, busy, other }

/// Parses a stored [MissedDayReason], defaulting to [MissedDayReason.other].
MissedDayReason missedDayReasonFromName(String? name) => MissedDayReason.values
    .firstWhere((r) => r.name == name, orElse: () => MissedDayReason.other);

/// What the user said about one calendar day they didn't train on — a reason,
/// a streak restore, or both.
///
/// **A reason and a restore are deliberately different things**, and keeping
/// them on one record is not the same as conflating them:
///
/// * A [reason] is *context*. It never touches the streak. Writing "travel" on
///   a missed Thursday does not train you on Thursday, and a system where
///   typing a word repairs your consistency is a system whose numbers are
///   worth nothing. It exists so the drill-down can say what happened.
/// * [restored] is the *one* deliberate, rationed act that bridges a gap the
///   streak would otherwise break on — see `training_streak.dart` for the
///   limits, and note it still adds no trained day to the count.
///
/// One document per calendar day, keyed `yyyy-MM-dd` (the shape sleep nights
/// already use), so writing the same mark twice is idempotent.
class TrainingDayMark {
  const TrainingDayMark({
    required this.day,
    required this.createdAt,
    this.reason,
    this.note,
    this.restored = false,
  });

  /// The calendar day this is about, as a day key (see [startOfDay]).
  final DateTime day;
  final DateTime createdAt;

  /// Context only. Never affects the streak.
  final MissedDayReason? reason;

  /// The user's own words, if they added any.
  final String? note;

  /// Whether this day is a spent streak restore.
  final bool restored;

  /// The document id — `yyyy-MM-dd`.
  String get key => dayKey(day);

  /// True when there is nothing left worth storing, so the caller can delete
  /// the document rather than leave an empty one behind.
  bool get isEmpty => reason == null && (note == null || note!.isEmpty) && !restored;

  TrainingDayMark copyWith({
    Object? reason = _keep,
    Object? note = _keep,
    bool? restored,
    DateTime? createdAt,
  }) => TrainingDayMark(
    day: day,
    createdAt: createdAt ?? this.createdAt,
    reason: reason == _keep ? this.reason : reason as MissedDayReason?,
    note: note == _keep ? this.note : note as String?,
    restored: restored ?? this.restored,
  );

  @override
  bool operator ==(Object other) =>
      other is TrainingDayMark &&
      other.day == day &&
      other.reason == reason &&
      other.note == note &&
      other.restored == restored;

  @override
  int get hashCode => Object.hash(day, reason, note, restored);
}

const Object _keep = Object();
