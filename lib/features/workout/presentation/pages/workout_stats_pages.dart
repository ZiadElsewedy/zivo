import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/time_ago.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/live_session.dart';
import '../../domain/session_status.dart';
import '../../domain/training_dashboard_stats.dart';
import '../pages/session_details_page.dart';

/// The drill-down pages behind the Workout dashboard's "This week" tiles.
/// One file because they are one idea — each tile's number, opened up into
/// the per-session history that produced it — sharing the dashboard's
/// ground-gradient language and pulse accents. Every page is self-sufficient
/// (its own [AppScope] streams), so the numbers stay live.

/// The shared scaffold chrome for all stat drill-downs: back chip, title,
/// and an optional summary line, over the dashboard's green-tinted gradient.
class StatDrillDownScaffold extends StatelessWidget {
  const StatDrillDownScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
            children: [
              Row(
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
                  Expanded(
                    child: Text(
                      title,
                      style: AppText.greeting.copyWith(fontSize: 26),
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: AppText.meta.copyWith(color: AppColors.ink3),
                ),
              ],
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// A big number + label header used at the top of a drill-down ("12
/// sessions", "4 days"), tinted with its stat hue so the page still reads as
/// the tile it came from.
class StatHeroValue extends StatelessWidget {
  const StatHeroValue({
    super.key,
    required this.value,
    required this.label,
    required this.accent,
  });

  final String value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return RiseIn(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: AppText.heroNumber.copyWith(fontSize: 40, color: AppColors.ink),
            ),
            const SizedBox(height: 2),
            Text(label, style: AppText.meta.copyWith(color: AppColors.ink3)),
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
            title: 'Sessions',
            children: [
              const SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    "Couldn't load sessions.",
                    style: TextStyle(color: AppColors.ink3),
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
        return StatDrillDownScaffold(
          title: 'Sessions',
          subtitle: completedCount == 0
              ? 'No completed workouts yet.'
              : '$completedCount completed ${completedCount == 1 ? 'workout' : 'workouts'}',
          children: [
            if (sessions.isEmpty)
              const _EmptyCard(
                icon: Icons.event_busy_rounded,
                text: 'Nothing here yet — finished workouts land here.',
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
      SessionStatus.completed => ('Completed', AppColors.pulse),
      SessionStatus.active => ('In progress', AppColors.solar),
      SessionStatus.abandoned => ('Ended early', AppColors.ink3),
    };
    return PressableScale(
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SessionDetailsPage(session: session)),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
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
                              style: AppText.rowTitle.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
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
                              statusLabel,
                              style: AppText.meta.copyWith(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: statusColor == AppColors.pulse
                                    ? AppColors.pulseText
                                    : statusColor == AppColors.solar
                                    ? AppColors.solarText
                                    : AppColors.ink3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${formatDayLabel(session.startedAt)} · '
                        '${formatClockTimeLabel(session.startedAt)} · '
                        '${_durationLabel(session.elapsed)} · '
                        '${session.completedSetCount}/${session.totalSets} sets',
                        style: AppText.meta.copyWith(color: AppColors.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.ink3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String formatDayLabel(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

String formatClockTimeLabel(DateTime d) {
  final period = d.hour < 12 ? 'AM' : 'PM';
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h12:${d.minute.toString().padLeft(2, '0')} $period';
}

String _durationLabel(Duration d) {
  final totalMinutes = d.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
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
        final streakDays = currentStreakTrainedDays(sessions: sessions, now: now);
        final best = bestStreakDays(sessions: sessions);
        return StatDrillDownScaffold(
          title: 'Day streak',
          children: [
            StatHeroValue(
              value: '${streakDays.length}',
              label: streakDays.isEmpty
                  ? 'No active streak — complete a workout to start one.'
                  : streakDays.length == 1
                  ? 'day in your current streak'
                  : 'days in your current streak',
              accent: AppColors.ember,
            ),
            const SizedBox(height: 10),
            StatHeroValue(
              value: '$best',
              label: best == 1 ? 'best day streak' : 'best day streak ever',
              accent: AppColors.ember,
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
              const _EmptyCard(
                icon: Icons.local_fire_department_rounded,
                text: 'Train today and day one starts now.',
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ember.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.ember.withValues(alpha: 0.25)),
            ),
            child: Icon(
              isToday ? Icons.today_rounded : Icons.check_rounded,
              size: 17,
              color: AppColors.ember,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday ? 'Today' : formatDayLabel(day),
                  style: AppText.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (labels.isNotEmpty)
                  Text(
                    labels,
                    style: AppText.meta.copyWith(color: AppColors.ink3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            '${trained.length} ${trained.length == 1 ? 'session' : 'sessions'}',
            style: AppText.meta.copyWith(color: AppColors.ink2),
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
          title: 'Session length',
          children: [
            StatHeroValue(
              value: avg == null ? '—' : _durationLabel(avg),
              label: avg == null
                  ? 'Complete a workout to see your average.'
                  : 'average completed session',
              accent: AppColors.iris,
            ),
            if (durations.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: StatHeroValue(
                      value: _durationLabel(durations.first),
                      label: 'shortest',
                      accent: AppColors.iris,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatHeroValue(
                      value: _durationLabel(durations.last),
                      label: 'longest',
                      accent: AppColors.iris,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            if (completed.isEmpty)
              const _EmptyCard(
                icon: Icons.timer_outlined,
                text: 'Durations appear once you finish workouts.',
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
                          '${formatDayLabel(session.startedAt)} · ${timeAgo(session.startedAt, DateTime.now())} ago',
                      trailing: _durationLabel(session.elapsed),
                      accent: AppColors.iris,
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
          title: 'Start times',
          children: [
            StatHeroValue(
              value: avgStart == null ? '—' : formatClockTimeDouble(avgStart),
              label: avgStart == null
                  ? 'Complete a workout to see your usual start time.'
                  : 'when you usually start training',
              accent: AppColors.solar,
            ),
            const SizedBox(height: 18),
            if (completed.isEmpty)
              const _EmptyCard(
                icon: Icons.schedule_rounded,
                text: 'Your start times will show up here.',
              )
            else
              for (final (i, session) in completed.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RiseIn(
                    delay: Duration(milliseconds: 30 * (i + 1).clamp(0, 8)),
                    child: _MetricRow(
                      title: formatClockTimeLabel(session.startedAt),
                      subtitle:
                          '${session.dayLabel} · ${formatDayLabel(session.startedAt)}',
                      trailing: timeAgo(session.startedAt, DateTime.now()),
                      accent: AppColors.solar,
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
  final list = (sessions ?? const <LiveSession>[])
      .where((s) => s.status == SessionStatus.completed)
      .toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return list;
}

/// Minutes-since-midnight → "6:30 AM" (the domain layer's own formatting
/// lives on the dashboard; duplicated here to keep pages dependency-light).
String formatClockTimeDouble(double minutesSinceMidnight) {
  final total = minutesSinceMidnight.round() % (24 * 60);
  final h24 = total ~/ 60;
  final minute = total % 60;
  final period = h24 < 12 ? 'AM' : 'PM';
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${minute.toString().padLeft(2, '0')} $period';
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppText.meta.copyWith(color: AppColors.ink3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            trailing,
            style: AppText.rowTitle.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
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
        color: AppColors.card.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: AppColors.ink3),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: AppColors.ink3, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
