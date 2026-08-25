
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/live_session.dart';
import '../../domain/session_status.dart';
import '../../domain/workout_session_repository.dart';
import 'session_details_page.dart';
import 'workout_dashboard_page.dart' show formatClockTime, formatDurationShort;

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
              child: _AuraBlob(color: AppColors.iris, size: 200),
            ),
            SafeArea(
              // The header lives OUTSIDE the stream so the page always has
              // its title and a way back — even while loading, on error, or
              // with nothing logged yet (a pushed page must never become a
              // chrome-less dead end).
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                    child: RiseIn(child: _HistoryHeader()),
                  ),
                  Expanded(child: _body(sessions)),
                ],
              ),
            ),
          ],
        ),
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

        final groups = <_WeekGroup>[];
        for (final session in items) {
          final ws = _startOfWeek(session.startedAt);
          final index = ws == weekStart
              ? 0
              : ws == weekStart.subtract(const Duration(days: 7))
              ? 1
              : 2;
          // Buckets can be sparse — e.g. every session is over two weeks old
          // (a returning user) lands in bucket 2 with nothing in 0/1. Grow
          // densely and drop empties below; indexing straight into a sparse
          // list crashed here (RangeError) whenever the newest session wasn't
          // THIS week.
          while (groups.length <= index) {
            groups.add(_WeekGroup(groups.length, []));
          }
          // Sessions arrive newest-first; each bucket keeps that order.
          if (groups[index].sessions.isEmpty) {
            groups[index].weekStart = ws;
          }
          groups[index].sessions.add(session);
        }
        final visibleGroups =
            groups.where((g) => g.sessions.isNotEmpty).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 100),
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
            for (final group in visibleGroups) ...[
              _WeekHeader(group.label(context)),
              for (final (i, session) in group.sessions.indexed)
                RiseIn(
                  delay: Duration(
                    milliseconds: (90 + i * 40).clamp(0, 320),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i == group.sessions.length - 1 ? 0 : 10,
                    ),
                    child: Dismissible(
                      key: ValueKey(session.id),
                      direction: DismissDirection.endToStart,
                      background: const _DeleteSwipeBackground(),
                      confirmDismiss: (_) => confirmDeleteSession(
                        context,
                        session.dayLabel,
                      ),
                      onDismissed: (_) =>
                          sessions.deleteSession(session.id),
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

/// A soft, blurred wash of color floating behind the content — the quiet
/// "energy" glow shared across the app's surfaces. Purely decorative.
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

/// The pushed-page header — back chip and display title.
class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader();

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
        Expanded(
          child: Text(
            'History',
            style: AppText.greeting.copyWith(fontSize: 30),
          ),
        ),
      ],
    );
  }
}

/// One week's worth of sessions, in list order.
class _WeekGroup {
  _WeekGroup(this.bucket, this.sessions);

  final int bucket; // 0 this week · 1 last week · 2 earlier
  final List<LiveSession> sessions;
  DateTime? weekStart;

  String label(BuildContext context) => switch (bucket) {
    0 => 'THIS WEEK',
    1 => 'LAST WEEK',
    _ => 'EARLIER',
  };
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
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryStat(
              icon: AppIcons.sessions,
              accent: AppColors.pulse,
              value: '$totalSessions',
              label: 'Sessions',
            ),
          ),
          const _SummaryDivider(),
          Expanded(
            child: _SummaryStat(
              icon: AppIcons.timer,
              accent: AppColors.iris,
              value: totalHours < 1
                  ? '${totalMinutesLabel(totalHours)}m'
                  : '${totalHours.toStringAsFixed(1)}h',
              label: 'Trained',
            ),
          ),
          const _SummaryDivider(),
          Expanded(
            child: _SummaryStat(
              icon: AppIcons.streak,
              accent: AppColors.ember,
              value: '$thisWeek',
              label: 'This week',
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
    color: AppColors.hairline2,
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
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 11),
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
      SessionStatus.completed => ('Completed', AppColors.pulse),
      SessionStatus.active => ('In progress', AppColors.solar),
      SessionStatus.abandoned => ('Not completed', AppColors.ink3),
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
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: session.status == SessionStatus.completed
                  ? AppColors.hairline
                  : color.withValues(alpha: 0.22),
            ),
            boxShadow: AppShadows.card,
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
                      color: color == AppColors.ink3 ? AppColors.ink2 : color,
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
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _dateAndTimeRange(session),
                          style: AppText.meta.copyWith(color: AppColors.ink3),
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
                    label: formatDurationShort(duration),
                  ),
                  const SizedBox(width: 14),
                  _MetaChip(
                    icon: AppIcons.workout,
                    label:
                        '${session.exercises.length} exercise${session.exercises.length == 1 ? '' : 's'}',
                  ),
                  const SizedBox(width: 14),
                  _MetaChip(
                    icon: AppIcons.check,
                    label:
                        '${session.completedSetCount}/${session.totalSets} sets',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateAndTimeRange(LiveSession s) {
    final date = _formatDate(s.startedAt);
    final start = formatClockTime(_minutesSinceMidnight(s.startedAt));
    if (s.completedAt == null) return '$date · $start';
    return '$date · $start–${formatClockTime(_minutesSinceMidnight(s.completedAt!))}';
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
        Icon(icon, size: 13, color: AppColors.ink3),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 12),
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
        color: AppColors.flare.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(AppIcons.trash, color: AppColors.flare, size: 20),
    );
  }
}

double _minutesSinceMidnight(DateTime dt) =>
    (dt.hour * 60 + dt.minute).toDouble();

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

class _HistoryLoadingState extends StatelessWidget {
  const _HistoryLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 140,
        height: 140,
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(10),
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(AppColors.ink2, BlendMode.srcIn),
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
              color: AppColors.ink3,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load this.",
              style: AppText.aside.copyWith(color: AppColors.ink2),
              textAlign: TextAlign.center,
            ),
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
                    AppColors.iris.withValues(alpha: 0.22),
                    AppColors.iris.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                AppIcons.history,
                size: 28,
                color: AppColors.iris,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No sessions logged yet.',
              style: AppText.aside.copyWith(color: AppColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Finish a workout and it shows up here.',
              style: AppText.meta.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
