/// The user's own training preferences — the knobs the workout feature reads
/// rather than hard-codes.
///
/// One document per account (`users/{uid}/settings/workout`), alongside the
/// media and Ask preferences that already live there.
class WorkoutSettings {
  const WorkoutSettings({required this.maxSessionMinutes});

  static const defaults = WorkoutSettings(
    maxSessionMinutes: kDefaultMaxSessionDurationMinutes,
  );

  /// How long a session may run before a still-active one is treated as left
  /// open rather than under way, and past which a finished session's duration
  /// is held out of the averages until it is corrected.
  ///
  /// Not a cap: nothing is ever truncated to this. It is the line between "a
  /// long workout" and "a session nobody closed", and it is the user's to draw
  /// — a strongman doing three-hour sessions and someone doing 40-minute ones
  /// do not share a threshold.
  final int maxSessionMinutes;

  Duration get maxSessionDuration => Duration(minutes: maxSessionMinutes);

  /// Clamped to something a session could plausibly be, so a typo or a bad
  /// stored value can't disable the protection (0) or make it meaningless
  /// (999 hours).
  WorkoutSettings copyWith({int? maxSessionMinutes}) => WorkoutSettings(
    maxSessionMinutes: _clampMinutes(
      maxSessionMinutes ?? this.maxSessionMinutes,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is WorkoutSettings && other.maxSessionMinutes == maxSessionMinutes;

  @override
  int get hashCode => maxSessionMinutes.hashCode;
}

/// The default maximum session length: 3 hours. Long enough that no real
/// workout trips it, short enough that "I left it running overnight" always
/// does.
const int kDefaultMaxSessionDurationMinutes = 180;

/// The bounds the setting may be moved between — 30 minutes to 12 hours.
const int kMinSessionDurationSettingMinutes = 30;
const int kMaxSessionDurationSettingMinutes = 12 * 60;

int _clampMinutes(int minutes) => minutes.clamp(
  kMinSessionDurationSettingMinutes,
  kMaxSessionDurationSettingMinutes,
);

/// Reads a stored maximum, falling back to the default for anything missing or
/// out of range — a corrupt setting must never leave the app with no
/// staleness protection at all.
int maxSessionMinutesFrom(Object? raw) {
  final value = (raw as num?)?.toInt();
  if (value == null) return kDefaultMaxSessionDurationMinutes;
  return _clampMinutes(value);
}
