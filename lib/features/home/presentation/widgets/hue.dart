import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';

/// A life-area hue. Each owns one meaning; on Today, the aggregation surface,
/// one hue lives per section (on dots/labels only) and Ember appears once.
enum ZHue { ember, pulse, solar, iris, flare, neutral }

extension ZHueColors on ZHue {
  Color get dot => switch (this) {
        ZHue.ember => AppColors.ember,
        ZHue.pulse => AppColors.pulse,
        ZHue.solar => AppColors.solar,
        ZHue.iris => AppColors.iris,
        ZHue.flare => AppColors.flare,
        ZHue.neutral => AppColors.hairline2,
      };

  Color get text => switch (this) {
        ZHue.ember => AppColors.emberText,
        ZHue.pulse => AppColors.pulseText,
        ZHue.solar => AppColors.solarText,
        ZHue.iris => AppColors.irisText,
        ZHue.flare => AppColors.flareText,
        ZHue.neutral => AppColors.ink3,
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
