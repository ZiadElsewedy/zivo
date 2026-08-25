import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';
import 'music_artwork.dart';
import 'music_player_page.dart';

/// The mini "now playing" bar mounted above the bottom nav (see
/// `home_shell.dart`, which only mounts this when `kMusicEnabled`) —
/// renders nothing until there's actually something to show: connected AND
/// a track loaded. Tapping the bar (anywhere but the two controls) opens
/// the full [MusicPlayerPage].
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({required this.controller, super.key});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MusicConnection>(
      stream: controller.connection,
      initialData: controller.currentConnection,
      builder: (context, connectionSnap) {
        if (connectionSnap.data != MusicConnection.connected) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<NowPlaying?>(
          stream: controller.nowPlaying,
          initialData: controller.currentNowPlaying,
          builder: (context, snap) {
            final playing = snap.data;
            if (playing == null) return const SizedBox.shrink();
            return _Bar(controller: controller, playing: playing);
          },
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.controller, required this.playing});

  final MusicController controller;
  final NowPlaying playing;

  @override
  Widget build(BuildContext context) {
    final fraction = playing.duration.inMilliseconds <= 0
        ? 0.0
        : (playing.position.inMilliseconds / playing.duration.inMilliseconds)
              .clamp(0.0, 1.0);
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MusicPlayerPage(controller: controller),
              fullscreenDialog: true,
            ),
          ),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    MusicArtwork(
                      bytes: playing.artworkBytes,
                      url: playing.artworkUrl,
                      size: 36,
                      iconSize: 18,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            playing.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.rowTitle.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            playing.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.meta.copyWith(fontSize: 12, color: AppColors.ink3),
                          ),
                        ],
                      ),
                    ),
                    PressableScale(
                      enabled: playing.hasControl,
                      child: IconButton(
                        splashRadius: 20,
                        onPressed: !playing.hasControl
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                playing.isPaused ? controller.play() : controller.pause();
                              },
                        icon: Icon(
                          playing.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          color: playing.hasControl ? AppColors.ink : AppColors.ink3,
                        ),
                      ),
                    ),
                    PressableScale(
                      enabled: playing.hasControl,
                      child: IconButton(
                        splashRadius: 20,
                        onPressed: !playing.hasControl
                            ? null
                            : () {
                                HapticFeedback.lightImpact();
                                controller.next();
                              },
                        icon: Icon(
                          Icons.skip_next_rounded,
                          color: playing.hasControl ? AppColors.ink : AppColors.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 2,
                    backgroundColor: AppColors.hairline2,
                    valueColor: const AlwaysStoppedAnimation(AppColors.ember),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

