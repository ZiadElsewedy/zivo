import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/zivo_toast.dart';
import '../../diet/presentation/pages/diet_plan_page.dart';
import '../../expenses/presentation/pages/expenses_list_page.dart';
import '../../moments/presentation/pages/moments_timeline_page.dart';
import '../../notes/presentation/pages/notes_list_page.dart';
import '../../schedule/presentation/pages/schedule_list_page.dart';
import '../../tasks/presentation/pages/task_list_page.dart';
import '../../shell/presentation/widgets/zivo_bottom_bar.dart';
import '../../university/presentation/pages/university_list_page.dart';
import '../../workout/presentation/pages/workout_dashboard_page.dart';

/// The Hub — the OS-style launcher into each module's depth. A clean two-column
/// grid of premium module cards, each with a tinted icon chip in its module
/// colour. Modules open as they are built; the rest show a "soon" chip.
class HubPage extends StatelessWidget {
  const HubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final modules = <_Module>[
      _Module('Schedule', AppIcons.schedule, AppColors.ember, AppColors.emberWash,
          (c) => const ScheduleListPage()),
      _Module('Tasks', AppIcons.tasks, AppColors.pulse, AppColors.pulseWash,
          (c) => const TaskListPage()),
      _Module('Workout', AppIcons.workout, AppColors.pulse, AppColors.pulseWash,
          (c) => const WorkoutDashboardPage()),
      _Module('Diet', AppIcons.diet, AppColors.solar, AppColors.solarWash,
          (c) => const DietPlanPage()),
      _Module('Expenses', AppIcons.expenses, AppColors.solar, AppColors.solarWash,
          (c) => const ExpensesListPage()),
      _Module('University', AppIcons.university, AppColors.iris, AppColors.irisWash,
          (c) => const UniversityListPage()),
      _Module('Notes', AppIcons.notes, AppColors.iris, AppColors.irisWash,
          (c) => const NotesListPage()),
      _Module('Moments', AppIcons.moments, AppColors.ember, AppColors.emberWash,
          (c) => const MomentsTimelinePage()),
    ];

    return Container(
      color: AppColors.ground,
      // The page is a single top-aligned scroll view: header, then the grid
      // directly beneath it. The grid is shrink-wrapped (`shrinkWrap: true`
      // + `NeverScrollableScrollPhysics`) so it sizes to its own content —
      // GridView.count derives row height from tile width alone, so left in
      // an `Expanded` its scroll viewport stretched taller than its content
      // and left a large dead band above the nav; shrink-wrapping removes
      // that. The outer `SingleChildScrollView` is the only scroller, so on
      // a short device (or a large text scale) the whole thing scrolls
      // naturally with nothing clipped. The bottom nav lives in
      // `HomeShell`'s Scaffold, independent of this content; because
      // `extendBody: true` draws the page behind it, the bottom scroll
      // padding reserves the nav bar's own exact rendered height
      // (`ZivoBottomBarMetrics.height`, safe-area inset included) so the
      // last row always clears it with a small, consistent breathing room.
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          media.padding.top + 20,
          AppSpacing.screen,
          ZivoBottomBarMetrics.height(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hub', style: AppText.greeting),
            const SizedBox(height: 4),
            Text('Everything, one tap away.', style: AppText.aside),
            const SizedBox(height: 26),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.32,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final m in modules) _ModuleTile(m)],
            ),
          ],
        ),
      ),
    );
  }
}

class _Module {
  const _Module(this.label, this.icon, this.color, this.wash, this.builder);
  final String label;
  final IconData icon;
  final Color color;
  final Color wash;
  final WidgetBuilder? builder;
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile(this.module);

  final _Module module;

  @override
  Widget build(BuildContext context) {
    final live = module.builder != null;
    return PressableScale(
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () {
            if (live) {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: module.builder!));
            } else {
              showZivoToast(context, '${module.label} — coming next.');
            }
          },
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.hairline),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: module.wash,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(module.icon, size: 23, color: module.color),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        module.label,
                        style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: MediaQuery.textScalerOf(context)
                            .clamp(maxScaleFactor: 1.3),
                      ),
                    ),
                    if (!live) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          'soon',
                          style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
