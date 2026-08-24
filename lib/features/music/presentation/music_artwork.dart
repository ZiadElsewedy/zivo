import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Shared artwork tile — `NowPlayingBar`'s mini square and
/// `MusicPlayerPage`'s big square, just different sizes. Prefers [bytes]
/// (what `SpotifyMusicController` actually populates — App Remote's
/// `getImage` returns raw bytes, not a URL) over [url], falling back to a
/// flat placeholder icon when neither is set or the source fails to
/// decode/load — the fake controller's demo tracks have neither, so this
/// also doubles as the no-artwork path's only exercise.
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
    final placeholder = Icon(Icons.music_note_rounded, size: iconSize, color: AppColors.ink3);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: AppColors.card,
          child: bytes != null
              ? Image.memory(
                  bytes!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder,
                )
              : url != null
              ? Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder,
                )
              : placeholder,
        ),
      ),
    );
  }
}
