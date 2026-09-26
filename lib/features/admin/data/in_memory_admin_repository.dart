import '../domain/admin_models.dart';
import '../domain/admin_repository.dart';

/// Offline/test [AdminRepository]: serves the rows it was given, filtering
/// and paging them the way the server does. It holds no real accounts — an
/// offline run (`USE_FIRESTORE=false`) has no admin to show.
class InMemoryAdminRepository implements AdminRepository {
  InMemoryAdminRepository({
    List<AdminUserRow> users = const [],
    List<AdminActivityEvent> events = const [],
    DateTime Function()? now,
  }) : _users = [...users],
       _events = [...events],
       _now = now ?? DateTime.now;

  final List<AdminUserRow> _users;
  final List<AdminActivityEvent> _events;
  final DateTime Function() _now;

  /// Uids deleted through [deleteUser], for tests.
  final List<String> deleted = [];

  @override
  Future<AdminOverview> overview() async {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    bool since(DateTime? d, DateTime t) => d != null && !d.isBefore(t);
    final week = now.subtract(const Duration(days: 7));
    return AdminOverview(
      generatedAt: now,
      totalUsers: _users.length,
      newToday: _users.where((u) => since(u.createdAt, today)).length,
      newThisWeek: _users.where((u) => since(u.createdAt, week)).length,
      activeToday: _users.where((u) => since(u.lastActiveAt, today)).length,
      active7d: _users.where((u) => since(u.lastActiveAt, week)).length,
      active30d: _users
          .where(
            (u) =>
                since(u.lastActiveAt, now.subtract(const Duration(days: 30))),
          )
          .length,
      withWorkoutPlan: _users.where((u) => u.hasWorkoutPlan).length,
      disabled: _users
          .where((u) => u.status == AdminAccountStatus.disabled)
          .length,
      workoutsCompletedToday: _events
          .where((e) => e.name == 'workout_completed' && since(e.at, today))
          .length,
      aiRequestsToday: _events
          .where((e) => e.name == 'ai_request' && since(e.at, today))
          .length,
      ai30d: const AiTotals(requests: 0, tokensIn: 0, tokensOut: 0, costUsd: 0),
      aiAllTime: AiTotals(
        requests: _users.fold(0, (n, u) => n + u.aiRequests),
        tokensIn: _users.fold(0, (n, u) => n + u.aiTokens),
        tokensOut: 0,
        costUsd: 0,
      ),
      series: [
        for (var i = 13; i >= 0; i--)
          AdminDayPoint(
            day: today.subtract(Duration(days: i)),
            workoutsCompleted: 0,
            appOpens: 0,
          ),
      ],
    );
  }

  @override
  Future<AdminUserPage> listUsers(AdminUserQuery query) async {
    final now = _now();
    Iterable<AdminUserRow> rows = _users;
    final search = query.search?.trim().toLowerCase();
    if (search != null && search.isNotEmpty) {
      rows = rows.where(
        (u) =>
            u.uid == search ||
            (u.displayName ?? '').toLowerCase().startsWith(search),
      );
    } else {
      rows = switch (query.segment) {
        AdminSegment.all => rows,
        AdminSegment.active => rows.where(
          (u) =>
              u.lastActiveAt?.isAfter(now.subtract(const Duration(days: 7))) ??
              false,
        ),
        AdminSegment.inactive => rows.where(
          (u) =>
              u.lastActiveAt?.isBefore(
                now.subtract(const Duration(days: 30)),
              ) ??
              true,
        ),
        AdminSegment.newUsers => rows.where(
          (u) =>
              u.createdAt?.isAfter(now.subtract(const Duration(days: 7))) ??
              false,
        ),
      };
      final f = query.filter;
      if (f != null) rows = rows.where((u) => _matches(u, f));
    }
    final sorted = rows.toList()
      ..sort(
        (a, b) => (b.lastActiveAt ?? DateTime(0)).compareTo(
          a.lastActiveAt ?? DateTime(0),
        ),
      );
    var start = 0;
    if (query.cursor != null) {
      start = sorted.indexWhere((u) => u.uid == query.cursor) + 1;
    }
    final page = sorted.skip(start).take(query.pageSize).toList();
    final more = start + page.length < sorted.length;
    return AdminUserPage(
      users: page,
      nextCursor: more && page.isNotEmpty ? page.last.uid : null,
    );
  }

  bool _matches(AdminUserRow u, AdminUserFilter f) => switch (f) {
    HasPlanFilter(:final hasPlan) => u.hasWorkoutPlan == hasPlan,
    StatusFilter(:final status) => u.status == status,
    PlatformFilter(:final platform) => u.platform == platform,
    AppVersionFilter(:final version) => u.appVersion == version,
  };

  @override
  Future<AdminUserDetail> user(String uid) async {
    final row = _users.firstWhere(
      (u) => u.uid == uid,
      orElse: () => throw const AdminFailure('That account doesn\'t exist.'),
    );
    return AdminUserDetail(
      row: row,
      isAdmin: false,
      providers: const ['password'],
      lastSignInAt: row.lastActiveAt,
      workoutPlans: row.hasWorkoutPlan ? 1 : 0,
      workoutPlanCreatedAt: null,
      workoutsStarted: row.workoutsCompleted,
      workoutsAbandoned: 0,
      lastWorkoutAt: null,
      aiTokensIn: row.aiTokens,
      aiTokensOut: 0,
      aiCostUsd: 0,
      features: const {},
      recentEvents: _events.where((e) => e.uid == uid).toList(),
    );
  }

  @override
  Future<AdminActivity> activity({
    int days = 7,
    String? eventName,
    String? cursor,
  }) async {
    final events = eventName == null
        ? _events
        : _events.where((e) => e.name == eventName).toList();
    final totals = <String, int>{};
    for (final e in _events) {
      totals[e.name] = (totals[e.name] ?? 0) + 1;
    }
    return AdminActivity(
      days: days,
      totals: totals,
      events: events,
      nextCursor: null,
    );
  }

  @override
  Future<void> setDisabled(String uid, {required bool disabled}) async {
    final i = _users.indexWhere((u) => u.uid == uid);
    if (i < 0) throw const AdminFailure('That account doesn\'t exist.');
    final u = _users[i];
    _users[i] = AdminUserRow(
      uid: u.uid,
      displayName: u.displayName,
      emailMasked: u.emailMasked,
      createdAt: u.createdAt,
      lastActiveAt: u.lastActiveAt,
      status: disabled
          ? AdminAccountStatus.disabled
          : AdminAccountStatus.active,
      platform: u.platform,
      appVersion: u.appVersion,
      hasWorkoutPlan: u.hasWorkoutPlan,
      workoutsCompleted: u.workoutsCompleted,
      aiRequests: u.aiRequests,
      aiTokens: u.aiTokens,
      lastEvent: u.lastEvent,
    );
  }

  @override
  Future<void> deleteUser(String uid) async {
    _users.removeWhere((u) => u.uid == uid);
    deleted.add(uid);
  }

  @override
  Future<AdminRebuildProgress> rebuildSummaries({String? pageToken}) async =>
      AdminRebuildProgress(processed: _users.length, nextPageToken: null);
}
