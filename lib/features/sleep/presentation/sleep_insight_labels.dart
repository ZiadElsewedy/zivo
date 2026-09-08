/// Turning a grounded observation into a sentence.
///
/// The domain produces [SleepInsightDraft]s — a kind, the fact ids behind it,
/// and the figures it will quote — and nothing else, because a `domain/` type
/// that carried copy could not be translated and could not be re-worded
/// without a data migration. This is where the words are attached.
///
/// Every sentence is built from values that came out of `sleep_metrics.dart`,
/// so every number in it is grounded by construction. That is the same
/// guarantee the numeral gate enforces on model-written text
/// (`docs/SLEEP_SYSTEM.md` §15) — here it holds without a check, which is why
/// this tier is the floor the feature never drops below.
library;

import 'package:flutter/widgets.dart';

import '../../../core/util/bidi.dart';
import '../../../l10n/l10n.dart';
import '../domain/sleep_insight.dart';
import 'sleep_labels.dart';

/// The rendered sentence for one draft, or null when the draft is not
/// attributable — an observation citing no facts is never shown.
String? sleepInsightText(BuildContext context, SleepInsightDraft draft) {
  final strings = l(context);
  final minutes = draft.values['minutes'];

  return switch (draft.kind) {
    SleepInsightKind.duration => minutes == null
        ? null
        : strings.sleepInsightDuration(sleepMinutesText(context, minutes)),

    SleepInsightKind.weekOverWeek => switch (minutes) {
      null => null,
      // The noise floor, restated in words. `SleepMetrics.compare` has already
      // decided a difference this small is not a direction; saying "about the
      // same" is reporting that decision, not hedging around it.
      final m when m.abs() < 15 => strings.sleepInsightWeekSame,
      final m when m > 0 => strings.sleepInsightWeekBetter(
        sleepMinutesText(context, m),
      ),
      _ => strings.sleepInsightWeekWorse(sleepMinutesText(context, minutes)),
    },

    // Half an hour of midpoint drift is roughly where a schedule stops feeling
    // regular — the same tolerance the bedtime target uses, so the two
    // sentences cannot contradict each other.
    SleepInsightKind.consistency => minutes == null
        ? null
        : (minutes <= 30
              ? strings.sleepInsightConsistent(
                  sleepMinutesText(context, minutes),
                )
              : strings.sleepInsightIrregular(
                  sleepMinutesText(context, minutes),
                )),

    SleepInsightKind.targetAdherence => () {
      final nights = draft.values['nights'];
      final total = draft.values['total'];
      if (nights == null || total == null) return null;
      return ltrFor(
        context,
        strings.sleepInsightAdherence(nights.round(), total.round()),
      );
    }(),

    // Direction only. A Theil-Sen slope in minutes per night is a real number
    // and a useless sentence — "1.4 minutes more per night" tells a reader
    // nothing they can act on, and quoting it would spend precision on
    // something the estimate does not really have.
    SleepInsightKind.trend => switch (draft.values['minutesPerNight']) {
      null => null,
      final slope when slope > 0 => strings.sleepInsightTrendUp,
      _ => strings.sleepInsightTrendDown,
    },

    SleepInsightKind.insufficientData => strings.sleepInsightsUnavailable,
  };
}
