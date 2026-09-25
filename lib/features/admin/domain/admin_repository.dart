import 'admin_models.dart';

/// The Admin Console's seam. Every method is a call to an admin-only
/// callable — the console never reads Firestore itself, so there is no
/// client path to anything the server's projection leaves out.
///
/// Implementations throw [AdminFailure] with a message safe to show.
abstract interface class AdminRepository {
  Future<AdminOverview> overview();

  Future<AdminUserPage> listUsers(AdminUserQuery query);

  Future<AdminUserDetail> user(String uid);

  /// [days] is 1, 7 or 30; [eventName] narrows the feed to one event.
  Future<AdminActivity> activity({
    int days = 7,
    String? eventName,
    String? cursor,
  });

  /// Suspends ([disabled] true) or re-enables an account.
  Future<void> setDisabled(String uid, {required bool disabled});

  /// Permanently deletes an account through the same server-side erasure as
  /// the user's own "Delete account". The admin must have reauthenticated
  /// moments before (the server checks).
  Future<void> deleteUser(String uid);

  /// One page of the server-side summary rebuild; call again with the
  /// returned token until it is null.
  Future<AdminRebuildProgress> rebuildSummaries({String? pageToken});
}

/// A refused or failed admin call.
class AdminFailure implements Exception {
  const AdminFailure(this.message, {this.reauthRequired = false});

  final String message;

  /// The server wants a fresh credential proof before this operation.
  final bool reauthRequired;

  @override
  String toString() => 'AdminFailure($message)';
}
