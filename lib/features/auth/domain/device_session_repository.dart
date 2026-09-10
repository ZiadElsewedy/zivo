import 'active_session.dart';

/// The persistence seam for the single-device session ledger
/// (`users/{uid}/session/current`). Backed by Firestore in production and by an
/// in-memory map offline/in tests — the same split every other repository uses.
abstract interface class DeviceSessionRepository {
  /// Atomically makes [session] the account's one active session, replacing any
  /// previous one. A single-document write, so two devices racing to activate
  /// resolve to exactly one winner (last write wins) — never a half-state.
  Future<void> activate(String uid, ActiveSession session);

  /// The account's current active session as it changes, so a device can notice
  /// the instant another one takes over. Emits null when no session is on record.
  Stream<ActiveSession?> watch(String uid);
}
