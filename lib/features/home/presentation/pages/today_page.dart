import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../auth/domain/user_profile.dart';
import '../../../diet/domain/diet_plan.dart';
import '../../../diet/domain/diet_summary.dart';
import '../../../diet/presentation/today_diet.dart';
import '../../../expenses/domain/expense.dart';
import '../../../expenses/domain/expense_repository.dart';
import '../../../schedule/domain/schedule_event.dart';
import '../../../schedule/domain/schedule_repository.dart';
import '../../../tasks/domain/task.dart';
import '../../../university/domain/university_item.dart';
import '../../../workout/domain/workout.dart';
import '../focus_builder.dart';
import '../header_builder.dart';
import '../now_next_builder.dart';
import '../training_builder.dart';
import '../widgets/common.dart';
import '../widgets/diet_glance.dart';
import '../widgets/focus_list.dart';
import '../widgets/now_next_card.dart';
import '../widgets/spending_glance.dart';
import '../widgets/training_card.dart';

/// The Today command centre — the adaptive surface that reads like a
/// sentence about the day, built live from the day's real signals.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -1.1),
          radius: 1.1,
          colors: [Color(0xFFFFFDF8), AppColors.ground, Color(0xFFF0EDE6)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: media.padding.top + 6),
          const _AskHint(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screen,
                AppSpacing.s,
                AppSpacing.screen,
                media.padding.bottom + 150,
              ),
              children: [
                const RiseIn(delay: Duration.zero, child: _Header()),
                const RiseIn(
                  delay: Duration(milliseconds: 90),
                  child: _NowNextSection(),
                ),
                const RiseIn(
                  delay: Duration(milliseconds: 170),
                  child: _FocusSection(),
                ), // live tasks merged with live university items
                const RiseIn(
                  delay: Duration(milliseconds: 250),
                  child: _TrainingSection(),
                ),
                const RiseIn(
                  delay: Duration(milliseconds: 330),
                  child: _SpendingSection(),
                ),
                const RiseIn(
                  delay: Duration(milliseconds: 400),
                  child: _DietSection(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AskHint extends StatelessWidget {
  const _AskHint();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.hairline2,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'PULL TO ASK',
          style: AppText.tabLabel.copyWith(
            color: AppColors.ink3,
            letterSpacing: 1.9,
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(formatTodayDate(now).toUpperCase(), style: AppText.dateLabel),
        const SizedBox(height: 10),
        _GreetingRow(now: now),
        const SizedBox(height: 11),
        _AsideLine(now: now),
      ],
    );
  }
}

class _GreetingRow extends StatelessWidget {
  const _GreetingRow({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final uid = scope.auth.currentUser?.uid;
    return StreamBuilder<UserProfile?>(
      stream: uid == null ? null : scope.profiles.watchProfile(uid),
      builder: (context, snapshot) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                greetingFor(now, snapshot.data?.name),
                style: AppText.greeting,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.wb_sunny_rounded,
              color: AppColors.ember,
              size: 25,
            ),
          ],
        );
      },
    );
  }
}

/// Composes the aside line live from the day's focus list + next event.
class _AsideLine extends StatelessWidget {
  const _AsideLine({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<Task>>(
      stream: scope.tasks.watchAll(),
      initialData: scope.tasks.current,
      builder: (context, taskSnapshot) {
        return StreamBuilder<List<UniversityItem>>(
          stream: scope.university.watchAll(),
          initialData: scope.university.current,
          builder: (context, universitySnapshot) {
            return StreamBuilder<List<ScheduleEvent>>(
              stream: scope.schedule.watchAll(),
              initialData: scope.schedule.current,
              builder: (context, scheduleSnapshot) {
                final focus = buildFocus(
                  tasks: taskSnapshot.data ?? const <Task>[],
                  universityItems:
                      universitySnapshot.data ?? const <UniversityItem>[],
                  now: now,
                );
                final event = nextRelevant(
                  scheduleSnapshot.data ?? const <ScheduleEvent>[],
                  now,
                );
                final next = event == null
                    ? null
                    : nowNextFromEvent(event, now);
                return Text(
                  buildAside(focus: focus, next: next),
                  style: AppText.aside,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _NowNextSection extends StatelessWidget {
  const _NowNextSection();

  @override
  Widget build(BuildContext context) {
    final schedule = AppScope.of(context).schedule;
    return StreamBuilder<List<ScheduleEvent>>(
      stream: schedule.watchAll(),
      initialData: schedule.current,
      builder: (context, snapshot) {
        final now = DateTime.now();
        final event = nextRelevant(
          snapshot.data ?? const <ScheduleEvent>[],
          now,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Now · Next', top: AppSpacing.section - 4),
            if (event == null)
              const _EmptyLine('No events today.')
            else
              NowNextCard(nowNextFromEvent(event, now)),
          ],
        );
      },
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Text(
        text,
        style: AppText.body.copyWith(color: AppColors.ink3, fontSize: 15),
      ),
    );
  }
}

class _FocusSection extends StatelessWidget {
  const _FocusSection();

  @override
  Widget build(BuildContext context) {
    final tasks = AppScope.of(context).tasks;
    final university = AppScope.of(context).university;
    return StreamBuilder<List<Task>>(
      stream: tasks.watchAll(),
      initialData: tasks.current,
      builder: (context, taskSnapshot) {
        return StreamBuilder<List<UniversityItem>>(
          stream: university.watchAll(),
          initialData: university.current,
          builder: (context, universitySnapshot) {
            final items = buildFocus(
              tasks: taskSnapshot.data ?? const <Task>[],
              universityItems:
                  universitySnapshot.data ?? const <UniversityItem>[],
              now: DateTime.now(),
            );
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader('Today'),
                FocusList(
                  items,
                  onToggle: (id, done) => tasks.setDone(id, done),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _TrainingSection extends StatelessWidget {
  const _TrainingSection();

  @override
  Widget build(BuildContext context) {
    final workouts = AppScope.of(context).workouts;
    return StreamBuilder<List<Workout>>(
      stream: workouts.watchAll(),
      initialData: workouts.current,
      builder: (context, snapshot) {
        final workout = todaysWorkout(
          snapshot.data ?? const <Workout>[],
          DateTime.now(),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Training'),
            if (workout == null)
              const _EmptyLine('No training logged yet today.')
            else
              TrainingCard(workout),
          ],
        );
      },
    );
  }
}

class _SpendingSection extends StatelessWidget {
  const _SpendingSection();

  @override
  Widget build(BuildContext context) {
    final expenses = AppScope.of(context).expenses;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Spending'),
        StreamBuilder<List<Expense>>(
          stream: expenses.watchAll(),
          initialData: expenses.current,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <Expense>[];
            final now = DateTime.now();
            return SpendingGlanceRow(
              todayMinor: todayTotalMinor(items, now),
              weekMinor: weekTotalMinor(items, now),
              currency: 'EGP',
            );
          },
        ),
      ],
    );
  }
}

class _DietSection extends StatelessWidget {
  const _DietSection();

  @override
  Widget build(BuildContext context) {
    final diet = AppScope.of(context).diet;
    return StreamBuilder<DietPlan?>(
      stream: diet.watchActivePlan(),
      initialData: diet.activePlan,
      builder: (context, planSnapshot) {
        final plan = planSnapshot.data;
        final now = DateTime.now();
        final day = dayForDate(plan, now);
        if (day == null) return const SizedBox.shrink();
        return StreamBuilder<Set<String>>(
          stream: diet.watchConsumed(now),
          initialData: const <String>{},
          builder: (context, consumedSnapshot) {
            final summary = dietDaySummary(
              day,
              consumedSnapshot.data ?? const <String>{},
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader('Diet'),
                DietGlanceRow(
                  eaten: summary.eaten,
                  total: summary.total,
                  kcalLeft: summary.kcalLeft,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
