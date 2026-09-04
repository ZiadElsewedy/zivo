import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../../core/util/time_ago.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/util/parse.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../domain/body_weight_entry.dart';
import '../../domain/body_weight_repository.dart';
import '../../domain/live_session.dart';
import '../../domain/session_status.dart';
import '../../domain/training_dashboard_stats.dart';
import '../../domain/up_next_selection.dart';
import '../../domain/weight_trend.dart';
import '../../domain/workout_plan.dart';
import '../widgets/up_next_workout_card.dart';
import 'bodyweight_history_page.dart';
import '../widgets/add_workout_sheet.dart';
import 'workout_plan_edit_page.dart';
import 'workout_progress_page.dart';
import 'workout_stats_pages.dart';
import '../../../../l10n/l10n.dart';
import 'package:intl/intl.dart';

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
/// Dressed to the design handoff's **Workout hub** screen (2c): the green
/// screen wash, a 36px back circle beside the Manrope 800/27 title, the
/// session slab, a 2×2 grid of stat tiles that each carry the SHAPE of their
/// own metric where a chevron used to sit, and the bodyweight card with its
/// hero reading, ghost log action and green area chart.
///
/// Each block still owns a distinct accent — sessions green, streak ember,
/// duration violet, start amber… — but within the handoff's palette rules:
/// one 13%-tint icon tile per hue, ember reserved for the single committing
/// action (Start Workout, inside the session card).
///
/// One deliberate departure from the prototype's sample data: it shows
/// Sessions as `3 / 4` (this week), while this tile keeps the ALL-TIME
/// completed count, because that is what the page it opens headlines — the
/// two disagreeing is the exact "17 completed workouts but 2 sessions" bug
/// this tile was fixed for. The week's count keeps its place as the section's
/// own trailing caption instead, so no information is lost.
class WorkoutDashboardPage extends StatelessWidget {
  const WorkoutDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    // One soft radial glow per screen, tinted toward that screen's meaning
    // (identity §2) — the hub's is the training green.
    return TrainScreen(
      tint: TrainColors.hubTint,
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
              final sessions = sessionsSnap.data ?? const <LiveSession>[];
              final now = DateTime.now();
              final stats = computeTrainingDashboardStats(
                sessions: sessions,
                now: now,
              );
              final selection = resolveUpNext(plan, _firstActive(sessions));

              final bodyWeight = scope.bodyWeight;
              return StreamBuilder<List<BodyWeightEntry>>(
                stream: bodyWeight?.watchAll() ?? const Stream.empty(),
                initialData: bodyWeight?.current ?? const <BodyWeightEntry>[],
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
                      TrainBottomInset.of(context),
                    ),
                    // Each block staggers in as its own step (see
                    // RiseIn) rather than the page popping in all at
                    // once — the spacers between them are left
                    // unwrapped so the layout rhythm doesn't shift.
                    children: [
                      RiseIn(
                        child: TrainPageHeader(
                          title: l(context).workoutTitle,
                          action: TrainHeaderAction(
                            icon: AppIcons.analysis,
                            semanticLabel: l(context).workoutProgress,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const WorkoutProgressPage(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
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
                            // "TRAINING", not "THIS WEEK" — the grid
                            // mixes all-time instruments (sessions,
                            // avg duration, avg start) with the
                            // rolling streak, so a week-scoped header
                            // mislabeled every number beneath it. The
                            // week's own count rides the trailing
                            // caption instead, where it scopes only
                            // itself.
                            TrainSectionLabel(
                              l(context).workoutTraining,
                              trailing: '${stats.sessionsThisWeek} THIS WEEK',
                            ),
                            const SizedBox(height: 11),
                            _StatsGrid(stats: stats, sessions: sessions),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      RiseIn(
                        delay: const Duration(milliseconds: 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TrainSectionLabel(
                              l(context).workoutBodyweight,
                              trailing: _weightDeltaCaption(weightTrend),
                              trailingColor: _weightDeltaColor(weightTrend),
                            ),
                            const SizedBox(height: 11),
                            _WeightCard(
                              trend: weightTrend,
                              bodyWeight: bodyWeight,
                              onLogWeight: bodyWeight == null
                                  ? null
                                  : () => _showLogWeightSheet(
                                      context,
                                      bodyWeight,
                                    ),
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
  return showZivoSheet<void>(
    context: context,
    builder: (sheetContext) {
      return ZivoSheetSurface(
        child: Padding(
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
              Text(
                "Log today's weight",
                style: AppText.cardTitle.copyWith(color: TrainColors.ink),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _WeightStepper(
                    icon: AppIcons.minus,
                    onTap: () {
                      final v =
                          parseDecimal(controller.text) ?? lastWeight ?? 0;
                      if (v <= 0.1) return;
                      controller.text = _trimNumber(v - 0.1);
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,1}$'),
                        ),
                      ],
                      style: AppText.heroNumber.copyWith(
                        fontSize: 40,
                        color: TrainColors.ink,
                      ),
                      cursorColor: TrainColors.green,
                      decoration: InputDecoration(
                        suffixText: 'kg',
                        suffixStyle: AppText.meta.copyWith(
                          color: TrainColors.ink3,
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  _WeightStepper(
                    icon: AppIcons.add,
                    onTap: () {
                      final v =
                          parseDecimal(controller.text) ?? lastWeight ?? 0;
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
                      l(context).weighInLast(_trimNumber(lastWeight)),
                      style: AppText.meta.copyWith(
                        color: TrainColors.ink3,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              PillButton(
                label: l(context).actionSave,
                icon: Icons.check_rounded,
                color: TrainColors.green,
                enabled: true,
                onTap: () {
                  final value = parsePositiveDecimal(controller.text);
                  if (value == null) return;
                  HapticFeedback.lightImpact();
                  final entry = BodyWeightEntry(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    weightKg: value,
                    loggedAt: DateTime.now(),
                  );
                  Navigator.of(sheetContext).pop();
                  // Fire-and-forget like every other write in the app —
                  // Firestore commits cache-first, so awaiting would hang the
                  // button offline (see live_session_page's _onFinish note) —
                  // but never SILENTLY: a rejected save (rules, signed-out)
                  // used to vanish without a trace, reading as "weight doesn't
                  // save". Surface it on the page beneath the sheet.
                  // Future.sync also catches save()'s synchronous signed-out
                  // StateError, which a bare catchError would miss.
                  unawaited(
                    Future.sync(() => bodyWeight.save(entry)).catchError((
                      Object error,
                    ) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: TrainColors.raised,
                          content: Text(
                            "Couldn't save that weigh-in — check your "
                            'connection and try again.',
                            style: AppText.body.copyWith(
                              color: TrainColors.ink,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ],
          ),
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
            color: TrainColors.raisedStrong,
            shape: BoxShape.circle,
            border: Border.all(color: TrainColors.hairlineStrong),
          ),
          child: Icon(icon, size: 20, color: TrainColors.ink2),
        ),
      ),
    );
  }
}

/// The 2×2 grid of training instruments. Every tile is a doorway, not a dead
/// end — each metric opens the per-session history that produced it — and
/// each carries the shape of its own metric where the old chevron sat.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats, required this.sessions});

  final TrainingDashboardStats stats;

  /// The raw sessions behind [stats] — the tile sparklines derive their own
  /// series from these rather than widening the stats record with four more
  /// chart-shaped fields.
  final List<LiveSession> sessions;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekly = weeklySessionCounts(sessions: sessions, now: now);
    final daily = dailySessionCounts(sessions: sessions, now: now);
    final durations = recentSessionDurationMinutes(sessions: sessions);

    return Column(
      children: [
        IntrinsicHeight(
          // `stretch` needs a bounded height to stretch to; inside a ListView
          // there isn't one. IntrinsicHeight measures the taller tile first so
          // the pair matches, instead of one sitting short beside the other.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TrainStatTile(
                  icon: AppIcons.sessions,
                  accent: TrainColors.green,
                  // ALL-TIME completed count, matching the page this tile
                  // opens — it used to show sessionsThisWeek here while
                  // WorkoutSessionsPage headlined the all-time total, so the
                  // tile said one number and its destination another (the
                  // "17 completed workouts but 2 sessions" report).
                  value: '${stats.totalCompletedSessions}',
                  unit: l(context).statTotal,
                  label: l(context).statSessions,
                  chart: weekly.any((v) => v > 0)
                      ? TrainSparkline(
                          values: weekly,
                          color: TrainColors.green.withValues(alpha: 0.5),
                        )
                      : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorkoutSessionsPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TrainStatTile(
                  icon: AppIcons.streak,
                  accent: TrainColors.green,
                  value: '${stats.currentStreakDays}',
                  unit: l(context).statDays,
                  label: l(context).statStreak,
                  // A count of days reads as discrete bars, never a line.
                  chart: daily.any((v) => v > 0)
                      ? TrainBarCluster(values: daily, color: TrainColors.ember)
                      : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorkoutStreakPage(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          // `stretch` needs a bounded height to stretch to; inside a ListView
          // there isn't one. IntrinsicHeight measures the taller tile first so
          // the pair matches, instead of one sitting short beside the other.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TrainStatTile(
                  icon: AppIcons.timer,
                  accent: TrainColors.green,
                  value: stats.averageSessionDuration == null
                      ? '—'
                      : '${stats.averageSessionDuration!.inMinutes}',
                  unit: stats.averageSessionDuration == null
                      ? null
                      : l(context).statMinAvg,
                  label: l(context).statDuration,
                  chart: durations.length >= 2
                      ? TrainSparkline(
                          values: durations,
                          color: TrainColors.violetGlyph.withValues(alpha: 0.5),
                          width: 60,
                        )
                      : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorkoutDurationStatsPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TrainStatTile(
                  icon: AppIcons.calendarClock,
                  accent: TrainColors.green,
                  value: stats.averageStartMinutesSinceMidnight == null
                      ? '—'
                      : _clock24(stats.averageStartMinutesSinceMidnight!),
                  label: l(context).statUsualStart,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorkoutStartTimesPage(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bodyweight block: the reading as the section's hero (mono 300/38 with
/// a smaller, dimmer `KG` beside it), a ghost `Log weigh-in` opposite it, then
/// the trend as a green area chart with a dot on the latest reading and the
/// window's own endpoints captioned beneath.
///
/// The whole card is a doorway to the full weigh-in history; the ghost pill
/// keeps its own tap (nested buttons win the gesture arena).
class _WeightCard extends StatelessWidget {
  const _WeightCard({
    required this.trend,
    required this.bodyWeight,
    required this.onLogWeight,
  });

  final WeightTrend trend;

  /// Null when the build has no bodyweight repository — the card then shows
  /// its log action disarmed.
  final BodyWeightRepository? bodyWeight;
  final VoidCallback? onLogWeight;

  @override
  Widget build(BuildContext context) {
    final latest = trend.latest;
    final series = [for (final e in trend.series) e.weightKg];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BodyweightHistoryPage()),
        );
      },
      child: TrainCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: latest == null
                      // Nothing logged: a 38px em dash reads as a rule drawn
                      // across the card, so the slot says what's missing
                      // instead of miming a reading.
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            l(context).weighInNone,
                            style: TrainType.mono(
                              size: 11,
                              weight: FontWeight.w500,
                              tracking: 0.14,
                              color: const Color(0x59F4F4F0),
                            ),
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                _trimNumber(latest.weightKg),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TrainType.mono(
                                  size: 38,
                                  weight: FontWeight.w300,
                                  tracking: -0.05,
                                  color: const Color(0xFFF9F9F5),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // The unit is always smaller and dimmer than the
                            // value it belongs to (identity §1.2).
                            Text(
                              'KG',
                              style: TrainType.mono(
                                size: 11,
                                weight: FontWeight.w500,
                                tracking: 0.14,
                                color: const Color(0x59F4F4F0),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 10),
                _LogWeighInPill(
                  enabled: onLogWeight != null,
                  onTap: onLogWeight ?? () {},
                ),
              ],
            ),
            if (series.length >= 2) ...[
              const SizedBox(height: 14),
              TrainAreaChart(values: series, color: TrainColors.green),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _shortDate(
                      trend.series.first.loggedAt,
                      Localizations.localeOf(context).toLanguageTag(),
                    ),
                    style: TrainType.caption(
                      size: 8,
                      tracking: 0.14,
                      color: const Color(0x47F4F4F0),
                    ),
                  ),
                  Text(
                    l(context).commonToday,
                    style: TrainType.caption(
                      size: 8,
                      tracking: 0.14,
                      color: const Color(0x47F4F4F0),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              // No chart to draw yet — the slot carries the reason instead of
              // an empty frame (identity §7).
              Text(
                latest == null
                    ? l(context).weighInStartTrend
                    : l(context).weighInOneMore(
                        timeAgo(latest.loggedAt, DateTime.now()),
                      ),
                style: TrainType.ui(
                  size: 12.5,
                  weight: FontWeight.w400,
                  color: TrainColors.ink4,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The bodyweight card's secondary action — a ghost pill, never ember: on a
/// screen whose one committing action is Start Workout, logging a weigh-in
/// doesn't get to compete for it (identity §3).
class _LogWeighInPill extends StatelessWidget {
  const _LogWeighInPill({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: PressableScale(
        enabled: enabled,
        scale: 0.97,
        child: Material(
          color: TrainColors.glassStrong,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onTap();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                l(context).weighInLog,
                style: TrainType.ui(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: const Color(0xBFF4F4F0),
                  height: 1,
                ),
              ),
            ),
          ),
        ),
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
        decoration: const BoxDecoration(
          color: TrainColors.raisedStrong,
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
            const Icon(
              Icons.cloud_off_rounded,
              size: 30,
              color: TrainColors.ink3,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load this.",
              style: AppText.aside.copyWith(color: TrainColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              l(context).errorCheckConnection,
              style: AppText.meta.copyWith(color: TrainColors.ink3),
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
            const _PhaseIconLike(
              icon: AppIcons.workout,
              color: TrainColors.green,
            ),
            const SizedBox(height: 18),
            Text(
              l(context).workoutNoPlanYet,
              style: AppText.cardTitle.copyWith(color: TrainColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Import a PDF or photo and I'll turn it into a real split, or build one from scratch.",
              style: AppText.body.copyWith(color: TrainColors.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 220,
              // Ember, not green: with no plan yet this IS the screen's one
              // committing action, and the hub's ember slot (Start Workout)
              // is empty until there's a split to start (identity §3).
              child: PillButton(
                label: l(context).todayImportPlan,
                icon: Icons.upload_file_rounded,
                color: TrainColors.ember,
                enabled: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  showAddWorkoutSheet(context);
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
                      builder: (_) =>
                          const WorkoutPlanEditPage(initialPlan: null),
                    ),
                  );
                },
                child: Text(
                  l(context).todayBuildManually,
                  style: AppText.meta.copyWith(color: TrainColors.ink2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The same tinted icon-chip language the shared import phase states use for
/// their own screens — reused here so the empty state that leads INTO
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
          colors: [
            color.withValues(alpha: 0.26),
            color.withValues(alpha: 0.08),
          ],
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

/// "82.5" — one decimal only when there is one.
String _trimNumber(double v) =>
    v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// `19:40` — a mean start time reads as a 24h clock here, not `7:40 PM`: at
/// 30px mono the meridiem would be a second unit competing with the value,
/// and the grid's tiles all read as instruments. The drill-down page keeps
/// the 12-hour label `formatClockTime` gives it, where there's room for it.
String _clock24(double minutesSinceMidnight) {
  final total = minutesSinceMidnight.round() % (24 * 60);
  return '${(total ~/ 60).toString().padLeft(2, '0')}:'
      '${(total % 60).toString().padLeft(2, '0')}';
}

/// `JUL 1` — the trend window's opening reading.
///
/// Month names come from `intl`, not from ZIVO's ARB files: they are calendar
/// data every locale already has (see `header_builder.dart`'s note). Falls
/// back to the default locale when the requested one's symbols aren't loaded,
/// which is the case in a widget test with no localization delegates.
String _shortDate(DateTime d, [String? localeName]) {
  try {
    return DateFormat('MMM d', localeName).format(d).toUpperCase();
  } on Exception {
    return DateFormat('MMM d').format(d).toUpperCase();
  }
}

/// The BODYWEIGHT section's trailing caption — a delta always states its own
/// baseline (identity §7), so it carries the window with it. Null (no
/// caption) until there are two readings in the window to compare.
String? _weightDeltaCaption(WeightTrend trend) {
  final change = trend.changeKgOverWindow;
  if (change == null) return null;
  final sign = change > 0
      ? '+'
      : change < 0
      ? '−'
      : '';
  return '$sign${_trimNumber(change.abs())} KG · 30D';
}

/// Losing reads green, gaining ember — the same state/attention split the
/// rest of the app uses. A flat window stays neutral rather than claiming a
/// direction it doesn't have.
Color? _weightDeltaColor(WeightTrend trend) {
  final change = trend.changeKgOverWindow;
  if (change == null || change == 0) return null;
  return change < 0 ? TrainColors.green : TrainColors.ember;
}
