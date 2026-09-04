import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../domain/live_session.dart';
import '../../domain/session_status.dart';
import '../../domain/workout_session_repository.dart';
import 'session_details_page.dart';
import '../../../../core/util/date_format.dart';
import '../../../../l10n/l10n.dart';
import '../workout_format.dart';

/// Every logged training session, newest first, grouped into weeks — the
/// same [LiveSession] model the Workout Dashboard's "Recent activity" and
/// [SessionDetailsPage] already read, so session → history → details is one
/// connected system on one real data model (R11) rather than History showing
/// a separate, disconnected flat log.
///
/// A summary strip up top answers "how much have I actually trained" at a
/// glance (total sessions, hours, this week), then week headers give the log
/// a timeline to read down through.
class WorkoutHistoryPage extends StatelessWidget {
  const WorkoutHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = AppScope.of(context).workoutSessions;
    return TrainScreen(
      tint: TrainColors.hubTint,
      // The header lives OUTSIDE the stream so the page always has its title
      // and a way back — even while loading, on error, or with nothing
      // logged yet (a pushed page must never become a chrome-less dead end).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: RiseIn(
              child: TrainPageHeader(title: l(context).workoutHistory),
            ),
          ),
          Expanded(child: _body(sessions)),
        ],
      ),
    );
  }

  Widget _body(WorkoutSessionRepository sessions) {
    return StreamBuilder<List<LiveSession>>(
      stream: sessions.watchAll(),
      initialData: sessions.current,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _HistoryErrorState();
        final items = snapshot.data ?? const <LiveSession>[];
        if (items.isEmpty &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const _HistoryLoadingState();
        }
        if (items.isEmpty) return const _HistoryEmptyState();
        final now = DateTime.now();
        final completed = items
            .where((s) => s.status == SessionStatus.completed)
            .toList();
        final totalMinutes = completed.fold<int>(
          0,
          (sum, s) => sum + s.elapsed.inMinutes,
        );
        final weekStart = _startOfWeek(now);

        // Group by calendar week, newest first. Every week gets its own
        // dated header (e.g. "AUG 18 – AUG 24") instead of the old three
        // buckets that collapsed everything past last week into one opaque
        // "EARLIER" pile — which made a long history read like it was
        // missing workouts even though the count above was correct.
        final byWeek = <DateTime, List<LiveSession>>{};
        for (final session in items) {
          byWeek
              .putIfAbsent(_startOfWeek(session.startedAt), () => [])
              .add(session);
        }
        final weekStarts = byWeek.keys.toList()..sort((a, b) => b.compareTo(a));

        return ListView(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            TrainBottomInset.of(context),
          ),
          children: [
            RiseIn(
              delay: const Duration(milliseconds: 50),
              child: _SummaryStrip(
                totalSessions: completed.length,
                totalHours: totalMinutes / 60,
                thisWeek: completed
                    .where((s) => !s.startedAt.isBefore(weekStart))
                    .length,
              ),
            ),
            const SizedBox(height: 10),
            for (final ws in weekStarts) ...[
              _WeekHeader(_WeekGroup(ws, byWeek[ws]!).label(context, weekStart)),
              for (final (i, session) in byWeek[ws]!.indexed)
                RiseIn(
                  delay: Duration(milliseconds: (90 + i * 40).clamp(0, 320)),
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i == byWeek[ws]!.length - 1 ? 0 : 10,
                    ),
                    child: Dismissible(
                      key: ValueKey(session.id),
                      direction: DismissDirection.endToStart,
                      background: const _DeleteSwipeBackground(),
                      confirmDismiss: (_) =>
                          confirmDeleteSession(context, session.dayLabel),
                      onDismissed: (_) => sessions.deleteSession(session.id),
                      child: _SessionHistoryRow(
                        session: session,
                        now: now,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SessionDetailsPage(session: session),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }

  static DateTime _startOfWeek(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    // Monday-based weeks.
    return day.subtract(Duration(days: d.weekday - 1));
  }
}

/// One calendar week's sessions, newest first — the unit the list groups by.
class _WeekGroup {
  _WeekGroup(this.weekStart, this.sessions);

  /// Midnight of this group's Monday.
  final DateTime weekStart;
  final List<LiveSession> sessions;

  DateTime get weekEnd => weekStart.add(const Duration(days: 6));

  /// "THIS WEEK", "LAST WEEK", or a dated range ("AUG 18 – AUG 24") for
  /// anything further back — so no stretch of history is ever lumped into
  /// an anonymous bucket.
  String label(BuildContext context, DateTime currentWeekStart) {
    if (weekStart == currentWeekStart) return l(context).workoutThisWeekCaps;
    if (weekStart == currentWeekStart.subtract(const Duration(days: 7))) {
      return l(context).workoutLastWeekCaps;
    }
    String part(DateTime d) => formatMonthDayCaps(context, d);
    return '${part(weekStart)} – ${part(weekEnd)}';
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
      child: Text(
        label,
        style: AppText.sectionLabel.copyWith(letterSpacing: 1.0),
      ),
    );
  }
}

/// The "how much have I trained" answer — three instruments with their own
/// hues (sessions pulse, hours iris, this week ember) so the strip reads as
/// different signals, not three identical numbers.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.totalSessions,
    required this.totalHours,
    required this.thisWeek,
  });

  final int totalSessions;
  final double totalHours;
  final int thisWeek;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryStat(
              icon: AppIcons.sessions,
              accent: TrainColors.green,
              value: '$totalSessions',
              label: l(context).workoutSessionsLabel,
            ),
          ),
          const _SummaryDivider(),
          Expanded(
            child: _SummaryStat(
              icon: AppIcons.timer,
              accent: TrainColors.green,
              value: totalHours < 1
                  ? l(context).workoutDurationM(totalMinutesLabel(totalHours))
                  : l(context).workoutDurationH(totalHours.toStringAsFixed(1)),
              label: l(context).workoutTrained,
            ),
          ),
          const _SummaryDivider(),
          Expanded(
            child: _SummaryStat(
              icon: AppIcons.streak,
              accent: TrainColors.green,
              value: '$thisWeek',
              label: l(context).workoutThisWeek,
            ),
          ),
        ],
      ),
    );
  }

  static int totalMinutesLabel(double hours) => (hours * 60).round();
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 38,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: TrainColors.hairline,
  );
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.icon,
    required this.accent,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color accent;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
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
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: accent),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppText.rowTitle.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: TrainColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppText.meta.copyWith(color: TrainColors.ink4, fontSize: 11),
        ),
      ],
    );
  }
}

/// One session's full-context row — day, date, start–end time, duration,
/// exercise/set counts, and completion status — everything History's own
/// list needs to say before a tap opens [SessionDetailsPage] for the
/// per-set breakdown. A status-colored edge on the leading chip lets the
/// eye triage the list before reading a word.
class _SessionHistoryRow extends StatelessWidget {
  const _SessionHistoryRow({
    required this.session,
    required this.now,
    required this.onTap,
  });

  final LiveSession session;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (session.status) {
      SessionStatus.completed => (
        l(context).workoutSessionCompleted,
        TrainColors.green,
      ),
      SessionStatus.active => (
        l(context).workoutSessionInProgress,
        TrainColors.amber,
      ),
      SessionStatus.abandoned => (
        l(context).workoutSessionNotCompleted,
        TrainColors.ink4,
      ),
    };
    final duration = session.status == SessionStatus.active
        ? session.activeElapsed(now: now)
        : session.elapsed;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x08FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: session.status == SessionStatus.completed
                  ? TrainColors.hairline
                  : color.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
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
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      switch (session.status) {
                        SessionStatus.completed => AppIcons.trendUp,
                        SessionStatus.active => AppIcons.bolt,
                        SessionStatus.abandoned => AppIcons.minus,
                      },
                      size: 16,
                      color: color == TrainColors.ink4
                          ? TrainColors.ink2
                          : color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.dayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.rowTitle.copyWith(
                            fontWeight: FontWeight.w600,
                            color: TrainColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _dateAndTimeRange(context, session),
                          style: AppText.meta.copyWith(color: TrainColors.ink4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      label,
                      style: AppText.meta.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MetaChip(
                    icon: AppIcons.timer,
                    label: formatDurationShort(context, duration),
                  ),
                  const SizedBox(width: 14),
                  _MetaChip(
                    icon: AppIcons.workout,
                    label:
                        l(context).workoutExerciseCount(session.exercises.length),
                  ),
                  const SizedBox(width: 14),
                  _MetaChip(
                    icon: AppIcons.check,
                    label:
                        l(context).workoutSetsOfTotal(
                          session.completedSetCount,
                          session.totalSets,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateAndTimeRange(BuildContext context, LiveSession s) {
    final date = formatMonthDay(context, s.startedAt);
    final start = formatClockTime(context, s.startedAt);
    if (s.completedAt == null) return '$date · $start';
    return '$date · $start–${formatClockTime(context, s.completedAt!)}';
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: TrainColors.ink4),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppText.meta.copyWith(color: TrainColors.ink4, fontSize: 12),
        ),
      ],
    );
  }
}

/// The red trailing reveal shown as a session row is swiped left to delete —
/// the confirm dialog ([confirmDeleteSession]) still gates the actual delete.
class _DeleteSwipeBackground extends StatelessWidget {
  const _DeleteSwipeBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: TrainColors.ember.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(AppIcons.trash, color: TrainColors.ember, size: 20),
    );
  }
}

class _HistoryLoadingState extends StatelessWidget {
  const _HistoryLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 140,
        height: 140,
        decoration: const BoxDecoration(
          color: TrainColors.glassStrong,
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

class _HistoryErrorState extends StatelessWidget {
  const _HistoryErrorState();

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
              color: TrainColors.ink4,
            ),
            const SizedBox(height: 12),
            Text(
              l(context).errorCouldntLoad,
              style: AppText.aside.copyWith(color: TrainColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              l(context).errorCheckConnection,
              style: AppText.meta.copyWith(color: TrainColors.ink4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    TrainColors.violetGlyph.withValues(alpha: 0.22),
                    TrainColors.violetGlyph.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                AppIcons.history,
                size: 28,
                color: TrainColors.violetGlyph,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l(context).workoutNoSessionsTitle,
              style: AppText.aside.copyWith(color: TrainColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              l(context).workoutNoSessionsBody,
              style: AppText.meta.copyWith(color: TrainColors.ink4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
