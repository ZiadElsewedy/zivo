/// The Admin Console's read models. Everything here is what the admin
/// callables return — counts, dates, platform and status — and nothing
/// else: the server's projection (`functions/admin/queries.js`) is the
/// privacy boundary, and these types mirror it rather than widen it.
library;

/// The dashboard's numbers.
class AdminOverview {
  const AdminOverview({
    required this.generatedAt,
    required this.totalUsers,
    required this.newToday,
    required this.newThisWeek,
    required this.activeToday,
    required this.active7d,
    required this.active30d,
    required this.withWorkoutPlan,
    required this.disabled,
    required this.workoutsCompletedToday,
    required this.aiRequestsToday,
    required this.ai30d,
    required this.aiAllTime,
    required this.series,
  });

  final DateTime generatedAt;
  final int totalUsers;
  final int newToday;
  final int newThisWeek;
  final int activeToday;
  final int active7d;
  final int active30d;
  final int withWorkoutPlan;
  final int disabled;
  final int workoutsCompletedToday;
  final int aiRequestsToday;
  final AiTotals ai30d;
  final AiTotals aiAllTime;

  /// Oldest day first.
  final List<AdminDayPoint> series;

  factory AdminOverview.fromJson(Map<String, dynamic> j) {
    final users = _map(j['users']);
    final workouts = _map(j['workouts']);
    final ai = _map(j['ai']);
    return AdminOverview(
      generatedAt: _date(j['generatedAt']) ?? DateTime.now(),
      totalUsers: _int(users['total']),
      newToday: _int(users['newToday']),
      newThisWeek: _int(users['newThisWeek']),
      activeToday: _int(users['activeToday']),
      active7d: _int(users['active7d']),
      active30d: _int(users['active30d']),
      withWorkoutPlan: _int(users['withWorkoutPlan']),
      disabled: _int(users['disabled']),
      workoutsCompletedToday: _int(workouts['completedToday']),
      aiRequestsToday: _int(ai['requestsToday']),
      ai30d: AiTotals.fromJson(_map(ai['last30d'])),
      aiAllTime: AiTotals.fromJson(_map(ai['allTime'])),
      series: [
        for (final p in _list(j['series'])) AdminDayPoint.fromJson(_map(p)),
      ],
    );
  }
}

/// AI requests, tokens and estimated cost over some window.
class AiTotals {
  const AiTotals({
    required this.requests,
    required this.tokensIn,
    required this.tokensOut,
    required this.costUsd,
  });

  final int requests;
  final int tokensIn;
  final int tokensOut;

  /// Estimated at each answering model's list price when the request ran
  /// (`functions/ai/routing/models.js`) — not an invoice.
  final double costUsd;

  int get tokens => tokensIn + tokensOut;

  factory AiTotals.fromJson(Map<String, dynamic> j) => AiTotals(
    requests: _int(j['requests']),
    tokensIn: _int(j['tokensIn']),
    tokensOut: _int(j['tokensOut']),
    costUsd: _double(j['costUsd']),
  );
}

/// One local day of the dashboard's activity chart.
class AdminDayPoint {
  const AdminDayPoint({
    required this.day,
    required this.workoutsCompleted,
    required this.appOpens,
  });

  final DateTime day;
  final int workoutsCompleted;
  final int appOpens;

  factory AdminDayPoint.fromJson(Map<String, dynamic> j) => AdminDayPoint(
    day: _date(j['day']) ?? DateTime.now(),
    workoutsCompleted: _int(j['workout_completed']),
    appOpens: _int(j['app_opened']),
  );
}

enum AdminAccountStatus { active, disabled }

/// One row of the users table.
class AdminUserRow {
  const AdminUserRow({
    required this.uid,
    required this.displayName,
    required this.emailMasked,
    required this.createdAt,
    required this.lastActiveAt,
    required this.status,
    required this.platform,
    required this.appVersion,
    required this.hasWorkoutPlan,
    required this.workoutsCompleted,
    required this.aiRequests,
    required this.aiTokens,
    required this.lastEvent,
  });

  final String uid;
  final String? displayName;

  /// `zi**@gmail.com` — masked on the server; the full address never
  /// reaches the console.
  final String? emailMasked;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;
  final AdminAccountStatus status;
  final String? platform;
  final String? appVersion;
  final bool hasWorkoutPlan;
  final int workoutsCompleted;
  final int aiRequests;
  final int aiTokens;
  final AdminEventRef? lastEvent;

  factory AdminUserRow.fromJson(Map<String, dynamic> j) => AdminUserRow(
    uid: j['uid'] as String? ?? '',
    displayName: j['displayName'] as String?,
    emailMasked: j['emailMasked'] as String?,
    createdAt: _date(j['createdAt']),
    lastActiveAt: _date(j['lastActiveAt']),
    status: _status(j['status']),
    platform: j['platform'] as String?,
    appVersion: j['appVersion'] as String?,
    hasWorkoutPlan: j['hasWorkoutPlan'] == true,
    workoutsCompleted: _int(j['workoutsCompleted']),
    aiRequests: _int(j['aiRequests']),
    aiTokens: _int(j['aiTokens']),
    lastEvent: j['lastEvent'] is Map
        ? AdminEventRef.fromJson(_map(j['lastEvent']))
        : null,
  );
}

/// An event name and when it happened.
class AdminEventRef {
  const AdminEventRef({required this.name, required this.at});

  final String name;
  final DateTime? at;

  factory AdminEventRef.fromJson(Map<String, dynamic> j) =>
      AdminEventRef(name: j['name'] as String? ?? '', at: _date(j['at']));
}

/// One user's focused overview.
class AdminUserDetail {
  const AdminUserDetail({
    required this.row,
    required this.isAdmin,
    required this.providers,
    required this.lastSignInAt,
    required this.workoutPlans,
    required this.workoutPlanCreatedAt,
    required this.workoutsStarted,
    required this.workoutsAbandoned,
    required this.lastWorkoutAt,
    required this.aiTokensIn,
    required this.aiTokensOut,
    required this.aiCostUsd,
    required this.features,
    required this.recentEvents,
  });

  final AdminUserRow row;

  /// An admin account can't be disabled or deleted from the console.
  final bool isAdmin;
  final List<String> providers;
  final DateTime? lastSignInAt;
  final int workoutPlans;
  final DateTime? workoutPlanCreatedAt;
  final int workoutsStarted;
  final int workoutsAbandoned;
  final DateTime? lastWorkoutAt;
  final int aiTokensIn;
  final int aiTokensOut;
  final double aiCostUsd;

  /// Feature-use counters keyed by the server's usage key (`app_opened`,
  /// `ai_chat`, `diet_imported`, …).
  final Map<String, int> features;
  final List<AdminActivityEvent> recentEvents;

  factory AdminUserDetail.fromJson(Map<String, dynamic> j) => AdminUserDetail(
    row: AdminUserRow.fromJson(j),
    isAdmin: j['isAdmin'] == true,
    providers: [
      for (final p in _list(j['providers']))
        if (p is String) p,
    ],
    lastSignInAt: _date(j['lastSignInAt']),
    workoutPlans: _int(j['workoutPlans']),
    workoutPlanCreatedAt: _date(j['workoutPlanCreatedAt']),
    workoutsStarted: _int(j['workoutsStarted']),
    workoutsAbandoned: _int(j['workoutsAbandoned']),
    lastWorkoutAt: _date(j['lastWorkoutAt']),
    aiTokensIn: _int(j['aiTokensIn']),
    aiTokensOut: _int(j['aiTokensOut']),
    aiCostUsd: _double(j['aiCostUsd']),
    features: {
      for (final e in _map(j['features']).entries) e.key: _int(e.value),
    },
    recentEvents: [
      for (final e in _list(j['recentEvents']))
        AdminActivityEvent.fromJson(_map(e)),
    ],
  );
}

/// One product event.
class AdminActivityEvent {
  const AdminActivityEvent({
    required this.id,
    required this.uid,
    required this.name,
    required this.at,
    required this.props,
    this.displayName,
  });

  final String id;
  final String uid;
  final String name;
  final DateTime? at;

  /// Small, whitelisted properties (platform, feature, token counts…).
  final Map<String, Object> props;
  final String? displayName;

  factory AdminActivityEvent.fromJson(Map<String, dynamic> j) =>
      AdminActivityEvent(
        id: j['id'] as String? ?? '',
        uid: j['uid'] as String? ?? '',
        name: j['name'] as String? ?? '',
        at: _date(j['at']),
        props: {
          for (final e in _map(j['props']).entries)
            if (e.value is num || e.value is String || e.value is bool)
              e.key: e.value as Object,
        },
        displayName: j['displayName'] as String?,
      );
}

/// The activity page: totals per event over the window + the recent feed.
class AdminActivity {
  const AdminActivity({
    required this.days,
    required this.totals,
    required this.events,
    required this.nextCursor,
  });

  final int days;
  final Map<String, int> totals;
  final List<AdminActivityEvent> events;
  final String? nextCursor;

  factory AdminActivity.fromJson(Map<String, dynamic> j) => AdminActivity(
    days: _int(j['days']),
    totals: {for (final e in _map(j['totals']).entries) e.key: _int(e.value)},
    events: [
      for (final e in _list(j['events'])) AdminActivityEvent.fromJson(_map(e)),
    ],
    nextCursor: j['nextCursor'] as String?,
  );
}

/// Which slice of users the table shows.
enum AdminSegment { all, active, inactive, newUsers }

/// A single attribute filter (the server allows one at a time, each backed
/// by an index).
sealed class AdminUserFilter {
  const AdminUserFilter();

  String get field;
  Object get value;
}

class HasPlanFilter extends AdminUserFilter {
  const HasPlanFilter(this.hasPlan);
  final bool hasPlan;
  @override
  String get field => 'hasWorkoutPlan';
  @override
  Object get value => hasPlan;
}

class StatusFilter extends AdminUserFilter {
  const StatusFilter(this.status);
  final AdminAccountStatus status;
  @override
  String get field => 'status';
  @override
  Object get value => status.name;
}

class PlatformFilter extends AdminUserFilter {
  const PlatformFilter(this.platform);
  final String platform;
  @override
  String get field => 'platform';
  @override
  Object get value => platform;
}

class AppVersionFilter extends AdminUserFilter {
  const AppVersionFilter(this.version);
  final String version;
  @override
  String get field => 'appVersion';
  @override
  Object get value => version;
}

/// A users-table request.
class AdminUserQuery {
  const AdminUserQuery({
    this.segment = AdminSegment.all,
    this.filter,
    this.search,
    this.cursor,
    this.pageSize = 25,
  });

  final AdminSegment segment;
  final AdminUserFilter? filter;
  final String? search;
  final String? cursor;
  final int pageSize;

  Map<String, dynamic> toJson() => {
    'segment': switch (segment) {
      AdminSegment.all => 'all',
      AdminSegment.active => 'active',
      AdminSegment.inactive => 'inactive',
      AdminSegment.newUsers => 'new',
    },
    if (filter != null)
      'filter': {'field': filter!.field, 'value': filter!.value},
    if (search != null && search!.trim().isNotEmpty) 'search': search!.trim(),
    if (cursor != null) 'cursor': cursor,
    'pageSize': pageSize,
  };
}

class AdminUserPage {
  const AdminUserPage({required this.users, required this.nextCursor});
  final List<AdminUserRow> users;
  final String? nextCursor;

  factory AdminUserPage.fromJson(Map<String, dynamic> j) => AdminUserPage(
    users: [for (final u in _list(j['users'])) AdminUserRow.fromJson(_map(u))],
    nextCursor: j['nextCursor'] as String?,
  );
}

/// Progress of a summary rebuild pass.
class AdminRebuildProgress {
  const AdminRebuildProgress({
    required this.processed,
    required this.nextPageToken,
  });
  final int processed;
  final String? nextPageToken;
}

// --- tolerant JSON readers -------------------------------------------------

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.map((k, v) => MapEntry(k.toString(), v)) : const {};

List<Object?> _list(Object? v) => v is List ? v : const [];

int _int(Object? v) => v is num ? v.round() : 0;

double _double(Object? v) => v is num ? v.toDouble() : 0;

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

AdminAccountStatus _status(Object? v) =>
    v == 'disabled' ? AdminAccountStatus.disabled : AdminAccountStatus.active;
