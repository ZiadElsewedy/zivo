import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
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
/// app-wide [AppColors] theme.
class SplitManagementPage extends StatelessWidget {
  const SplitManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final plans = AppScope.of(context).workoutPlans;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.ink2),
        title: Text('Splits', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.pulse,
        elevation: 2,
        tooltip: 'New split',
        onPressed: () => _openNewSplitSheet(context),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: StreamBuilder<List<WorkoutPlan>>(
        stream: plans.watchSplits(),
        initialData: plans.splits,
        builder: (context, splitsSnap) {
          if (splitsSnap.hasError) return const _SplitsErrorState();
          final splits = splitsSnap.data ?? const <WorkoutPlan>[];
          final loading = splits.isEmpty && splitsSnap.connectionState == ConnectionState.waiting;
          if (loading) return const _SplitsLoadingState();
          if (splits.isEmpty) return const _SplitsEmptyState();

          return StreamBuilder<WorkoutPlan?>(
            stream: plans.watchActivePlan(),
            initialData: plans.activePlan,
            builder: (context, activeSnap) {
              final activeId = activeSnap.data?.id;
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
                itemCount: splits.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => StaggeredReveal(
                  index: i,
                  child: _SplitTile(split: splits[i], isActive: splits[i].id == activeId, plans: plans),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

enum _SplitAction { setActive, edit, duplicate, delete }

enum _NewSplitAction { manual, importAi }

Future<void> _openNewSplitSheet(BuildContext context) async {
  final action = await showModalBottomSheet<_NewSplitAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _NewSplitActionsSheet(),
  );
  if (action == null || !context.mounted) return;
  HapticFeedback.selectionClick();
  switch (action) {
    case _NewSplitAction.manual:
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WorkoutPlanEditPage(asSplit: true)),
      );
    case _NewSplitAction.importAi:
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WorkoutPdfImportPage()),
      );
  }
}

/// The FAB's "new split" sheet — exactly two ways in: build it by hand, or
/// hand a PDF to AI. Matches [_SplitActionsSheet]'s styling.
class _NewSplitActionsSheet extends StatelessWidget {
  const _NewSplitActionsSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.only(top: 12, left: 8, right: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: AppColors.hairline2, borderRadius: BorderRadius.circular(999)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'New split',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _ActionRow(
            icon: Icons.edit_outlined,
            label: 'Create Manually',
            color: AppColors.ink2,
            onTap: () => Navigator.of(context).pop(_NewSplitAction.manual),
          ),
          _ActionRow(
            icon: Icons.auto_awesome_rounded,
            label: 'Import with AI',
            color: AppColors.pulse,
            onTap: () => Navigator.of(context).pop(_NewSplitAction.importAi),
          ),
        ],
      ),
    );
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
  const _SplitTile({required this.split, required this.isActive, required this.plans});

  final WorkoutPlan split;
  final bool isActive;
  final WorkoutPlanRepository plans;

  @override
  Widget build(BuildContext context) {
    final dayCount = split.days.length;
    final exerciseCount = split.days.fold<int>(0, (sum, d) => sum + d.exercises.length);
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openActions(context),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: isActive ? AppColors.pulse.withValues(alpha: 0.5) : AppColors.hairline2),
            ),
            child: Row(
              children: [
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
                              style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                            ),
                          ),
                          if (isActive) ...[const SizedBox(width: 8), const _ActiveBadge()],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$dayCount day${dayCount == 1 ? '' : 's'} · $exerciseCount exercise${exerciseCount == 1 ? '' : 's'}',
                        style: AppText.meta.copyWith(color: AppColors.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.more_vert_rounded, color: AppColors.ink3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openActions(BuildContext context) async {
    final action = await showModalBottomSheet<_SplitAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SplitActionsSheet(splitName: split.name, isActive: isActive),
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
          MaterialPageRoute(builder: (_) => WorkoutPlanEditPage(initialPlan: split, asSplit: true)),
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
        backgroundColor: AppColors.card,
        title: Text('Delete "${split.name}"?', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
        content: Text(
          'This removes the split and all its days and exercises. Logged '
          "history for it is kept, just no longer editable here. This can't be undone.",
          style: AppText.body.copyWith(color: AppColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppText.button.copyWith(color: AppColors.ink3)),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context, true);
            },
            child: Text('Delete', style: AppText.button.copyWith(color: AppColors.flare)),
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
        color: AppColors.pulse.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'Active',
        style: AppText.meta.copyWith(color: AppColors.pulse, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The per-split action sheet — "Set as active" (hidden when already
/// active), Edit, Duplicate, Delete. A bottom sheet rather than a
/// `PopupMenuButton`, matching this feature's existing sheet-driven actions
/// (day/exercise editing) instead of introducing a new interaction pattern.
class _SplitActionsSheet extends StatelessWidget {
  const _SplitActionsSheet({required this.splitName, required this.isActive});

  final String splitName;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.only(top: 12, left: 8, right: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: AppColors.hairline2, borderRadius: BorderRadius.circular(999)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                splitName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (!isActive)
            _ActionRow(
              icon: Icons.check_circle_outline_rounded,
              label: 'Set as active',
              color: AppColors.pulse,
              onTap: () => Navigator.of(context).pop(_SplitAction.setActive),
            ),
          _ActionRow(
            icon: Icons.edit_outlined,
            label: 'Edit',
            color: AppColors.ink2,
            onTap: () => Navigator.of(context).pop(_SplitAction.edit),
          ),
          _ActionRow(
            icon: Icons.copy_all_outlined,
            label: 'Duplicate',
            color: AppColors.ink2,
            onTap: () => Navigator.of(context).pop(_SplitAction.duplicate),
          ),
          _ActionRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            color: AppColors.flare,
            onTap: () => Navigator.of(context).pop(_SplitAction.delete),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 14),
                Text(label, style: AppText.body.copyWith(fontSize: 15, color: color, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
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
        decoration: const BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle),
        padding: const EdgeInsets.all(10),
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(AppColors.ink2, BlendMode.srcIn),
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
            const Icon(Icons.cloud_off_rounded, size: 30, color: AppColors.ink3),
            const SizedBox(height: 12),
            Text("Couldn't load this.", style: AppText.aside.copyWith(color: AppColors.ink2), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Check your connection and try again in a moment.',
              style: AppText.meta.copyWith(color: AppColors.ink3),
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
            const Icon(Icons.layers_outlined, size: 30, color: AppColors.ink3),
            const SizedBox(height: 12),
            Text('No splits yet.', style: AppText.aside.copyWith(color: AppColors.ink2), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Tap + to build your first one.', style: AppText.meta.copyWith(color: AppColors.ink3)),
          ],
        ),
      ),
    );
  }
}
