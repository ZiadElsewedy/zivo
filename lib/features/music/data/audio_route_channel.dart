import 'package:flutter/services.dart';

import '../domain/audio_output.dart';

/// Bridges the OS audio route — which speaker / headphones / Bluetooth device
/// sound is actually going to — into an [AudioOutput], via platform channels
/// implemented natively in `ios/Runner/AppDelegate.swift` (AVAudioSession) and
/// `android/.../MainActivity.kt` (AudioManager).
///
/// Deliberately defensive: any host WITHOUT the native side — the iOS
/// Simulator, a desktop/test host, an older OS — resolves cleanly to `null`
/// (via `MissingPluginException`/stream errors), so the player simply omits the
/// output row rather than crashing. This is why `FakeMusicController` (dev
/// default) never touches this class; only `SpotifyMusicController` does, and
/// only on a real device.
///
/// Channel contract (native → Dart), a map or null:
/// ```
/// { "name": String, "kind": "bluetooth"|"headphones"|"speaker"|"phone",
///   "battery": int? }   // battery omitted where the OS doesn't expose one
/// ```
class AudioRouteChannel {
  const AudioRouteChannel();

  static const MethodChannel _method = MethodChannel('zivo/audio_route');
  static const EventChannel _events = EventChannel('zivo/audio_route/events');

  /// The route right now — used for `initialData`/`currentOutput`. Returns null
  /// on any host without the native handler, or when nothing routable is active.
  Future<AudioOutput?> current() async {
    try {
      final map = await _method.invokeMapMethod<String, Object?>('current');
      return _fromMap(map);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Emits on every route change (plug/unplug, BT connect/disconnect). Stream
  /// errors — including a missing native handler — are swallowed to `null`
  /// updates, never surfaced as a crash.
  Stream<AudioOutput?> changes() => _events
      .receiveBroadcastStream()
      .map<AudioOutput?>(
        (event) =>
            event is Map ? _fromMap(Map<String, Object?>.from(event)) : null,
      )
      .handleError((Object _) {});

  static AudioOutput? _fromMap(Map<String, Object?>? map) {
    if (map == null) return null;
    final name = map['name'] as String?;
    if (name == null || name.isEmpty) return null;
    final battery = map['battery'] as int?;
    return AudioOutput(
      name: name,
      kind: _kind(map['kind'] as String?),
      batteryPercent: (battery != null && battery >= 0) ? battery : null,
    );
  }

  static AudioOutputKind _kind(String? raw) => switch (raw) {
    'bluetooth' => AudioOutputKind.bluetooth,
    'headphones' => AudioOutputKind.headphones,
    'speaker' => AudioOutputKind.speaker,
    'phone' => AudioOutputKind.phone,
    _ => AudioOutputKind.unknown,
  };
}
