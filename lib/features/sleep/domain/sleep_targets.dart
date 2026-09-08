/// What the user is aiming for. Three plain numbers, deliberately not a goal
/// engine: adherence is reported as a signed delta ("47 min later than
/// target"), never as a score or a grade, because ZIVO can tell you how long
/// you slept but not whether the night was good.
class SleepTargets {
  const SleepTargets({
    required this.bedtimeMinutes,
    required this.wakeMinutes,
    required this.durationMinutes,
  });

  /// Target bedtime as local minutes since midnight. `1380` is 23:00.
  final int bedtimeMinutes;

  /// Target wake time as local minutes since midnight. `420` is 07:00.
  final int wakeMinutes;

  /// Target sleep length in minutes. Stored independently of the two clock
  /// times rather than derived from them: a user may want eight hours while
  /// keeping a flexible bedtime, and deriving would silently overwrite one
  /// intention with another.
  final int durationMinutes;

  /// 23:00 → 07:00, eight hours. The neutral opening position — shown as a
  /// suggestion the user confirms, never applied silently, because an
  /// unconfirmed target would make every adherence figure meaningless.
  static const SleepTargets defaults = SleepTargets(
    bedtimeMinutes: 23 * 60,
    wakeMinutes: 7 * 60,
    durationMinutes: 8 * 60,
  );

  /// Nights within this many minutes of [bedtimeMinutes] count as on target.
  /// Half an hour is the tolerance sleep-hygiene guidance uses, and it is wide
  /// enough that ordinary life does not read as failure.
  static const int adherenceToleranceMinutes = 30;

  SleepTargets copyWith({
    int? bedtimeMinutes,
    int? wakeMinutes,
    int? durationMinutes,
  }) => SleepTargets(
    bedtimeMinutes: bedtimeMinutes ?? this.bedtimeMinutes,
    wakeMinutes: wakeMinutes ?? this.wakeMinutes,
    durationMinutes: durationMinutes ?? this.durationMinutes,
  );
}
