import 'package:flutter/material.dart';
import '../../../../l10n/l10n.dart';

import '../../../../core/theme/train_tokens.dart';
import '../../../capture/presentation/import/plan_describe_page.dart';
import '../../domain/workout_import_input.dart';
import 'workout_import_page.dart';

/// Describing your training split in your own words — spoken or typed —
/// instead of having a document to import.
///
/// A thin wrapper over the shared [PlanDescribePage] (the diet route is the
/// other), supplying only the workout copy and tint and sending the finished
/// words into `WorkoutImportPage` as a [WorkoutImportDescription] — the same
/// review-and-import gate a PDF or photo lands in.
class WorkoutDescribePage extends StatelessWidget {
  const WorkoutDescribePage({super.key, this.startRecording = true});

  /// Whether to open the mic straight away. False is the "type it out" route
  /// into the same screen.
  final bool startRecording;

  @override
  Widget build(BuildContext context) {
    return PlanDescribePage(
      keyPrefix: 'workout-describe',
      startRecording: startRecording,
      title: startRecording
          ? l(context).workoutDescribeTitleVoice
          : l(context).workoutDescribeTitleType,
      intro: l(context).workoutDescribeBody,
      example: l(context).workoutDescribeExample,
      hint: l(context).workoutDescribeHint,
      extractLabel: l(context).workoutDescribeSubmit,
      doneTalkingLabel: l(context).workoutDescribeDoneTalking,
      tint: TrainColors.hubTint,
      buildImportPage: (text, dictated) => WorkoutImportPage(
        input: WorkoutImportDescription(text: text, dictated: dictated),
      ),
    );
  }
}
