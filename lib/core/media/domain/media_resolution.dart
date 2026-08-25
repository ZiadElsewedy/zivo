import 'dart:io';

/// How a stored media reference stands **on this device** — the honest
/// three-state answer a read-side widget (see `MediaImage`) needs in order to
/// render without lying:
///
/// - [onDevice] — bytes are here; render them.
/// - [cloudOnly] — not local, but a backup copy exists remotely, so it IS
///   fetchable (and [MediaService] fetches it automatically when a session is
///   live). A tile in this state is "on its way", never an error.
/// - [nowhere] — neither local nor backed up anywhere this device can reach.
///   This is the photo captured on another device that was never backed up:
///   no retry can succeed until some other device uploads it, so UI must NOT
///   offer a tap-to-retry that would always fail — it should say, honestly,
///   where the photo actually lives.
enum MediaAvailability { onDevice, cloudOnly, nowhere }

/// The result of resolving a reference through [MediaService].
final class MediaResolution {
  const MediaResolution(this.availability, {this.file});

  final MediaAvailability availability;

  /// The resolved file — non-null exactly when [availability] is
  /// [MediaAvailability.onDevice].
  final File? file;

  bool get hasBytes => file != null;
}
