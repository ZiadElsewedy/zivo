/// **The copy contract.** Every reader-facing sentence about sleep is built
/// here, and nowhere else.
///
/// Sleep's accuracy rule is not really a data rule — the data layer already
/// records how each night was produced. It is a *wording* rule
/// (`docs/SLEEP_SYSTEM.md` §11): "Asleep 1:47 AM", "You logged 1:30 AM" and
/// "Likely asleep around 1:45 AM" are three different claims, and the one a
/// screen is entitled to make is decided by [SleepMethod]. A widget that
/// composed its own sentence could make the wrong one while every stored value
/// stayed correct, so widgets do not compose sentences.
///
/// Two rules the functions here enforce that a call site could not:
///
/// * **Rounding matches precision.** An estimate rendered as "1:47 AM" is
///   false precision even inside a hedged sentence — the minute digit asserts
///   a resolution the method does not have. [sleepOnsetText] rounds estimates
///   to the quarter hour, and there is no way to ask it not to.
/// * **Composed numeric runs are pinned for bidi.** `6h 52m`, `±48 min`,
///   `4 of 7` are digits and neutrals end to end and reverse inside an Arabic
///   paragraph (`core/util/bidi.dart`). Every one is wrapped with `ltrFor`,
///   which is a no-op in English.
///
/// Same split as `workout_labels.dart` and `diet_labels.dart`: arithmetic in
/// `domain/`, anything a reader sees here, taking a [BuildContext].
library;

import 'package:flutter/widgets.dart';

import '../../../core/util/bidi.dart';
import '../../../core/util/date_format.dart';
import '../../../l10n/l10n.dart';
import '../domain/sleep_night.dart';
import '../domain/sleep_provenance.dart';
import '../domain/sleep_session.dart';
import '../domain/sleep_targets.dart';

/// A duration split into its number/unit pairs — `[(7, "h"), (12, "m")]`.
///
/// The split is the point. Azeret Mono carries no Arabic, so `7س 12د` built as
/// one mono string falls back to a system face for `س` and `د` alone: two
/// typefaces inside one figure, with different weights and vertical metrics,
/// which at hero size reads as broken rather than as a duration. ZIVO's own
/// answer to this is everywhere already — `TrainStatTile` keeps `value` and
/// `unit` apart, and the You header renders `12.9` over `الإجمالي` rather than
/// interpolating the word.
///
/// So the number stays in mono and the unit is rendered beside it in the text
/// face ([SleepDurationText]). English gains from the same treatment: a
/// lighter, smaller `h`/`m` is how a hero duration is set.
List<(String, String)> sleepDurationParts(
  BuildContext context,
  Duration duration,
) {
  final strings = l(context);
  final total = duration.inMinutes.abs();
  final hours = total ~/ 60;
  final minutes = total % 60;

  if (hours == 0) return [('$minutes', strings.sleepUnitMinute)];
  if (minutes == 0) return [('$hours', strings.sleepUnitHour)];
  return [
    ('$hours', strings.sleepUnitHour),
    ('$minutes', strings.sleepUnitMinute),
  ];
}

/// "6h 52m", "48m", "8h" — the plain-string form, for a chip, a sentence, or a
/// semantics label, where there is no room to set the units separately.
///
/// **Deliberately not pinned with `ltrFor`.** That was the first attempt and it
/// rendered `7س 12د` as `س12د7` on device. `core/util/bidi.dart` says why:
/// `ltrFor` is for a composed run of digits and *neutral* punctuation, and the
/// Arabic form is not one — `س` and `د` are abbreviated words, strong RTL
/// characters, so forcing the run left-to-right interleaves the two
/// number+unit pairs backwards.
String sleepDurationText(BuildContext context, Duration duration) => [
  for (final (value, unit) in sleepDurationParts(context, duration))
    '$value$unit',
].join(' ');

/// A minute count as a duration, for deltas and variability figures.
String sleepMinutesText(BuildContext context, num minutes) =>
    sleepDurationText(context, Duration(minutes: minutes.abs().round()));

/// When the user fell asleep, phrased for how we know it.
///
/// The whole point of this function is that it is impossible to call it and
/// get a stronger claim than the method supports.
String sleepOnsetText(BuildContext context, SleepSession session) {
  final strings = l(context);
  final time = _clockFor(context, session.localStart, session.provenance);
  return switch (session.provenance.method) {
    SleepMethod.measuredWearable ||
    SleepMethod.measuredNearable => strings.sleepOnsetMeasured(time),
    SleepMethod.platformDerived => strings.sleepOnsetPlatform(time),
    SleepMethod.userReported => strings.sleepOnsetReported(time),
    SleepMethod.deviceEstimated => strings.sleepOnsetEstimated(time),
  };
}

/// When the user woke, phrased for how we know it.
String sleepWakeText(BuildContext context, SleepSession session) {
  final strings = l(context);
  final time = _clockFor(context, session.localEnd, session.provenance);
  return switch (session.provenance.method) {
    SleepMethod.measuredWearable ||
    SleepMethod.measuredNearable => strings.sleepWakeMeasured(time),
    SleepMethod.platformDerived => strings.sleepWakePlatform(time),
    SleepMethod.userReported => strings.sleepWakeReported(time),
    SleepMethod.deviceEstimated => strings.sleepWakeEstimated(time),
  };
}

/// A bare clock time at the precision the method earns — for an axis label or
/// a compact row, where the full sentence would not fit.
String sleepClockText(
  BuildContext context,
  DateTime localTime,
  SleepProvenance provenance,
) => _clockFor(context, localTime, provenance);

/// How this night was produced, in two words.
String sleepMethodLabel(BuildContext context, SleepMethod method) {
  final strings = l(context);
  return switch (method) {
    SleepMethod.measuredWearable ||
    SleepMethod.measuredNearable => strings.sleepMethodMeasured,
    SleepMethod.platformDerived => strings.sleepMethodRecorded,
    SleepMethod.userReported => strings.sleepMethodLogged,
    SleepMethod.deviceEstimated => strings.sleepMethodEstimated,
  };
}

String sleepConfidenceLabel(
  BuildContext context,
  SleepConfidence confidence,
) {
  final strings = l(context);
  return switch (confidence) {
    SleepConfidence.high => strings.sleepConfidenceHigh,
    SleepConfidence.medium => strings.sleepConfidenceMedium,
    SleepConfidence.low => strings.sleepConfidenceLow,
  };
}

/// The writing app's name, as a reader should see it.
///
/// ZIVO's own manual entries become the localized "You" — the provider id is
/// ours, so we own the wording. Everything else is a name we did not write
/// (an app title out of Apple Health), so it is [isolate]d: its direction is
/// its own to decide, and an unisolated one fragments the sentence around it.
String sleepProviderName(BuildContext context, SleepProvenance provenance) {
  if (provenance.providerId == SleepProvenance.manualProviderId) {
    return l(context).sleepProviderYou;
  }
  final name = provenance.providerName.trim();
  if (name.isEmpty) return l(context).sleepMethodRecorded;
  return isolate(name);
}

/// "Apple Watch · Measured" — the chip that sits under every sleep figure.
///
/// Not decoration. A duration without its source is the exact claim this
/// feature exists to refuse, so the chip travels with the number everywhere.
String sleepSourceChipText(BuildContext context, SleepProvenance provenance) =>
    l(context).sleepSourceChip(
      sleepProviderName(context, provenance),
      sleepMethodLabel(context, provenance.method),
    );

/// The name of whichever health store this platform has, for the permission
/// and empty states. Never guessed from a string — the caller passes what the
/// source layer reported.
String sleepProviderStoreName(BuildContext context, {required bool isApple}) =>
    isApple
    ? l(context).sleepProviderApple
    : l(context).sleepProviderHealthConnect;

String sleepStageLabel(BuildContext context, SleepStage stage) {
  final strings = l(context);
  return switch (stage) {
    SleepStage.light => strings.sleepStageLight,
    SleepStage.deep => strings.sleepStageDeep,
    SleepStage.rem => strings.sleepStageRem,
    SleepStage.awake => strings.sleepStageAwake,
    SleepStage.asleepUnspecified => strings.sleepStageAsleep,
    SleepStage.inBed || SleepStage.outOfBed => strings.sleepStageInBed,
  };
}

/// Why the resolver picked the session it picked — the answer the "why this
/// number?" sheet leads with.
String sleepResolutionText(BuildContext context, SleepResolution resolution) {
  final strings = l(context);
  return switch (resolution) {
    SleepResolution.none => strings.sleepNoData,
    SleepResolution.soleSource => strings.sleepWhySole,
    SleepResolution.bestMethod => strings.sleepWhyMethod,
    SleepResolution.bestCoverage => strings.sleepWhyCoverage,
    SleepResolution.richestDetail => strings.sleepWhyDetail,
    SleepResolution.userOverride => strings.sleepWhyOverride,
  };
}

/// "+22 min vs your 7h30 target", as a sentence.
///
/// Returns null when there is no target — which renders as an invitation to
/// set one, not as a zero delta against a goal nobody chose.
String? sleepDurationDeltaText(BuildContext context, SleepNight night) {
  final delta = night.durationDeltaMinutes;
  final targets = night.targets;
  if (delta == null || targets == null) return null;

  final strings = l(context);
  final target = sleepDurationText(
    context,
    Duration(minutes: targets.durationMinutes),
  );
  final amount = sleepMinutesText(context, delta);

  // Under a quarter hour either way is "on target": reporting a four-minute
  // shortfall as a miss implies a precision the target itself never had.
  if (delta.abs() < 15) return strings.sleepDeltaOnTarget(target);
  return delta > 0
      ? strings.sleepDeltaLonger(amount, target)
      : strings.sleepDeltaShorter(amount, target);
}

/// "47 min later than your target bedtime".
String? sleepBedtimeDeltaText(BuildContext context, SleepNight night) {
  final delta = night.bedtimeDeltaMinutes;
  if (delta == null) return null;

  final strings = l(context);
  if (delta.abs() <= SleepTargets.adherenceToleranceMinutes) {
    return strings.sleepBedtimeOnTarget;
  }
  final amount = sleepMinutesText(context, delta);
  return delta > 0
      ? strings.sleepBedtimeLater(amount)
      : strings.sleepBedtimeEarlier(amount);
}

/// "6 of 7 nights" — the denominator is never dropped. A figure without its n
/// is a claim without its evidence.
///
/// Unpinned for the same reason as [sleepDurationText]: the Arabic form is a
/// sentence ("٦ من ٧ ليالٍ"), not a numeric run.
String sleepNightsOfText(BuildContext context, int count, int total) =>
    l(context).sleepNightsOf(count, total);

/// "±48 min" — a variability figure. The `±` is neutral and the duration
/// inside carries its own direction, so this needs no pinning either.
String sleepVariabilityText(BuildContext context, double minutes) =>
    l(context).sleepVariability(sleepMinutesText(context, minutes));

/// A percentage, pinned. Only ever called where the underlying value is
/// non-null — "not tracked" is a different string, not `0%`.
String sleepPercentText(BuildContext context, double fraction) =>
    ltrFor(context, '${(fraction * 100).round()}%');

/// The clock time at the precision [provenance]'s method earns.
///
/// Estimates round to the quarter hour. This is the only place that decision
/// is made, which is what stops "around 1:47" — a hedge wrapped around a
/// precision the hedge contradicts — from ever reaching a screen.
String _clockFor(
  BuildContext context,
  DateTime localTime,
  SleepProvenance provenance,
) {
  final shown = provenance.method.supportsExactMinute
      ? localTime
      : _roundToQuarterHour(localTime);
  return ltrFor(context, formatClockTime(context, shown));
}

DateTime _roundToQuarterHour(DateTime time) {
  final rounded = ((time.minute + 7) ~/ 15) * 15;
  return DateTime(
    time.year,
    time.month,
    time.day,
    time.hour,
  ).add(Duration(minutes: rounded));
}
