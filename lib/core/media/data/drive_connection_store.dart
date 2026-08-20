import 'package:shared_preferences/shared_preferences.dart';

/// Persists, **per device**, whether Google Drive has been connected here and
/// which Google account. This is deliberately device-local (not synced through
/// Firestore): "I want Drive backup" is an account intention, but "this phone
/// is authorized to talk to Drive" is a per-device fact. Keeping them separate
/// is what stops a second device from being nagged to sign in.
class DriveConnectionStore {
  static const _kConnected = 'zivo.drive.device_connected';
  static const _kEmail = 'zivo.drive.device_email';

  Future<bool> isConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kConnected) ?? false;
  }

  Future<String?> email() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEmail);
  }

  Future<void> setConnected(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConnected, true);
    await prefs.setString(_kEmail, email);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kConnected);
    await prefs.remove(_kEmail);
  }
}
