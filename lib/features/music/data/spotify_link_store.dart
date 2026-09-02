import 'package:shared_preferences/shared_preferences.dart';

/// Remembers, **per device**, that the user has connected this app to Spotify
/// here — the consent that lets [SpotifyMusicController] re-establish the App
/// Remote connection on its own at launch and on every resume.
///
/// Device-local on purpose, exactly like [DriveConnectionStore]: "I use
/// Spotify" is an account intention, but "this phone is authorized to talk to
/// the Spotify app installed on it" is a per-device fact, and App Remote
/// authorization is granted per device anyway.
///
/// It stores consent, not a credential — the PKCE token exchange lives inside
/// the Spotify SDK. Nothing secret goes in here.
class SpotifyLinkStore {
  static const _kLinked = 'zivo.spotify.device_linked';

  Future<bool> isLinked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kLinked) ?? false;
  }

  Future<void> setLinked(bool linked) async {
    final prefs = await SharedPreferences.getInstance();
    if (linked) {
      await prefs.setBool(_kLinked, true);
    } else {
      await prefs.remove(_kLinked);
    }
  }
}
