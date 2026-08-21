import 'package:flutter/painting.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/expense_category.dart';

/// Maps a category's [CategoryHue] to its vivid tone and translucent wash
/// from the app's fixed 5-hue palette (`AppColors`).
Color hueColor(CategoryHue hue) => switch (hue) {
  CategoryHue.ember => AppColors.ember,
  CategoryHue.pulse => AppColors.pulse,
  CategoryHue.solar => AppColors.solar,
  CategoryHue.iris => AppColors.iris,
  CategoryHue.flare => AppColors.flare,
};

Color hueWash(CategoryHue hue) => switch (hue) {
  CategoryHue.ember => AppColors.emberWash,
  CategoryHue.pulse => AppColors.pulseWash,
  CategoryHue.solar => AppColors.solarWash,
  CategoryHue.iris => AppColors.irisWash,
  CategoryHue.flare => AppColors.flareWash,
};
