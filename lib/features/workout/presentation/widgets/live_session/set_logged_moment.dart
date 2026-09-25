import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/theme/train_tokens.dart';

/// What [SetLoggedFace] is confirming — one logged set, and whether that
/// set closed out its exercise.
class SetLoggedEvent {
  SetLoggedEvent({
    required this.serial,
    required this.caption,
    this.detail,
    this.exerciseName,
  });

  /// Increments per logged set. Two sets can carry identical copy (same
  /// reps, same load), so each logged set is its own event, never a change
  /// of text.
  final int serial;

  /// "SET 2 LOGGED", or "EXERCISE DONE" when the set closed the exercise.
  final String caption;

  /// What was recorded — "60kg × 10", or the exercise's sets/volume summary.
  final String? detail;

  /// Present only when this set finished its exercise: the bigger moment.
  final String? exerciseName;

  bool get closesExercise => exerciseName != null;

  bool _claimed = false;

  /// True exactly once. The event outlives its moment in the page's state,
  /// so a rest ring mounting later for another reason (a skipped set starts
  /// a rest too) must not replay a check it has already shown.
  bool claim() {
    if (_claimed) return false;
    return _claimed = true;
  }
}

/// The confirmation that a set was logged — played by the rest ring's own
/// FACE, not laid over it. The countdown rest is about to show starts out
/// hidden, so the first thing in the ring's centre is the check: it springs
/// in, draws itself, one ripple runs out to the ring's stroke and the haptic
/// lands with the stroke's last pixel. Then the face hands over — the check
/// contracts and goes out of focus while the digits come INTO focus in the
/// same spot — so "done" becomes the timer as one motion.
///
/// Two earlier versions both read as three states. A translucent check
/// floated over a ring that had already faded in, so the digits collided
/// with it; then an opaque disc covered a countdown that was visible for the
/// first frames and uncovered again at the end — timer, check, timer. Here
/// the countdown simply isn't shown until the check gives the centre up.
///
/// [child] is the timer face the check hands over to. The moment never
/// takes a tap, so the ring underneath stays the pause control throughout.
class SetLoggedFace extends StatefulWidget {
  const SetLoggedFace({required this.event, required this.child, super.key});

  /// What to confirm. Played once — see [SetLoggedEvent.claim].
  final SetLoggedEvent? event;
  final Widget child;

  @override
  State<SetLoggedFace> createState() => _SetLoggedFaceState();
}

class _SetLoggedFaceState extends State<SetLoggedFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this)
    ..addListener(_maybeLand);

  SetLoggedEvent? _playing;
  bool _reduced = false;
  bool _landed = false;

  // Timeline, in milliseconds from the tap.
  static const _checkStart = 80.0;
  static const _checkEnd = 320.0;

  /// When the check starts giving the centre back. A finished exercise holds
  /// its name long enough to be read.
  double get _handoff => _reduced
      ? 700
      : _playing?.closesExercise ?? false
      ? 1080
      : 640;

  double get _totalMs => _handoff + (_reduced ? 260 : 460);

  double get _ms => _t.value * _totalMs;

  bool _mounted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The rest phase mounts on the very frame the set is logged, so this is
    // where the moment normally starts — before the first paint, which is
    // what keeps the countdown from flashing up underneath it. (Here rather
    // than initState: it reads the reduced-motion setting.)
    if (_mounted) return;
    _mounted = true;
    _claim();
  }

  @override
  void didUpdateWidget(covariant SetLoggedFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.event, oldWidget.event)) _claim();
  }

  void _claim() {
    final event = widget.event;
    if (event == null || !event.claim()) return;
    _playing = event;
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
    if (_playing?.closesExercise ?? false) {
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
  double get _badgeScale {
    if (_reduced) return 1;
    final sim = SpringSimulation(AppSprings.bounce, 0.6, 1, 0);
    return sim.x(_ms / 1000);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, timer) {
        final event = _playing;
        final playing = event != null && _t.isAnimating;
        // The digits start focusing in as the check's last glow is going —
        // an overlap of a few frames, so the centre is never empty, but the
        // eye never reads a sharp check and a numeral at once.
        final arrive = !playing
            ? 1.0
            : _reduced
            ? _phase(_handoff + 60, _handoff + 260)
            : _phase(_handoff + 160, _handoff + 460, Curves.easeOutCubic);

        final face = _Focus(
          opacity: arrive,
          // Grows out of the point the check just drew into, so the check
          // reads as BECOMING the numeral rather than swapping for it.
          scale: _reduced ? 1 : 0.9 + 0.1 * arrive,
          blur: _reduced ? 0 : 6 * (1 - arrive),
          child: timer!,
        );
        if (!playing) return face;

        return Stack(
          fit: StackFit.expand,
          children: [
            face,
            IgnorePointer(
              child: Semantics(
                liveRegion: true,
                label: [
                  event.exerciseName,
                  event.caption,
                  event.detail,
                ].whereType<String>().join(', '),
                child: ExcludeSemantics(child: _moment(event)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _moment(SetLoggedEvent event) {
    final enter = _reduced ? 1.0 : _phase(0, 90, Curves.easeOut);
    final out = _reduced
        ? _phase(_handoff, _handoff + 200)
        : _phase(_handoff, _handoff + 200, Curves.easeInCubic);
    final check = _reduced
        ? 1.0
        : _phase(_checkStart, _checkEnd, Curves.easeOutCubic);
    final ripple = _reduced ? 0.0 : _phase(_checkEnd - 60, _checkEnd + 420);
    final caption = _reduced ? 1.0 : _phase(170, 400, Curves.easeOutCubic);
    final mark = event.closesExercise ? 64.0 : 76.0;
    // A set's check owns the ring's exact centre, where the numeral will
    // be; a finished exercise lifts it to make room for the name.
    final lift = event.closesExercise ? 30.0 : 0.0;

    return CustomPaint(
      painter: _RipplePainter(
        ripple: ripple,
        origin: -lift,
        from: mark / 2,
        color: TrainColors.green,
      ),
      child: _Focus(
        opacity: enter * (1 - out),
        scale: _reduced ? 1 : 1 - 0.2 * out,
        blur: _reduced ? 0 : 6 * out,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: Offset(0, -lift),
                child: Transform.scale(
                  scale: _badgeScale,
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
              ),
              // The caption hangs below the check the way the countdown's
              // "of 1:30" hangs below the digits — it can't move the check.
              Positioned(
                left: 0,
                right: 0,
                top: box.maxHeight / 2 - lift + mark / 2 + 14,
                child: Opacity(
                  opacity: caption,
                  child: Transform.translate(
                    offset: Offset(0, 5 * (1 - caption)),
                    child: Center(child: _Caption(event: event)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opacity, scale and a lens blur as one — how both halves of the handoff
/// move, so the check and the numeral read as one face going out of and
/// coming into focus rather than two layers cross-fading.
class _Focus extends StatelessWidget {
  const _Focus({
    required this.opacity,
    required this.scale,
    required this.blur,
    required this.child,
  });

  final double opacity;
  final double scale;
  final double blur;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: ImageFiltered(
          enabled: blur > 0.05,
          imageFilter: ui.ImageFilter.blur(
            sigmaX: blur,
            sigmaY: blur,
            tileMode: TileMode.decal,
          ),
          child: child,
        ),
      ),
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

/// The one ripple that runs from the check out to the ring's stroke — the
/// check's "landed" travelling to the thing that is about to count down.
class _RipplePainter extends CustomPainter {
  _RipplePainter({
    required this.ripple,
    required this.origin,
    required this.from,
    required this.color,
  });

  /// 0..1 — the ripple's life; 0 and 1 draw nothing.
  final double ripple;

  /// The check's vertical offset from the ring's centre. The ripple starts
  /// there and drifts onto the ring's own centre as it grows, so it always
  /// lands concentric with the stroke.
  final double origin;

  /// The radius it starts at: the check's own disc.
  final double from;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (ripple <= 0 || ripple >= 1) return;
    // Ends on the inner edge of the ring's 7pt stroke (centred 132 out).
    final to = size.shortestSide / 2 - 13 - 4;
    final eased = Curves.easeOutCubic.transform(ripple);
    final center = size.center(Offset(0, origin * (1 - eased)));
    canvas.drawCircle(
      center,
      from + (to - from) * eased,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + 2 * (1 - ripple)
        ..color = color.withValues(alpha: 0.45 * (1 - ripple)),
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.ripple != ripple ||
      old.origin != origin ||
      old.from != from ||
      old.color != color;
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
