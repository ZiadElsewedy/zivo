import 'dart:async';
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
import '../../../workout/domain/live_session.dart';
import '../../../workout/domain/up_next_selection.dart';
import '../../../workout/domain/workout_plan.dart';
import '../header_builder.dart';
import '../widgets/common.dart';
import '../widgets/diet_glance.dart';
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
                    // Primary tier — the day's training, full-weight card.
                    const RiseIn(
                      delay: Duration(milliseconds: 90),
                      child: _TrainingSection(),
                    ),
                    // Tertiary tier — quiet glances, muted ink tones (no bright hues).
                    const RiseIn(
                      delay: Duration(milliseconds: 170),
                      child: _SpendingSection(),
                    ),
                    const RiseIn(
                      delay: Duration(milliseconds: 250),
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
        const SizedBox(height: 6),
        // The live clock is the header's anchor — the biggest thing on the
        // screen, so a glance answers "what time is it" before anything else.
        const _LiveTime(),
        const SizedBox(height: 10),
        _GreetingRow(now: now),
      ],
    );
  }
}

/// A live wall clock (`H:MM` + AM/PM), the Today header's visual anchor.
///
/// Ticks on each minute boundary rather than every second — a calm, premium
/// cadence that still stays exactly accurate (the first timer is aligned to
/// the next whole minute, then it repeats every minute). Tabular figures
/// (inherited from [AppText.heroNumber]) keep the digits from shifting width
/// as the time changes, so the clock never jitters.
class _LiveTime extends StatefulWidget {
  const _LiveTime();

  @override
  State<_LiveTime> createState() => _LiveTimeState();
}

class _LiveTimeState extends State<_LiveTime> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final nextMinute =
        DateTime(now.year, now.month, now.day, now.hour, now.minute)
            .add(const Duration(minutes: 1));
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour;
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final minute = _now.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$h12:$minute',
          style: AppText.heroNumber.copyWith(
            fontSize: 58,
            letterSpacing: -1.6,
          ),
        ),
        const SizedBox(width: 9),
        Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Text(
            period,
            style: AppText.meta.copyWith(
              fontSize: 17,
              color: AppColors.ink3,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _TimeOfDayOrb(now: _now),
        ),
      ],
    );
  }
}

/// The soft glowing orb beside the clock — sun by day, twilight at dusk, moon
/// at night — so the header carries the feel of the actual hour, not a fixed
/// icon. Purely atmospheric.
class _TimeOfDayOrb extends StatelessWidget {
  const _TimeOfDayOrb({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final h = now.hour;
    final IconData icon;
    final Color color;
    if (h >= 6 && h < 18) {
      icon = Icons.wb_sunny_rounded;
      color = AppColors.ember;
    } else if (h >= 18 && h < 22) {
      icon = Icons.wb_twilight_rounded;
      color = AppColors.solar;
    } else {
      icon = Icons.nightlight_round;
      color = AppColors.iris;
    }
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0)],
        ),
      ),
      child: Icon(icon, color: color, size: 26),
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
        return Text(
          greetingFor(now, snapshot.data?.name),
          style: AppText.greeting,
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
