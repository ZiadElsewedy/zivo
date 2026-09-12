import '../../../core/util/calendar.dart';
import '../../sleep/domain/sleep_night.dart';
import '../../sleep/domain/sleep_targets.dart';
import '../../sleep/domain/sleep_window.dart';
import '../../workout/domain/analytics/workout_analytics.dart';
import '../../workout/domain/live_session.dart';
import '../../workout/domain/session_status.dart';
import '../../workout/domain/weight_trend.dart';

/// The Daily Readiness call — ZIVO's one deterministic "train hard / go light /
/// rest" recommendation, fused from data the app already holds: last night's
/// sleep, the training analysis (including a stall/deload signal), how recently
/// you trained, and your body-weight trend.
///
/// The design rules (see `docs/DECISIONS/ADR-015-readiness.md`):
///
/// * **Derived, never stored.** This is computed on the client from existing
///   streams (like `SleepGlanceSection` derives from nights); there is no
///   readiness collection.
/// * **It fuses, it does not re-derive.** Sleep facts come off [SleepNight] +
///   [SleepTargets]; the stall/deload signal off [analyzeTraining]; weight off
///   [computeWeightTrend]. This engine combines their verdicts and cites their
///   numbers — it never re-implements a stall test or a strength calc.
/// * **The gate returns null.** With nothing to stand on (no recent sleep, no
///   training, no weigh-in) [computeReadiness] returns null and the surface
///   hides — never a fabricated call or a zero.
/// * **Explainable.** Every [ReadinessFactor] carries the raw number behind it,
///   so the card and the coach can say *why*, never just *what*.

/// The three possible calls, weakest-recovery to strongest.
enum ReadinessVerdict {
  /// Compounding recovery debt — hold back today.
  rest,

  /// Something says ease off (short sleep, a due deload, trained today).
  goLight,

  /// Recovered and nothing is flagging — push.
  trainHard,
}

/// Which input a [ReadinessFactor] speaks for.
enum ReadinessFactorKind { sleep, deload, recentLoad, bodyWeight }

/// Which way a factor pushes the call. [supports] nudges toward training hard;
/// [caution] toward going light; [limits] is a strong pull toward rest.
enum ReadinessDirection { supports, caution, limits }

/// One reason behind the call, with the number it cites. The copy is built in
/// `presentation/readiness_labels.dart` — the domain only carries facts.
class ReadinessFactor {
  const ReadinessFactor({
    required this.kind,
    required this.direction,
    this.sleepDurationMinutes,
    this.sleepDeltaMinutes,
    this.deloadExerciseCount,
    this.restDays,
    this.weightChangeKg,
  });

  final ReadinessFactorKind kind;
  final ReadinessDirection direction;

  /// [sleep]: last night's asleep minutes, and minutes vs the duration target
  /// (negative for short of it).
  final int? sleepDurationMinutes;
  final int? sleepDeltaMinutes;

  /// [deload]: how many working lifts are plateauing or regressing.
  final int? deloadExerciseCount;

  /// [recentLoad]: calendar days since the last completed session (0 = today).
  final int? restDays;

  /// [bodyWeight]: signed change over the trend window, kg (negative = loss).
  final double? weightChangeKg;
}

/// The finished call and the factors that produced it, factors ordered
/// strongest-pull first (limits → caution → supports).
class Readiness {
  const Readiness({required this.verdict, required this.factors});

  final ReadinessVerdict verdict;
  final List<ReadinessFactor> factors;

  /// The single most important factor to lead with, or null when empty.
  ReadinessFactor? get leadFactor => factors.isEmpty ? null : factors.first;
}

// ---- Thresholds (documented, deterministic) --------------------------------

/// Minutes short of the sleep-duration target that counts as a mild deficit.
const int kReadinessSleepShortMinutes = 30;

/// Minutes short that counts as a serious deficit (a strong pull toward rest).
const int kReadinessSleepSevereMinutes = 90;

/// Plateauing/regressing lifts at or above this raise the deload signal.
const int kReadinessDeloadStalledCount = 2;

/// Calendar days since the last session at or above which you read as recovered.
const int kReadinessRecoveredRestDays = 2;

/// A body-weight loss over the trend window at or beyond this (kg) reads as an
/// aggressive-enough deficit to lightly bias toward recovery. Conservative on
/// purpose — weight is the softest of the four signals.
const double kReadinessRapidLossKg = 2.0;

/// Whether the workout analysis is telling us a deload is due: a cluster of
/// stalled/regressing lifts, or an overall regression. Reads the Workout
/// engine's verdicts ([ProgressStatus]) — it never re-tests a stall itself.
/// Split out so readiness's own logic can be verified without reconstructing a
/// regressing history (that classifier is the Workout suite's to pin).
bool readinessDeloadDue({
  required int stalledCount,
  required ProgressStatus overallStatus,
}) => readinessDeloadDueFrom(
  stalledCount: stalledCount,
  overallRegressing: overallStatus == ProgressStatus.regressing,
);

/// The primitive form of [readinessDeloadDue], over a bool rather than the
/// [ProgressStatus] enum — the shape the signal-level engine and the Node
/// mirror share.
bool readinessDeloadDueFrom({
  required int stalledCount,
  required bool overallRegressing,
}) => stalledCount >= kReadinessDeloadStalledCount || overallRegressing;

/// Fuses the available inputs into a [Readiness], or null when there is nothing
/// to base a call on. See the class doc for the rules.
///
/// [sessions] is the raw session list (any status); this runs [analyzeTraining]
/// itself so the deload signal cannot disagree with the Workout screens.
Readiness? computeReadiness({
  required DateTime now,
  SleepNight? lastNight,
  SleepTargets? fallbackTargets,
  required List<LiveSession> sessions,
  WeightTrend? weight,
}) {
  // ---- Extract the signals from the domain objects -----------------------

  // Sleep is only judged when the night is genuinely recent — an old night
  // under "last night" is the one claim this must not make (mirrors the glance).
  int? sleepDurationMinutes;
  int? sleepTargetMinutes;
  if (lastNight != null &&
      lastNight.hasData &&
      SleepWindow.ageInDays(lastNight, now) <= 1) {
    sleepDurationMinutes = lastNight.main!.asleepDuration.inMinutes;
    // Judge against the night's snapshotted target, else the current target,
    // else the neutral 8h default. The default is only ever used to *judge*
    // recovery here, never surfaced as an adherence figure.
    final target =
        lastNight.targets ?? fallbackTargets ?? SleepTargets.defaults;
    sleepTargetMinutes = target.durationMinutes;
  }

  // Deload reuses the Workout analytics verdicts — no new stall maths.
  final training = analyzeTraining(sessions: sessions, now: now);

  // Days since the last completed session (null when never trained).
  final completed = sessions.where((s) => s.status == SessionStatus.completed);
  DateTime? lastSessionAt;
  for (final s in completed) {
    final at = s.completedAt ?? s.startedAt;
    if (lastSessionAt == null || at.isAfter(lastSessionAt)) lastSessionAt = at;
  }
  final lastSessionDaysAgo = lastSessionAt == null
      ? null
      : calendarDaysBetween(startOfDay(lastSessionAt), startOfDay(now));

  return readinessFromSignals(
    sleepDurationMinutes: sleepDurationMinutes,
    sleepTargetMinutes: sleepTargetMinutes,
    stalledCount: training.needsAttention.length,
    overallStatusRegressing:
        training.overallStatus == ProgressStatus.regressing,
    lastSessionDaysAgo: lastSessionDaysAgo,
    weightChangeKg: weight?.changeKgOverWindow,
    hasWeighIn: weight?.latest != null,
  );
}

/// The pure combination logic, over primitive signals only — no domain objects,
/// no other engines. This is the layer pinned to the Node coach mirror
/// (`functions/ai/readiness.js`) by the shared golden vectors, so the card and
/// the coach can never phrase the same call two different ways.
///
/// Returns null on the gate: no recent sleep, no training, and no weigh-in.
Readiness? readinessFromSignals({
  int? sleepDurationMinutes,
  int? sleepTargetMinutes,
  int stalledCount = 0,
  bool overallStatusRegressing = false,
  int? lastSessionDaysAgo,
  double? weightChangeKg,
  bool hasWeighIn = false,
}) {
  final factors = <ReadinessFactor>[];

  // Sleep.
  if (sleepDurationMinutes != null) {
    final target = sleepTargetMinutes ?? SleepTargets.defaults.durationMinutes;
    final delta = sleepDurationMinutes - target;
    final direction = delta <= -kReadinessSleepSevereMinutes
        ? ReadinessDirection.limits
        : delta <= -kReadinessSleepShortMinutes
        ? ReadinessDirection.caution
        : ReadinessDirection.supports;
    factors.add(
      ReadinessFactor(
        kind: ReadinessFactorKind.sleep,
        direction: direction,
        sleepDurationMinutes: sleepDurationMinutes,
        sleepDeltaMinutes: delta,
      ),
    );
  }

  // Deload.
  if (readinessDeloadDueFrom(
    stalledCount: stalledCount,
    overallRegressing: overallStatusRegressing,
  )) {
    factors.add(
      ReadinessFactor(
        kind: ReadinessFactorKind.deload,
        direction: ReadinessDirection.caution,
        deloadExerciseCount: stalledCount,
      ),
    );
  }

  // Recent load / recovery.
  if (lastSessionDaysAgo != null) {
    if (lastSessionDaysAgo >= kReadinessRecoveredRestDays) {
      factors.add(
        ReadinessFactor(
          kind: ReadinessFactorKind.recentLoad,
          direction: ReadinessDirection.supports,
          restDays: lastSessionDaysAgo,
        ),
      );
    } else if (lastSessionDaysAgo <= 0) {
      // Already trained today — a reason to ease off, not push again.
      factors.add(
        ReadinessFactor(
          kind: ReadinessFactorKind.recentLoad,
          direction: ReadinessDirection.caution,
          restDays: lastSessionDaysAgo,
        ),
      );
    }
    // A single rest day is neutral: no factor either way.
  }

  // Body weight.
  if (weightChangeKg != null && weightChangeKg <= -kReadinessRapidLossKg) {
    factors.add(
      ReadinessFactor(
        kind: ReadinessFactorKind.bodyWeight,
        direction: ReadinessDirection.caution,
        weightChangeKg: weightChangeKg,
      ),
    );
  }

  // Gate: nothing to stand on ⇒ no call at all.
  final haveSleep = sleepDurationMinutes != null;
  final haveTraining = lastSessionDaysAgo != null;
  if (!haveSleep && !haveTraining && !hasWeighIn) return null;

  // Combine into one call.
  var limits = 0;
  var cautions = 0;
  var supports = 0;
  for (final f in factors) {
    switch (f.direction) {
      case ReadinessDirection.limits:
        limits++;
      case ReadinessDirection.caution:
        cautions++;
      case ReadinessDirection.supports:
        supports++;
    }
  }
  final debt = limits * 2 + cautions;
  final ReadinessVerdict verdict;
  if (debt >= 3) {
    verdict = ReadinessVerdict.rest;
  } else if (debt >= 1) {
    verdict = ReadinessVerdict.goLight;
  } else {
    // No debt. Push only with a genuine positive signal; otherwise the honest
    // default is to go light rather than to claim you're primed on no evidence.
    verdict = supports >= 1
        ? ReadinessVerdict.trainHard
        : ReadinessVerdict.goLight;
  }

  factors.sort((a, b) => _pull(b.direction).compareTo(_pull(a.direction)));
  return Readiness(verdict: verdict, factors: factors);
}

int _pull(ReadinessDirection d) => switch (d) {
  ReadinessDirection.limits => 2,
  ReadinessDirection.caution => 1,
  ReadinessDirection.supports => 0,
};
