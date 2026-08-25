import 'auth_event_type.dart';

/// One entry in the append-only `users/{uid}/authEvents` log — a single,
/// timestamped authentication occurrence (a sign-in, an emailed code, a
/// verification, …).
///
/// Events are facts, not state: they are written once and never mutated, so
/// the type stays immutable and [occurredAt] is the only clock that matters.
class AuthEvent {
  const AuthEvent({
    required this.id,
    required this.type,
    this.occurredAt,
    this.provider,
    this.platform,
  });

  /// The Firestore document id (`users/{uid}/authEvents/{id}`).
  final String id;

  /// What happened. See [AuthEventType] for the vocabulary.
  final AuthEventType type;

  /// When it happened (server clock). Null only while the write's
  /// server-timestamp is still pending resolution.
  final DateTime? occurredAt;

  /// The auth provider involved, when one applies — Firebase Auth's canonical
  /// ids: `password`, `google.com`, `apple.com`. Server-written email events
  /// omit it (the account itself implies the address).
  final String? provider;

  /// The client platform that produced client-written events (`ios`,
  /// `android`, `macos`, `web`). Null for server-written events.
  final String? platform;

  @override
  bool operator ==(Object other) =>
      other is AuthEvent &&
      other.id == id &&
      other.type == type &&
      other.occurredAt == occurredAt &&
      other.provider == provider &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(id, type, occurredAt, provider, platform);

  @override
  String toString() =>
      'AuthEvent(${type.id}, at: $occurredAt, provider: $provider)';
}
