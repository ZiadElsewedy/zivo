import 'package:flutter/material.dart';

import '../../../../core/theme/train_tokens.dart';
import '../../domain/sleep_night.dart';
import '../../domain/sleep_session.dart';
import 'sleep_axis.dart';

/// One night drawn on [SleepAxis] — the shared primitive behind both the daily
/// hero bar and every row of the weekly raster.
///
/// Three rules it does not let a caller break:
///
/// * **An empty night is a hairline, never a zero-height bar.** A bar of zero
///   height reads as "slept 0 hours", which is a statement about the night;
///   a hairline reads as "nothing recorded", which is a statement about the
///   data. They are different claims and only one of them is true.
/// * **Fill encodes method** ([SleepBarFill]) so a week of typed entries can
///   never pass for a week of measurement.
/// * **In-bed time sits behind the sleep bar, not inside it.** An hour of
///   reading in bed is drawn as the fainter frame around the night, so it can
///   be seen without being counted as sleep.
class SleepBar extends StatelessWidget {
  const SleepBar({
    required this.night,
    this.height = 14,
    this.showInterruptions = true,
    super.key,
  });

  final SleepNight night;
  final double height;

  /// Awake bouts notch the bar. Off in the compact week rows, where a notch
  /// would be a single pixel and read as a rendering artefact.
  final bool showInterruptions;

  @override
  Widget build(BuildContext context) {
    final session = night.main;
    return SizedBox(
      height: height,
      child: session == null
          ? const _EmptyNightRule()
          : CustomPaint(
              painter: _SleepBarPainter(
                session: session,
                showInterruptions: showInterruptions,
              ),
              size: Size.infinite,
            ),
    );
  }
}

/// A night with nothing in it: one hairline across the row.
class _EmptyNightRule extends StatelessWidget {
  const _EmptyNightRule();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(height: 1, color: TrainColors.hairline),
  );
}

class _SleepBarPainter extends CustomPainter {
  const _SleepBarPainter({
    required this.session,
    required this.showInterruptions,
  });

  final SleepSession session;
  final bool showInterruptions;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = SleepBarFill.forMethod(session.provenance.method);
    final radius = Radius.circular(size.height / 2);

    // In bed, behind: visible, and clearly not the sleep itself.
    final inBedStart = session.inBedStartAt;
    final inBedEnd = session.inBedEndAt;
    if (inBedStart != null && inBedEnd != null) {
      final rect = _rect(
        _fractionOf(inBedStart, session.startOffsetMinutes),
        _fractionOf(inBedEnd, session.endOffsetMinutes),
        size,
        inset: 0,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()..color = TrainColors.sleepAccent.withValues(alpha: 0.14),
      );
    }

    final rect = _rect(
      SleepAxis.fractionFor(session.localBedtimeMinutes),
      SleepAxis.fractionFor(session.localWakeMinutes),
      size,
      inset: 1.5,
    );
    final rrect = RRect.fromRectAndRadius(rect, radius);

    switch (fill) {
      case SleepBarFill.solid:
        canvas.drawRRect(rrect, Paint()..color = TrainColors.sleepGlyph);
      case SleepBarFill.muted:
        canvas.drawRRect(
          rrect,
          Paint()..color = TrainColors.sleepAccent.withValues(alpha: 0.55),
        );
      case SleepBarFill.outlined:
        _outline(canvas, rrect);
      case SleepBarFill.hatched:
        _hatch(canvas, rrect);
        _outline(canvas, rrect);
    }

    if (!showInterruptions) return;
    // Awake bouts are cut OUT of the bar rather than drawn over it: a notch
    // says "no sleep happened here", where an overlay would only say "look at
    // this bit".
    final notch = Paint()..blendMode = BlendMode.clear;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRRect(rrect, Paint()..color = const Color(0x00000000));
    for (final interruption in session.interruptions) {
      final gap = _rect(
        _fractionOf(interruption.startAt, session.startOffsetMinutes),
        _fractionOf(interruption.endAt, session.startOffsetMinutes),
        size,
        inset: 0,
      );
      canvas.drawRect(gap, notch);
    }
    canvas.restore();
  }

  void _outline(Canvas canvas, RRect rrect) => canvas.drawRRect(
    rrect.deflate(0.5),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = TrainColors.sleepGlyph.withValues(alpha: 0.75),
  );

  /// Diagonal stripes — the visual shorthand for "provisional".
  void _hatch(Canvas canvas, RRect rrect) {
    canvas.save();
    canvas.clipRRect(rrect);
    final paint = Paint()
      ..color = TrainColors.sleepAccent.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final bounds = rrect.outerRect;
    for (var x = bounds.left - bounds.height; x < bounds.right; x += 5) {
      canvas.drawLine(
        Offset(x, bounds.bottom),
        Offset(x + bounds.height, bounds.top),
        paint,
      );
    }
    canvas.restore();
  }

  /// A UTC instant's place on the axis, read through the offset it was lived
  /// in — so a night slept abroad lands where its own clock put it.
  double _fractionOf(DateTime utc, int offsetMinutes) {
    final local = utc.add(Duration(minutes: offsetMinutes));
    return SleepAxis.fractionFor(local.hour * 60 + local.minute);
  }

  Rect _rect(double start, double end, Size size, {required double inset}) {
    final left = start * size.width;
    // A bar that would round to nothing is still a real night; a two-pixel
    // minimum keeps a short one visible instead of vanishing into the axis.
    final right = (end * size.width).clamp(left + 2, size.width);
    return Rect.fromLTRB(left, inset, right, size.height - inset);
  }

  @override
  bool shouldRepaint(_SleepBarPainter old) =>
      old.session != session || old.showInterruptions != showInterruptions;
}
