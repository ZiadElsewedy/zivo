import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../auth/domain/user_profile.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../diet/domain/diet_plan.dart';
import '../../../diet/domain/diet_summary.dart';
import '../../../diet/presentation/today_diet.dart';
import '../../../expenses/domain/expense.dart';
import '../../../expenses/presentation/pages/expense_capture_page.dart';
import '../../../workout/domain/live_session.dart';
import '../../../workout/domain/up_next_selection.dart';
import '../../../workout/domain/workout_plan.dart';
import '../../../workout/presentation/pages/workout_plan_edit_page.dart';
import '../../../workout/presentation/pages/workout_pdf_import_page.dart';
import '../header_builder.dart';
import '../widgets/common.dart';
import '../widgets/diet_glance.dart';
import '../widgets/today_pulse_card.dart';
import '../../../workout/presentation/widgets/up_next_workout_card.dart';
import '../../../shell/presentation/widgets/zivo_bottom_bar.dart';

/// The Today command centre — the adaptive surface that reads like a
/// sentence about the day, built live from the day's real signals.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key, this.onOpenAsk, this.onQuickLog});

  /// Opens the Ask tab — Today can't switch tabs itself (HomeShell owns the
  /// tab index), so this is how the pull/tap gesture below reaches it.
  final VoidCallback? onOpenAsk;

  /// Opens the voice quick-log sheet; HomeShell transcribes and lands the
  /// text in Ask's composer, switching tabs itself.
  final VoidCallback? onQuickLog;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

/// How far (in logical pixels) the list must be pulled below its top —
/// i.e. how negative [ScrollMetrics.pixels] must go under the app-wide
/// bouncing overscroll (see `ZivoScrollBehavior`, applied on every platform)
/// — before a pull-down is treated as "open Ask" rather than an incidental
/// rubber-band wobble.
const double _kAskPullThreshold = 80;

class _TodayPageState extends State<TodayPage> {
  bool _askTriggered = false;

  bool _handleScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _askTriggered = false;
    } else if (!_askTriggered &&
        notification.metrics.pixels <= -_kAskPullThreshold) {
      _askTriggered = true;
      _openAsk();
    }
    return false;
  }

  void _openAsk() {
    if (widget.onOpenAsk == null) return;
    HapticFeedback.selectionClick();
    widget.onOpenAsk!();
  }

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
              _AskHint(onTap: _openAsk),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScroll,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.screen,
                      AppSpacing.s,
                      AppSpacing.screen,
                      ZivoBottomBarMetrics.height(context) + AppSpacing.base,
                    ),
                    children: [
                      RiseIn(
                        delay: Duration.zero,
                        child: _Header(onQuickLog: widget.onQuickLog),
                      ),
                      // Primary tier — the day at a glance: train / fuel /
                      // move rings answering "what have I done today?"
                      const RiseIn(
                        delay: Duration(milliseconds: 70),
                        child: TodayPulseSection(),
                      ),
                      // The day's training, full-weight card.
                      const RiseIn(
                        delay: Duration(milliseconds: 140),
                        child: _TrainingSection(),
                      ),
                      // Momentum — "how am I doing?" streak, week bars,
                      // weight trend.
                      const RiseIn(
                        delay: Duration(milliseconds: 210),
                        child: MomentumSection(),
                      ),
                      // Worth knowing — computed right-now nudges.
                      const RiseIn(
                        delay: Duration(milliseconds: 280),
                        child: InsightsSection(),
                      ),
                      // Tertiary tier — quiet glances, muted ink tones (no bright hues).
                      const RiseIn(
                        delay: Duration(milliseconds: 350),
                        child: _DietSection(),
                      ),
                    ],
                  ),
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
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // A radial gradient, not an ImageFiltered blur — visually the
          // same soft glow at a fraction of the GPU cost, which matters
          // during page transitions (blur layers repaint per frame).
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.14),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pull-to-ask handle — also the discoverable, tappable fallback for
/// anyone who doesn't try the drag (see [_TodayPageState._handleScroll] for
/// the gesture itself).
class _AskHint extends StatelessWidget {
  const _AskHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.onQuickLog});

  final VoidCallback? onQuickLog;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text(formatTodayDate(now).toUpperCase(), style: AppText.dateLabel)),
            // Voice quick-log — one tap from the command centre to a logged
            // expense/workout via Ask's proposal flow.
            if (onQuickLog != null) _QuickLogButton(onTap: onQuickLog!),
          ],
        ),
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

/// The header's compact mic affordance for the voice quick-log sheet.
class _QuickLogButton extends StatelessWidget {
  const _QuickLogButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        key: const Key('today-quicklog'),
        color: AppColors.card,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.hairline),
        ),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 38,
            height: 38,
            child: Icon(AppIcons.mic, size: 18, color: AppColors.iris),
          ),
        ),
      ),
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
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
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
          style: AppText.heroNumber.copyWith(fontSize: 58, letterSpacing: -1.6),
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
/// so the card falls back to the new next-due day on its own. Falls back to
/// [_EmptySplitCard] when the plan has no days left, and (via
/// [_TrainingEmptyFallback]) to a no-plan card when there's no plan at all.
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
          return const _TrainingEmptyFallback();
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
              // A plan whose days were all removed still resolves here —
              // that's a split to fix, not "nothing logged today".
              return _EmptySplitCard(plan: plan);
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

/// What Training shows when there's no workout plan but the user already has
/// real data elsewhere (a diet plan or a logged expense) — a proper
/// actionable card, not the bare grey line it replaced ("No training logged
/// yet today.", which also misdescribed the state: nothing about it was
/// about *today*, and the actual gap is that no plan exists yet).
///
/// Reactive: as soon as a diet plan or an expense shows up, this collapses
/// back from [_GetStartedCard] on its own (and disappears entirely once a
/// workout plan exists, since the outer [_TrainingUpNext] stops reaching
/// this branch at all).
class _TrainingEmptyFallback extends StatelessWidget {
  const _TrainingEmptyFallback();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<DietPlan?>(
      stream: scope.diet.watchActivePlan(),
      initialData: scope.diet.activePlan,
      builder: (context, dietSnapshot) {
        if (dietSnapshot.data != null) return const _NoPlanTrainingCard();
        return StreamBuilder<List<Expense>>(
          stream: scope.expenses.watchAll(),
          initialData: scope.expenses.current,
          builder: (context, expenseSnapshot) {
            final expenses = expenseSnapshot.data ?? const <Expense>[];
            if (expenses.isNotEmpty) return const _NoPlanTrainingCard();
            return const _GetStartedCard();
          },
        );
      },
    );
  }
}

/// The Training section's own empty-state card: same card surface, gradient
/// icon-chip and pill-CTA language as the rest of Today (and the Workout
/// tab's no-plan state), with both ways forward one tap away.
class _NoPlanTrainingCard extends StatelessWidget {
  const _NoPlanTrainingCard();

  @override
  Widget build(BuildContext context) {
    return RiseIn(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TrainingIconChip(
                  icon: Icons.fitness_center_rounded,
                  color: AppColors.pulse,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No training plan yet',
                    style: AppText.rowTitle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Import your split from a PDF or photo and Zivo turns it into '
              'a real rotating plan — or build one by hand.',
              style: AppText.body.copyWith(
                color: AppColors.ink2,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: PillButton(
                label: 'Import a plan',
                icon: Icons.upload_file_rounded,
                color: AppColors.pulse,
                enabled: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorkoutPdfImportPage(),
                    ),
                  );
                },
              ),
            ),
            Center(
              child: PressableScale(
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const WorkoutPlanEditPage(initialPlan: null),
                      ),
                    );
                  },
                  child: Text(
                    'Build manually instead',
                    style: AppText.meta.copyWith(color: AppColors.ink2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The active split exists but has no days left (every day was deleted) —
/// previously this collapsed into the generic empty line, which read as
/// "nothing logged today" while the actual fix is editing the split.
class _EmptySplitCard extends StatelessWidget {
  const _EmptySplitCard({required this.plan});

  final WorkoutPlan plan;

  @override
  Widget build(BuildContext context) {
    return RiseIn(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TrainingIconChip(
                  icon: Icons.post_add_rounded,
                  color: AppColors.solar,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${plan.name} has no days',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowTitle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Add training days and exercises to this split and it will '
              'show up here, ready to start.',
              style: AppText.body.copyWith(
                color: AppColors.ink2,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: PillButton(
                label: 'Edit split',
                icon: Icons.edit_rounded,
                color: AppColors.solar,
                enabled: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WorkoutPlanEditPage(initialPlan: plan),
                    ),
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

/// The tinted gradient icon chip shared by both Training empty cards — the
/// same visual unit the Workout tab's phase states use, so the flows read
/// as one product.
class _TrainingIconChip extends StatelessWidget {
  const _TrainingIconChip({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.26),
            color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.26),
            blurRadius: 18,
            spreadRadius: -5,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Icon(icon, size: 22, color: color),
    );
  }
}

/// A brand-new signed-in user's first Today: one calm, actionable card
/// instead of a bare empty line — two taps to real data, not a wizard.
class _GetStartedCard extends StatelessWidget {
  const _GetStartedCard();

  @override
  Widget build(BuildContext context) {
    return RiseIn(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Get started',
              style: AppText.rowTitle.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Import a plan or log a spend — Zivo builds Today from there.",
              style: AppText.body.copyWith(color: AppColors.ink2, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _GetStartedAction(
                    icon: Icons.upload_file_rounded,
                    label: 'Import a\nworkout plan',
                    color: AppColors.pulse,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WorkoutPdfImportPage(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _GetStartedAction(
                    icon: Icons.receipt_long_rounded,
                    label: 'Add an\nexpense',
                    color: AppColors.solar,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ExpenseCapturePage(),
                        fullscreenDialog: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GetStartedAction extends StatelessWidget {
  const _GetStartedAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // GestureDetector, not InkWell — Today has no Scaffold of its own (it's
    // embedded in HomeShell's), so an InkWell here would depend on that
    // ambient Material ancestor rather than working standalone.
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadius.chip * 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 8),
              Text(
                label,
                style: AppText.meta.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
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
