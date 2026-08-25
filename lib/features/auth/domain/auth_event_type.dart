/// The kinds of authentication-related events ZIVO records to the backend.
///
/// Events live in the append-only `users/{uid}/authEvents` log and are the
/// audit trail behind [AccountAuthMetadata]'s summary fields:
///
/// - `accountCreated` — the auth account came into existence (first-ever
///   sign-in for a federated provider, or an explicit email sign-up).
/// - `signIn` — every subsequent successful authentication.
/// - `signOut` — an explicit session end from this device.
/// - `emailOtpSent` — a verification code was actually emailed (server-written).
/// - `emailVerified` — a code verified successfully; email became trusted
///   (server-written).
/// - `passwordChanged` — the password was set/changed (server-written once a
///   password-management flow lands; reserved today so the log's vocabulary is
///   stable before then).
enum AuthEventType {
  accountCreated,
  signIn,
  signOut,
  emailOtpSent,
  emailVerified,
  passwordChanged;

  /// The wire name persisted in Firestore (`type`). Stable by contract —
  /// never rename a value without a migration.
  String get id => name;

  /// Parses a persisted `type` back into an event kind. Unknown values
  /// (an older client reading a newer backend) resolve to null rather than
  /// throwing, so one stale build can't crash on fresh data.
  static AuthEventType? tryParse(Object? value) => switch (value) {
    final String s => values.asNameMap()[s],
    _ => null,
  };
}
