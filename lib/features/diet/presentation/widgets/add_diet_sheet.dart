import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../capture/presentation/import/add_plan_route_tile.dart';
import '../pages/diet_dictate_page.dart';
import '../pages/diet_import_page.dart';
import '../pages/diet_plan_edit_page.dart';
import '../pages/diet_preferences_page.dart';
import '../../../../l10n/l10n.dart';

/// Every way a plan gets into ZIVO, in one place.
///
/// They are *routes*, not features: a PDF, a photo, a spoken description, a
/// typed one and a generated plan all reach the same review editor and the
/// same saved `DietPlan`. Listing them together is the point — a user with a
/// plan in their head shouldn't have to discover that the app can take
/// dictation by finding a mic button somewhere else, and a user with no plan
/// at all shouldn't have to guess that ZIVO can write one.
///
/// Ordered by how most plans actually arrive: people are handed a document,
/// then they photograph one, then they describe their own — and last, for the
/// people who have no plan at all, ZIVO builds one.
Future<void> showAddDietSheet(BuildContext context) {
  return showZivoSheet<void>(
    context: context,
    builder: (sheetContext) => _AddDietSheet(sheetContext: sheetContext),
  );
}

class _AddDietSheet extends StatelessWidget {
  const _AddDietSheet({required this.sheetContext});

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
      decoration: const BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l(context).dietAddPlan, style: AppText.rowTitle),
          const SizedBox(height: 4),
          Text(
            l(context).addDietIntro,
            style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.4),
          ),
          const SizedBox(height: 18),
          AddPlanRouteTile(
            routeKey: const Key('add-diet-document'),
            icon: Icons.description_outlined,
            label: l(context).addDietPdfOrPhoto,
            detail: l(context).addDietPdfOrPhotoDetail,
            onTap: () => _open(context, const DietImportPage()),
          ),
          if (hasRecorder)
            AddPlanRouteTile(
              routeKey: const Key('add-diet-dictate'),
              icon: Icons.mic_none_rounded,
              label: l(context).addDietDictate,
              detail: l(context).addDietDictateDetail,
              onTap: () => _open(context, const DietDictatePage()),
            ),
          AddPlanRouteTile(
            routeKey: const Key('add-diet-type'),
            icon: Icons.notes_rounded,
            label: l(context).addDietType,
            detail: l(context).addDietTypeDetail,
            onTap: () =>
                _open(context, const DietDictatePage(startRecording: false)),
          ),
          AddPlanRouteTile(
            routeKey: const Key('add-diet-generate'),
            icon: Icons.auto_awesome_rounded,
            label: l(context).addDietGenerate,
            detail: l(context).addDietGenerateDetail,
            onTap: () => _open(context, const DietPreferencesPage()),
          ),
          AddPlanRouteTile(
            routeKey: const Key('add-diet-manual'),
            icon: Icons.edit_outlined,
            label: l(context).addDietManual,
            detail: l(context).addDietManualDetail,
            onTap: () => _open(context, const DietPlanEditPage()),
            last: true,
          ),
        ],
      ),
    );
  }
}

