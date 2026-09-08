import 'package:flutter/material.dart';
import '../../../../l10n/l10n.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../capture/presentation/import/add_plan_route_tile.dart';
import '../pages/workout_describe_page.dart';
import '../pages/workout_import_page.dart';
import '../pages/workout_plan_edit_page.dart';

/// Every way a training split gets into ZIVO, in one place — the workout mirror
/// of `showAddDietSheet`.
///
/// They are *routes*, not features: a PDF, a photo, a spoken description, a
/// typed one and a hand-built split all reach the same review editor and the
/// same saved `WorkoutPlan`. Listing them together is the point — a user with
/// a split in their head shouldn't have to discover that the app can take
/// dictation by finding a mic button somewhere else, and the import route no
/// longer pretends (as the old "Import PDF" button did) that a document is the
/// only way in.
///
/// Ordered by how most splits actually arrive: people are handed or photograph
/// a document, then they describe their own program.
Future<void> showAddWorkoutSheet(BuildContext context) {
  return showZivoSheet<void>(
    context: context,
    builder: (sheetContext) => _AddWorkoutSheet(sheetContext: sheetContext),
  );
}

class _AddWorkoutSheet extends StatelessWidget {
  const _AddWorkoutSheet({required this.sheetContext});

  /// The sheet's own context, so each route can close the sheet before
  /// pushing — otherwise the pushed page slides in under it.
  final BuildContext sheetContext;

  void _open(BuildContext context, Widget page) {
    HapticFeedback.selectionClick();
    final navigator = Navigator.of(sheetContext);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final hasRecorder = AppScope.of(context).recorder != null;
    return Container(
      decoration: BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l(context).addPlanTitle, style: AppText.rowTitle),
          const SizedBox(height: 4),
          Text(
            l(context).addPlanBody,
            style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.4),
          ),
          const SizedBox(height: 18),
          AddPlanRouteTile(
            routeKey: const Key('add-workout-document'),
            icon: Icons.description_outlined,
            label: l(context).addPlanPdfTitle,
            detail: l(context).addPlanPdfBody,
            onTap: () => _open(context, const WorkoutImportPage()),
          ),
          if (hasRecorder)
            AddPlanRouteTile(
              routeKey: const Key('add-workout-dictate'),
              icon: Icons.mic_none_rounded,
              label: l(context).addPlanVoiceTitle,
              detail: l(context).addPlanVoiceBody,
              onTap: () => _open(context, const WorkoutDescribePage()),
            ),
          AddPlanRouteTile(
            routeKey: const Key('add-workout-type'),
            icon: Icons.notes_rounded,
            label: l(context).addPlanTypeTitle,
            detail: l(context).addPlanTypeBody,
            onTap: () => _open(
              context,
              const WorkoutDescribePage(startRecording: false),
            ),
          ),
          AddPlanRouteTile(
            routeKey: const Key('add-workout-manual'),
            icon: Icons.edit_outlined,
            label: l(context).addPlanManualTitle,
            detail: l(context).addPlanManualBody,
            onTap: () =>
                _open(context, const WorkoutPlanEditPage(asSplit: true)),
            last: true,
          ),
        ],
      ),
    );
  }
}
