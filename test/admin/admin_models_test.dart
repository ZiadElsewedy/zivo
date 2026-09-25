import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/admin/domain/admin_models.dart';

void main() {
  test('overview parses the server shape and tolerates gaps', () {
    final o = AdminOverview.fromJson({
      'generatedAt': '2026-09-25T12:00:00.000Z',
      'users': {'total': 12, 'active7d': 5, 'withWorkoutPlan': 3},
      'workouts': {'completedToday': 2},
      'ai': {
        'requestsToday': 4,
        'last30d': {
          'requests': 40,
          'tokensIn': 1000,
          'tokensOut': 250,
          'costUsd': 0.42,
        },
        'allTime': {},
      },
      'series': [
        {
          'day': '2026-09-24T00:00:00.000Z',
          'workout_completed': 1,
          'app_opened': 7,
        },
      ],
    });
    expect(o.totalUsers, 12);
    expect(o.active7d, 5);
    expect(o.newToday, 0); // absent → 0, never a crash
    expect(o.ai30d.tokens, 1250);
    expect(o.ai30d.costUsd, 0.42);
    expect(o.aiAllTime.requests, 0);
    expect(o.series.single.appOpens, 7);
  });

  test('a user row reads status, plan and last event', () {
    final r = AdminUserRow.fromJson({
      'uid': 'u1',
      'displayName': 'Sara',
      'emailMasked': 'sa**@x.com',
      'status': 'disabled',
      'hasWorkoutPlan': true,
      'workoutsCompleted': 9,
      'lastEvent': {
        'name': 'workout_completed',
        'at': '2026-09-25T10:00:00.000Z',
      },
    });
    expect(r.status, AdminAccountStatus.disabled);
    expect(r.hasWorkoutPlan, isTrue);
    expect(r.lastEvent?.name, 'workout_completed');
    expect(r.createdAt, isNull);
  });

  test('queries serialize the one filter the server allows', () {
    final q = AdminUserQuery(
      segment: AdminSegment.newUsers,
      filter: const HasPlanFilter(false),
      search: '  ',
      cursor: 'abc',
    ).toJson();
    expect(q['segment'], 'new');
    expect(q['filter'], {'field': 'hasWorkoutPlan', 'value': false});
    expect(q.containsKey('search'), isFalse); // blank search is no search
    expect(q['cursor'], 'abc');
    expect(
      const AdminUserQuery(
        filter: StatusFilter(AdminAccountStatus.disabled),
      ).toJson()['filter'],
      {'field': 'status', 'value': 'disabled'},
    );
  });

  test('event props keep only scalar values', () {
    final e = AdminActivityEvent.fromJson({
      'id': 'e1',
      'uid': 'u1',
      'name': 'ai_request',
      'props': {
        'tokensIn': 5,
        'feature': 'chat',
        'nested': {'x': 1},
      },
    });
    expect(e.props, {'tokensIn': 5, 'feature': 'chat'});
  });
}
