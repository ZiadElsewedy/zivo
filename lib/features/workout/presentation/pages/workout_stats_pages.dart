import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/time_ago.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../domain/live_session.dart';
import '../../domain/session_status.dart';
import '../../domain/training_dashboard_stats.dart';
import '../pages/session_details_page.dart';
import '../../../../core/util/date_format.dart';
import '../../../../l10n/l10n.dart';
import '../workout_format.dart';

/// The drill-down pages behind the Workout dashboard's "This week" tiles.
/// One file because they are one idea — each tile's number, opened up into
/// the per-session history that produced it — sharing the hub's own green
/// wash and handoff chrome. Every page is self-sufficient (its own
/// [AppScope] streams), so the numbers stay live.
/// The shared shell for the four stat drill-downs the Workout hub's tiles
/// open — Sessions, Streak, Duration, Start times.
///
/// Dressed to the design handoff like the hub itself: the green screen wash,
/// the 36px back circle beside a Manrope 800/27 title, and an optional mono
/// caption beneath it. One shell rather than four, so a tile and the page it
/// opens can never look like they belong to different apps.
class StatDrillDownScaffold extends StatelessWidget {
  const StatDrillDownScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;

  /// A mono caption under the title, scoping what's below it.
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return TrainScreen(
      tint: TrainColors.hubTint,
      child: ListView(
        padding: EdgeInsets.fromLTRB(22, 12, 22, TrainBottomInset.of(context)),
        children: [
          TrainPageHeader(title: title),
          if (subtitle != null) ...[
            const SizedBox(height: 14),
            Text(
              subtitle!.toUpperCase(),
              style: TrainType.mono(
                size: 11.5,
                tracking: 0.06,
                color: TrainColors.ink3,
              ),
            ),
          ],
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

/// A big number + label header used at the top of a drill-down ("12
/// sessions", "4 days"), tinted with its stat hue so the page still reads as
/// the tile it came from.
/// A drill-down's one hero number: mono 300/40 over a mono caption. The
/// page's single large figure — everything below it demotes to a row
/// (identity §1.1).
class StatHeroValue extends StatelessWidget {
  const StatHeroValue({
    super.key,
    required this.value,
    required this.label,
    required this.accent,
    this.unit,
  });

  final String value;

  /// The value's unit — always smaller and dimmer than the value it belongs
  /// to (identity §1.2).
  final String? unit;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return RiseIn(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          gradient: TrainColors.cardGradient,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TrainType.mono(
                      size: 40,
                      weight: FontWeight.w300,
                      tracking: -0.05,
                      color: const Color(0xFFF9F9F5),
                    ),
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 7),
                  Text(
                    unit!,
                    style: TrainType.mono(
                      size: 11,
                      weight: FontWeight.w500,
                      tracking: 0.14,
                      color: const Color(0x59F4F4F0),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 9),
            Text(
              label.toUpperCase(),
              style: TrainType.caption(
                size: 9,
                tracking: 0.16,
                color: TrainColors.ink4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Sessions ---------------------------------------------------------------

/// The Sessions tile's page: every logged workout, newest first — date,
/// duration, sets done, and status — tapping through to the full
/// [SessionDetailsPage].
class WorkoutSessionsPage extends StatelessWidget {
  const WorkoutSessionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StatDrillDownScaffold(
            title: l(context).workoutSessionsLabel,
            children: [
              SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    l(context).workoutSessionsLoadError,
                    style: const TextStyle(color: TrainColors.ink4),
                  ),
                ),
              ),
            ],
          );
        }
        final sessions = [...(snapshot.data ?? const <LiveSession>[])]
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
        final completedCount = sessions
            .where((s) => s.status == SessionStatus.completed)
            .length;
        final unfinishedCount = sessions.length - completedCount;
        // The subtitle must describe EVERY row below it: the list shows
        // active and ended-early sessions too, so a bare "N completed"
        // read as if the page were dropping workouts when the counts and
        // rows didn't line up.
        final subtitle = switch ((completedCount, unfinishedCount)) {
          (0, 0) => l(context).workoutNoCompletedWorkouts,
          (_, 0) => l(context).workoutCompletedCount(completedCount),
          (0, _) => l(context).workoutNoCompletedWithEntries(unfinishedCount),
          (_, _) => l(context).workoutCompletedAndNotCompleted(
            l(context).workoutCompletedCount(completedCount),
            unfinishedCount,
          ),
        };
        return StatDrillDownScaffold(
          title: l(context).workoutSessionsLabel,
          subtitle: subtitle,
          children: [
            if (sessions.isEmpty)
              _EmptyCard(
                icon: Icons.event_busy_rounded,
                text: l(context).workoutSessionsEmpty,
              )
            else
              for (final (i, session) in sessions.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RiseIn(
                    delay: Duration(milliseconds: 30 * (i + 1).clamp(0, 8)),
                    child: _SessionRow(session: session),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final LiveSession session;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = switch (session.status) {
      SessionStatus.completed => (
        l(context).workoutSessionCompleted,
        TrainColors.green,
      ),
      SessionStatus.active => (
        l(context).workoutSessionInProgress,
        TrainColors.ember,
      ),
      SessionStatus.abandoned => (
        l(context).workoutSessionEndedEarly,
        TrainColors.ink4,
      ),
    };
    // An active session's `elapsed` is ~0 (completedAt is null, so it
    // measures start→start minus pauses) and renders as "0m"/"-1m" — the
    // live reading is `activeElapsed`. Completed AND ended-early sessions
    // both have a real completedAt, so plain `elapsed` is right for them.
    final duration = session.status == SessionStatus.active
        ? session.activeElapsed(now: DateTime.now())
        : session.elapsed;
    return PressableScale(
      child: Material(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SessionDetailsPage(session: session),
            ),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TrainColors.hairline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              session.dayLabel,
                              style: TrainType.ui(
                                size: 14,
                                weight: FontWeight.w700,
                                color: TrainColors.inkPlain,
                                height: 1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel.toUpperCase(),
                              style: TrainType.caption(
                                size: 8.5,
                                tracking: 0.12,
                                weight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${formatMonthDay(context, session.startedAt)} · '
                        '${formatClockTime(context, session.startedAt)} · '
                        '${formatDurationShort(context, duration)} · '
                        '${l(context).workoutSetsCaps(session.completedSetCount, session.totalSets)}',
                        style: TrainType.mono(
                          size: 9.5,
                          tracking: 0.08,
                          color: const Color(0x59F4F4F0),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0x4DF4F4F0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Day streak -------------------------------------------------------------

/// The Day Streak tile's page: the current streak's headline, which exact
/// days contributed to it, and the best streak ever — all from the same
/// computation the tile reads, so they can't drift apart.
class WorkoutStreakPage extends StatelessWidget {
  const WorkoutStreakPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const <LiveSession>[];
        final now = DateTime.now();
        final streakDays = currentStreakTrainedDays(
          sessions: sessions,
          now: now,
        );
        final best = bestStreakDays(sessions: sessions);
        return StatDrillDownScaffold(
          title: l(context).workoutDayStreak,
          children: [
            StatHeroValue(
              value: '${streakDays.length}',
              label: streakDays.isEmpty
                  ? l(context).workoutNoActiveStreak
                  : l(context).workoutStreakDays(streakDays.length),
              accent: TrainColors.green,
            ),
            const SizedBox(height: 10),
            StatHeroValue(
              value: '$best',
              label: l(context).workoutBestStreak,
              accent: TrainColors.green,
            ),
            const SizedBox(height: 18),
            if (streakDays.isNotEmpty)
              for (final (i, day) in streakDays.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RiseIn(
                    delay: Duration(milliseconds: 30 * (i + 1).clamp(0, 8)),
                    child: _StreakDayRow(day: day, sessions: sessions),
                  ),
                )
            else
              _EmptyCard(
                icon: Icons.local_fire_department_rounded,
                text: l(context).workoutStreakEmpty,
              ),
          ],
        );
      },
    );
  }
}

class _StreakDayRow extends StatelessWidget {
  const _StreakDayRow({required this.day, required this.sessions});

  final DateTime day;
  final List<LiveSession> sessions;

  @override
  Widget build(BuildContext context) {
    final trained = sessionsOnDay(sessions, day);
    final labels = trained.map((s) => s.dayLabel).toSet().join(' · ');
    final isToday = DateUtils.isSameDay(day, DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TrainColors.ember.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: TrainColors.ember.withValues(alpha: 0.22),
              ),
            ),
            child: Icon(
              isToday ? Icons.today_rounded : Icons.check_rounded,
              size: 16,
              color: TrainColors.ember,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday
                      ? l(context).workoutToday
                      : formatMonthDay(context, day),
                  style: TrainType.ui(
                    size: 14,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                    height: 1,
                  ),
                ),
                if (labels.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    labels.toUpperCase(),
                    style: TrainType.mono(
                      size: 9.5,
                      tracking: 0.08,
                      color: const Color(0x59F4F4F0),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Text(
            l(context).workoutSessionsCountCaps(trained.length),
            style: TrainType.caption(
              size: 9,
              tracking: 0.12,
              color: TrainColors.ink4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Duration & start-time stats ---------------------------------------------

/// The Avg Duration tile's page: the average, shortest and longest sessions,
/// then every completed session's duration as history.
class WorkoutDurationStatsPage extends StatelessWidget {
  const WorkoutDurationStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, snapshot) {
        final completed = _completed(snapshot.data);
        final durations = [for (final s in completed) s.elapsed];
        durations.sort((a, b) => a.inMicroseconds.compareTo(b.inMicroseconds));
        final avg = computeTrainingDashboardStats(
          sessions: snapshot.data ?? const [],
          now: DateTime.now(),
        ).averageSessionDuration;
        return StatDrillDownScaffold(
          title: l(context).workoutSessionLength,
          children: [
            StatHeroValue(
              value: avg == null ? '—' : formatDurationShort(context, avg),
              label: avg == null
                  ? l(context).workoutNoAverageYet
                  : l(context).workoutAverageSession,
              accent: TrainColors.green,
            ),
            if (durations.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: StatHeroValue(
                      value: formatDurationShort(context, durations.first),
                      label: 'shortest',
                      accent: TrainColors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatHeroValue(
                      value: formatDurationShort(context, durations.last),
                      label: 'longest',
                      accent: TrainColors.green,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            if (completed.isEmpty)
              _EmptyCard(
                icon: Icons.timer_outlined,
                text: l(context).workoutDurationsEmpty,
              )
            else
              for (final (i, session) in completed.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RiseIn(
                    delay: Duration(milliseconds: 30 * (i + 1).clamp(0, 8)),
                    child: _MetricRow(
                      title: session.dayLabel,
                      subtitle:
                          '${formatMonthDay(context, session.startedAt)} · '
                          '${l(context).workoutAgo(timeAgo(session.startedAt, DateTime.now()))}',
                      trailing: formatDurationShort(context, session.elapsed),
                      accent: TrainColors.green,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// The Avg Start tile's page: your mean clock-in time plus every session's
/// actual start, newest first.
class WorkoutStartTimesPage extends StatelessWidget {
  const WorkoutStartTimesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, snapshot) {
        final stats = computeTrainingDashboardStats(
          sessions: snapshot.data ?? const [],
          now: DateTime.now(),
        );
        final completed = _completed(snapshot.data);
        final avgStart = stats.averageStartMinutesSinceMidnight;
        return StatDrillDownScaffold(
          title: l(context).workoutStartTimes,
          children: [
            StatHeroValue(
              value: avgStart == null
                  ? '—'
                  : formatMinutesSinceMidnight(context, avgStart.round()),
              label: avgStart == null
                  ? l(context).workoutNoStartTimeYet
                  : l(context).workoutUsualStartTime,
              accent: TrainColors.green,
            ),
            const SizedBox(height: 18),
            if (completed.isEmpty)
              _EmptyCard(
                icon: Icons.schedule_rounded,
                text: l(context).workoutStartTimesEmpty,
              )
            else
              for (final (i, session) in completed.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RiseIn(
                    delay: Duration(milliseconds: 30 * (i + 1).clamp(0, 8)),
                    child: _MetricRow(
                      title: formatClockTime(context, session.startedAt),
                      subtitle:
                          '${session.dayLabel} · ${formatMonthDay(context, session.startedAt)}',
                      trailing: timeAgo(session.startedAt, DateTime.now()),
                      accent: TrainColors.green,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

List<LiveSession> _completed(List<LiveSession>? sessions) {
  final list =
      (sessions ?? const <LiveSession>[])
          .where((s) => s.status == SessionStatus.completed)
          .toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return list;
}

// ---- Shared bits --------------------------------------------------------------

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          // The 4px spine the handoff uses in place of a saturated icon
          // tile — it says which signal without competing with the value.
          Container(
            width: 4,
            height: 26,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TrainType.ui(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle.toUpperCase(),
                  style: TrainType.mono(
                    size: 9.5,
                    tracking: 0.08,
                    color: const Color(0x59F4F4F0),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            trailing,
            style: TrainType.mono(size: 14, color: TrainColors.ink),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0x06FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: TrainColors.ink4),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TrainType.ui(
              size: 13.5,
              weight: FontWeight.w400,
              color: TrainColors.ink4,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
