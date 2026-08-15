import '../../schedule/domain/event_time.dart';
import '../../schedule/domain/schedule_event.dart';
import '../domain/today_snapshot.dart';

/// Maps a schedule event into the Today Now/Next view model.
NowNext nowNextFromEvent(ScheduleEvent e, DateTime now) {
  return NowNext(
    kind: e.label ?? 'Event',
    time: eventTimeLabel(e, now),
    title: e.title,
    detail: e.location ?? '',
  );
}
