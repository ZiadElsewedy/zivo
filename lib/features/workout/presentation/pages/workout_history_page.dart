import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/live_session.dart';
import '../../domain/session_status.dart';
import 'session_details_page.dart';
import 'workout_dashboard_page.dart' show formatClockTime, formatDurationShort;

/// Every logged training session, newest first — the same [LiveSession]
/// model the Workout Dashboard's "Recent activity" and [SessionDetailsPage]
/// already read, so session → history → details is one connected system on
/// one real data model (R11) rather than History showing a separate,
/// disconnected flat log.
///
/// Dark, immersive — matching the dashboard/live-session pages on the
/// app-wide [AppColors] dark theme.
class WorkoutHistoryPage extends StatelessWidget {
  const WorkoutHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = AppScope.of(context).workoutSessions;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.ink2),
        title: Text('History', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
      ),
      body: StreamBuilder<List<LiveSession>>(
        stream: sessions.watchAll(),
        initialData: sessions.current,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _HistoryErrorState();
          final items = snapshot.data ?? const <LiveSession>[];
          if (items.isEmpty && snapshot.connectionState == ConnectionState.waiting) {
            return const _HistoryLoadingState();
          }
          if (items.isEmpty) return const _HistoryEmptyState();
          final now = DateTime.now();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final session = items[i];
              return Dismissible(
                key: ValueKey(session.id),
                direction: DismissDirection.endToStart,
                background: const _DeleteSwipeBackground(),
                confirmDismiss: (_) => confirmDeleteSession(context, session.dayLabel),
                onDismissed: (_) => sessions.deleteSession(session.id),
                child: _SessionHistoryRow(
                  session: session,
                  now: now,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SessionDetailsPage(session: session)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One session's full-context row — day, date, start–end time, duration,
/// exercise/set counts, and completion status — everything History's own
/// list needs to say before a tap opens [SessionDetailsPage] for the
/// per-set breakdown.
class _SessionHistoryRow extends StatelessWidget {
  const _SessionHistoryRow({required this.session, required this.now, required this.onTap});

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
    final duration = session.status == SessionStatus.active ? session.activeElapsed(now: now) : session.elapsed;

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
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.dayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      label,
                      style: AppText.meta.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(_dateAndTimeRange(session), style: AppText.meta.copyWith(color: AppColors.ink3)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _MetaChip(icon: Icons.timer_outlined, label: formatDurationShort(duration)),
                  const SizedBox(width: 14),
                  _MetaChip(
                    icon: Icons.fitness_center_rounded,
                    label:
                        '${session.exercises.length} exercise${session.exercises.length == 1 ? '' : 's'}',
                  ),
                  const SizedBox(width: 14),
                  _MetaChip(
                    icon: Icons.check_circle_outline_rounded,
                    label: '${session.completedSetCount}/${session.totalSets} sets',
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
        Text(label, style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 12)),
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
      child: const Icon(Icons.delete_outline_rounded, color: AppColors.flare),
    );
  }
}

double _minutesSinceMidnight(DateTime dt) => (dt.hour * 60 + dt.minute).toDouble();

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
            const Icon(Icons.cloud_off_rounded, size: 30, color: AppColors.ink3),
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
            const Icon(Icons.history_rounded, size: 30, color: AppColors.ink3),
            const SizedBox(height: 12),
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
