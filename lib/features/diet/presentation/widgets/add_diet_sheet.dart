import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../pages/diet_dictate_page.dart';
import '../pages/diet_import_page.dart';
import '../pages/diet_plan_edit_page.dart';

/// The four ways a plan gets into ZIVO, in one place.
///
/// They are four *capture* routes, not four features: a PDF, a photo, a
/// spoken description and a typed one all reach the same extractor, the same
/// review editor and the same saved `DietPlan`. Listing them together is the
/// point — a user with a plan in their head shouldn't have to discover that
/// the app can take dictation by finding a mic button somewhere else.
///
/// Ordered by how most plans actually arrive: people are handed a document,
/// then they photograph one, then they describe their own.
Future<void> showAddDietSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
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
          Text('Add a diet', style: AppText.rowTitle),
          const SizedBox(height: 4),
          Text(
            'However it reaches ZIVO, you review every meal and every figure '
            'before it is saved.',
            style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.4),
          ),
          const SizedBox(height: 18),
          _Route(
            routeKey: const Key('add-diet-document'),
            icon: Icons.description_outlined,
            label: 'PDF or photo',
            detail: "Your nutritionist's plan, or a picture of one.",
            onTap: () => _open(context, const DietImportPage()),
          ),
          if (hasRecorder)
            _Route(
              routeKey: const Key('add-diet-dictate'),
              icon: Icons.mic_none_rounded,
              label: 'Say it out loud',
              detail: 'Describe your meals; ZIVO writes them down.',
              onTap: () => _open(context, const DietDictatePage()),
            ),
          _Route(
            routeKey: const Key('add-diet-type'),
            icon: Icons.notes_rounded,
            label: 'Type it out',
            detail: 'Write your meals in your own words.',
            onTap: () => _open(
              context,
              const DietDictatePage(startRecording: false),
            ),
          ),
          _Route(
            routeKey: const Key('add-diet-manual'),
            icon: Icons.edit_outlined,
            label: 'Build it meal by meal',
            detail: 'The full editor, nothing extracted for you.',
            onTap: () => _open(context, const DietPlanEditPage()),
            last: true,
          ),
        ],
      ),
    );
  }
}

class _Route extends StatelessWidget {
  const _Route({
    required this.routeKey,
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
    this.last = false,
  });

  final Key routeKey;
  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 9),
      child: TrainCard(
        radius: 18,
        padding: EdgeInsets.zero,
        child: InkWell(
          key: routeKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                // Differentiated by icon, not by colour — a hue here would
                // have to mean something, and "dictation" isn't a hue
                // (identity §3).
                Icon(icon, size: 19, color: TrainColors.ink2),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppText.rowTitle),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: AppText.meta.copyWith(color: TrainColors.ink3),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: TrainColors.ink3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
