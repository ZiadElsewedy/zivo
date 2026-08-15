import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/event_time.dart';
import '../../domain/schedule_event.dart';
import 'event_capture_page.dart';

/// The Schedule list — events grouped by day (Today, Tomorrow, then dated
/// headers), ordered by start time within a day. Events still to come are
/// shown first; events that have already ended sit dimmed under "Earlier".
class ScheduleListPage extends StatelessWidget {
  const ScheduleListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final schedule = AppScope.of(context).schedule;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Schedule', style: AppText.cardTitle),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.ink,
        elevation: 2,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EventCapturePage()),
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: StreamBuilder<List<ScheduleEvent>>(
        stream: schedule.watchAll(),
        initialData: schedule.current,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <ScheduleEvent>[];
          if (items.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.ink3),
            );
          }
          if (items.isEmpty) {
            return Center(
              child: Text(
                'Nothing on the calendar — enjoy the quiet.',
                style: AppText.aside,
              ),
            );
          }
          final now = DateTime.now();
          final groups = _groupUpcoming(items, now);
          final past = _sortedPast(items, now);
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
            children: [
              for (final group in groups) ...[
                _DayHeader(_dayLabel(group.day, now)),
                for (final event in group.events)
                  _EventRow(
                    event,
                    dimmed: false,
                    onTap: () => _openEdit(context, event),
                    onDelete: () => schedule.remove(event.id),
                  ),
              ],
              if (past.isNotEmpty) ...[
                const _DayHeader('Earlier'),
                for (final event in past)
                  _EventRow(
                    event,
                    dimmed: true,
                    onTap: () => _openEdit(context, event),
                    onDelete: () => schedule.remove(event.id),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, ScheduleEvent event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventCapturePage(initial: event)),
    );
  }
}

bool _isUpcoming(ScheduleEvent event, DateTime now) {
  final endsAt = event.end ?? event.start.add(const Duration(hours: 1));
  return endsAt.isAfter(now);
}

class _DayGroup {
  _DayGroup(this.day, this.events);
  final DateTime day;
  final List<ScheduleEvent> events;
}

List<_DayGroup> _groupUpcoming(List<ScheduleEvent> items, DateTime now) {
  final upcoming = items.where((e) => _isUpcoming(e, now)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final groups = <_DayGroup>[];
  for (final event in upcoming) {
    final day = DateTime(event.start.year, event.start.month, event.start.day);
    if (groups.isNotEmpty && groups.last.day == day) {
      groups.last.events.add(event);
    } else {
      groups.add(_DayGroup(day, [event]));
    }
  }
  return groups;
}

List<ScheduleEvent> _sortedPast(List<ScheduleEvent> items, DateTime now) {
  final past = items.where((e) => !_isUpcoming(e, now)).toList()
    ..sort((a, b) => b.start.compareTo(a.start));
  return past;
}

String _dayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Today';
  if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${weekdays[day.weekday - 1]} ${day.day} ${months[day.month - 1]}';
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Text(
        label,
        style: AppText.meta.copyWith(
          color: AppColors.ink3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(
    this.event, {
    required this.dimmed,
    required this.onTap,
    required this.onDelete,
  });

  final ScheduleEvent event;
  final bool dimmed;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('event-row-${event.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 14),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppColors.flareText,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    clockLabel(event),
                    style: AppText.meta.copyWith(
                      color: dimmed ? AppColors.ink3 : AppColors.ink2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: dimmed ? AppColors.ink3 : AppColors.ink,
                        ),
                      ),
                      if (event.location != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          event.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.meta.copyWith(color: AppColors.ink3),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
