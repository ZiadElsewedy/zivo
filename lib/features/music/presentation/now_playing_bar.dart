import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/train_tokens.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';
import 'music_player_page.dart';
import 'spotify_strip.dart';

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
    // Text-first per the workout-tracking handoff: no artwork tile, and so no
    // artwork-derived background tint either — the strip is instrumentation,
    // and a cover image (plus the wash pulled off it) competed with the
    // screen's own numbers. Identity now comes from the live equalizer glyph.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        0,
        AppSpacing.screen,
        6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The shell runs `extendBody: true`, so page content scrolls
          // BEHIND this bar. The handoff's strip fill is nearly transparent
          // (by design — nothing sits behind it in the prototype), which here
          // let headings read straight through it. A frosted plate underneath
          // keeps the spec's fill on top while giving it something opaque
          // enough to sit on.
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: reducedMotion(context)
                  ? ImageFilter.blur()
                  : ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: ColoredBox(
                color: TrainColors.base.withValues(alpha: 0.82),
                child: SpotifyStrip.full(
                  controller: controller,
                  playing: playing,
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MusicPlayerPage(controller: controller),
                      fullscreenDialog: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
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
    );
  }
}
