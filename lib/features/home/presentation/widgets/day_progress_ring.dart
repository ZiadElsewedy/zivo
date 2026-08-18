import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';

/// A small multi-hue "energy" ring — the day's completion at a glance,
/// blending every life area's color into one live arc. Animates in once
/// (bounded duration) and never loops, so it settles cleanly in tests.
class DayProgressRing extends StatelessWidget {
  const DayProgressRing({
    required this.progress,
    this.size = 56,
    this.strokeWidth = 5,
    super.key,
  });

  final double progress; // 0..1
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: clamped),
      duration: const Duration(milliseconds: 850),
      curve: AppMotion.ease,
      builder: (context, value, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(progress: value, strokeWidth: strokeWidth),
            child: Center(
              child: Text(
                '${(value * 100).round()}%',
                style: AppText.meta.copyWith(
                  fontSize: size * 0.24,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.strokeWidth});

  final double progress;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = AppColors.hairline2
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);

    if (progress <= 0) return;

    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        transform: GradientRotation(-math.pi / 2),
        colors: [
          AppColors.ember,
          AppColors.solar,
          AppColors.pulse,
          AppColors.iris,
          AppColors.ember,
        ],
      ).createShader(rect);

    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
