import 'package:flutter/painting.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/train_tokens.dart';
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

/// The same mapping on the design handoff's palette — what the Expenses
/// screen's category bars and row spines are drawn in.
///
/// Only four hues, because the handoff only defines four: [CategoryHue.flare]
/// folds onto ember rather than inventing a fifth. Two categories sharing a
/// hue is a smaller cost than a colour that means nothing anywhere else in
/// the system.
Color trainHueColor(CategoryHue hue) => switch (hue) {
  CategoryHue.ember || CategoryHue.flare => TrainColors.ember,
  CategoryHue.pulse => TrainColors.green,
  CategoryHue.solar => TrainColors.amber,
  CategoryHue.iris => TrainColors.violetGlyph,
};

Color hueWash(CategoryHue hue) => switch (hue) {
  CategoryHue.ember => AppColors.emberWash,
  CategoryHue.pulse => AppColors.pulseWash,
  CategoryHue.solar => AppColors.solarWash,
  CategoryHue.iris => AppColors.irisWash,
  CategoryHue.flare => AppColors.flareWash,
};
