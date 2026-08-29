import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/train_tokens.dart';
import '../domain/music_connection.dart';
import '../domain/music_controller.dart';

/// The full player's position scrubber — the whole seek experience in one
/// component: the draggable track, its growing thumb, and the live time
/// labels underneath.
///
/// Seek semantics (deliberately boring — a scrubber must be predictable):
/// - While dragging, the playhead IS the finger, 1:1, and the labels count
///   with it — you always know exactly what second you're on.
/// - Release seeks to exactly where the finger is. No momentum projection,
///   no overshoot: audio lands where you let go, every time. (The old
///   flick-flings-somewhere-ahead behavior made the song's actual landing
///   spot unguessable.)
/// - A plain tap jumps straight to that point on the track.
///
/// Between controller emissions the bar ticks forward as a steady real-time
/// clock (`animateTo` over the remaining track time) — emissions only ever
/// correct drift, never drive the motion.
class MusicScrubber extends StatefulWidget {
  const MusicScrubber({
    required this.controller,
    required this.trackId,
    required this.duration,
    required this.position,
    required this.isPaused,
    this.accentColor = TrainColors.ember,
    super.key,
  });

  final MusicController controller;

  /// The colour of the played track, its thumb and glow. Defaults to ember;
  /// the immersive player passes the current track's neon accent so the scrub
  /// line reacts to the artwork alongside the rest of the screen.
  final Color accentColor;

  /// Identifies the current track — a change resets the bar to zero instantly
  /// instead of animating from the previous song's last position.
  final String trackId;
  final Duration duration;

  /// The last known position from the controller's stream — the scrubber
  /// resyncs to this whenever the user isn't actively dragging.
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

  bool _seekable(Duration duration) =>
      duration.inMilliseconds > 0 &&
      widget.controller.currentConnection == MusicConnection.connected;

  @override
  void didUpdateWidget(covariant MusicScrubber old) {
    super.didUpdateWidget(old);
    if (_dragging) return; // the user's thumb is the source of truth right now
    if (old.trackId != widget.trackId) {
      // New song: land at zero (or its reported start), don't glide there.
      _progress.stop();
      _progress.value = _fractionOf(widget.position, widget.duration);
      return;
    }
    if (old.position == widget.position &&
        old.isPaused == widget.isPaused &&
        old.duration == widget.duration) {
      return;
    }
    _resync();
  }

  /// Jumps to the latest known position, then — if playing — animates smoothly
  /// toward the end over the remaining real time. The next stream emission
  /// re-anchors, so interpolation drift self-corrects continuously.
  void _resync() {
    _progress.stop();
    _progress.value = _fractionOf(widget.position, widget.duration);
    if (!widget.isPaused) {
      final remaining = widget.duration - widget.position;
      if (remaining > Duration.zero && !reducedMotion(context)) {
        _progress.animateTo(1, duration: remaining, curve: Curves.linear);
      }
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _beginDrag() {
    if (!_seekable(widget.duration)) return;
    HapticFeedback.selectionClick();
    setState(() => _dragging = true);
    _progress.stop();
  }

  double _fractionAt(double localDx) =>
      (_trackWidth <= 0 ? 0.0 : localDx / _trackWidth).clamp(0.0, 1.0);

  void _onDragUpdate(DragUpdateDetails details) {
    _progress.value = _fractionAt(details.localPosition.dx);
  }

  /// Commits a seek to exactly [fraction] of the track — release and tap both
  /// land through here, so what you see is what plays.
  void _commitSeek(double fraction) {
    final target = Duration(
      milliseconds: (widget.duration.inMilliseconds * fraction).round(),
    );
    HapticFeedback.lightImpact();
    // Fire-and-forget by design: the controller swallows its own errors (a
    // stale connection surfaces through the connection stream instead), and
    // awaiting here would let a slow platform call pin [_dragging] — freezing
    // the bar mid-song over a cosmetic detail.
    unawaited(widget.controller.seek(target));
    // Adopt the committed position immediately rather than waiting for the
    // stream echo — the bar reads as instantaneous, and the next emission
    // simply confirms it.
    _progress.stop();
    _progress.value = fraction;
    setState(() => _dragging = false);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    // Velocity is read but deliberately unused for projection — a scrubber's
    // contract is "release == play from here", full stop.
    _commitSeek(_progress.value);
  }

  static final _timecode = TrainType.mono(
    size: 11,
    tracking: 0.02,
    color: const Color(0x73F4F4F0),
  );

  String _format(double fraction) {
    final d = Duration(
      milliseconds: (widget.duration.inMilliseconds * fraction).round(),
    );
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final seekable = _seekable(widget.duration);
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final fraction = _progress.value.clamp(0.0, 1.0);
        final remainingFraction = 1.0 - fraction;
        return Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                _trackWidth = constraints.maxWidth;
                const trackHeight = 4.0;
                final activeTrackHeight = _dragging ? 6.0 : trackHeight;
                final thumbSize = _dragging ? 20.0 : 14.0;
                final thumbLeft = ((_trackWidth * fraction) - thumbSize / 2)
                    .clamp(
                      0.0,
                      (_trackWidth - thumbSize).clamp(0.0, double.infinity),
                    );
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    // The tappable/draggable surface sits over generous
                    // vertical padding — a 28px-tall hit area, Spotify-style.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: seekable
                          ? (d) {
                              _beginDrag();
                              _progress.value = _fractionAt(d.localPosition.dx);
                            }
                          : null,
                      onTapUp: seekable
                          ? (d) => _commitSeek(_fractionAt(d.localPosition.dx))
                          : null,
                      onHorizontalDragStart: seekable
                          ? (d) => _beginDrag()
                          : null,
                      onHorizontalDragUpdate: seekable ? _onDragUpdate : null,
                      onHorizontalDragEnd: seekable ? _onDragEnd : null,
                      onHorizontalDragCancel: seekable
                          ? () => setState(() => _dragging = false)
                          : null,
                      child: SizedBox(height: 30, width: double.infinity),
                    ),
                    // Track + thumb render BELOW the gesture surface so the
                    // finger never occludes them mid-drag.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(
                                  height: trackHeight,
                                  decoration: BoxDecoration(
                                    color: TrainColors.hairlineStrong,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                Container(
                                  height: activeTrackHeight,
                                  width: _trackWidth * fraction,
                                  decoration: BoxDecoration(
                                    color: widget.accentColor,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: thumbLeft,
                      top: 15 - thumbSize / 2,
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          width: thumbSize,
                          height: thumbSize,
                          decoration: BoxDecoration(
                            color: widget.accentColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: widget.accentColor.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: _dragging ? 10 : 4,
                                spreadRadius: -1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // The drag-time readout floating over the thumb — the
                    // answer to "what second am I on" while your finger is
                    // still down.
                    if (_dragging)
                      Positioned(
                        left: (thumbLeft + thumbSize / 2).clamp(
                          24.0,
                          _trackWidth - 24.0,
                        ),
                        top: -22,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, 0),
                          child: _TimeBubble(label: _format(fraction)),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_format(fraction), style: _timecode),
                Text('-${_format(remainingFraction)}', style: _timecode),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The little rounded time chip that rides above the thumb mid-drag.
class _TimeBubble extends StatelessWidget {
  const _TimeBubble({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: TrainColors.raisedStrong,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: TrainColors.hairlineStrong),
      ),
      child: Text(
        label,
        style: TrainType.mono(size: 11.5, color: TrainColors.ink),
      ),
    );
  }
}
