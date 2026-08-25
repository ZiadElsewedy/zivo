import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';
import 'music_artwork.dart';
import 'music_player_page.dart';

/// How far down (px or velocity) a swipe must travel before the bar hands
/// playback over to the floating orb instead of springing back.
const _kCollapseDistance = 56.0;
const _kCollapseVelocity = 450.0;

/// The mini "now playing" bar mounted above the bottom nav (see
/// `home_shell.dart`, which only mounts this when `kMusicEnabled`) —
/// renders nothing until there's actually something to show: connected AND
/// a track loaded. Tapping the bar (anywhere but the two controls) opens
/// the full [MusicPlayerPage].
///
/// Swiping it DOWN shrinks it into [MusicOrb] — a floating bubble that
/// keeps playback controls reachable without spending a full bar of screen
/// space (the whole point on the chat tab, where vertical room is scarce).
/// [collapsed] drives the size animation; [onCollapse]/[onExpand] are the
/// dock's state transitions.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({
    required this.controller,
    this.collapsed = false,
    this.onCollapse,
    super.key,
  });

  final MusicController controller;
  final bool collapsed;
  final VoidCallback? onCollapse;

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
            return AnimatedSize(
              duration: reducedMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: collapsed
                  ? const SizedBox(width: double.infinity)
                  : _CollapsibleBar(
                      controller: controller,
                      playing: playing,
                      onCollapse: onCollapse,
                    ),
            );
          },
        );
      },
    );
  }
}

/// Wraps [_Bar] with the swipe-to-shrink gesture and its live drag feedback:
/// the bar follows the finger downward, dimming, then either springs back or
/// commits the collapse.
class _CollapsibleBar extends StatefulWidget {
  const _CollapsibleBar({
    required this.controller,
    required this.playing,
    this.onCollapse,
  });

  final MusicController controller;
  final NowPlaying playing;
  final VoidCallback? onCollapse;

  @override
  State<_CollapsibleBar> createState() => _CollapsibleBarState();
}

class _CollapsibleBarState extends State<_CollapsibleBar> {
  double _dragDy = 0;

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    // Only downward drags shrink the bar; upward resistance stays put.
    setState(() => _dragDy = (_dragDy + d.delta.dy).clamp(0.0, 90.0));
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    final commit =
        _dragDy > _kCollapseDistance || d.velocity.pixelsPerSecond.dy > _kCollapseVelocity;
    if (commit) {
      HapticFeedback.lightImpact();
      widget.onCollapse?.call();
    }
    // Spring back visually; the parent's AnimatedSize handles the real
    // collapse transition.
    setState(() => _dragDy = 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      onVerticalDragCancel: () => setState(() => _dragDy = 0),
      child: Transform.translate(
        offset: Offset(0, _dragDy),
        child: Opacity(
          opacity: (1 - _dragDy / 110).clamp(0.35, 1.0),
          child: _Bar(
            controller: widget.controller,
            playing: widget.playing,
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.controller, required this.playing});

  final MusicController controller;
  final NowPlaying playing;

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(10, 5, 6, 7),
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
                const SizedBox(height: 4),
                // Interpolated so it ticks every frame between the
                // controller's coarse emissions — same trick as the full
                // player's scrubber, sized for a hairline.
                _TickingProgressLine(
                  key: ValueKey(playing.trackId),
                  position: playing.position,
                  duration: playing.duration,
                  isPaused: playing.isPaused,
                ),
                const SizedBox(height: 4),
                // Quiet grab-handle affordance: this bar can be swiped away.
                Container(
                  width: 26,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.hairline2,
                    borderRadius: BorderRadius.circular(2),
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

/// A 2dp progress line that animates forward in real time between emissions
/// (jump to the reported fraction, then glide to full over the remaining
/// track time; emissions re-anchor and correct drift).
class _TickingProgressLine extends StatefulWidget {
  const _TickingProgressLine({
    super.key,
    required this.position,
    required this.duration,
    required this.isPaused,
  });

  final Duration position;
  final Duration duration;
  final bool isPaused;

  @override
  State<_TickingProgressLine> createState() => _TickingProgressLineState();
}

class _TickingProgressLineState extends State<_TickingProgressLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this)
    ..value = _fraction;

  double get _fraction {
    if (widget.duration.inMilliseconds <= 0) return 0;
    return (widget.position.inMilliseconds / widget.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant _TickingProgressLine old) {
    super.didUpdateWidget(old);
    _c.stop();
    _c.value = _fraction;
    if (!widget.isPaused && !reducedMotion(context)) {
      final remaining = widget.duration - widget.position;
      if (remaining > Duration.zero) {
        _c.animateTo(1, duration: remaining, curve: Curves.linear);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final fraction = _c.value.clamp(0.0, 1.0);
        return ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 2,
            backgroundColor: AppColors.hairline2,
            valueColor: const AlwaysStoppedAnimation(AppColors.ember),
          ),
        );
      },
    );
  }
}
