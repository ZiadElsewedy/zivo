import 'package:flutter/foundation.dart';

/// What kind of device audio is currently routing to — drives which glyph the
/// player's output row shows. Kept small and presentation-agnostic; the UI maps
/// each case to an icon.
enum AudioOutputKind {
  /// A Bluetooth device (AirPods, buds, a speaker paired over BT).
  bluetooth,

  /// A wired headset / headphones.
  headphones,

  /// An external / AirPlay / cast speaker.
  speaker,

  /// The phone's own speaker or earpiece.
  phone,

  /// Route unknown — the UI falls back to a neutral glyph.
  unknown,
}

/// The audio output the current track is playing through — "AirPods Pro · 72%"
/// in the design. A **pure domain value** (no colour, no widgets): the
/// controller port exposes it, the player renders it.
///
/// Deliberately nullable at the port: when nothing is known (no route info, or
/// a controller that can't report it) the UI shows *nothing* rather than a
/// guessed device — the handoff's "nothing shifts when a module is absent" rule.
@immutable
class AudioOutput {
  const AudioOutput({
    required this.name,
    this.kind = AudioOutputKind.unknown,
    this.batteryPercent,
  });

  /// Human-readable device name, e.g. "AirPods Pro". Shown verbatim.
  final String name;

  final AudioOutputKind kind;

  /// 0–100 battery for the device, or null when the platform doesn't report one
  /// (most wired/speaker routes). Null hides the battery pill; it never shows 0
  /// as "unknown".
  final int? batteryPercent;

  @override
  bool operator ==(Object other) =>
      other is AudioOutput &&
      other.name == name &&
      other.kind == kind &&
      other.batteryPercent == batteryPercent;

  @override
  int get hashCode => Object.hash(name, kind, batteryPercent);
}
