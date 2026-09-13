import 'package:flutter/widgets.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/train_tokens.dart';
import '../../../core/util/bidi.dart';
import '../../../l10n/l10n.dart';
import '../../sleep/presentation/sleep_labels.dart';
import '../domain/readiness.dart';

/// The copy contract for readiness — the ONE place a verdict or a factor
/// becomes words and a colour, so the Today card and the detail page can never
/// phrase the same call two ways. The domain carries facts; this carries voice.
///
/// Colour here follows the app's status semantics (ADR-006): green = go
/// (train hard / a supporting factor), amber = ease off (go light / a caution),
/// ember = the thing that wants your eye (rest / a limiting factor). No new hue.

/// The headline call: the word, a one-line blurb, and its status colour.
class ReadinessVerdictCopy {
  const ReadinessVerdictCopy({
    required this.word,
    required this.blurb,
    required this.color,
  });

  final String word;
  final String blurb;
  final Color color;
}

ReadinessVerdictCopy readinessVerdictCopy(
  BuildContext context,
  ReadinessVerdict verdict,
) {
  final strings = l(context);
  return switch (verdict) {
    ReadinessVerdict.trainHard => ReadinessVerdictCopy(
      word: strings.readinessTrainHard,
      blurb: strings.readinessTrainHardBlurb,
      color: TrainColors.green,
    ),
    ReadinessVerdict.goLight => ReadinessVerdictCopy(
      word: strings.readinessGoLight,
      blurb: strings.readinessGoLightBlurb,
      color: TrainColors.amber,
    ),
    ReadinessVerdict.rest => ReadinessVerdictCopy(
      word: strings.readinessRest,
      blurb: strings.readinessRestBlurb,
      color: TrainColors.ember,
    ),
  };
}

/// One factor rendered: an icon, a status colour, a title, and the number it
/// cites ([detail], which may be empty when the factor has no figure).
class ReadinessFactorCopy {
  const ReadinessFactorCopy({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
}

Color _directionColor(ReadinessDirection direction) => switch (direction) {
  ReadinessDirection.supports => TrainColors.green,
  ReadinessDirection.caution => TrainColors.amber,
  ReadinessDirection.limits => TrainColors.ember,
};

ReadinessFactorCopy readinessFactorCopy(
  BuildContext context,
  ReadinessFactor factor,
) {
  final strings = l(context);
  final color = _directionColor(factor.direction);

  switch (factor.kind) {
    case ReadinessFactorKind.sleep:
      final minutes = factor.sleepDurationMinutes ?? 0;
      final duration = sleepDurationText(context, Duration(minutes: minutes));
      final short = factor.direction != ReadinessDirection.supports;
      return ReadinessFactorCopy(
        icon: AppIcons.sleep,
        color: color,
        title: short ? strings.readinessSleepShort : strings.readinessSleptWell,
        detail: duration,
      );
    case ReadinessFactorKind.deload:
      final count = factor.deloadExerciseCount ?? 0;
      return ReadinessFactorCopy(
        icon: AppIcons.workout,
        color: color,
        title: strings.readinessDeloadDueTitle,
        detail: strings.readinessDeloadDetail(count),
      );
    case ReadinessFactorKind.recentLoad:
      final days = factor.restDays ?? 0;
      if (factor.direction == ReadinessDirection.supports) {
        return ReadinessFactorCopy(
          icon: AppIcons.timer,
          color: color,
          title: strings.readinessRecoveredTitle,
          detail: strings.readinessRestDaysDetail(days),
        );
      }
      return ReadinessFactorCopy(
        icon: AppIcons.timer,
        color: color,
        title: strings.readinessTrainedTodayTitle,
        detail: '',
      );
    case ReadinessFactorKind.bodyWeight:
      final kg = (factor.weightChangeKg ?? 0).abs().toStringAsFixed(1);
      return ReadinessFactorCopy(
        icon: AppIcons.scale,
        color: color,
        // "Down 2.4 kg" — a signed-ish figure whose digits+unit run must be
        // pinned so it does not reorder in an Arabic paragraph.
        title: strings.readinessWeightDropTitle,
        detail: ltrFor(context, strings.readinessWeightDropDetail(kg)),
      );
  }
}
