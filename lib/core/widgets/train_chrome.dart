import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/train_tokens.dart';
import 'pressable_scale.dart';

/// The shared chrome of the workout-tracking screens (Today · Active Set ·
/// Rest), built to the handoff in `assets/design_handoff_workout_tracking/`.
///
/// Everything here is presentational and stateless-by-default: the pieces
/// take values and callbacks, never repositories, so Today and the live
/// session can compose them from their own (already-correct) data sources.

/// A "glass" card — a 1px hairline over a top-lit gradient. This is how the
/// handoff builds depth: no drop shadows anywhere except the colored bloom
/// under a primary action ([TrainPrimaryButton]).
class TrainCard extends StatelessWidget {
  const TrainCard({
    required this.child,
    this.radius = 22,
    this.padding = const EdgeInsets.all(18),
    this.gradient,
    this.border,
    super.key,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  /// Defaults to [TrainColors.cardGradient]; pass a hue slab (e.g. the
  /// session card's green) to override.
  final Gradient? gradient;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient ?? TrainColors.cardGradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? TrainColors.hairline),
      ),
      child: child,
    );
  }
}

/// The one committing action on a screen: a 60px accent pill under its own
/// colored bloom. Ember for "commit this" (Start Workout, Log set), green for
/// "move on" (Skip rest).
class TrainPrimaryButton extends StatelessWidget {
  const TrainPrimaryButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.color = TrainColors.ember,
    this.labelColor = Colors.white,
    this.height = 60,
    this.glowAlpha = 0.32,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final Widget? icon;
  final Color color;
  final Color labelColor;
  final double height;
  final double glowAlpha;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.985,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: TrainColors.actionGlow(color, alpha: glowAlpha),
        ),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              HapticFeedback.mediumImpact();
              onTap();
            },
            child: SizedBox(
              height: height,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[icon!, const SizedBox(width: 10)],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TrainType.ui(
                        size: 16.5,
                        weight: FontWeight.w800,
                        tracking: -0.01,
                        color: labelColor,
                        height: 1,
                      ),
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

/// A ghost pill — the secondary, never-the-default action (Skip, ±15s).
class TrainGhostButton extends StatelessWidget {
  const TrainGhostButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.height = 52,
    this.mono = true,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final Widget? icon;
  final double height;

  /// ±15s read as numbers (mono); "Skip" reads as a word (Manrope).
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.985,
      child: Material(
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 8)],
                Text(
                  label,
                  style: mono
                      ? TrainType.mono(
                          size: 14,
                          weight: FontWeight.w500,
                          color: const Color(0xBFF4F4F0),
                        )
                      : TrainType.ui(
                          size: 14,
                          color: const Color(0xB2F4F4F0),
                          height: 1,
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

/// A 36/40px circular glass control — the header's close/delete and Today's
/// mic/night chips.
class TrainCircleButton extends StatelessWidget {
  const TrainCircleButton({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.size = 36,
    this.fill = TrainColors.glassStrong,
    this.border,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;
  final double size;
  final Color fill;
  final Color? border;

  /// The accessible minimum the visible chip is centred inside.
  static const double target = 44;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Tooltip(
        message: semanticLabel,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: target,
            height: target,
            child: Center(
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: border == null ? null : Border.all(color: border!),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The session progress bar: one 3px segment per exercise, 3px apart —
/// green behind you, ember where you are, dim ahead. Replaces a continuous
/// bar because "exercise 4 of 10" is the unit that actually means something
/// mid-workout.
class TrainSegmentBar extends StatelessWidget {
  const TrainSegmentBar({
    required this.total,
    required this.completed,
    required this.current,
    super.key,
  });

  final int total;

  /// How many segments are fully behind you.
  final int completed;

  /// The index of the in-progress segment, or null when none is (every
  /// exercise finished).
  final int? current;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox(height: 3);
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < completed
                    ? TrainColors.green
                    : i == current
                    ? TrainColors.ember.withValues(alpha: 0.85)
                    : const Color(0x1AFFFFFF),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The caption pair under [TrainSegmentBar] — "EXERCISE 4 / 10" on the left,
/// the session's running tally on the right.
class TrainSegmentCaptions extends StatelessWidget {
  const TrainSegmentCaptions({
    required this.left,
    required this.right,
    this.rightColor = TrainColors.ink4,
    super.key,
  });

  final String left;
  final String right;
  final Color rightColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 10.5, not the 9 this row shipped with. It is read from arm's
        // length, one-handed, by someone who is out of breath — "EXERCISE 4 /
        // 10" and the running set tally are the two things you check without
        // picking the phone up, and at 9pt mono they were decoration.
        Text(
          left,
          style: TrainType.caption(
            size: 10.5,
            tracking: 0.14,
            color: const Color(0x7AF4F4F0),
          ),
        ),
        Text(
          right,
          key: const Key('session-tally'),
          style: TrainType.caption(
            size: 10.5,
            tracking: 0.14,
            color: rightColor,
          ),
        ),
      ],
    );
  }
}

/// A 74px metric ring — a 3px round-capped arc with a value or glyph in its
/// core and a Manrope label plus mono sub-caption beneath. Today's three-up
/// row is built from these.
class TrainMetricRing extends StatelessWidget {
  const TrainMetricRing({
    required this.progress,
    required this.color,
    required this.label,
    required this.sub,
    this.value,
    this.unit,
    this.glyph,
    this.subColor,
    super.key,
  });

  /// 0..1.
  final double progress;
  final Color color;

  /// "Trained" / "Steps" / "Volume".
  final String label;

  /// "PULL · 62 MIN" / "OF 8K" / "+12% WoW".
  final String sub;

  /// The ring's core number ("5.4"), or null to show [glyph] instead.
  final String? value;

  /// The number's unit ("K", "T") — always smaller and dimmer than the value.
  final String? unit;
  final Widget? glyph;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 74,
          height: 74,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) =>
                      CustomPaint(painter: _RingPainter(t, color)),
                ),
              ),
              if (value != null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value!,
                      style: TrainType.mono(
                        size: 20,
                        tracking: -0.03,
                        color: TrainColors.ink,
                      ),
                    ),
                    if (unit != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        unit!,
                        style: TrainType.mono(
                          size: 8,
                          weight: FontWeight.w500,
                          tracking: 0.12,
                          color: const Color(0x61F4F4F0),
                        ),
                      ),
                    ],
                  ],
                )
              else
                ?glyph,
            ],
          ),
        ),
        const SizedBox(height: 11),
        Text(
          label,
          style: TrainType.ui(
            size: 12.5,
            weight: FontWeight.w700,
            height: 1,
            color: TrainColors.inkPlain,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          sub,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TrainType.mono(
            size: 9.5,
            tracking: 0.08,
            color: subColor ?? const Color(0x61F4F4F0),
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 5;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = TrainColors.hairline;
    canvas.drawCircle(center, radius, track);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// A mono micro-caption above a block ("TODAY", "NEXT SESSION", "NOW").
class TrainCaption extends StatelessWidget {
  const TrainCaption(
    this.text, {
    this.color = TrainColors.ink4,
    this.size = 9.5,
    this.tracking = 0.2,
    super.key,
  });

  final String text;
  final Color color;
  final double size;
  final double tracking;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TrainType.caption(size: size, tracking: tracking, color: color),
  );
}

/// A solid right-pointing triangle — the handoff draws play/skip glyphs as
/// filled shapes rather than Material's outlined icons, which read as chunky
/// at these sizes.
class TrainPlayGlyph extends StatelessWidget {
  const TrainPlayGlyph({
    required this.color,
    this.size = 13,
    this.bar = false,
    super.key,
  });

  final Color color;
  final double size;

  /// Adds the trailing bar that turns "play" into "skip to next".
  final bool bar;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(bar ? size * 1.18 : size * 0.87, size),
    painter: _PlayPainter(color, bar),
  );
}

class _PlayPainter extends CustomPainter {
  const _PlayPainter(this.color, this.bar);

  final Color color;
  final bool bar;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final triWidth = bar ? size.width * 0.68 : size.width;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(triWidth, size.height / 2)
        ..lineTo(0, size.height)
        ..close(),
      paint,
    );
    if (!bar) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.79, 0, size.width * 0.21, size.height),
        const Radius.circular(1),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlayPainter old) => old.color != color || old.bar != bar;
}

/// The two-bar pause glyph.
class TrainPauseGlyph extends StatelessWidget {
  const TrainPauseGlyph({required this.color, this.size = 13, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size * 0.93, size),
    painter: _PausePainter(color),
  );
}

class _PausePainter extends CustomPainter {
  const _PausePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final barWidth = size.width * 0.34;
    for (final left in [0.0, size.width - barWidth]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, barWidth, size.height),
          const Radius.circular(1.2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PausePainter old) => old.color != color;
}
