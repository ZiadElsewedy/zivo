import 'package:shared_preferences/shared_preferences.dart';

/// What this device remembers about its Spotify link, read in one shot so the
/// controller never has to sequence two awaits before its first attach.
class SpotifyLink {
  const SpotifyLink({required this.linked, this.accessToken});

  /// Nothing stored — a fresh install, or a host with no prefs at all.
  static const none = SpotifyLink(linked: false);

  /// The user connected here at least once and has not disconnected.
  final bool linked;

  /// The App Remote access token captured on that connect, or null if this
  /// device has none (never connected, disconnected since, or Android — see
  /// [SpotifyLinkStore]).
  final String? accessToken;
}

/// Remembers, **per device**, that the user has connected this app to Spotify
/// here — and the App Remote access token that lets it re-attach to a running
/// Spotify **without opening it**.
///
/// Device-local on purpose, exactly like [DriveConnectionStore]: "I use
/// Spotify" is an account intention, but "this phone is authorized to talk to
/// the Spotify app installed on it" is a per-device fact, and App Remote
/// authorization is granted per device anyway.
///
/// ## Why a token lives here now
///
/// It used to store consent and nothing else, because the token exchange lived
/// inside the Spotify SDK. That was only true for the *authorizing* connect —
/// and on iOS the authorizing connect is `authorizeAndPlayURI`, which **opens
/// Spotify and starts playback**. Running that on every launch and resume is
/// what made the app drag Spotify open when the user only wanted to log a set.
/// The silent alternative (`SPTAppRemote.connect`) attaches to a Spotify that
/// is already running and fails harmlessly when it isn't — but it needs an
/// access token, and the only place to keep one across launches is here.
///
/// So this *is* a credential store now, and the doc says so rather than
/// pretending otherwise. What it holds is narrow: a Spotify **access** token
/// (no refresh token — the App Remote flow issues none), scoped to
/// `app-remote-control` and expiring in about an hour, which buys the holder
/// nothing but the ability to drive playback in the Spotify app on this very
/// device. It sits in the app's own sandboxed preferences, is never sent
/// anywhere, and is erased by [clear] the moment the user disconnects. If that
/// bar ever needs raising, the change is local: swap the two token methods
/// below onto the Keychain/Keystore.
class SpotifyLinkStore {
  static const _kLinked = 'zivo.spotify.device_linked';
  static const _kToken = 'zivo.spotify.access_token';

  Future<SpotifyLink> read() async {
    final prefs = await SharedPreferences.getInstance();
    return SpotifyLink(
      linked: prefs.getBool(_kLinked) ?? false,
      accessToken: prefs.getString(_kToken),
    );
  }

  Future<void> setLinked(bool linked) async {
    final prefs = await SharedPreferences.getInstance();
    if (linked) {
      await prefs.setBool(_kLinked, true);
    } else {
      await prefs.remove(_kLinked);
    }
  }

  Future<void> setAccessToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
  }

  /// Unlink: consent AND token go, so nothing can reattach afterwards.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLinked);
    await prefs.remove(_kToken);
  }
}
