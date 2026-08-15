import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../diet/presentation/pages/diet_plan_page.dart';
import '../../moments/presentation/pages/moments_timeline_page.dart';
import '../../notes/presentation/pages/notes_list_page.dart';
import '../../schedule/presentation/pages/schedule_list_page.dart';
import '../../tasks/presentation/pages/task_list_page.dart';
import '../../university/presentation/pages/university_list_page.dart';
import '../../workout/presentation/pages/workout_history_page.dart';

/// The Hub — the OS-style launcher into each module's depth. Notes and Moments
/// are live; the rest open as they are built.
class HubPage extends StatelessWidget {
  const HubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final modules = <_Module>[
      _Module(
        'Schedule',
        Icons.calendar_today_rounded,
        AppColors.emberText,
        (c) => const ScheduleListPage(),
      ),
      _Module(
        'Tasks',
        Icons.check_circle_outline_rounded,
        AppColors.ink,
        (c) => const TaskListPage(),
      ),
      _Module(
        'Workout',
        Icons.fitness_center_rounded,
        AppColors.pulseText,
        (c) => const WorkoutHistoryPage(),
      ),
      _Module(
        'Diet',
        Icons.restaurant_rounded,
        AppColors.pulseText,
        (c) => const DietPlanPage(),
      ),
      _Module('Expenses', Icons.payments_rounded, AppColors.solarText, null),
      _Module(
        'University',
        Icons.school_outlined,
        AppColors.irisText,
        (c) => const UniversityListPage(),
      ),
      _Module(
        'Notes',
        Icons.sticky_note_2_rounded,
        AppColors.ink,
        (c) => const NotesListPage(),
      ),
      _Module(
        'Moments',
        Icons.photo_camera_rounded,
        AppColors.ink,
        (c) => const MomentsTimelinePage(),
      ),
    ];

    return Container(
      color: AppColors.ground,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          media.padding.top + 20,
          AppSpacing.screen,
          media.padding.bottom + 120,
        ),
        children: [
          Text('Hub', style: AppText.greeting),
          const SizedBox(height: 4),
          Text('Everything, one tap away.', style: AppText.aside),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.5,
            children: [for (final m in modules) _ModuleTile(m)],
          ),
        ],
      ),
    );
  }
}

class _Module {
  const _Module(this.label, this.icon, this.color, this.builder);
  final String label;
  final IconData icon;
  final Color color;
  final WidgetBuilder? builder;
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile(this.module);

  final _Module module;

  @override
  Widget build(BuildContext context) {
    final live = module.builder != null;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () {
          if (live) {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: module.builder!));
          } else {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.ink,
                  content: Text(
                    '${module.label} — coming next.',
                    style: AppText.button.copyWith(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
          }
        },
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(module.icon, size: 24, color: module.color),
              Row(
                children: [
                  Text(
                    module.label,
                    style: AppText.rowTitle.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!live) ...[
                    const SizedBox(width: 6),
                    Text(
                      'soon',
                      style: AppText.meta.copyWith(
                        color: AppColors.ink3,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
