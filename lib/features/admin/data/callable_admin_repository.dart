import 'package:cloud_functions/cloud_functions.dart';

import '../domain/admin_models.dart';
import '../domain/admin_repository.dart';

/// [AdminRepository] over the admin-only callables in `functions/admin/`.
///
/// Every call carries the signed-in admin's ID token; the server re-checks
/// the `admin` claim against the Auth record on each one, so this class
/// holds no authority of its own — a non-admin calling it gets
/// `permission-denied` and nothing else.
class CallableAdminRepository implements AdminRepository {
  CallableAdminRepository({FirebaseFunctions? functions})
    : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;

  // Resolved lazily so constructing the repository never touches Firebase
  // (the app builds it for every account, admin or not).
  FirebaseFunctions get _fns =>
      _functionsOverride ?? FirebaseFunctions.instance;

  @override
  Future<AdminOverview> overview() async => AdminOverview.fromJson(
    await _call('adminOverview', {
      'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
    }),
  );

  @override
  Future<AdminUserPage> listUsers(AdminUserQuery query) async =>
      AdminUserPage.fromJson(await _call('adminListUsers', query.toJson()));

  @override
  Future<AdminUserDetail> user(String uid) async =>
      AdminUserDetail.fromJson(await _call('adminGetUser', {'uid': uid}));

  @override
  Future<AdminActivity> activity({
    int days = 7,
    String? eventName,
    String? cursor,
  }) async => AdminActivity.fromJson(
    await _call('adminActivity', {
      'days': days,
      'name': ?eventName,
      'cursor': ?cursor,
    }),
  );

  @override
  Future<void> setDisabled(String uid, {required bool disabled}) =>
      _call('adminSetUserDisabled', {'uid': uid, 'disabled': disabled});

  @override
  Future<void> deleteUser(String uid) =>
      _call('adminDeleteUser', {'uid': uid, 'confirmUid': uid});

  @override
  Future<AdminRebuildProgress> rebuildSummaries({String? pageToken}) async {
    final j = await _call('adminRebuildSummaries', {'pageToken': ?pageToken});
    return AdminRebuildProgress(
      processed: (j['processed'] as num?)?.toInt() ?? 0,
      nextPageToken: j['nextPageToken'] as String?,
    );
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await _fns
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
          )
          .call<Object?>(data);
      final value = result.data;
      return value is Map
          ? value.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final reauth =
          e.code == 'failed-precondition' &&
          e.details is Map &&
          (e.details as Map)['reason'] == 'reauthRequired';
      throw AdminFailure(
        e.message ?? 'That didn\'t work. Try again.',
        reauthRequired: reauth,
      );
    } catch (_) {
      throw const AdminFailure('Couldn\'t reach ZIVO. Check your connection.');
    }
  }
}
