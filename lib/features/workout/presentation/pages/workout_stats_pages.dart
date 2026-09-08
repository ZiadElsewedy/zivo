import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../../../core/util/time_ago.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../domain/live_session.dart';
import '../../domain/session_status.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/calendar.dart';
import '../../domain/training_dashboard_stats.dart';
import '../../domain/training_day_mark.dart';
import '../../domain/training_day_mark_repository.dart';
import '../../domain/training_streak.dart';
import '../widgets/missed_day_sheet.dart';
import '../workout_labels.dart';
import '../pages/session_details_page.dart';
import '../../../../core/util/date_format.dart';
import '../../../../l10n/l10n.dart';
import '../workout_format.dart';

/// The drill-down pages behind the Workout dashboard's "This week" tiles.
/// One file because they are one idea — each tile's number, opened up into
/// the per-session history that produced it — sharing the hub's own green
/// wash and handoff chrome. Every page is self-sufficient (its own
/// [AppScope] streams), so the numbers stay live.
///
/// **Every list on these four pages is one card**, with the rows separated by
/// the house hairline. They used to be a stack of individually bordered,
/// individually rounded boxes — the same frame drawn twenty times down a page
/// whose whole content is one number per line, so the borders carried more ink
/// than the readings. A history is a list; a list is a card.
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
                      color: TrainColors.voiceInk,
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
                      color: TrainColors.inkAt(0.35),
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
              // The shared error view, not a bare line of text: a failed read
              // says what failed, why it might have, and looks the same here
              // as it does on every other stream-backed surface.
              SizedBox(
                height: 200,
                child: ErrorStateView(message: l(context).workoutSessionsLoadError),
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
              TrainListCard(
                rows: [
                  for (final (i, session) in sessions.indexed)
                    RiseIn(
                      delay: Duration(milliseconds: 30 * (i + 1).clamp(0, 8)),
                      child: _SessionRow(session: session),
                    ),
                ],
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
      // Voided reads as its own state, not as "abandoned": the session
      // happened and its numbers are intact, it simply no longer counts.
      SessionStatus.voided => (
        l(context).sessionVoided,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SessionDetailsPage(session: session),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
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
                          color: TrainColors.inkAt(0.35),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: TrainColors.inkAt(0.3),
                ),
              ],
            ),
          ),
      ),
    );
  }
}

// ---- Day streak -------------------------------------------------------------

/// The Day Streak tile's page.
///
/// Shows the rule the streak actually follows — train at least every
/// [kStreakMaxGapDays] days — and then the run itself as a continuous stretch
/// of calendar days: the ones trained, the rest days between them, and any day
/// held together by a restore. A row of trained days with the gaps deleted was
/// the old version, and it made a perfectly healthy streak look like it had
/// holes in it.
///
/// Every number here comes from the same `computeTrainingStreak` the tile
/// reads, so the two cannot drift.
class WorkoutStreakPage extends StatelessWidget {
  const WorkoutStreakPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final marksRepo = scope.trainingDayMarks;
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const <LiveSession>[];
        return StreamBuilder<List<TrainingDayMark>>(
          stream: marksRepo?.watchAll() ?? const Stream.empty(),
          initialData: marksRepo?.current ?? const <TrainingDayMark>[],
          builder: (context, marksSnapshot) {
            final marks = marksSnapshot.data ?? const <TrainingDayMark>[];
            final now = DateTime.now();
            final streak = computeTrainingStreak(
              sessions: sessions,
              now: now,
              marks: marks,
            );
            final rows = streak.days.isNotEmpty
                ? streak.days
                : _recentDays(sessions: sessions, marks: marks, now: now);
            return StatDrillDownScaffold(
              title: l(context).workoutDayStreak,
              children: [
                StatHeroValue(
                  value: '${streak.currentDays}',
                  label: streak.isActive
                      ? l(context).workoutStreakDays(streak.currentDays)
                      : l(context).workoutNoActiveStreak,
                  accent: TrainColors.green,
                ),
                const SizedBox(height: 8),
                _StreakRuleLine(streak: streak),
                const SizedBox(height: 10),
                StatHeroValue(
                  value: '${streak.bestDays}',
                  label: l(context).workoutBestStreak,
                  accent: TrainColors.green,
                ),
                const SizedBox(height: 18),
                // When a run is going, these are its days. When it has just
                // broken there IS no run — and that is precisely the moment
                // the restore exists for, so the page falls back to the last
                // week of days rather than an empty card with nothing to tap.
                // A dead end here would make the whole restore feature
                // unreachable exactly when it is wanted.
                if (rows.isNotEmpty)
                  TrainListCard(
                    rows: [
                      for (final (i, day) in rows.indexed)
                        RiseIn(
                          delay: Duration(milliseconds: 30 * (i + 1).clamp(0, 8)),
                          child: _StreakDayRow(
                            entry: day,
                            sessions: sessions,
                            marks: marks,
                            now: now,
                            marksRepo: marksRepo,
                          ),
                        ),
                    ],
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
      },
    );
  }
}

/// The last week of calendar days, newest first — the fallback list shown when
/// there is no run, so a broken streak still offers the days a restore could
/// be spent on and the days a reason could be written against.
///
/// Reaches exactly as far back as a restore may
/// ([kRestoreReachDays]); showing days that cannot be acted on would be a list
/// of dead rows.
List<StreakDay> _recentDays({
  required List<LiveSession> sessions,
  required List<TrainingDayMark> marks,
  required DateTime now,
}) {
  final counts = trainedDayCounts(sessions);
  final marksByDay = {for (final m in marks) startOfDay(m.day): m};
  return [
    for (var i = 0; i <= kRestoreReachDays; i++)
      () {
        final day = addCalendarDays(now, -i);
        final mark = marksByDay[day];
        final trained = counts.containsKey(day);
        return StreakDay(
          day: day,
          kind: trained
              ? StreakDayKind.trained
              : (mark?.restored ?? false
                    ? StreakDayKind.restored
                    : StreakDayKind.rest),
          sessionCount: counts[day] ?? 0,
          reason: mark?.reason,
          note: mark?.note,
        );
      }(),
  ];
}

/// The rule, and how much room is left in it — the two things that make the
/// number above mean something. Without them "12" is a score; with them it is
/// a statement about the next three days.
class _StreakRuleLine extends StatelessWidget {
  const _StreakRuleLine({required this.streak});

  final TrainingStreak streak;

  @override
  Widget build(BuildContext context) {
    final left = streak.daysUntilBreak;
    return Column(
      children: [
        Text(
          ltrFor(context, l(context).workoutStreakRule(kStreakMaxGapDays)),
          textAlign: TextAlign.center,
          style: TrainType.ui(size: 12.5, color: TrainColors.ink3),
        ),
        const SizedBox(height: 4),
        Text(
          left == null
              ? l(context).workoutStreakBroken
              : l(context).workoutStreakDaysLeft(left),
          textAlign: TextAlign.center,
          style: TrainType.mono(
            size: 10,
            tracking: 0.08,
            color: streak.isAtRisk
                ? TrainColors.ember
                : TrainColors.inkAt(0.4),
          ),
        ),
      ],
    );
  }
}

/// One calendar day in the run — trained, rest, or restored.
class _StreakDayRow extends StatelessWidget {
  const _StreakDayRow({
    required this.entry,
    required this.sessions,
    required this.marks,
    required this.now,
    required this.marksRepo,
  });

  final StreakDay entry;
  final List<LiveSession> sessions;
  final List<TrainingDayMark> marks;
  final DateTime now;
  final TrainingDayMarkRepository? marksRepo;

  @override
  Widget build(BuildContext context) {
    final trained = sessionsOnDay(sessions, entry.day);
    final isToday = DateUtils.isSameDay(entry.day, now);

    final (IconData icon, Color accent) = switch (entry.kind) {
      // Green, not ember. A day you already trained is training state, which
      // is green's job; ember is the committing action and the "you are here"
      // marker, and this page's hero figures above are green.
      StreakDayKind.trained => (
        isToday ? AppIcons.calendarClock : AppIcons.check,
        TrainColors.green,
      ),
      StreakDayKind.rest => (AppIcons.minus, TrainColors.ink4),
      StreakDayKind.restored => (AppIcons.streak, TrainColors.ember),
    };

    final String subtitle = switch (entry.kind) {
      StreakDayKind.trained => trained.map((s) => s.dayLabel).toSet().join(' · '),
      StreakDayKind.restored => l(context).workoutStreakRestored,
      StreakDayKind.rest => entry.reason == null
          ? l(context).workoutStreakRestDay
          : missedDayReasonLabel(context, entry.reason!),
    };

    final trailing = switch (entry.kind) {
      StreakDayKind.trained => l(context).workoutSessionsCountCaps(trained.length),
      _ => '',
    };

    // A rest day is the only one worth tapping: it is where a reason is added
    // and where a restore can be spent. A trained day has nothing to change.
    final tappable = entry.kind != StreakDayKind.trained && marksRepo != null;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      child: Row(
        children: [
          TrainIconTile(icon: icon, accent: accent, iconSize: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isToday
                      ? l(context).workoutToday
                      : formatMonthDay(context, entry.day),
                  style: TrainType.ui(
                    size: 14,
                    weight: FontWeight.w700,
                    color: entry.isTrained
                        ? TrainColors.inkPlain
                        : TrainColors.ink2,
                    height: 1,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle.toUpperCase(),
                    style: TrainType.mono(
                      size: 9.5,
                      tracking: 0.08,
                      color: TrainColors.inkAt(0.35),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing.isNotEmpty)
            Text(
              trailing,
              style: TrainType.caption(
                size: 9,
                tracking: 0.12,
                color: TrainColors.ink4,
              ),
            ),
        ],
      ),
    );

    if (!tappable) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showMissedDaySheet(
        context,
        day: entry.day,
        now: now,
        sessions: sessions,
        marks: marks,
        repository: marksRepo!,
      ),
      child: row,
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
        final maxDuration = scope.maxSessionDuration;
        final completed = _completed(snapshot.data);
        // Shortest/longest read the same gated set the average does — a
        // "longest session" of nineteen hours would be the loudest wrong
        // number on the page.
        final usable = completed
            .where((s) => s.hasUsableDuration(maxDuration))
            .toList();
        final durations = [for (final s in usable) s.elapsed];
        durations.sort((a, b) => a.inMicroseconds.compareTo(b.inMicroseconds));
        final stats = computeTrainingDashboardStats(
          sessions: snapshot.data ?? const [],
          now: DateTime.now(),
          maxSessionDuration: maxDuration,
        );
        final avg = stats.averageSessionDuration;
        return StatDrillDownScaffold(
          title: l(context).workoutSessionLength,
          children: [
            StatHeroValue(
              value: avg == null ? '—' : formatDurationShort(context, avg),
              // When some sessions were held out, the label says so. An
              // average presented as covering everything when it covers 23 of
              // 24 is the quiet kind of wrong this whole change is about.
              label: avg == null
                  ? (completed.isEmpty
                        ? l(context).workoutNoAverageYet
                        : l(context).statDurationAllExcluded)
                  : (stats.durationsExcluded > 0
                        ? '${l(context).workoutAverageSession} · '
                              '${l(context).statDurationOver(stats.durationsCounted, completed.length)}'
                        : l(context).workoutAverageSession),
              accent: TrainColors.green,
            ),
            if (durations.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: StatHeroValue(
                      value: formatDurationShort(context, durations.first),
                      label: l(context).workoutShortestSession,
                      accent: TrainColors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatHeroValue(
                      value: formatDurationShort(context, durations.last),
                      label: l(context).workoutLongestSession,
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
              TrainListCard(
                rows: [
                  for (final (i, session) in completed.indexed)
                    RiseIn(
                      delay: Duration(milliseconds: 30 * (i + 1).clamp(0, 8)),
                      child: _MetricRow(
                        title: session.dayLabel,
                        subtitle:
                            '${formatMonthDay(context, session.startedAt)} · '
                            '${l(context).workoutAgo(timeAgo(context, session.startedAt, DateTime.now()))}',
                        // A session held out of the average says so here
                        // rather than printing a duration the page has
                        // already decided not to believe.
                        trailing: session.hasUsableDuration(maxDuration)
                            ? formatDurationShort(context, session.elapsed)
                            : l(context).sessionNeedsDuration,
                        accent: session.hasUsableDuration(maxDuration)
                            ? TrainColors.green
                            : TrainColors.amber,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                SessionDetailsPage(session: session),
                          ),
                        ),
                      ),
                    ),
                ],
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
              TrainListCard(
                rows: [
                  for (final (i, session) in completed.indexed)
                    RiseIn(
                      delay: Duration(milliseconds: 30 * (i + 1).clamp(0, 8)),
                      child: _MetricRow(
                        title: formatClockTime(context, session.startedAt),
                        subtitle:
                            '${session.dayLabel} · ${formatMonthDay(context, session.startedAt)}',
                        trailing: timeAgo(
                          context,
                          session.startedAt,
                          DateTime.now(),
                        ),
                        accent: TrainColors.green,
                      ),
                    ),
                ],
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
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
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
                    color: TrainColors.inkAt(0.35),
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
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
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
        color: TrainColors.liftAt(0.024),
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
