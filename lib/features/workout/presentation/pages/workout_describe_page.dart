import 'package:flutter/material.dart';

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
      title: startRecording ? 'Describe your training' : 'Type it out',
      intro:
          'Say or write your split — the days, the exercises, and the sets '
          'and reps for each. ZIVO turns it into a real, editable split you '
          'review before anything is saved.',
      example:
          'Example: "Day A is push — bench press 4 sets of 8, incline '
          'dumbbell press 3 by 10, then cable flyes 3 by 15. Day B is pull…"',
      hint: 'Day A is push…',
      extractLabel: 'Turn this into a split',
      doneTalkingLabel: 'Done talking',
      tint: TrainColors.hubTint,
      buildImportPage: (text, dictated) => WorkoutImportPage(
        input: WorkoutImportDescription(text: text, dictated: dictated),
      ),
    );
  }
}
