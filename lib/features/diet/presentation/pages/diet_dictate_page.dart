import 'package:flutter/material.dart';

import '../../../../core/theme/train_tokens.dart';
import '../../../capture/presentation/import/plan_describe_page.dart';
import '../../domain/diet_import_input.dart';
import 'diet_import_page.dart';
import '../../../../l10n/l10n.dart';

/// Describing your diet in your own words — spoken or typed — instead of
/// having a document to import.
///
/// A thin wrapper over the shared [PlanDescribePage]: the record → transcribe
/// → edit-before-extract machinery is identical to the workout route, so it
/// lives once. This screen supplies only the diet copy, the diet tint, and
/// where the finished words go — into `DietImportPage` as a
/// [DietImportDescription], the same review gate every other diet route lands
/// in.
class DietDictatePage extends StatelessWidget {
  const DietDictatePage({super.key, this.startRecording = true});

  /// Whether to open the mic straight away. False is the "type it out" route
  /// into the same screen.
  final bool startRecording;

  @override
  Widget build(BuildContext context) {
    return PlanDescribePage(
      keyPrefix: 'dictate',
      startRecording: startRecording,
      title: startRecording ? 'Describe your diet' : 'Type it out',
      intro:
          'Say or write what you eat in a day — meals, foods and rough '
          'amounts. ZIVO turns it into a plan you review before anything is '
          'saved.',
      example:
          'Example: "Breakfast is three eggs and 60 grams of oats. Lunch is '
          '200 grams of chicken with rice and salad."',
      hint: l(context).dictateHint,
      extractLabel: l(context).dictateTurnIntoPlan,
      doneTalkingLabel: l(context).dictateDoneTalking,
      tint: TrainColors.dietTint,
      buildImportPage: (text, dictated) => DietImportPage(
        input: DietImportDescription(text: text, dictated: dictated),
      ),
    );
  }
}
