import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../../core/util/time_ago.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/body_weight_entry.dart';
import '../../domain/body_weight_repository.dart';
import '../../domain/live_session.dart';
import '../../domain/session_status.dart';
import '../../domain/training_dashboard_stats.dart';
import '../../domain/up_next_selection.dart';
import '../../domain/weight_trend.dart';
import '../../domain/workout_plan.dart';
import '../widgets/animated_stat_value.dart';
import '../widgets/trend_chart.dart';
import '../widgets/up_next_workout_card.dart';
import '../widgets/workout_section_label.dart';
import 'workout_pdf_import_page.dart';
import 'workout_plan_edit_page.dart';
import 'workout_progress_page.dart';

/// The Workout tab's landing page — a real training dashboard, not just a
/// session log. Reads [LiveSession]s directly (the record of what actually
/// happened, when, and for how long — never the lossy flat `Workout` log
/// `WorkoutHistoryPage` shows) to answer: did I train today, what/how
/// consistently am I training, how long do sessions run, and how's my
/// bodyweight moving. Deliberately only three blocks: the training card, this
/// week, and bodyweight. The split breakdown, progress verdict and recent
/// activity — plus the Analysis/History/Splits destinations — live one tap
/// away on [WorkoutProgressPage] via the header's Progress action, so this
/// landing stays calm instead of stacking six similar-looking cards.
///
/// Each block owns a distinct accent hue — sessions pulse-green, streak
/// ember, duration iris, start solar, bodyweight solar — so the grid scans
/// as four different signals instead of four identical boxes.
class WorkoutDashboardPage extends StatelessWidget {
  const WorkoutDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1),
            radius: 1.15,
            colors: [Color(0xFF182016), AppColors.ground, Color(0xFF0E0B08)],
            stops: [0.0, 0.52, 1.0],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -60,
              right: -70,
              child: _AuraBlob(color: AppColors.pulse, size: 210),
            ),
            SafeArea(
              child: StreamBuilder<WorkoutPlan?>(
                stream: scope.workoutPlans.watchActivePlan(),
                initialData: scope.workoutPlans.activePlan,
                builder: (context, planSnap) {
                  if (planSnap.hasError) return const _DashboardErrorState();
                  final plan = planSnap.data;
                  final loading =
                      plan == null &&
                      planSnap.connectionState == ConnectionState.waiting;
                  if (loading) return const _DashboardLoadingState();
                  if (plan == null) return const _NoPlanState();

                  return StreamBuilder<List<LiveSession>>(
                    stream: scope.workoutSessions.watchAll(),
                    initialData: scope.workoutSessions.current,
                    builder: (context, sessionsSnap) {
                      if (sessionsSnap.hasError) {
                        return const _DashboardErrorState();
                      }
                      final sessions =
                          sessionsSnap.data ?? const <LiveSession>[];
                      final now = DateTime.now();
                      final stats = computeTrainingDashboardStats(
                        sessions: sessions,
                        now: now,
                      );
                      final selection = resolveUpNext(
                        plan,
                        _firstActive(sessions),
                      );

                      final bodyWeight = scope.bodyWeight;
                      return StreamBuilder<List<BodyWeightEntry>>(
                        stream: bodyWeight?.watchAll() ?? const Stream.empty(),
                        initialData:
                            bodyWeight?.current ?? const <BodyWeightEntry>[],
                        builder: (context, weightSnap) {
                          final weightTrend = computeWeightTrend(
                            entries: weightSnap.data ?? const <BodyWeightEntry>[],
                            now: now,
                          );
                          // Deliberately just three blocks — the training card,
                          // this week, and bodyweight. Split/progress/recent-
                          // activity depth lives on `WorkoutProgressPage` (the
                          // header's Progress action) so this landing stays
                          // calm and scannable.
                          return ListView(
                            // This page is pushed (its own header, no bottom
                            // nav), so the bottom padding only needs to clear
                            // the home indicator plus a small margin — not the
                            // ~110 nav-bar clearance a tab page would reserve,
                            // which here left a large dead band of blank space
                            // under the last card.
                            padding: EdgeInsets.fromLTRB(
                              22,
                              12,
                              22,
                              MediaQuery.of(context).padding.bottom + 24,
                            ),
                            // Each block staggers in as its own step (see
                            // RiseIn) rather than the page popping in all at
                            // once — the spacers between them are left
                            // unwrapped so the layout rhythm doesn't shift.
                            children: [
                              RiseIn(
                                child: _DashboardHeader(
                                  onOpenProgress: () {
                                    HapticFeedback.selectionClick();
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const WorkoutProgressPage(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (selection.day != null) ...[
                                RiseIn(
                                  delay: const Duration(milliseconds: 40),
                                  child: UpNextWorkoutCard(
                                    plan: plan,
                                    day: selection.day!,
                                    resumable: selection.resumable,
                                  ),
                                ),
                                const SizedBox(height: 30),
                              ],
                              RiseIn(
                                delay: const Duration(milliseconds: 80),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const WorkoutSectionLabel('This week'),
                                    const SizedBox(height: 10),
                                    _StatsGrid(stats: stats),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 30),
                              RiseIn(
                                delay: const Duration(milliseconds: 120),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const WorkoutSectionLabel('Bodyweight'),
                                    const SizedBox(height: 10),
                                    _WeightCard(
                                      trend: weightTrend,
                                      bodyWeight: bodyWeight,
                                      onLogWeight: bodyWeight == null
                                          ? null
                                          : () => _showLogWeightSheet(
                                              context, bodyWeight),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
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

/// A soft, blurred wash of color floating behind the content — the quiet
/// "energy" glow shared across the app's surfaces. Purely decorative.
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
            color: color.withValues(alpha: 0.14),
          ),
        ),
      ),
    );
  }
}

/// The pushed-page header — back chip, display title, and the Progress action
/// that leads to [WorkoutProgressPage] (the tooltip is the action's
/// accessible name, asserted by tests).
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.onOpenProgress});

  final VoidCallback onOpenProgress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PressableScale(
          child: Tooltip(
            message: 'Back',
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              customBorder: const CircleBorder(),
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.hairline2),
                ),
                child: const Icon(
                  AppIcons.back,
                  size: 18,
                  color: AppColors.ink2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text('Workout', style: AppText.greeting.copyWith(fontSize: 30))),
        const SizedBox(width: 12),
        PressableScale(
          child: Tooltip(
            message: 'Progress',
            child: InkWell(
              onTap: onOpenProgress,
              customBorder: const CircleBorder(),
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.pulse.withValues(alpha: 0.30),
                      AppColors.pulse.withValues(alpha: 0.10),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.pulse.withValues(alpha: 0.20)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.pulse.withValues(alpha: 0.25),
                      blurRadius: 18,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(AppIcons.analysis, size: 18, color: AppColors.pulse),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

LiveSession? _firstActive(List<LiveSession> sessions) {
  for (final s in sessions) {
    if (s.status == SessionStatus.active) return s;
  }
  return null;
}

/// The log-weight sheet — a big, glanceable readout you can nudge with ±0.1
/// steppers or type into directly, pre-filled with the last weigh-in so
/// "same as yesterday, confirm it" is the zero-effort path. Saving is a
/// pulse-gradient action matching the card that launched it.
Future<void> _showLogWeightSheet(
  BuildContext context,
  BodyWeightRepository bodyWeight, {
  double? lastWeight,
}) {
  final controller = TextEditingController(
    text: lastWeight == null ? '' : _trimNumber(lastWeight),
  );
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          20,
          22,
          MediaQuery.of(sheetContext).viewInsets.bottom + 22,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Log today's weight", style: AppText.cardTitle.copyWith(color: AppColors.ink)),
            const SizedBox(height: 18),
            Row(
              children: [
                _WeightStepper(
                  icon: AppIcons.minus,
                  onTap: () {
                    final v = double.tryParse(controller.text) ?? lastWeight ?? 0;
                    if (v <= 0.1) return;
                    controller.text = _trimNumber(v - 0.1);
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}$')),
                    ],
                    style: AppText.heroNumber.copyWith(fontSize: 40, color: AppColors.ink),
                    cursorColor: AppColors.pulse,
                    decoration: InputDecoration(
                      suffixText: 'kg',
                      suffixStyle: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 16),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                _WeightStepper(
                  icon: AppIcons.add,
                  onTap: () {
                    final v = double.tryParse(controller.text) ?? lastWeight ?? 0;
                    controller.text = _trimNumber(v + 0.1);
                  },
                ),
              ],
            ),
            if (lastWeight != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Center(
                  child: Text(
                    'Last weigh-in: ${_trimNumber(lastWeight)} kg',
                    style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            PillButton(
              label: 'Save',
              icon: Icons.check_rounded,
              color: AppColors.pulse,
              enabled: true,
              onTap: () {
                final value = double.tryParse(controller.text);
                if (value == null || value <= 0) return;
                HapticFeedback.lightImpact();
                bodyWeight.save(
                  BodyWeightEntry(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    weightKg: value,
                    loggedAt: DateTime.now(),
                  ),
                );
                Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      );
    },
  );
}

/// A round ±0.1 nudge button flanking the weight readout — the fast path for
/// "basically the same as last time".
class _WeightStepper extends StatelessWidget {
  const _WeightStepper({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        customBorder: const CircleBorder(),
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Icon(icon, size: 20, color: AppColors.ink2),
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final TrainingDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: AppIcons.sessions,
                accent: AppColors.pulse,
                label: 'Sessions',
                value: '${stats.sessionsThisWeek}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: AppIcons.streak,
                accent: AppColors.ember,
                label: 'Day streak',
                value: '${stats.currentStreakDays}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: AppIcons.timer,
                accent: AppColors.iris,
                label: 'Avg duration',
                value: stats.averageSessionDuration == null
                    ? '—'
                    : formatDurationShort(stats.averageSessionDuration!),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                icon: AppIcons.calendarClock,
                accent: AppColors.solar,
                label: 'Avg start',
                value: stats.averageStartMinutesSinceMidnight == null
                    ? '—'
                    : formatClockTime(stats.averageStartMinutesSinceMidnight!),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One stat tile — a glowing gradient icon chip in the stat's own hue above
/// the animated value, so each tile reads as a different signal at a glance.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.28),
                  accent.withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 16,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(height: 12),
          AnimatedStatValue(
            value: value,
            style: AppText.heroNumber.copyWith(fontSize: 24, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppText.meta.copyWith(color: AppColors.ink3)),
        ],
      ),
    );
  }
}

class _WeightCard extends StatelessWidget {
  const _WeightCard({
    required this.trend,
    required this.bodyWeight,
    required this.onLogWeight,
  });

  final WeightTrend trend;

  /// Null when the build has no bodyweight repository — the card then hides
  /// its quick-edit chip (the main Log button already disables itself).
  final BodyWeightRepository? bodyWeight;
  final VoidCallback? onLogWeight;

  @override
  Widget build(BuildContext context) {
    final latest = trend.latest;
    final change = trend.changeKgOverWindow;
    final repo = bodyWeight;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedStatValue(
                value: latest == null ? '—' : '${_trimNumber(latest.weightKg)} kg',
                style: AppText.heroNumber.copyWith(fontSize: 28, color: AppColors.ink),
              ),
              if (change != null) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  // Color here is semantic (gaining vs. losing) — an implicit
                  // tween is fine per the motion guardrails, folded into the
                  // same fade+slide via AnimatedSwitcher rather than a bare
                  // color snap.
                  child: AnimatedStatValue(
                    value: '${change > 0 ? '+' : ''}${_trimNumber(change)}kg / 30d',
                    style: AppText.meta.copyWith(
                      color: change > 0 ? AppColors.flare : AppColors.pulse,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (latest != null && repo != null)
                PressableScale(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _showLogWeightSheet(
                        context,
                        repo,
                        lastWeight: latest.weightKg,
                      );
                    },
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.hairline2),
                      ),
                      child: const Icon(AppIcons.edit, size: 14, color: AppColors.ink3),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            latest == null
                ? 'No weigh-ins logged yet.'
                : 'Last logged ${timeAgo(latest.loggedAt, DateTime.now())} ago',
            style: AppText.meta.copyWith(color: AppColors.ink3),
          ),
          if (trend.series.length >= 2) ...[
            const SizedBox(height: 14),
            TrendChart(values: [for (final e in trend.series) e.weightKg], color: AppColors.solar),
          ],
          const SizedBox(height: 14),
          PillButton(
            label: 'Log weight',
            icon: Icons.add_rounded,
            color: AppColors.solar,
            enabled: onLogWeight != null,
            onTap: onLogWeight ?? () {},
          ),
        ],
      ),
    );
  }
}

class _DashboardLoadingState extends StatelessWidget {
  const _DashboardLoadingState();

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

class _DashboardErrorState extends StatelessWidget {
  const _DashboardErrorState();

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

class _NoPlanState extends StatelessWidget {
  const _NoPlanState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PhaseIconLike(icon: AppIcons.workout, color: AppColors.pulse),
            const SizedBox(height: 18),
            Text(
              'No workout plan yet',
              style: AppText.cardTitle.copyWith(color: AppColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Import a PDF and I'll turn it into a real split, or build one from scratch.",
              style: AppText.body.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 220,
              child: PillButton(
                label: 'Import from PDF',
                icon: Icons.upload_file_rounded,
                color: AppColors.pulse,
                enabled: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WorkoutPdfImportPage()),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            PressableScale(
              child: TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorkoutPlanEditPage(initialPlan: null),
                    ),
                  );
                },
                child: Text('Build manually instead', style: AppText.meta.copyWith(color: AppColors.ink2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The same tinted icon-chip language `workout_pdf_import_page.dart` uses for
/// its own phase states — reused here so the empty state that leads INTO
/// that flow already looks like part of the same product.
class _PhaseIconLike extends StatelessWidget {
  const _PhaseIconLike({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.26), color.withValues(alpha: 0.08)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 24,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(icon, size: 28, color: color),
    );
  }
}

/// "52m" under an hour, "1h 12m" past one.
String formatDurationShort(Duration d) {
  final totalMinutes = d.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

/// "82.5" — one decimal only when there is one.
String _trimNumber(double v) =>
    v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Minutes-since-midnight to a 12-hour clock label, e.g. 390 -> "6:30 AM".
String formatClockTime(double minutesSinceMidnight) {
  final total = minutesSinceMidnight.round() % (24 * 60);
  final h24 = total ~/ 60;
  final minute = total % 60;
  final period = h24 < 12 ? 'AM' : 'PM';
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${minute.toString().padLeft(2, '0')} $period';
}
