import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/train_tokens.dart';

/// The artwork tile behind `MusicPlayerPage`'s big square. Prefers [bytes]
/// (what `SpotifyMusicController` actually populates — App Remote's
/// `getImage` returns raw bytes, not a URL) over [url].
///
/// **With no artwork it draws no tile at all** — just a centred glyph over
/// whatever the player is already painting behind it (the colour-adaptive
/// wash). It used to fill the full square with an opaque plate, which at the
/// player's size read as a large empty box: the "container waiting on data"
/// the identity doc warns against. A track with no cover isn't loading and
/// isn't broken, so the honest shape is an absence, not a placeholder.
///
/// The opaque backdrop is kept only where an image is genuinely on its way,
/// so a decoding frame doesn't flash the wash through.
class MusicArtwork extends StatelessWidget {
  const MusicArtwork({
    required this.bytes,
    required this.url,
    required this.size,
    required this.iconSize,
    required this.borderRadius,
    super.key,
  });

  final Uint8List? bytes;
  final String? url;
  final double size;
  final double iconSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final glyph = SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(AppIcons.music, size: iconSize, color: TrainColors.ink3),
      ),
    );

    if (bytes == null && url == null) return glyph;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: TrainColors.raisedStrong,
          child: bytes != null
              ? Image.memory(
                  bytes!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => glyph,
                )
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => glyph,
                ),
        ),
      ),
    );
  }
}
