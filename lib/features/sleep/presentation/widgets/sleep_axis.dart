import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../../domain/sleep_provenance.dart';

/// The shared local-time axis both sleep charts are drawn on: **18:00 through
/// noon the next day**.
///
/// One axis for every row is what makes the weekly raster work. A per-row axis
/// would rescale each night to fill the width and destroy the only thing the
/// chart is for — seeing that Thursday's bar starts further right than
/// Monday's. Eighteen hours is the smallest window that holds an ordinary
/// night with its edges intact: an early 20:30 bedtime and a late 11:00 lie-in
/// both fit, so neither gets clipped into looking normal.
abstract final class SleepAxis {
  /// Minutes since midnight where the axis starts (18:00).
  static const int startMinutes = 18 * 60;

  /// The axis span, in minutes (18:00 → 12:00 = 18 hours).
  static const int spanMinutes = 18 * 60;

  /// Where a local wall-clock time falls on the axis, `0..1`.
  ///
  /// Clamped: a bedtime outside the window (an afternoon sleep, a night that
  /// ran past noon) pins to the edge rather than drawing off-canvas. The clamp
  /// is visible as a bar touching the frame, which reads correctly as "this
  /// ran past the end of the chart".
  static double fractionFor(int minutesSinceMidnight) {
    var offset = minutesSinceMidnight - startMinutes;
    if (offset < 0) offset += 24 * 60;
    return (offset / spanMinutes).clamp(0.0, 1.0);
  }

  /// The hours the axis labels: 6pm, 9pm, 12am, 3am, 6am, 9am, 12pm.
  static const List<int> gridHours = [18, 21, 0, 3, 6, 9, 12];
}

/// The axis's own labels, drawn once above a raster.
class SleepAxisLabels extends StatelessWidget {
  const SleepAxisLabels({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (final hour in SleepAxis.gridHours)
              _label(context, hour, constraints.maxWidth),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, int hour, double width) {
    final fraction = SleepAxis.fractionFor(hour * 60);
    // The end labels are pulled inside the frame rather than centred on their
    // tick, so neither is half-clipped by the chart's edge.
    final alignment = fraction <= 0.01
        ? -1.0
        : (fraction >= 0.99 ? 1.0 : (fraction * 2) - 1);
    return Align(
      alignment: Alignment(alignment, 0),
      child: Text(
        ltrFor(context, formatClockTime(context, DateTime(2000, 1, 1, hour))),
        style: AppText.sectionLabel.copyWith(
          color: TrainColors.ink4,
          fontSize: 9,
        ),
      ),
    );
  }
}

/// The faint verticals behind every raster row — the grid, plus the two target
/// lines when targets are set.
class SleepAxisGrid extends StatelessWidget {
  const SleepAxisGrid({
    this.targetBedtimeMinutes,
    this.targetWakeMinutes,
    super.key,
  });

  final int? targetBedtimeMinutes;
  final int? targetWakeMinutes;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GridPainter(
      targetBedtime: targetBedtimeMinutes,
      targetWake: targetWakeMinutes,
    ),
    size: Size.infinite,
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter({this.targetBedtime, this.targetWake});

  final int? targetBedtime;
  final int? targetWake;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = TrainColors.hairline
      ..strokeWidth = 1;
    for (final hour in SleepAxis.gridHours) {
      final x = SleepAxis.fractionFor(hour * 60) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    // The target lines read as goalposts: adherence becomes something you see
    // rather than something you compute from two numbers in your head.
    final target = Paint()
      ..color = TrainColors.sleepAccent.withValues(alpha: 0.38)
      ..strokeWidth = 1;
    for (final minutes in [targetBedtime, targetWake]) {
      if (minutes == null) continue;
      final x = SleepAxis.fractionFor(minutes) * size.width;
      _dashed(canvas, x, size.height, target);
    }
  }

  void _dashed(Canvas canvas, double x, double height, Paint paint) {
    const dash = 3.0;
    const gap = 3.0;
    var y = 0.0;
    while (y < height) {
      canvas.drawLine(Offset(x, y), Offset(x, (y + dash).clamp(0, height)),
          paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.targetBedtime != targetBedtime || old.targetWake != targetWake;
}

/// How a night's bar is filled, from how the night was produced.
///
/// **Method is encoded as fill, never as hue.** One glance at a week then says
/// how much of it is real measurement — a solid week and a week of outlines
/// are different weeks, and no legend is needed to see it. Encoding method as
/// a second colour instead would put a typed guess and a wrist sensor on equal
/// visual footing, which is the failure this whole design is built against.
enum SleepBarFill {
  /// A sensor measured it — solid.
  solid,

  /// A platform record we cannot attribute — solid, dimmer.
  muted,

  /// The user said so — outline only.
  outlined,

  /// Inferred — outline with a diagonal hatch, so it reads as provisional
  /// even at a glance.
  hatched;

  static SleepBarFill forMethod(SleepMethod method) => switch (method) {
    SleepMethod.measuredWearable ||
    SleepMethod.measuredNearable => SleepBarFill.solid,
    SleepMethod.platformDerived => SleepBarFill.muted,
    SleepMethod.userReported => SleepBarFill.outlined,
    SleepMethod.deviceEstimated => SleepBarFill.hatched,
  };
}
