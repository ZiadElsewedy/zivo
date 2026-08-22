import 'dart:ui';

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
import '../../../expenses/domain/wallet.dart';
import '../../../schedule/domain/schedule_event.dart';
import '../../../schedule/domain/schedule_repository.dart';
import '../../../tasks/domain/task.dart';
import '../../../university/domain/university_item.dart';
import '../../../workout/domain/live_session.dart';
import '../../../workout/domain/up_next_selection.dart';
import '../../../workout/domain/workout_plan.dart';
import '../focus_builder.dart';
import '../header_builder.dart';
import '../now_next_builder.dart';
import '../widgets/common.dart';
import '../widgets/day_progress_ring.dart';
import '../widgets/diet_glance.dart';
import '../widgets/focus_list.dart';
import '../widgets/now_next_card.dart';
import '../widgets/spending_glance.dart';
import '../../../workout/presentation/widgets/up_next_workout_card.dart';
import '../../../shell/presentation/widgets/zivo_bottom_bar.dart';

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
          colors: [Color(0xFF241C15), AppColors.ground, Color(0xFF0E0B08)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -40,
            right: -60,
            child: _AuraBlob(color: AppColors.ember, size: 220),
          ),
          const Positioned(
            top: 160,
            left: -80,
            child: _AuraBlob(color: AppColors.iris, size: 200),
          ),
          Column(
            children: [
              SizedBox(height: media.padding.top + 6),
              const _AskHint(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    AppSpacing.s,
                    AppSpacing.screen,
                    ZivoBottomBarMetrics.height(context) + AppSpacing.base,
                  ),
                  children: [
                    const RiseIn(delay: Duration.zero, child: _Header()),
                    // Primary tier — the two time-relevant things, full-weight cards.
                    const RiseIn(
                      delay: Duration(milliseconds: 90),
                      child: _NowNextSection(),
                    ),
                    const RiseIn(
                      delay: Duration(milliseconds: 170),
                      child: _TrainingSection(),
                    ),
                    // Secondary tier — today's tasks, neutral rows.
                    const RiseIn(
                      delay: Duration(milliseconds: 250),
                      child: _FocusSection(),
                    ), // live tasks merged with live university items
                    // Tertiary tier — quiet glances, muted ink tones (no bright hues).
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
        ],
      ),
    );
  }
}

/// A soft, blurred wash of color for atmosphere behind the header — the
/// quiet "energy" glow behind a premium dashboard. Purely decorative.
class _AuraBlob extends StatelessWidget {
  const _AuraBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.16),
          ),
        ),
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
            const SizedBox(width: 10),
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x33FF5A1F), Color(0x00FF5A1F)],
                ),
              ),
              child: const Icon(
                Icons.wb_sunny_rounded,
                color: AppColors.ember,
                size: 25,
              ),
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
                final asideText = Text(
                  buildAside(focus: focus, next: next),
                  style: AppText.aside,
                );
                if (focus.isEmpty) return asideText;
                final done = focus.where((f) => f.done).length;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    DayProgressRing(progress: done / focus.length),
                    const SizedBox(width: 14),
                    Expanded(child: asideText),
                  ],
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
              const _EmptyLine(
                'No events today.',
                icon: Icons.event_available_rounded,
              )
            else
              NowNextCard(nowNextFromEvent(event, now)),
          ],
        );
      },
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text, {this.icon = Icons.spa_rounded});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.ink3),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: AppText.body.copyWith(
                color: AppColors.ink3,
                fontSize: 14.5,
              ),
            ),
          ),
        ],
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
            // Secondary tier: silently hides when empty, unlike Now·Next and
            // Training (primary tier, which may show a gentle empty state).
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

/// Always shows the active plan's up-next day, resolved by the SAME
/// `resolveUpNext` (see `up_next_selection.dart`) the Workout tab's own page
/// reads, so the two surfaces can't drift apart. Deliberately does NOT branch
/// on whatever's been logged today (`todaysWorkout`) — that used to show a
/// second, different card once anything was logged, which put Home and the
/// Workout page out of sync (owner-reported, root-caused, fixed). The full
/// history of what was actually done stays reachable via Workout History.
class _TrainingSection extends StatelessWidget {
  const _TrainingSection();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Training'),
        _TrainingUpNext(scope: scope),
      ],
    );
  }
}

/// The active plan's training card, driven by the live-session repository as
/// the single source of truth for whether a workout is under way. When a
/// session is active for the plan the card mirrors *its* day with a Resume CTA
/// — whichever day it is, and through pause/resume, since a pause keeps the
/// session `active` (see [LiveSession.isPaused]). With nothing running it
/// offers the next-due day with a Start CTA. Finishing a workout advances the
/// plan cursor and clears the active session (see `live_session_page.dart`),
/// so the card falls back to the new next-due day on its own. Falls back to a
/// plain empty line only when there's genuinely no plan/day to offer.
class _TrainingUpNext extends StatelessWidget {
  const _TrainingUpNext({required this.scope});

  final AppScope scope;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WorkoutPlan?>(
      stream: scope.workoutPlans.watchActivePlan(),
      initialData: scope.workoutPlans.activePlan,
      builder: (context, planSnapshot) {
        final plan = planSnapshot.data;
        if (plan == null) {
          return const _EmptyLine(
            'No training logged yet today.',
            icon: Icons.fitness_center_rounded,
          );
        }
        // Nested under the plan so the session stream — the source of truth for
        // a running workout — drives the card. Kept inside (not merged with the
        // plan stream) so a session save re-renders the card without waiting on
        // a plan emission.
        return StreamBuilder<LiveSession?>(
          stream: scope.workoutSessions.watchActiveSession(),
          initialData: scope.workoutSessions.activeSession,
          builder: (context, sessionSnapshot) {
            // Shared with the Workout tab's own "up next" card (see
            // `up_next_selection.dart`) so the two surfaces can't drift apart.
            final selection = resolveUpNext(plan, sessionSnapshot.data);
            final day = selection.day;
            if (day == null) {
              return const _EmptyLine(
                'No training logged yet today.',
                icon: Icons.fitness_center_rounded,
              );
            }
            return UpNextWorkoutCard(
              plan: plan,
              day: day,
              resumable: selection.resumable,
            );
          },
        );
      },
    );
  }
}

class _SpendingSection extends StatelessWidget {
  const _SpendingSection();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final expenses = scope.expenses;
    final wallet = scope.wallet;
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
            final todayMinor = todayTotalMinor(items, now);
            final weekMinor = weekTotalMinor(items, now);
            if (wallet == null) {
              return SpendingGlanceRow(
                todayMinor: todayMinor,
                weekMinor: weekMinor,
                currency: 'EGP',
              );
            }
            return StreamBuilder<Wallet?>(
              stream: wallet.watch(),
              initialData: wallet.current,
              builder: (context, walletSnapshot) {
                return SpendingGlanceRow(
                  todayMinor: todayMinor,
                  weekMinor: weekMinor,
                  currency: walletSnapshot.data?.currency ?? 'EGP',
                  walletMinor: walletSnapshot.data?.balanceMinor,
                );
              },
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
        // Tertiary tier: silently hides when empty, same rule as Focus above.
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
