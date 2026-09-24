import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/train_tokens.dart';

/// What [SetLoggedMoment] is confirming — one logged set, and whether that
/// set closed out its exercise.
class SetLoggedEvent {
  const SetLoggedEvent({
    required this.serial,
    required this.caption,
    this.detail,
    this.exerciseName,
  });

  /// Increments per logged set. Two sets can carry identical copy (same
  /// reps, same load), so the moment replays on a new [serial], never on a
  /// change of text.
  final int serial;

  /// "SET 2 LOGGED", or "EXERCISE DONE" when the set closed the exercise.
  final String caption;

  /// What was recorded — "60kg × 10", or the exercise's sets/volume summary.
  final String? detail;

  /// Present only when this set finished its exercise: the bigger moment.
  final String? exerciseName;

  bool get closesExercise => exerciseName != null;
}

/// Where the moment sits, measured from the top of the phase area: the
/// centre of the rest ring the rest phase fades in (the phase padding, the
/// eyebrow pill, its 26pt gap, then half the 290pt ring).
const double _ringCentreY = AppSpacing.base + 32 + 26 + 145;

/// The ring's face: its stroke is centred 132pt out and 7pt wide, so 128
/// covers everything inside it (the countdown digits and their caption)
/// while leaving the green sweep itself in view.
const double _faceRadius = 128;

/// The one-shot confirmation that a set was logged. It takes over the rest
/// ring's FACE: an opaque disc covers the countdown, a checkmark draws
/// itself, one ripple runs out to the ring's stroke and a haptic lands with
/// the check — then the face dissolves and the countdown is simply there
/// underneath. The ring says "done", then becomes the timer. ~0.95s for a
/// set, a beat longer for the set that finishes an exercise.
///
/// The face is opaque on purpose: the first version floated a translucent
/// check over a ring that had already faded in, so the digits, their
/// "of 1:30" caption and a long exercise name all collided with it.
/// Everything the moment says is sized to fit inside the circle.
///
/// Owned by the page rather than any phase, because the phase it would
/// belong to (running) is already cross-fading out on the frame the set is
/// logged. Never takes a tap: it must not swallow Skip rest or ±15s.
class SetLoggedMoment extends StatefulWidget {
  const SetLoggedMoment({required this.event, super.key});

  final SetLoggedEvent? event;

  @override
  State<SetLoggedMoment> createState() => _SetLoggedMomentState();
}

class _SetLoggedMomentState extends State<SetLoggedMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this)
    ..addListener(_maybeLand);

  bool _reduced = false;
  bool _landed = false;

  // Timeline, in milliseconds from the tap.
  static const _checkStart = 90.0;
  static const _checkEnd = 330.0;
  static const _exitLength = 260.0;

  double get _totalMs => _reduced
      ? 900
      : widget.event?.closesExercise ?? false
      ? 1400
      : 950;

  double get _ms => _t.value * _totalMs;

  @override
  void didUpdateWidget(covariant SetLoggedMoment oldWidget) {
    super.didUpdateWidget(oldWidget);
    final event = widget.event;
    if (event != null && event.serial != oldWidget.event?.serial) _play();
  }

  void _play() {
    _reduced = reducedMotion(context);
    _landed = false;
    _t.duration = Duration(milliseconds: _totalMs.round());
    // Reduced motion has no stroke to wait for, so the haptic is the whole
    // confirmation and it lands on the tap.
    if (_reduced) _land();
    _t.forward(from: 0);
  }

  void _maybeLand() {
    if (!_landed && _ms >= _checkEnd) _land();
  }

  void _land() {
    _landed = true;
    // The second beat of two: the button already answered the press, this
    // answers "that counted", on the stroke's last pixel. Finishing a whole
    // exercise lands a step firmer.
    if (widget.event?.closesExercise ?? false) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  /// 0→1 across [start, end] ms, clamped and eased.
  double _phase(double start, double end, [Curve curve = Curves.linear]) =>
      curve.transform(((_ms - start) / (end - start)).clamp(0.0, 1.0));

  /// The house bounce spring, evaluated at the current time — the same
  /// "momentum moment" material a set chip completing already uses.
  double get _discScale {
    if (_reduced) return 1;
    final sim = SpringSimulation(AppSprings.bounce, 0.55, 1, 0);
    return sim.x(_ms / 1000);
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        if (event == null || !_t.isAnimating) return const SizedBox.shrink();

        final exitStart = _totalMs - _exitLength;
        final enter = _reduced
            ? _phase(0, 120)
            : _phase(0, 120, Curves.easeOut);
        final exit = _phase(exitStart, _totalMs, Curves.easeInCubic);
        final check = _reduced
            ? 1.0
            : _phase(_checkStart, _checkEnd, Curves.easeOutCubic);
        final ripple = _reduced ? 0.0 : _phase(_checkEnd - 60, _checkEnd + 420);
        final caption = _reduced ? 1.0 : _phase(200, 420, Curves.easeOutCubic);
        final mark = event.closesExercise ? 68.0 : 76.0;

        return IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: _ringCentreY - _faceRadius,
                height: _faceRadius * 2,
                child: Center(
                  child: Semantics(
                    liveRegion: true,
                    label: [
                      event.exerciseName,
                      event.caption,
                      event.detail,
                    ].whereType<String>().join(', '),
                    child: ExcludeSemantics(
                      child: Opacity(
                        opacity: (enter * (1 - exit)).clamp(0.0, 1.0),
                        child: SizedBox.square(
                          dimension: _faceRadius * 2,
                          child: CustomPaint(
                            painter: _FacePainter(
                              ripple: ripple,
                              color: TrainColors.green,
                              face: TrainColors.base,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Transform.scale(
                                  scale: _discScale * (1 - 0.1 * exit),
                                  child: SizedBox.square(
                                    dimension: mark,
                                    child: CustomPaint(
                                      painter: _CheckPainter(
                                        check: check,
                                        color: TrainColors.green,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Opacity(
                                  opacity: caption,
                                  child: Transform.translate(
                                    offset: Offset(0, 5 * (1 - caption)),
                                    child: _Caption(event: event),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// What the face says under the check. Its width is the circle's chord at
/// that height, not the screen's, so a long exercise name ellipsizes inside
/// the ring instead of running across its stroke.
class _Caption extends StatelessWidget {
  const _Caption({required this.event});

  final SetLoggedEvent event;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 188,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TrainType.mono(
              size: 10,
              weight: FontWeight.w600,
              tracking: 0.2,
              color: TrainColors.green,
            ),
          ),
          if (event.exerciseName != null) ...[
            const SizedBox(height: 7),
            Text(
              event.exerciseName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TrainType.ui(
                size: 17,
                weight: FontWeight.w700,
                height: 1.15,
                color: TrainColors.inkPlain,
              ),
            ),
          ],
          if (event.detail != null) ...[
            const SizedBox(height: 5),
            Text(
              event.detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TrainType.mono(size: 14, color: TrainColors.inkAt(0.7)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The ring's face: an opaque disc that covers the countdown (feathered at
/// its rim so it meets the ring's own inner glow rather than cutting a hard
/// circle), and the one ripple that runs from the check out to the stroke.
class _FacePainter extends CustomPainter {
  _FacePainter({required this.ripple, required this.color, required this.face});

  /// 0..1 — the ripple's life; 0 draws nothing.
  final double ripple;
  final Color color;
  final Color face;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(face, color, 0.07)!,
            face,
            face.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.95, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    if (ripple > 0 && ripple < 1) {
      final eased = Curves.easeOutCubic.transform(ripple);
      canvas.drawCircle(
        center,
        radius * (0.3 + 0.7 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + 2 * (1 - ripple)
          ..color = color.withValues(alpha: 0.5 * (1 - ripple)),
      );
    }
  }

  @override
  bool shouldRepaint(_FacePainter old) =>
      old.ripple != ripple || old.color != color || old.face != face;
}

/// The check on its small green disc.
class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.check, required this.color});

  /// 0..1 — how much of the checkmark's stroke is drawn.
  final double check;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: 0.16),
    );
    canvas.drawCircle(
      center,
      radius - 0.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.6),
    );

    if (check <= 0) return;
    // Short leg down-right, long leg up-right, optically centred.
    final s = radius * 0.9;
    final path = Path()
      ..moveTo(center.dx - s * 0.42, center.dy + s * 0.02)
      ..lineTo(center.dx - s * 0.12, center.dy + s * 0.32)
      ..lineTo(center.dx + s * 0.46, center.dy - s * 0.30);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * check),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = math.max(4, radius * 0.11)
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.check != check || old.color != color;
}
