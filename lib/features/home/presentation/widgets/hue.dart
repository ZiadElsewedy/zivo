import 'package:flutter/widgets.dart';
import '../../../../core/theme/train_tokens.dart';

/// A life-area hue. Each owns one meaning; on Today, the aggregation surface,
/// one hue lives per section (on dots/labels only) and Ember appears once.
///
/// Mirrors the handoff's four hues plus a neutral. There is deliberately no
/// fifth red: the old `flare` resolved to the same ember as [ZHue.ember] once
/// this moved onto `TrainColors`, and two names for one colour is precisely
/// what "one hue = one meaning" rules out.
///
/// Only [ZHue.neutral] currently has callers (the Today glance rows); the rest
/// are here for the sections that will.
enum ZHue { ember, pulse, solar, iris, neutral }

extension ZHueColors on ZHue {
  Color get dot => switch (this) {
    ZHue.ember => TrainColors.ember,
    ZHue.pulse => TrainColors.green,
    ZHue.solar => TrainColors.amber,
    ZHue.iris => TrainColors.violet,
    ZHue.neutral => TrainColors.hairlineStrong,
  };

  Color get text => switch (this) {
    ZHue.ember => TrainColors.ember,
    ZHue.pulse => TrainColors.green,
    ZHue.solar => TrainColors.amber,
    ZHue.iris => TrainColors.violet,
    ZHue.neutral => TrainColors.ink3,
  };
}

/// A small meaning-carrying dot.
class HueDot extends StatelessWidget {
  const HueDot(this.hue, {this.size = 8, super.key});

  final ZHue hue;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: hue.dot, shape: BoxShape.circle),
    );
  }
}
