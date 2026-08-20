import 'package:shared_preferences/shared_preferences.dart';

/// Persists, **per device**, whether the cloud backup provider has been
/// connected here, which cloud account, and — critically — which ZIVO account
/// connected it. This is deliberately device-local (not synced through
/// Firestore): "I want backup" is an account intention, but "this phone is
/// authorized" is a per-device fact. Recording the owning ZIVO account lets the
/// service refuse a stale connection after a sign-out / account switch, so one
/// account can never use another's backup connection.
class DriveConnectionStore {
  static const _kConnected = 'zivo.drive.device_connected';
  static const _kEmail = 'zivo.drive.device_email';
  static const _kOwner = 'zivo.drive.owner_uid';

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

  Future<void> setConnected({required String email, required String ownerUid}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConnected, true);
    await prefs.setString(_kEmail, email);
    await prefs.setString(_kOwner, ownerUid);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kConnected);
    await prefs.remove(_kEmail);
    await prefs.remove(_kOwner);
  }
}
