import 'account_auth_metadata.dart';
import 'auth_event.dart';
import 'auth_event_type.dart';

/// The seam between the app and wherever authentication activity — the
/// account summary plus its append-only event log — is persisted.
///
/// Split from [AuthRepository]'s session duties on purpose: auth *state*
/// (signing in/out) and auth *bookkeeping* (recording that it happened)
/// change for different reasons, and bookkeeping must never be able to fail
/// a sign-in. Implementations are expected to swallow their own errors.
abstract interface class AuthActivityRepository {
  /// Records that this account came into existence right now: stamps
  /// `createdAt`/`registered*` on `users/{uid}/auth/account` and appends an
  /// `accountCreated` event. Also writes the first sign-in fields, since a
  /// registration *is* the account's first successful authentication.
  Future<void> recordAccountCreated({
    required String uid,
    required String provider,
    required String platform,
  });

  /// Records a successful authentication on an existing account: advances
  /// `lastSignInAt`/`previousSignInAt`/`signInCount` atomically and appends a
  /// `signIn` event. When [fallbackCreatedAt] is supplied and the summary doc
  /// has no `createdAt` yet (e.g. the registration write was lost), it is
  /// backfilled from Firebase Auth's own server-side creation time.
  Future<void> recordSignIn({
    required String uid,
    required String provider,
    required String platform,
    DateTime? fallbackCreatedAt,
  });

  /// Appends a `signOut` event to the log.
  Future<void> recordSignOut({required String uid});

  /// Appends one raw [AuthEventType] to the log — the escape hatch used by
  /// server-adjacent flows and future event kinds (e.g. `passwordChanged`).
  Future<void> recordEvent({
    required String uid,
    required AuthEventType type,
    String? provider,
    String? platform,
  });

  /// Emits the current account-auth summary, or null when none exists yet,
  /// and every subsequent change.
  Stream<AccountAuthMetadata?> watchAccount(String uid);

  /// One-shot read of the account-auth summary, or null if none exists.
  Future<AccountAuthMetadata?> fetchAccount(String uid);

  /// Emits the most recent events, newest first, up to [limit].
  Stream<List<AuthEvent>> watchRecentEvents({required String uid, int limit});
}
