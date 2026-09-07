import 'package:flutter/widgets.dart';

import '../../../../core/theme/train_tokens.dart';
import '../sleep_labels.dart';

/// A sleep duration set as a figure: the number in mono, the unit beside it in
/// the text face, smaller and dimmer.
///
/// This exists because of Arabic. `7س 12د` built as a single mono string puts
/// `س` and `د` — which Azeret Mono does not carry — into a system fallback
/// face, so one figure ends up in two typefaces with different weights and
/// vertical metrics. At the hero's 54px that does not read as a duration.
///
/// Keeping the unit out of the mono run is ZIVO's existing answer to exactly
/// this: `TrainStatTile` holds `value` and `unit` apart, and the You header
/// sets `12.9` over `الإجمالي` rather than interpolating the word. English
/// gains too — a lighter, smaller `h`/`m` is how a hero duration is set
/// everywhere it is set well.
class SleepDurationText extends StatelessWidget {
  const SleepDurationText({
    required this.duration,
    required this.size,
    this.color = TrainColors.ink,
    this.unitColor,
    this.weight = FontWeight.w300,
    super.key,
  });

  final Duration duration;

  /// Size of the numerals. The unit is set from this.
  final double size;

  final Color color;
  final Color? unitColor;
  final FontWeight weight;

  /// The unit's share of the numeral size. Small enough to sit under the
  /// number without competing, large enough to read at a glance.
  static const double _unitScale = 0.46;

  @override
  Widget build(BuildContext context) {
    final parts = sleepDurationParts(context, duration);
    final numberStyle = TrainType.mono(
      size: size,
      weight: weight,
      tracking: -0.03,
      height: 1,
      color: color,
    );
    final unitStyle = TrainType.ui(
      size: size * _unitScale,
      weight: FontWeight.w600,
      height: 1,
      color: unitColor ?? color.withValues(alpha: 0.55),
    );

    return Semantics(
      // The screen reader gets the plain composed string; the visual split is
      // typography, not meaning. `container` is required — without it this
      // merges into the parent and the label never becomes a node of its own.
      container: true,
      label: sleepDurationText(context, duration),
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0) TextSpan(text: ' ', style: unitStyle),
              TextSpan(text: parts[i].$1, style: numberStyle),
              TextSpan(text: parts[i].$2, style: unitStyle),
            ],
          ],
        ),
        maxLines: 1,
        // The figure is a number, and a number reads left-to-right in every
        // language ZIVO speaks. Pinning the WIDGET's direction is safe where
        // pinning the string was not: the unit spans keep their own shaping,
        // they are simply laid out after the number they belong to.
        textDirection: TextDirection.ltr,
      ),
    );
  }
}
