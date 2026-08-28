import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_repository.dart';
import '../widgets/staggered_reveal.dart';
import 'workout_pdf_import_page.dart';
import 'workout_plan_edit_page.dart';

/// Split management (WORKOUT_SYSTEM.md Phase 4) — list every saved split,
/// see which one is active, switch, edit (reusing [WorkoutPlanEditPage] in
/// `asSplit` mode), duplicate, or delete. Switching only moves the active
/// pointer (`setActiveSplit`) — it never touches a split's own session
/// history (§3.2 invariant 4: every split keeps its own sessions).
///
/// Dark, immersive body — matching the plan/analysis/history pages on the
/// app-wide [AppColors] theme; each tile carries a gradient mark in the
/// training hue, glowing for the active split.
class SplitManagementPage extends StatelessWidget {
  const SplitManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final plans = AppScope.of(context).workoutPlans;
    return Scaffold(
      backgroundColor: AppColors.ground,
      floatingActionButton: FloatingActionButton(
        backgroundColor: TrainColors.green,
        elevation: 3,
        tooltip: 'New split',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onPressed: () => _openNewSplitSheet(context),
        child: const Icon(AppIcons.add, color: Colors.white),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: TrainColors.hubTint),
        child: Stack(
          children: [
            SafeArea(
              child: StreamBuilder<List<WorkoutPlan>>(
                stream: plans.watchSplits(),
                initialData: plans.splits,
                builder: (context, splitsSnap) {
                  if (splitsSnap.hasError) return const _SplitsErrorState();
                  final splits = splitsSnap.data ?? const <WorkoutPlan>[];
                  final loading =
                      splits.isEmpty &&
                      splitsSnap.connectionState == ConnectionState.waiting;
                  if (loading) return const _SplitsLoadingState();
                  if (splits.isEmpty) return const _SplitsEmptyState();

                  return StreamBuilder<WorkoutPlan?>(
                    stream: plans.watchActivePlan(),
                    initialData: plans.activePlan,
                    builder: (context, activeSnap) {
                      final activeId = activeSnap.data?.id;
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(22, 12, 22, 100),
                        children: [
                          StaggeredReveal(
                            index: 0,
                            child: const TrainPageHeader(title: 'Splits'),
                          ),
                          const SizedBox(height: 22),
                          for (var i = 0; i < splits.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: StaggeredReveal(
                                index: i + 1,
                                child: _SplitTile(
                                  split: splits[i],
                                  isActive: splits[i].id == activeId,
                                  plans: plans,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SplitAction { setActive, edit, duplicate, delete }

enum _NewSplitAction { manual, importAi }

Future<void> _openNewSplitSheet(BuildContext context) async {
  final action = await showCupertinoModalPopup<_NewSplitAction>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: const Text('New split'),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () =>
              Navigator.of(sheetContext).pop(_NewSplitAction.manual),
          child: const Text('Create Manually'),
        ),
        CupertinoActionSheetAction(
          onPressed: () =>
              Navigator.of(sheetContext).pop(_NewSplitAction.importAi),
          child: const Text('Import with AI'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(sheetContext).pop(),
        child: const Text('Cancel'),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  HapticFeedback.selectionClick();
  switch (action) {
    case _NewSplitAction.manual:
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const WorkoutPlanEditPage(asSplit: true),
        ),
      );
    case _NewSplitAction.importAi:
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const WorkoutPdfImportPage()));
  }
}

/// A fresh split from [original]'s content — new id/createdAt/updatedAt, name
/// suffixed " copy". Reuses the SAME day/exercise ids as the original: safe,
/// because every history/analysis read filters by `planId` first (see
/// `day_progress_analysis.dart`), so two different splits sharing an
/// `exerciseId` never cross-contaminates either one's history.
WorkoutPlan _duplicateOf(WorkoutPlan original) {
  final now = DateTime.now();
  return WorkoutPlan(
    id: 'split-${now.microsecondsSinceEpoch}',
    name: '${original.name} copy',
    status: original.status,
    source: original.source,
    createdAt: now,
    updatedAt: now,
    cycleCursor: original.cycleCursor,
    days: original.days,
  );
}

class _SplitTile extends StatelessWidget {
  const _SplitTile({
    required this.split,
    required this.isActive,
    required this.plans,
  });

  final WorkoutPlan split;
  final bool isActive;
  final WorkoutPlanRepository plans;

  @override
  Widget build(BuildContext context) {
    final dayCount = split.days.length;
    final exerciseCount = split.days.fold<int>(
      0,
      (sum, d) => sum + d.exercises.length,
    );
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openActions(context),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x08FFFFFF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isActive
                    ? TrainColors.green.withValues(alpha: 0.45)
                    : TrainColors.hairline,
              ),
              boxShadow: [
                if (isActive)
                  BoxShadow(
                    color: TrainColors.green.withValues(alpha: 0.16),
                    blurRadius: 26,
                    spreadRadius: -8,
                    offset: const Offset(0, 12),
                  ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        TrainColors.green.withValues(
                          alpha: isActive ? 0.30 : 0.14,
                        ),
                        TrainColors.green.withValues(
                          alpha: isActive ? 0.10 : 0.04,
                        ),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: TrainColors.green.withValues(
                        alpha: isActive ? 0.24 : 0.10,
                      ),
                    ),
                  ),
                  child: Icon(
                    AppIcons.splits,
                    size: 20,
                    color: isActive ? TrainColors.green : TrainColors.ink2,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              split.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.rowTitle.copyWith(
                                fontWeight: FontWeight.w600,
                                color: TrainColors.ink,
                              ),
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 8),
                            const _ActiveBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$dayCount day${dayCount == 1 ? '' : 's'} · $exerciseCount exercise${exerciseCount == 1 ? '' : 's'}',
                        style: AppText.meta.copyWith(color: TrainColors.ink4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.more_vert_rounded,
                  color: TrainColors.ink4,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openActions(BuildContext context) async {
    final action = await showCupertinoModalPopup<_SplitAction>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(split.name),
        actions: [
          if (!isActive)
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.of(sheetContext).pop(_SplitAction.setActive),
              child: const Text('Set as active'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(_SplitAction.edit),
            child: const Text('Edit'),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(sheetContext).pop(_SplitAction.duplicate),
            child: const Text('Duplicate'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () =>
                Navigator.of(sheetContext).pop(_SplitAction.delete),
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    // Haptic fires per-resolved-action (not on opening the sheet) — each
    // case below picks the feel that matches what it actually does.
    switch (action) {
      case _SplitAction.setActive:
        HapticFeedback.selectionClick();
        await plans.setActiveSplit(split.id);
      case _SplitAction.edit:
        HapticFeedback.selectionClick();
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                WorkoutPlanEditPage(initialPlan: split, asSplit: true),
          ),
        );
      case _SplitAction.duplicate:
        HapticFeedback.lightImpact();
        await plans.saveSplit(_duplicateOf(split));
      case _SplitAction.delete:
        // mediumImpact fires inside _confirmDelete, right at the actual
        // commit — the dialog's Delete tap is this flow's "point of no
        // return", same role the chat-delete swipe threshold plays.
        await _confirmDelete(context);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0x08FFFFFF),
        title: Text(
          'Delete "${split.name}"?',
          style: AppText.cardTitle.copyWith(color: TrainColors.ink),
        ),
        content: Text(
          'This removes the split and all its days and exercises. Logged '
          "history for it is kept, just no longer editable here. This can't be undone.",
          style: AppText.body.copyWith(color: TrainColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppText.button.copyWith(color: TrainColors.ink4),
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context, true);
            },
            child: Text(
              'Delete',
              style: AppText.button.copyWith(color: TrainColors.ember),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await plans.deleteSplit(split.id);
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: TrainColors.green.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'Active',
        style: AppText.meta.copyWith(
          color: TrainColors.green,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SplitsLoadingState extends StatelessWidget {
  const _SplitsLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 140,
        height: 140,
        decoration: const BoxDecoration(
          color: TrainColors.glassStrong,
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(10),
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(
            TrainColors.ink2,
            BlendMode.srcIn,
          ),
          child: Lottie.asset('assets/loading.json', fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _SplitsErrorState extends StatelessWidget {
  const _SplitsErrorState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 30,
              color: TrainColors.ink4,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load this.",
              style: AppText.aside.copyWith(color: TrainColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Check your connection and try again in a moment.',
              style: AppText.meta.copyWith(color: TrainColors.ink4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitsEmptyState extends StatelessWidget {
  const _SplitsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    TrainColors.green.withValues(alpha: 0.22),
                    TrainColors.green.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                AppIcons.splits,
                size: 28,
                color: TrainColors.green,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No splits yet.',
              style: AppText.aside.copyWith(color: TrainColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Tap + to build your first one.',
              style: AppText.meta.copyWith(color: TrainColors.ink4),
            ),
          ],
        ),
      ),
    );
  }
}
