import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/train_tokens.dart';
import 'pressable_scale.dart';
import 'train_chrome.dart';

/// The **surface** half of the workout-tracking design language — the pieces
/// every handoff screen beyond the workout flow is assembled from: the tinted
/// page scaffold, the pushed-page header, section labels, list rows, the 2×2
/// stat tile with its own sparkline, category bars, and the FAB.
///
/// [train_chrome.dart] holds the other half — the actions and the live
/// session's own chrome (primary/ghost pills, the segment bar, metric rings).
/// Both are presentational and take values + callbacks, never repositories,
/// so each feature composes them from its existing data sources.
///
/// The rules these encode, from the handoff's identity doc:
///
/// * **Depth from light, not shadow** — a 1px hairline over a top-lit
///   gradient; the only shadow in the app is the colored bloom under a
///   primary pill or FAB.
/// * **Captions are mono, uppercase, wide** — 8.5–10px, .14–.24em, 28–40%.
/// * **One hero number per screen** — a tile's value is the tile's hero, and
///   its unit is always smaller and dimmer than the value it belongs to.
/// * **Single-hue icon tiles** — a 13% tint of one colour with a 22% border,
///   never a saturated multi-hue chip.

// ---------------------------------------------------------------------------
// Page scaffolding
// ---------------------------------------------------------------------------

/// A handoff screen's ground: the near-black base under the one soft radial
/// glow that screen is allowed (identity §2, "screen glows"), with the whole
/// page laid over it.
///
/// Every screen gets exactly one glow, tinted toward that screen's meaning —
/// green for training, violet for the assistant, amber for money. Pass the
/// matching `TrainColors.*Tint`.
class TrainScreen extends StatelessWidget {
  const TrainScreen({
    required this.tint,
    required this.child,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset,
    super.key,
  });

  final Gradient tint;
  final Widget child;
  final Widget? floatingActionButton;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TrainColors.base,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      floatingActionButton: floatingActionButton,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: tint),
        child: SafeArea(bottom: false, child: child),
      ),
    );
  }
}

/// The pushed-page header the handoff repeats on Workout, Diet, Expenses,
/// Moments and Settings: a 36px glass back circle, the screen title in
/// Manrope 800/27, and one optional accent-tinted action on the right.
class TrainPageHeader extends StatelessWidget {
  const TrainPageHeader({
    required this.title,
    this.onBack,
    this.action,
    super.key,
  });

  final String title;

  /// Defaults to popping the route.
  final VoidCallback? onBack;

  /// The single trailing action — build it with [TrainHeaderAction].
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TrainCircleButton(
          semanticLabel: 'Back',
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
          child: const Icon(
            Icons.arrow_back_rounded,
            size: 17,
            color: Color(0xBFF4F4F0),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TrainType.ui(
              size: 27,
              weight: FontWeight.w800,
              tracking: -0.025,
              color: TrainColors.ink,
              height: 1,
            ),
          ),
        ),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ],
    );
  }
}

/// The header's trailing action — a 36px circle carrying one accent, tinted
/// 10% with a 22% border, exactly like the icon tiles below it.
class TrainHeaderAction extends StatelessWidget {
  const TrainHeaderAction({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.accent = TrainColors.green,
    super.key,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return TrainCircleButton(
      semanticLabel: semanticLabel,
      onTap: onTap,
      fill: accent.withValues(alpha: 0.10),
      border: accent.withValues(alpha: 0.22),
      child: Icon(icon, size: 16, color: accent),
    );
  }
}

/// A section label: the mono caption on the left, and an optional second
/// caption right-aligned carrying the section's own qualifier
/// ("LAST 7 DAYS", "−1.4 KG · 8 WKS").
class TrainSectionLabel extends StatelessWidget {
  const TrainSectionLabel(
    this.label, {
    this.trailing,
    this.trailingColor,
    super.key,
  });

  final String label;
  final String? trailing;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label.toUpperCase(),
          style: TrainType.caption(
            size: 9.5,
            tracking: 0.2,
            color: const Color(0x4DF4F4F0),
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: TrainType.caption(
              size: 9.5,
              tracking: 0.08,
              weight: trailingColor == null ? FontWeight.w400 : FontWeight.w600,
              color: trailingColor ?? const Color(0x4DF4F4F0),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rows and tiles
// ---------------------------------------------------------------------------

/// The 32px single-hue icon tile every list row and stat tile leads with —
/// a 13% tint of one colour behind a 22% border, radius 10. Never a
/// multi-hue gradient chip (identity §8).
class TrainIconTile extends StatelessWidget {
  const TrainIconTile({
    required this.icon,
    required this.accent,
    this.size = 32,
    this.iconSize = 15,
    this.radius = 10,
    super.key,
  });

  final IconData icon;
  final Color accent;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, size: iconSize, color: accent),
    );
  }
}

/// One row of a [TrainListCard]: icon tile · Manrope 700/15 label · mono
/// value · 7px chevron at 30%.
///
/// [trailing] replaces the value+chevron pair outright, for rows whose right
/// edge is a state badge (the Google row's green `CONNECTED`) rather than a
/// value to drill into.
class TrainListRow extends StatelessWidget {
  const TrainListRow({
    required this.icon,
    required this.accent,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.iconTile,
    super.key,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Overrides the leading tile outright — for the Google mark and other
  /// brand glyphs that aren't a stroked icon.
  final Widget? iconTile;

  /// The divider inset — the icon column's width, so rules start at the
  /// label rather than cutting under the tile (identity §4).
  static const double dividerInset = 63;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
      child: Row(
        children: [
          iconTile ?? TrainIconTile(icon: icon, accent: accent),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TrainType.ui(
                size: 15,
                weight: FontWeight.w700,
                color: TrainColors.inkPlain,
                height: 1.1,
              ),
            ),
          ),
          if (trailing != null)
            trailing!
          else ...[
            if (value != null)
              Text(
                value!,
                style: TrainType.mono(size: 12.5, color: TrainColors.ink4),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Color(0x4DF4F4F0),
              ),
            ],
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: row,
      ),
    );
  }
}

/// The hairline card [TrainListRow]s sit in, with each rule inset by the icon
/// column so it starts at the label.
class TrainListCard extends StatelessWidget {
  const TrainListCard({required this.rows, this.radius = 20, super.key});

  final List<Widget> rows;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.only(left: TrainListRow.dividerInset),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: TrainColors.hairline,
                ),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One tile of the Workout hub's 2×2 grid: the icon tile, then the value with
/// its dimmer unit, the Manrope label, and — instead of a chevron — a small
/// chart of the thing the number measures ([chart]).
///
/// The handoff swaps the chevron out on purpose: a tile that shows the shape
/// of its own metric earns its space; one that shows an arrow just says
/// "there is more elsewhere".
class TrainStatTile extends StatelessWidget {
  const TrainStatTile({
    required this.icon,
    required this.accent,
    required this.value,
    required this.label,
    this.unit,
    this.chart,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final Color accent;
  final String value;
  final String? unit;
  final String label;

  /// A sparkline or bar cluster, pinned bottom-right.
  final Widget? chart;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
      decoration: BoxDecoration(
        gradient: TrainColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TrainIconTile(icon: icon, accent: accent, size: 30),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TrainType.mono(
                        size: 30,
                        weight: FontWeight.w400,
                        tracking: -0.04,
                        color: const Color(0xFFF9F9F5),
                      ),
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      unit!,
                      style: TrainType.mono(
                        size: 10,
                        weight: FontWeight.w500,
                        tracking: 0.1,
                        color: const Color(0x4DF4F4F0),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 9),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TrainType.ui(
                  size: 11.5,
                  weight: FontWeight.w600,
                  color: const Color(0x80F4F4F0),
                  height: 1,
                ),
              ),
            ],
          ),
          if (chart != null)
            Positioned(
              right: 0,
              bottom: 2,
              child: IgnorePointer(child: chart!),
            ),
        ],
      ),
    );

    if (onTap == null) return body;
    return PressableScale(
      scale: 0.985,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: body,
      ),
    );
  }
}

/// An n-up mono readout split by vertical hairlines — the You screen's
/// `128 / 14 / 412t` card and the metric footer under a hero value
/// (identity §5, "metric card").
class TrainStatStrip extends StatelessWidget {
  const TrainStatStrip({
    required this.items,
    this.valueSize = 22,
    this.centered = true,
    this.dividerColor = const Color(0x14FFFFFF),
    super.key,
  });

  final List<TrainStat> items;
  final double valueSize;
  final bool centered;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Container(width: 1, color: dividerColor),
            Expanded(
              child: Column(
                crossAxisAlignment: centered
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    items[i].value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TrainType.mono(
                      size: valueSize,
                      tracking: -0.03,
                      color: items[i].color ?? const Color(0xFFF9F9F5),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    items[i].label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TrainType.caption(
                      size: 8,
                      tracking: 0.16,
                      color: TrainColors.ink4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One column of a [TrainStatStrip].
class TrainStat {
  const TrainStat(this.value, this.label, {this.color});

  final String value;
  final String label;

  /// Green marks the one figure in the strip that means "progress"
  /// (lifetime volume); the rest stay plain ink.
  final Color? color;
}

// ---------------------------------------------------------------------------
// Charts
// ---------------------------------------------------------------------------

/// A bare polyline — the shape of a metric, no axes, no labels. Sized by its
/// parent; values are normalised over their own min/max.
class TrainSparkline extends StatelessWidget {
  const TrainSparkline({
    required this.values,
    required this.color,
    this.width = 72,
    this.height = 20,
    this.strokeWidth = 1.6,
    super.key,
  });

  final List<double> values;
  final Color color;
  final double width;
  final double height;
  final double strokeWidth;

  /// Whether [values] would draw anything worth looking at — at least two
  /// points, and some actual variation between them. A flat series renders as
  /// a horizontal rule that reads as a stray divider, so callers check this
  /// and leave the slot to something else (identity §7).
  static bool hasShape(List<double> values) =>
      values.length >= 2 && values.reduce(math.max) != values.reduce(math.min);

  @override
  Widget build(BuildContext context) {
    if (!hasShape(values)) return SizedBox(width: width, height: height);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _SparkPainter(values, color, strokeWidth)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.values, this.color, this.strokeWidth);

  final List<double> values;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _seriesPath(values, size, strokeWidth / 2);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.color != color || !listEquals(old.values, values);
}

/// A filled trend chart — the line, a fade of its own colour beneath it, and
/// a dot on the last reading. The Workout hub's bodyweight card and the
/// assistant's answer card both run on this.
class TrainAreaChart extends StatelessWidget {
  const TrainAreaChart({
    required this.values,
    required this.color,
    this.height = 52,
    this.endDot = true,
    super.key,
  });

  final List<double> values;
  final Color color;
  final double height;
  final bool endDot;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _AreaPainter(values, color, endDot)),
    );
  }
}

class _AreaPainter extends CustomPainter {
  const _AreaPainter(this.values, this.color, this.endDot);

  final List<double> values;
  final Color color;
  final bool endDot;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 4.0;
    final line = _seriesPath(values, size, inset);
    final metrics = line.getBounds();
    if (metrics.isEmpty && values.length < 2) return;

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, size.height), [
          color.withValues(alpha: 0.30),
          color.withValues(alpha: 0.0),
        ]),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    if (endDot) {
      canvas.drawCircle(
        _pointAt(values, values.length - 1, size, inset),
        3.4,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.color != color || !listEquals(old.values, values);
}

/// The bar cluster the streak tile carries instead of a sparkline — a count
/// reads as discrete bars, not a continuous line. The last bar is the live
/// one and carries the full accent.
class TrainBarCluster extends StatelessWidget {
  const TrainBarCluster({
    required this.values,
    required this.color,
    this.barWidth = 5,
    this.maxHeight = 18,
    super.key,
  });

  final List<double> values;
  final Color color;
  final double barWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final peak = values.reduce(math.max);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: 2.5),
          Container(
            width: barWidth,
            height: peak <= 0 ? 4 : math.max(4, maxHeight * (values[i] / peak)),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              color: i == values.length - 1
                  ? color
                  : color.withValues(alpha: 0.55),
            ),
          ),
        ],
      ],
    );
  }
}

/// Normalises [values] over their own range and returns the polyline across
/// the full width of [size], inset vertically by [inset] so a round cap or an
/// end dot never clips.
Path _seriesPath(List<double> values, Size size, double inset) {
  final path = Path();
  for (var i = 0; i < values.length; i++) {
    final p = _pointAt(values, i, size, inset);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path;
}

Offset _pointAt(List<double> values, int i, Size size, double inset) {
  final min = values.reduce(math.min);
  final max = values.reduce(math.max);
  final span = max - min;
  final usable = math.max(1.0, size.height - inset * 2);
  final dx = values.length == 1
      ? size.width / 2
      : size.width * (i / (values.length - 1));
  // A flat series draws through the middle rather than pinned to an edge.
  final t = span == 0 ? 0.5 : (values[i] - min) / span;
  return Offset(dx, inset + usable * (1 - t));
}

/// A 4px progress bar — the category rows on Expenses and the macro bars on
/// Diet. The track is the standard hairline so an empty bar still reads as a
/// bar rather than as nothing.
class TrainBar extends StatelessWidget {
  const TrainBar({
    required this.progress,
    required this.color,
    this.height = 4,
    this.animate = true,
    super.key,
  });

  /// 0..1; values above 1 clamp so an over-target bar never overflows.
  final double progress;
  final Color color;
  final double height;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final target = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: const Color(0x14FFFFFF),
        child: Align(
          alignment: Alignment.centerLeft,
          child: animate
              ? TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: target),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => FractionallySizedBox(
                    widthFactor: t,
                    child: Container(color: color),
                  ),
                )
              : FractionallySizedBox(
                  widthFactor: target,
                  child: Container(color: color),
                ),
        ),
      ),
    );
  }
}

/// Label + right-aligned mono amount on one line, with the 4px bar beneath —
/// the Expenses category row and Diet's macro rows. Amounts stay in a single
/// right-hand mono column so the eye reads straight down them.
class TrainBarRow extends StatelessWidget {
  const TrainBarRow({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
    this.labelStyle,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final double progress;
  final Color color;
  final TextStyle? labelStyle;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    labelStyle ??
                    TrainType.ui(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: TrainColors.inkPlain,
                      height: 1.1,
                    ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              value,
              style: TrainType.mono(
                size: 13,
                tracking: -0.02,
                color: valueColor ?? TrainColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TrainBar(progress: progress, color: color),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Actions and empty states
// ---------------------------------------------------------------------------

/// The 58px bottom-right FAB — radius 20 (not a circle), under its own
/// colored bloom. Ember on the training and capture surfaces, amber on
/// Expenses, because amber is money and nothing else.
class TrainFab extends StatelessWidget {
  const TrainFab({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.color = TrainColors.ember,
    this.iconColor = Colors.white,
    super.key,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.96,
      child: Tooltip(
        message: semanticLabel,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: TrainColors.actionGlow(color, alpha: 0.34),
          ),
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                HapticFeedback.mediumImpact();
                onTap();
              },
              child: SizedBox(
                width: 58,
                height: 58,
                child: Icon(icon, size: 24, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A filter pill — ember when it's the selected one, glass when it isn't.
/// Ember is allowed here because the selected filter *is* the screen's
/// current position marker (identity §3).
class TrainFilterPill extends StatelessWidget {
  const TrainFilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.97,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? TrainColors.ember.withValues(alpha: 0.12)
                : TrainColors.glass,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? TrainColors.ember.withValues(alpha: 0.35)
                  : TrainColors.hairline,
            ),
          ),
          child: Text(
            label,
            style: TrainType.ui(
              size: 12.5,
              weight: FontWeight.w700,
              color: selected ? TrainColors.ember : const Color(0x8CF4F4F0),
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed empty state — a prompt with nothing behind it yet. Dashed,
/// never a filled card, so an empty slot never reads as a real surface
/// waiting on data (identity §8).
class TrainDashedCard extends StatelessWidget {
  const TrainDashedCard({
    required this.child,
    this.onTap,
    this.radius = 18,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16),
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final body = CustomPaint(
      painter: _DashedBorderPainter(radius: radius),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return body;
    return PressableScale(
      scale: 0.99,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: body,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x1CFFFFFF);
    // 5-on / 4-off, walked around the rounded rect by path metrics — Flutter
    // has no dashed stroke of its own.
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + 5, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + 4;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.radius != radius;
}
