import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/springs.dart';
import '../theme/app_spacing.dart';
import '../theme/app_icons.dart';
import '../theme/train_tokens.dart';
import '../theme/zivo_palette.dart';
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
    this.radius = AppRadius.card,
    this.padding = const EdgeInsets.all(18),
    this.gradient,
    this.border,
    super.key,
  });

  final Widget child;

  /// Defaults to [AppRadius.card] — the app's one card radius.
  ///
  /// It used to default to 22 while `AppRadius.card` said 20, so the design
  /// system carried two answers to "how round is a card". Six of this
  /// widget's own call sites were already passing `radius: 20` to override
  /// the default back to the token, which is the drift stating itself out
  /// loud.
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
    Color? color,
    this.labelColor = Colors.white,
    this.height = 60,
    this.glowAlpha = 0.32,
    super.key,
  // `this._x`, which the lint asks for here, is not a thing Dart will
  // accept: a named parameter cannot be private. The field is private
  // so that the public name can be the *resolved* getter below, which
  // is what keeps this constructor `const` (ADR-011).
  // ignore: prefer_initializing_formals
  }) : _color = color;

  final String label;
  final VoidCallback onTap;
  final Widget? icon;
  final Color? _color;

  /// Defaults to the active skin's `ember` — resolved on read
  /// rather than as a parameter default, which is what lets this
  /// constructor stay `const` (ADR-011).
  Color get color => _color ?? TrainColors.ember;
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
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final Widget? icon;
  final double height;

  /// ±15s read as numbers (mono); "Skip" reads as a word (Manrope).
  final bool mono;

  /// Swaps the label for a spinner and stops accepting taps.
  ///
  /// Here rather than at a call site because Settings had written this whole
  /// widget out a second time — same glass fill, same pill, same hairline,
  /// same pressable — purely to add a spinner to Sign out, and the copy had
  /// drifted three values away (border `.12` vs `.10`, label 15/w700 vs
  /// 14/w400) from the ghost pill sitting ten rows above it.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: !loading,
      scale: 0.985,
      child: Material(
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: loading
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: TrainColors.liftAt(0.1)),
            ),
            child: loading
                ? Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: TrainColors.ink2,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[icon!, const SizedBox(width: 8)],
                      Text(
                        label,
                        style: mono
                            ? TrainType.mono(
                                size: 14,
                                weight: FontWeight.w500,
                                color: TrainColors.inkAt(0.75),
                              )
                            : TrainType.ui(
                                size: 14,
                                color: TrainColors.inkAt(0.7),
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
    Color? fill,
    this.border,
    super.key,
  // `this._x`, which the lint asks for here, is not a thing Dart will
  // accept: a named parameter cannot be private. The field is private
  // so that the public name can be the *resolved* getter below, which
  // is what keeps this constructor `const` (ADR-011).
  // ignore: prefer_initializing_formals
  }) : _fill = fill;

  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;
  final double size;
  final Color? _fill;

  /// Defaults to the active skin's `glassStrong` — resolved on read
  /// rather than as a parameter default, which is what lets this
  /// constructor stay `const` (ADR-011).
  Color get fill => _fill ?? TrainColors.glassStrong;
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
    this.currentFraction,
    super.key,
  });

  final int total;

  /// How many segments are fully behind you.
  final int completed;

  /// The index of the in-progress segment, or null when none is (every
  /// exercise finished).
  final int? current;

  /// How far through itself the [current] segment is, 0..1. When given, that
  /// segment draws as a dim ember track that fills as sets are logged; when
  /// null it is solid ember, as before.
  final double? currentFraction;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox(height: 3);
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: i == current && currentFraction != null
                ? _FillingSegment(fraction: currentFraction!)
                : AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOut,
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: i < completed
                          ? TrainColors.green
                          : i == current
                          ? TrainColors.ember.withValues(alpha: 0.85)
                          : TrainColors.liftAt(0.1),
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

/// The in-progress segment of [TrainSegmentBar]: a dim ember track with a
/// solid ember fill that sweeps forward by one set's worth each time a set
/// is logged. Fills from the reading edge, so it runs right-to-left in RTL.
class _FillingSegment extends StatelessWidget {
  const _FillingSegment({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: TrainColors.ember.withValues(alpha: 0.22),
      ),
      alignment: AlignmentDirectional.centerStart,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: fraction.clamp(0.0, 1.0)),
        duration: reducedMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => FractionallySizedBox(
          widthFactor: value,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: TrainColors.ember.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

/// The caption pair under [TrainSegmentBar] — "EXERCISE 4 / 10" on the left,
/// the session's running tally on the right.
class TrainSegmentCaptions extends StatelessWidget {
  const TrainSegmentCaptions({
    required this.left,
    required this.right,
    Color? rightColor,
    this.onLeftTap,
    this.leftSemanticLabel,
    this.leftKey,
    super.key,
  // `this._x`, which the lint asks for here, is not a thing Dart will
  // accept: a named parameter cannot be private. The field is private
  // so that the public name can be the *resolved* getter below, which
  // is what keeps this constructor `const` (ADR-011).
  // ignore: prefer_initializing_formals
  }) : _rightColor = rightColor;

  final String left;
  final String right;
  final Color? _rightColor;

  /// Makes the left caption a control (the live session opens its workout
  /// map from "EXERCISE 4 / 10" — the caption already IS where you are in
  /// the workout). It gains a small caret so it reads as one.
  final VoidCallback? onLeftTap;
  final String? leftSemanticLabel;
  final Key? leftKey;

  /// Defaults to the active skin's `ink4` — resolved on read
  /// rather than as a parameter default, which is what lets this
  /// constructor stay `const` (ADR-011).
  Color get rightColor => _rightColor ?? TrainColors.ink4;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 10.5, not the 9 this row shipped with. It is read from arm's
        // length, one-handed, by someone who is out of breath — "EXERCISE 4 /
        // 10" and the running set tally are the two things you check without
        // picking the phone up, and at 9pt mono they were decoration.
        _left(),
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

  Widget _left() {
    final style = TrainType.caption(
      size: 10.5,
      tracking: 0.14,
      color: TrainColors.inkAt(0.48),
    );
    final onTap = onLeftTap;
    if (onTap == null) return Text(left, style: style);
    return Semantics(
      button: true,
      label: leftSemanticLabel,
      child: GestureDetector(
        key: leftKey,
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        // A taller hit area than the caption's own line — it is read at a
        // glance and tapped without looking closely.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(left, style: style),
              const SizedBox(width: 5),
              Icon(
                AppIcons.chevronDown,
                size: 11,
                color: TrainColors.inkAt(0.48),
              ),
            ],
          ),
        ),
      ),
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
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 820),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => CustomPaint(
                    painter: _RingPainter(
                      t,
                      color,
                      glow: ZivoTheme.brightness == Brightness.dark,
                    ),
                  ),
                ),
              ),
              if (value != null)
                // Held inside the stroke: a four-character figure ("22.0")
                // used to run edge to edge and touch the ring.
                SizedBox(
                  width: 52,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          value!,
                          style: TrainType.mono(
                            size: 20,
                            weight: FontWeight.w500,
                            tracking: -0.04,
                            color: TrainColors.ink,
                          ),
                        ),
                        if (unit != null && unit!.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            unit!,
                            style: TrainType.mono(
                              size: 8,
                              weight: FontWeight.w600,
                              tracking: 0.14,
                              color: TrainColors.inkAt(0.4),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                ?glyph,
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TrainType.ui(
            size: 13,
            weight: FontWeight.w800,
            tracking: -0.01,
            height: 1,
            color: TrainColors.inkPlain,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TrainType.mono(
            size: 9.5,
            tracking: 0.08,
            color: subColor ?? TrainColors.inkAt(0.38),
          ),
        ),
      ],
    );
  }
}

/// A Today ring. Light comes from what was earned: the arc runs from the
/// metric's colour into a brighter tip, a soft bloom sits under it on the
/// dark skin, and the leading end carries a lit cap — so a ring that is
/// moving reads as moving, and an empty one stays a quiet matte track.
class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress, this.color, {required this.glow});

  final double progress;
  final Color color;

  /// The bloom and lit cap — dark skin only; on paper a glow is a smudge.
  final bool glow;

  static const _stroke = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - _stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = TrainColors.hairline,
    );
    if (progress <= 0) return;

    final sweep = 2 * math.pi * progress;
    final tip = Color.lerp(color, Colors.white, 0.35)!;
    if (glow) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke + 2
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.max(sweep, 0.01),
          colors: [color.withValues(alpha: 0.75), glow ? tip : color],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
    // The lit leading edge — only while the ring is still filling.
    if (glow && progress < 1) {
      final end = -math.pi / 2 + sweep;
      final at = center + Offset(math.cos(end), math.sin(end)) * radius;
      canvas.drawCircle(
        at,
        _stroke / 2 + 2,
        Paint()
          ..color = tip.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(at, _stroke / 2 - 1, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.glow != glow;
}

/// A mono micro-caption above a block ("TODAY", "NEXT SESSION", "NOW").
class TrainCaption extends StatelessWidget {
  const TrainCaption(
    this.text, {
    Color? color,
    this.size = 9.5,
    this.tracking = 0.2,
    super.key,
  // `this._x`, which the lint asks for here, is not a thing Dart will
  // accept: a named parameter cannot be private. The field is private
  // so that the public name can be the *resolved* getter below, which
  // is what keeps this constructor `const` (ADR-011).
  // ignore: prefer_initializing_formals
  }) : _color = color;

  final String text;
  final Color? _color;

  /// Defaults to the active skin's `ink4` — resolved on read
  /// rather than as a parameter default, which is what lets this
  /// constructor stay `const` (ADR-011).
  Color get color => _color ?? TrainColors.ink4;
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
