import 'sleep_metrics.dart';
import 'sleep_night.dart';
import 'sleep_provenance.dart';
import 'sleep_targets.dart';

/// The boundary between arithmetic and language.
///
/// ZIVO computes every sleep number deterministically (`sleep_metrics.dart`)
/// and the model only ever *interprets* what it is handed
/// (`docs/SLEEP_SYSTEM.md` §15). This file is that hand-off: a [SleepFactSheet]
/// of already-validated figures goes out, typed [SleepInsight]s come back, and
/// [groundedNumerals] refuses anything carrying a number the fact sheet never
/// contained.
///
/// The model gets no raw sessions and no ability to compute. It cannot report
/// a 34-minute improvement, because the only place a 34 can legitimately come
/// from is a field we put in the input.

/// One computed figure, with everything needed to say it honestly.
class SleepFact {
  const SleepFact({
    required this.id,
    required this.value,
    required this.unit,
    required this.nightCount,
    this.confidence,
    this.method,
  });

  /// Stable identifier the model cites in [SleepInsight.basedOn] — so every
  /// generated sentence can render its own provenance footnote, and one that
  /// cites nothing cannot be displayed at all.
  final String id;

  final num value;

  /// `minutes`, `nights`, `minutesPerNight`, `count`.
  final String unit;

  /// How many nights this figure rests on. Travels with the number because a
  /// mean over three nights and a mean over thirty are different claims.
  final int nightCount;

  /// Weakest confidence among the nights behind this figure — a week built
  /// mostly from typed entries cannot yield a high-confidence average.
  final SleepConfidence? confidence;

  /// Dominant method across those nights.
  final SleepMethod? method;

  Map<String, Object?> toJson() => {
    'id': id,
    'value': value,
    'unit': unit,
    'nights': nightCount,
    if (confidence != null) 'confidence': confidence!.name,
    if (method != null) 'method': method!.name,
  };
}

/// Everything the model is allowed to know, and an explicit list of what it is
/// forbidden to discuss.
class SleepFactSheet {
  const SleepFactSheet({
    required this.facts,
    required this.insufficient,
    required this.windowNights,
    required this.nightsWithData,
  });

  final List<SleepFact> facts;

  /// Metric ids that failed their gate in [SleepGates].
  ///
  /// Sent explicitly rather than simply omitted, because a missing field
  /// invites a model to fill it in and a named absence does not. The prompt's
  /// instruction is to say "not enough nights yet" about these and never to
  /// soften that into a hedged claim.
  final List<String> insufficient;

  final int windowNights;
  final int nightsWithData;

  Map<String, Object?> toJson() => {
    'windowNights': windowNights,
    'nightsWithData': nightsWithData,
    'facts': [for (final fact in facts) fact.toJson()],
    'insufficient': insufficient,
  };

  /// Every numeral the model is permitted to use, as strings — the allow-list
  /// [groundedNumerals] checks against.
  ///
  /// Includes each fact's rounded value in the forms a sentence might render
  /// it: the raw minutes, and the hours/minutes split, since "412 minutes" is
  /// legitimately written "6h 52m".
  Set<String> get allowedNumerals {
    final allowed = <String>{
      windowNights.toString(),
      nightsWithData.toString(),
    };
    for (final fact in facts) {
      final rounded = fact.value.round();
      allowed
        ..add(rounded.abs().toString())
        ..add(fact.nightCount.toString());
      if (fact.unit == 'minutes' || fact.unit == 'minutesPerNight') {
        final total = rounded.abs();
        allowed
          ..add((total ~/ 60).toString())
          ..add((total % 60).toString());
      }
    }
    return allowed;
  }
}

/// One generated sentence.
class SleepInsight {
  const SleepInsight({
    required this.kind,
    required this.text,
    required this.basedOn,
    required this.nightCount,
  });

  final SleepInsightKind kind;
  final String text;

  /// [SleepFact.id]s this sentence rests on. **An insight citing nothing is
  /// not rendered** — an unattributable claim is the thing this feature
  /// exists to refuse.
  final List<String> basedOn;

  final int nightCount;

  bool get isAttributable => basedOn.isNotEmpty;
}

enum SleepInsightKind {
  duration,
  consistency,
  targetAdherence,
  trend,
  weekOverWeek,

  /// "Not enough nights yet to say." A real answer, produced deterministically
  /// rather than generated, and never dressed up as a finding.
  insufficientData,
}

/// Builds the fact sheet from computed metrics. Only figures that passed their
/// gate become facts; the rest are named in [SleepFactSheet.insufficient].
SleepFactSheet buildFactSheet({
  required SleepWindowMetrics current,
  required SleepWindowMetrics previous,
  required SleepComparison comparison,
  required SleepTrend trend,
  required List<SleepNight> nights,
  SleepTargets? targets,
}) {
  final facts = <SleepFact>[];
  final insufficient = <String>[];

  final withData = nights.where((n) => n.hasData).toList();
  final confidence = _weakestConfidence(withData);
  final method = _dominantMethod(withData);

  void add(String id, num? value, String unit, {int? nights}) {
    if (value == null) {
      insufficient.add(id);
      return;
    }
    facts.add(
      SleepFact(
        id: id,
        value: value,
        unit: unit,
        nightCount: nights ?? current.nightCount,
        confidence: confidence,
        method: method,
      ),
    );
  }

  add('meanDuration', current.meanDurationMinutes?.round(), 'minutes');
  add('medianDuration', current.medianDurationMinutes?.round(), 'minutes');
  add('meanBedtime', current.meanBedtimeMinutes?.round(), 'minutes');
  add('meanWake', current.meanWakeMinutes?.round(), 'minutes');
  add('midpointVariability', current.midpointSdMinutes?.round(), 'minutes');
  add('bedtimeVariability', current.bedtimeSdMinutes?.round(), 'minutes');

  if (targets != null) {
    add('nightsOnTargetBedtime', current.nightsOnTargetBedtime, 'count');
    add('nightsMeetingDuration', current.nightsMeetingDuration, 'count');
    add('targetDuration', targets.durationMinutes, 'minutes');
  }

  switch (comparison.verdict) {
    case SleepComparisonVerdict.insufficientData:
      insufficient.add('weekOverWeekDelta');
    case SleepComparisonVerdict.unchanged:
    case SleepComparisonVerdict.improved:
    case SleepComparisonVerdict.declined:
      add(
        'weekOverWeekDelta',
        comparison.deltaMinutes,
        'minutes',
        nights: comparison.currentNights,
      );
      add(
        'previousMeanDuration',
        previous.meanDurationMinutes?.round(),
        'minutes',
        nights: comparison.previousNights,
      );
  }

  if (trend.direction == SleepTrendDirection.insufficientData) {
    insufficient.add('trend');
  } else {
    add(
      'trend',
      trend.minutesPerNight,
      'minutesPerNight',
      nights: trend.nightCount,
    );
  }

  return SleepFactSheet(
    facts: facts,
    insufficient: insufficient,
    windowNights: current.windowNights,
    nightsWithData: current.nightCount,
  );
}

/// **The numeral gate.** Whether every number in [text] came from [sheet].
///
/// The single highest-value control in the AI layer, and deliberately dumb:
/// pull every digit-run out of the generated sentence and check each against
/// the fact sheet's allow-list. A model cannot claim "you slept 34 minutes
/// more" past a filter holding the real delta, however fluent the claim.
///
/// Runs on the client as well as on the server — the server is the boundary,
/// this is the last thing between an ungrounded number and a user's eyes, and
/// a check this cheap is worth having twice.
///
/// Ordinals and small counts written as words ("first", "three") are outside
/// its reach by construction; that is an accepted limit, because the failure
/// mode being defended against is a fabricated *figure*, and figures are
/// written as digits.
bool groundedNumerals(String text, SleepFactSheet sheet) {
  final allowed = sheet.allowedNumerals;
  for (final match in RegExp(r'\d+').allMatches(text)) {
    final numeral = match.group(0)!;
    // A leading zero is a clock-time artefact ("07" in 07:15); compare on the
    // numeric value so `07` matches an allowed `7`.
    final normalized = int.tryParse(numeral)?.toString() ?? numeral;
    if (!allowed.contains(normalized) && !allowed.contains(numeral)) {
      return false;
    }
  }
  return true;
}

/// Weakest confidence across [nights] — a week is only as trustworthy as its
/// shakiest night, and averaging confidence would invent a middle tier that
/// describes no night in it.
SleepConfidence? _weakestConfidence(List<SleepNight> nights) {
  if (nights.isEmpty) return null;
  var weakest = SleepConfidence.high;
  for (final night in nights) {
    final c = night.confidence;
    if (c == null) continue;
    if (c.index > weakest.index) weakest = c;
  }
  return weakest;
}

/// The method behind the most nights in the window.
SleepMethod? _dominantMethod(List<SleepNight> nights) {
  if (nights.isEmpty) return null;
  final counts = <SleepMethod, int>{};
  for (final night in nights) {
    final m = night.method;
    if (m == null) continue;
    counts[m] = (counts[m] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// A grounded observation, before it has any words.
///
/// The deterministic floor of the AI layer. Sleep insights are generated in
/// two tiers and this is the lower one: pure arithmetic that is *always*
/// available, always true, and needs no model round trip. The model's job is
/// to say the same things better — never to say more of them.
///
/// Carries no copy, because copy is `presentation/`'s. It carries the
/// **values** the sentence will contain, so the numeral gate can be applied to
/// the model's version of that sentence against the same numbers.
class SleepInsightDraft {
  const SleepInsightDraft({
    required this.kind,
    required this.basedOn,
    required this.nightCount,
    this.values = const {},
  });

  final SleepInsightKind kind;

  /// [SleepFact.id]s this rests on. Empty means unattributable, and an
  /// unattributable observation is not rendered.
  final List<String> basedOn;

  final int nightCount;

  /// The figures the sentence will quote, keyed by role.
  final Map<String, num> values;
}

/// The observations a window actually supports — no more, and never fewer
/// than the data allows.
///
/// Each one is produced only when its gate passed, so there is no path here
/// that yields a claim over three nights. When nothing qualifies the result is
/// a single [SleepInsightKind.insufficientData] draft, which the UI renders as
/// "No conclusion can be drawn from the nights recorded so far" — an answer,
/// not an empty section.
List<SleepInsightDraft> deterministicInsights({
  required SleepFactSheet sheet,
  required SleepWindowMetrics metrics,
  required SleepComparison comparison,
  required SleepTrend trend,
}) {
  final drafts = <SleepInsightDraft>[];
  final byId = {for (final fact in sheet.facts) fact.id: fact};

  final mean = byId['meanDuration'];
  if (mean != null) {
    drafts.add(
      SleepInsightDraft(
        kind: SleepInsightKind.duration,
        basedOn: const ['meanDuration'],
        nightCount: mean.nightCount,
        values: {'minutes': mean.value},
      ),
    );
  }

  // Week over week, including "about the same" — which is a real finding, and
  // the one a model is most tempted to inflate into a direction.
  if (comparison.verdict != SleepComparisonVerdict.insufficientData &&
      comparison.deltaMinutes != null) {
    drafts.add(
      SleepInsightDraft(
        kind: SleepInsightKind.weekOverWeek,
        basedOn: const ['weekOverWeekDelta', 'previousMeanDuration'],
        nightCount: comparison.currentNights,
        values: {'minutes': comparison.deltaMinutes!},
      ),
    );
  }

  final variability = byId['midpointVariability'];
  if (variability != null) {
    drafts.add(
      SleepInsightDraft(
        kind: SleepInsightKind.consistency,
        basedOn: const ['midpointVariability'],
        nightCount: variability.nightCount,
        values: {'minutes': variability.value},
      ),
    );
  }

  final onTarget = byId['nightsOnTargetBedtime'];
  if (onTarget != null) {
    drafts.add(
      SleepInsightDraft(
        kind: SleepInsightKind.targetAdherence,
        basedOn: const ['nightsOnTargetBedtime'],
        nightCount: onTarget.nightCount,
        values: {
          'nights': onTarget.value,
          'total': metrics.nightCount,
        },
      ),
    );
  }

  if (trend.direction != SleepTrendDirection.insufficientData &&
      trend.direction != SleepTrendDirection.flat &&
      trend.minutesPerNight != null) {
    drafts.add(
      SleepInsightDraft(
        kind: SleepInsightKind.trend,
        basedOn: const ['trend'],
        nightCount: trend.nightCount,
        values: {'minutesPerNight': trend.minutesPerNight!},
      ),
    );
  }

  if (drafts.isEmpty) {
    return [
      SleepInsightDraft(
        kind: SleepInsightKind.insufficientData,
        basedOn: const [],
        nightCount: sheet.nightsWithData,
      ),
    ];
  }

  // Three is the cap. A screenful of observations reads as a report and stops
  // being read; the ordering above puts the ones that change behaviour first.
  return drafts.take(3).toList(growable: false);
}
