/// The account-level authentication summary for one user — the "state"
/// distilled from the `authEvents` fact log, kept in a single always-current
/// document at `users/{uid}/auth/account`.
///
/// This is what a future Settings > Account screen (or support tooling)
/// reads: one cheap document instead of a query over the event log. Every
/// timestamp answers a specific question:
///
/// - [createdAt]            — when did this account come into existence?
/// - [registeredVia]        — through which provider was it created?
/// - [lastSignInAt]         — when did they last authenticate?
/// - [previousSignInAt]     — the sign-in before that (device/session audits).
/// - [signInCount]          — how many successful authentications, ever.
/// - [emailVerifiedAt]      — when the email became trusted (server-written).
/// - [emailLastSentAt]      — when a verification code was last emailed
///   (server-written).
/// - [lastPasswordChangeAt] — when the password was last set/changed; null
///   until a password-management flow exists to write it.
///
/// All fields are nullable: a missing document or field means "not known
/// yet", never a zero date.
class AccountAuthMetadata {
  const AccountAuthMetadata({
    required this.uid,
    this.createdAt,
    this.registeredVia,
    this.registeredPlatform,
    this.lastSignInAt,
    this.lastSignInVia,
    this.lastSignInPlatform,
    this.previousSignInAt,
    this.signInCount = 0,
    this.emailVerifiedAt,
    this.emailLastSentAt,
    this.lastPasswordChangeAt,
  });

  /// The owning auth user (`users/{uid}` path root).
  final String uid;

  /// When the account was created (server clock).
  final DateTime? createdAt;

  /// The provider that created the account (`password`, `google.com`,
  /// `apple.com`).
  final String? registeredVia;

  /// The platform the account was created from (`ios`, `android`, …).
  final String? registeredPlatform;

  /// The most recent successful authentication (server clock).
  final DateTime? lastSignInAt;

  /// Provider used for the most recent sign-in.
  final String? lastSignInVia;

  /// Platform of the most recent sign-in.
  final String? lastSignInPlatform;

  /// The successful authentication immediately before [lastSignInAt].
  final DateTime? previousSignInAt;

  /// Total successful authentications since account creation.
  final int signInCount;

  /// When the email address became verified (server-written only).
  final DateTime? emailVerifiedAt;

  /// When the last verification email was sent (server-written only).
  final DateTime? emailLastSentAt;

  /// When the password was last changed (reserved; null today).
  final DateTime? lastPasswordChangeAt;

  @override
  bool operator ==(Object other) =>
      other is AccountAuthMetadata &&
      other.uid == uid &&
      other.createdAt == createdAt &&
      other.registeredVia == registeredVia &&
      other.registeredPlatform == registeredPlatform &&
      other.lastSignInAt == lastSignInAt &&
      other.lastSignInVia == lastSignInVia &&
      other.lastSignInPlatform == lastSignInPlatform &&
      other.previousSignInAt == previousSignInAt &&
      other.signInCount == signInCount &&
      other.emailVerifiedAt == emailVerifiedAt &&
      other.emailLastSentAt == emailLastSentAt &&
      other.lastPasswordChangeAt == lastPasswordChangeAt;

  @override
  int get hashCode => Object.hash(
    uid,
    createdAt,
    registeredVia,
    registeredPlatform,
    lastSignInAt,
    lastSignInVia,
    lastSignInPlatform,
    previousSignInAt,
    signInCount,
    emailVerifiedAt,
    emailLastSentAt,
    lastPasswordChangeAt,
  );

  @override
  String toString() =>
      'AccountAuthMetadata(uid: $uid, signInCount: $signInCount, '
      'createdAt: $createdAt)';
}
