import 'package:flutter/material.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// A small, self-contained sparkline/line chart for an exercise's recent
/// trend (top-set weight or volume) — no external chart package, just a
/// [CustomPainter] over a smoothed path. Values are oldest-to-newest; a null
/// entry is a session where this metric wasn't available and is skipped when
/// drawing the line (its slot still reserves horizontal space).
///
/// Draws itself in with a calm left-to-right reveal (skipped under reduced
/// motion — the chart just appears complete), and gives the newest point a
/// slightly larger, ringed dot so "where we are now" reads at a glance.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.values, this.color = AppColors.pulse, this.height = 52});

  final List<double?> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final real = values.whereType<double>().toList();
    if (real.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            real.isEmpty ? 'No data yet' : '${_trim(real.single)} kg',
            style: AppText.meta.copyWith(color: AppColors.ink3),
          ),
        ),
      );
    }

    final reduced = reducedMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduced ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => SizedBox(
        width: double.infinity,
        height: height,
        child: CustomPaint(painter: _TrendPainter(values: values, color: color, progress: progress)),
      ),
    );
  }

  static String _trim(double v) => v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.values, required this.color, required this.progress});

  final List<double?> values;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final indexed = [
      for (var i = 0; i < values.length; i++)
        if (values[i] != null) (i, values[i]!),
    ];
    if (indexed.length < 2) return;

    final minV = indexed.map((e) => e.$2).reduce((a, b) => a < b ? a : b);
    final maxV = indexed.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
    final span = maxV - minV;
    const topPad = 8.0, bottomPad = 8.0;
    final plotHeight = size.height - topPad - bottomPad;
    final lastIndex = values.length - 1;

    double xOf(int i) => lastIndex == 0 ? 0 : (i / lastIndex) * size.width;
    double yOf(double v) =>
        topPad + (span == 0 ? plotHeight / 2 : plotHeight - ((v - minV) / span) * plotHeight);

    final points = [for (final (i, v) in indexed) Offset(xOf(i), yOf(v))];

    // A gently smoothed line — quadratic curves through each consecutive
    // midpoint — rather than a raw polyline, so the trend reads as a real
    // sparkline instead of jagged connect-the-dots.
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      line.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);

    // Reveal the line left-to-right for the entrance flourish.
    final metrics = line.computeMetrics().toList();
    final drawn = Path();
    for (final metric in metrics) {
      drawn.addPath(metric.extractPath(0, metric.length * progress), Offset.zero);
    }

    final fill = Path.from(drawn)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots only for the portion of the line already revealed.
    final visibleCount = (points.length * progress).ceil().clamp(0, points.length);
    for (var i = 0; i < visibleCount; i++) {
      final isNewest = i == points.length - 1;
      final radius = isNewest ? 4.5 : 2.6;
      if (isNewest) {
        canvas.drawCircle(points[i], radius + 2.5, Paint()..color = AppColors.ground);
      }
      canvas.drawCircle(points[i], radius, Paint()..color = isNewest ? color : color.withValues(alpha: 0.55));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color || oldDelegate.progress != progress;
}
