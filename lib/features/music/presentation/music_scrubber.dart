import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/music_controller.dart';

/// Apple's momentum-projection formula (apple-design skill §6) — reused
/// verbatim from `workout_start_sheet.dart`'s drag-to-dismiss handoff:
/// where released momentum would coast to a stop, absent further input.
/// Fed a fraction-of-track-per-second velocity here rather than px/sec —
/// the formula is unit-agnostic (it just scales whatever velocity it's
/// given), and the scrubber already does its own math in track-fraction
/// space (see [_MusicScrubberState]).
double _projectMomentum(
  double velocityPerSecond, {
  double decelerationRate = 0.998,
}) => (velocityPerSecond / 1000) * decelerationRate / (1 - decelerationRate);

/// The full player's draggable position scrubber — tracks the finger 1:1
/// while dragging, and on release hands the release velocity to a spring
/// that settles on a momentum-projected final position (a fast flick lands
/// further along the track than a slow one stopped at the same point),
/// mirroring `workout_start_sheet.dart`'s drag-to-dismiss handoff exactly:
/// same [_projectMomentum] formula, same `SpringSimulation` velocity
/// carry-through via [AppSprings].
///
/// The actual seek fires immediately on release — audio should respond
/// right away, not wait on a cosmetic animation. The spring is purely the
/// visual landing; [_dragging] stays true until it finishes settling, so
/// the next stream-driven resync (see [_resync]) doesn't cut the spring off
/// mid-flight.
class MusicScrubber extends StatefulWidget {
  const MusicScrubber({
    required this.controller,
    required this.duration,
    required this.position,
    required this.isPaused,
    super.key,
  });

  final MusicController controller;
  final Duration duration;

  /// The last known position from the controller's stream — the scrubber
  /// resyncs to this (see [_MusicScrubberState.didUpdateWidget]) whenever
  /// the user isn't actively dragging.
  final Duration position;
  final bool isPaused;

  @override
  State<MusicScrubber> createState() => _MusicScrubberState();
}

class _MusicScrubberState extends State<MusicScrubber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this)
    ..value = _fractionOf(widget.position, widget.duration);

  bool _dragging = false;
  double _trackWidth = 0;

  double _fractionOf(Duration position, Duration duration) {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant MusicScrubber old) {
    super.didUpdateWidget(old);
    if (_dragging) return; // the user's thumb is the source of truth right now
    if (old.position == widget.position &&
        old.isPaused == widget.isPaused &&
        old.duration == widget.duration) {
      return;
    }
    _resync();
  }

  /// Jumps to the latest known position, then — if playing — animates
  /// smoothly toward the end over the remaining real time. `animateTo`
  /// (not a spring) here: this is a steady real-time clock, not a
  /// momentum-driven gesture — the spring belongs to [_onDragEnd] alone.
  /// The fake controller only emits every ~250ms; this is what makes the
  /// bar itself read as continuously moving between those emissions.
  void _resync() {
    _progress.stop();
    _progress.value = _fractionOf(widget.position, widget.duration);
    if (!widget.isPaused) {
      final remaining = widget.duration - widget.position;
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

  void _onDragStart(DragStartDetails details) {
    _dragging = true;
    _progress.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_trackWidth <= 0) return;
    _progress.value = (details.localPosition.dx / _trackWidth).clamp(0.0, 1.0);
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (_trackWidth <= 0) {
      _dragging = false;
      return;
    }
    final velocity = details.velocity.pixelsPerSecond.dx / _trackWidth;
    final projected = (_progress.value + _projectMomentum(velocity)).clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (widget.duration.inMilliseconds * projected).round(),
    );
    unawaited(widget.controller.seek(target));
    if (reducedMotion(context)) {
      _progress.value = projected;
      _dragging = false;
      return;
    }
    // Bypasses the `springTo` convenience extension only to recover the
    // `TickerFuture` it doesn't expose — same spring, same velocity
    // handoff, just awaited so `_dragging` doesn't clear (and a stream
    // resync doesn't cut in) until the visual landing actually finishes.
    await _progress.animateWith(
      SpringSimulation(AppSprings.standard, _progress.value, projected, velocity),
    );
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _trackWidth = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: (d) => unawaited(_onDragEnd(d)),
          child: SizedBox(
            height: 28,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _progress,
              builder: (context, _) {
                final fraction = _progress.value.clamp(0.0, 1.0);
                final fillWidth = _trackWidth * fraction;
                final thumbLeft = (fillWidth - 7).clamp(0.0, (_trackWidth - 14).clamp(0.0, double.infinity));
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.hairline2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      height: 4,
                      width: fillWidth,
                      decoration: BoxDecoration(
                        color: AppColors.ember,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Positioned(
                      left: thumbLeft,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: AppColors.ember,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
