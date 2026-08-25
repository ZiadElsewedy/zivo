import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';
import '../domain/now_playing.dart';
import 'music_artwork.dart';

/// The collapsed resting place of the now-playing dock: a floating artwork
/// bubble that hugs either bottom corner above the tab bar.
///
/// - **Tap** re-expands the full bar (see [onExpand]).
/// - **Horizontal drag** repositions it; release magnetically snaps it to the
///   nearest corner with a spring, so it never sits mid-screen.
/// - A hairline progress ring fills clockwise around it in real time —
///   playback stays legible from the corner of your eye while the chat gets
///   every pixel of width the bar used to spend.
class MusicOrb extends StatefulWidget {
  const MusicOrb({required this.controller, required this.onExpand, super.key});

  final MusicController controller;
  final VoidCallback onExpand;

  @override
  State<MusicOrb> createState() => _MusicOrbState();
}

class _MusicOrbState extends State<MusicOrb>
    with TickerProviderStateMixin {
  static const _diameter = 54.0;
  static const _edgeMargin = 14.0;

  /// Horizontal translation from the left-docked rest position — lives IN
  /// the animation controller so drags write it directly and release hands
  /// it to one continuous spring.
  late final AnimationController _dx =
      AnimationController(vsync: this)
        ..addListener(() => setState(() {}));
  bool _dragging = false;

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  double get _maxDx {
    final screenW = MediaQuery.of(context).size.width;
    return math.max(0, screenW - _diameter - _edgeMargin * 2);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _dx.stop();
    _dx.value = (_dx.value + d.delta.dx).clamp(0.0, _maxDx);
  }

  void _onDragEnd(DragEndDetails d) {
    HapticFeedback.selectionClick();
    // A deliberate fling wins; otherwise whichever corner is nearer.
    final bool targetIsRight;
    if (d.velocity.pixelsPerSecond.dx.abs() > 350) {
      targetIsRight = d.velocity.pixelsPerSecond.dx > 0;
    } else {
      targetIsRight = _dx.value * 2 >= _maxDx;
    }
    final target = targetIsRight ? _maxDx : 0.0;
    if (reducedMotion(context)) {
      _dx.value = target;
      return;
    }
    _dx.animateWith(SpringSimulation(
      AppSprings.standard,
      _dx.value,
      target,
      d.velocity.pixelsPerSecond.dx,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MusicConnection>(
      stream: widget.controller.connection,
      initialData: widget.controller.currentConnection,
      builder: (context, connectionSnap) {
        if (connectionSnap.data != MusicConnection.connected) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<NowPlaying?>(
          stream: widget.controller.nowPlaying,
          initialData: widget.controller.currentNowPlaying,
          builder: (context, snap) {
            final playing = snap.data;
            if (playing == null) return const SizedBox.shrink();
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onExpand();
              },
              onPanStart: (_) => setState(() => _dragging = true),
              onPanUpdate: _onDragUpdate,
              onPanEnd: (d) {
                _dragging = false;
                _onDragEnd(d);
              },
              onPanCancel: () => setState(() => _dragging = false),
              child: Transform.translate(
                offset: Offset(_dx.value, _dragging ? -4 : 0),
                child: _OrbBody(
                  playing: playing,
                  dragging: _dragging,
                  onToggle: () => playing.isPaused
                      ? widget.controller.play()
                      : widget.controller.pause(),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _OrbBody extends StatefulWidget {
  const _OrbBody({
    required this.playing,
    required this.dragging,
    required this.onToggle,
  });

  final NowPlaying playing;
  final bool dragging;
  final VoidCallback onToggle;

  @override
  State<_OrbBody> createState() => _OrbBodyState();
}

class _OrbBodyState extends State<_OrbBody> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this)
    ..value = _fraction;

  double get _fraction {
    if (widget.playing.duration.inMilliseconds <= 0) return 0;
    return (widget.playing.position.inMilliseconds /
            widget.playing.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant _OrbBody old) {
    super.didUpdateWidget(old);
    _progress.stop();
    _progress.value = _fraction;
    if (!widget.playing.isPaused && !reducedMotion(context)) {
      final remaining = widget.playing.duration - widget.playing.position;
      if (remaining > Duration.zero) {
        _progress.animateTo(1, duration: remaining, curve: Curves.linear);
      }
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) => AnimatedScale(
        scale: widget.dragging ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                spreadRadius: -2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: CustomPaint(
            foregroundPainter: _RingPainter(fraction: _progress.value),
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: AppColors.surfaceRaised,
                    child: MusicArtwork(
                      bytes: widget.playing.artworkBytes,
                      url: widget.playing.artworkUrl,
                      size: 54,
                      iconSize: 22,
                      borderRadius: 27,
                    ),
                  ),
                  // Paused: dim + play glyph so the bubble still invites a tap.
                  if (widget.playing.isPaused)
                    const ColoredBox(
                      color: Color(0x88000000),
                      child: Center(
                        child:
                            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The clockwise progress ring hugging the orb's rim.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction});

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.5;
    final inset = stroke / 2 + 0.5;
    final rect = Offset(inset, inset) &
        Size(size.width - inset * 2, size.height - inset * 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.hairline2;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    if (fraction <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.ember;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * fraction.clamp(0.0, 1.0),
        false, fill);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction;
}
