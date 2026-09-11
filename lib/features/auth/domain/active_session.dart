/// The one session currently allowed to act on an account.
///
/// ZIVO enforces **one account = one active device**: signing in (or launching)
/// on a device writes a fresh [ActiveSession] to `users/{uid}/session/current`,
/// atomically replacing whatever was there. Every device watches that document;
/// the moment its own [sessionId] is no longer the one on record, it is stale
/// and must sign out. The uid alone can't do this — Firebase Auth keeps every
/// device's token valid independently — so this small server-owned record is
/// the source of truth instead. See [DeviceSessionGuard].
class ActiveSession {
  const ActiveSession({
    required this.sessionId,
    required this.deviceId,
    required this.platform,
  });

  /// Unique per sign-in/activation. This is the field correctness rides on: a
  /// device is the active one iff its local [sessionId] equals the one stored.
  final String sessionId;

  /// Stable per install, so the record can name *which* device won.
  final String deviceId;

  /// `ios` / `android` / `web` — for display and debugging, never for the
  /// active-vs-stale decision.
  final String platform;
}
