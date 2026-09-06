import 'package:shared_preferences/shared_preferences.dart';

/// Persists, **per device**, whether the cloud backup provider has been
/// connected here, which cloud account, and — critically — which ZIVO account
/// connected it. This is deliberately device-local (not synced through
/// Firestore): "I want backup" is an account intention, but "this phone is
/// authorized" is a per-device fact. Recording the owning ZIVO account lets the
/// service refuse a stale connection after a sign-out / account switch, so one
/// account can never use another's backup connection.
///
/// The Google account is recorded twice, for two different jobs: [email] is
/// for display, and [accountKey] — the stable Google account id — is the one
/// every correctness decision uses. Emails get renamed and reused; an account
/// id does not, and a stored file id is only meaningful alongside the account
/// key it was minted in.
class DriveConnectionStore {
  static const _kConnected = 'zivo.drive.device_connected';
  static const _kEmail = 'zivo.drive.device_email';
  static const _kOwner = 'zivo.drive.owner_uid';
  static const _kAccountKey = 'zivo.drive.account_key';

  Future<bool> isConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kConnected) ?? false;
  }

  Future<String?> email() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEmail);
  }

  /// The ZIVO account uid that connected this device, or null.
  Future<String?> ownerUid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kOwner);
  }

  /// The stable Google account id this device is connected to, or null — null
  /// on a connection made before this was recorded, which reads as *unknown*
  /// rather than as any particular account.
  Future<String?> accountKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAccountKey);
  }

  Future<void> setConnected({
    required String email,
    required String ownerUid,
    required String accountKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConnected, true);
    await prefs.setString(_kEmail, email);
    await prefs.setString(_kOwner, ownerUid);
    await prefs.setString(_kAccountKey, accountKey);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kConnected);
    await prefs.remove(_kEmail);
    await prefs.remove(_kOwner);
    await prefs.remove(_kAccountKey);
  }
}
