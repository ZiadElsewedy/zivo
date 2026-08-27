import '../domain/account_auth_metadata.dart';
import '../domain/auth_activity_repository.dart';
import '../domain/auth_event.dart';
import '../domain/auth_event_type.dart';

/// The offline/dev stand-in for [AuthActivityRepository]: accepts every
/// recording call and does nothing. Bound when the app runs without
/// Firestore (`USE_FIRESTORE=false`) so auth bookkeeping simply vanishes
/// instead of erroring — mirroring how the in-memory feature repositories
/// replace their Firestore-backed counterparts.
class NoopAuthActivityRepository implements AuthActivityRepository {
  const NoopAuthActivityRepository();

  @override
  Future<void> recordAccountCreated({
    required String uid,
    required String provider,
    required String platform,
  }) async {}

  @override
  Future<void> recordSignIn({
    required String uid,
    required String provider,
    required String platform,
    DateTime? fallbackCreatedAt,
  }) async {}

  @override
  Future<void> recordSignOut({required String uid}) async {}

  @override
  Future<void> recordPasswordChanged({required String uid}) async {}

  @override
  Future<void> recordEvent({
    required String uid,
    required AuthEventType type,
    String? provider,
    String? platform,
  }) async {}

  @override
  Stream<AccountAuthMetadata?> watchAccount(String uid) =>
      const Stream.empty();

  @override
  Future<AccountAuthMetadata?> fetchAccount(String uid) async => null;

  @override
  Stream<List<AuthEvent>> watchRecentEvents({
    required String uid,
    int limit = 50,
  }) => Stream.value(const []);
}
