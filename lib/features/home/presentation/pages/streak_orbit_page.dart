import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../../workout/domain/live_session.dart';
import '../../../workout/domain/training_day_mark.dart';
import '../../../workout/domain/training_streak.dart';

/// The **Streak Orbit** — the visual, celebratory face of your consistency,
/// opened by tapping Today's Momentum card.
///
/// The Workout hub already has a plain, list-style `WorkoutStreakPage` for the
/// mechanics (the rule, the day-by-day rows, spending a restore). This is the
/// opposite register: one luminous scene. A pulsing ember flame at the centre
/// holds the streak count; every day in the current run rides a slowly turning
/// ring of light around it — a bright green bead for a day you trained, a
/// faint tick for a rest day the rule allows, an ember dot where a restore
/// bridged the gap. The most recent trained day carries the ember "you are
/// here" ring.
///
/// Every number comes from the SAME [computeTrainingStreak] the Momentum card
/// and the hub page read, so the three surfaces can never disagree. The page
/// owns its own [AppScope] streams, so it stays live while open.
class StreakOrbitPage extends StatelessWidget {
  const StreakOrbitPage({super.key, this.now});

  /// The clock "today" is judged against — real wall time in production,
  /// injectable so a widget test can assert a fixed streak regardless of when
  /// it runs (the same reason Today's sections take one).
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final clock = now ?? DateTime.now;
    final marksRepo = scope.trainingDayMarks;
    return TrainScreen(
      tint: TrainColors.hubTint,
      child: StreamBuilder<List<LiveSession>>(
        stream: scope.workoutSessions.watchAll(),
        initialData: scope.workoutSessions.current,
        builder: (context, sessionsSnapshot) {
          final sessions = sessionsSnapshot.data ?? const <LiveSession>[];
          return StreamBuilder<List<TrainingDayMark>>(
            stream: marksRepo?.watchAll() ?? const Stream.empty(),
            initialData: marksRepo?.current ?? const <TrainingDayMark>[],
            builder: (context, marksSnapshot) {
              final marks = marksSnapshot.data ?? const <TrainingDayMark>[];
              final streak = computeTrainingStreak(
                sessions: sessions,
                now: clock(),
                marks: marks,
              );
              // Lifetime distinct days trained — a record independent of the
              // current run, so a broken streak still has something proud to
              // show.
              final trainedTotal = trainedDayCounts(sessions).length;
              return _OrbitBody(streak: streak, trainedTotal: trainedTotal);
            },
          );
        },
      ),
    );
  }
}

class _OrbitBody extends StatelessWidget {
  const _OrbitBody({required this.streak, required this.trainedTotal});

  final TrainingStreak streak;
  final int trainedTotal;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(22, 12, 22, TrainBottomInset.of(context)),
      children: [
        TrainPageHeader(title: l(context).streakOrbitTitle),
        const SizedBox(height: 8),
        RiseIn(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(constraints.maxWidth, 360.0);
              return Center(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: _OrbitScene(streak: streak),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        RiseIn(
          delay: const Duration(milliseconds: 90),
          child: _RuleLine(streak: streak),
        ),
        const SizedBox(height: 22),
        RiseIn(
          delay: const Duration(milliseconds: 150),
          child: Row(
            children: [
              Expanded(
                child: _RecordTile(
                  value: '${streak.bestDays}',
                  label: l(context).streakOrbitBestLabel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RecordTile(
                  value: '$trainedTotal',
                  label: l(context).streakOrbitTrainedTotal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The turning ring of light with the flame at its heart. A [Stack] of a
/// painted layer (glow, orbit ring, day beads) beneath crisp, localized text —
/// numbers stay in the real font rather than being drawn onto the canvas.
class _OrbitScene extends StatefulWidget {
  const _OrbitScene({required this.streak});

  final TrainingStreak streak;

  @override
  State<_OrbitScene> createState() => _OrbitSceneState();
}

class _OrbitSceneState extends State<_OrbitScene>
    with TickerProviderStateMixin {
  /// One slow full turn — a constellation drifting, never a spinner.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 64),
  );

  /// The flame's breath — a calm in-and-out, not a heartbeat.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );

  bool _motionStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the platform's reduce-motion setting: a passive ambient scene
    // must hold still rather than drift, so it settles on one frame instead of
    // running the controllers.
    if (!reducedMotion(context) && !_motionStarted) {
      _motionStarted = true;
      _spin.repeat();
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streak = widget.streak;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: Listenable.merge([_spin, _pulse]),
            builder: (context, _) {
              final pulse = reducedMotion(context)
                  ? 0.5
                  : Curves.easeInOut.transform(_pulse.value);
              return CustomPaint(
                painter: _OrbitPainter(
                  days: streak.days,
                  rotation: _spin.value * 2 * math.pi,
                  pulse: pulse,
                  active: streak.isActive,
                ),
              );
            },
          ),
        ),
        _OrbitCentre(streak: streak),
      ],
    );
  }
}

/// The flame's core reading: the streak count in the app's one hero size, over
/// a mono caption. Sits above the painted glow so the digits stay sharp.
class _OrbitCentre extends StatelessWidget {
  const _OrbitCentre({required this.streak});

  final TrainingStreak streak;

  @override
  Widget build(BuildContext context) {
    final active = streak.isActive;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${streak.currentDays}',
          style: TrainType.mono(
            size: 68,
            weight: FontWeight.w300,
            tracking: -0.05,
            color: active ? TrainColors.ink : TrainColors.inkAt(0.5),
            height: 1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l(context).workoutDayStreak.toUpperCase(),
          style: TrainType.caption(
            size: 9.5,
            tracking: 0.22,
            color: active
                ? TrainColors.ember.withValues(alpha: 0.8)
                : TrainColors.ink4,
          ),
        ),
      ],
    );
  }
}

/// Paints the ambient scene: a layered ember glow, one faint orbit ring, and a
/// bead for every day in the current run.
class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({
    required this.days,
    required this.rotation,
    required this.pulse,
    required this.active,
  });

  /// The current run, newest first (as [TrainingStreak.days] gives it).
  final List<StreakDay> days;
  final double rotation;

  /// 0..1 breath of the flame.
  final double pulse;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final ringRadius = size.width * 0.40;

    _paintGlow(canvas, centre, size.width);

    // The orbit path itself — a hairline the beads ride on, so the run reads
    // as one continuous loop even where a rest day sits between two sessions.
    if (active && days.isNotEmpty) {
      canvas.drawCircle(
        centre,
        ringRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = TrainColors.green.withValues(alpha: 0.12),
      );
      _paintBeads(canvas, centre, ringRadius, size.width);
    }
  }

  void _paintGlow(Canvas canvas, Offset centre, double width) {
    // Depth from light, not shadow (identity §5): a few blurred discs stacked
    // warm-to-bright fake a soft bloom without a shader. The flame breathes on
    // [pulse]; when there's no streak it cools to a dim, still ember.
    final base = active ? 1.0 : 0.4;
    final breath = 0.85 + pulse * 0.15;
    final layers = <(double radiusFactor, double alpha)>[
      (0.42, 0.16 * base),
      (0.30, 0.20 * base),
      (0.20, 0.28 * base),
      (0.12, 0.42 * base),
    ];
    for (final (rf, a) in layers) {
      final r = width * rf * breath;
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..color = TrainColors.ember.withValues(alpha: a)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55),
      );
    }
    // A tight, brighter heart on top of the wash.
    canvas.drawCircle(
      centre,
      width * 0.05 * breath,
      Paint()
        ..color = TrainColors.emberLift.withValues(alpha: 0.5 * base)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  void _paintBeads(Canvas canvas, Offset centre, double radius, double width) {
    final n = days.length;
    // Even spacing round the loop; a long run becomes a dense halo of light,
    // which is itself the reward. Newest day starts at the top and the ring
    // turns from there.
    final step = 2 * math.pi / n;
    // The most recent trained day — the one bead that carries the ember "you
    // are here" marker (identity reserves ember for the current position).
    final newestTrained = days.indexWhere((d) => d.isTrained);

    final beadR = (width * 0.020).clamp(2.2, 7.2);
    for (var i = 0; i < n; i++) {
      final day = days[i];
      final angle = -math.pi / 2 + i * step + rotation;
      final pos =
          centre + Offset(math.cos(angle), math.sin(angle)) * radius;

      switch (day.kind) {
        case StreakDayKind.trained:
          final isNewest = i == newestTrained;
          final colour = isNewest ? TrainColors.ember : TrainColors.green;
          // A double day (trained twice) sits a touch brighter and larger.
          final grow = day.sessionCount > 1 ? 1.3 : 1.0;
          final r = beadR * (isNewest ? 1.25 : 1.0) * grow;
          // Soft halo.
          canvas.drawCircle(
            pos,
            r * 2.4,
            Paint()
              ..color = colour.withValues(alpha: 0.28)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.6),
          );
          canvas.drawCircle(
            pos,
            r,
            Paint()..color = colour.withValues(alpha: 0.95),
          );
          if (isNewest) {
            // The "you are here" ring around the freshest bead.
            canvas.drawCircle(
              pos,
              r * 1.9,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4
                ..color = TrainColors.ember.withValues(alpha: 0.75),
            );
          }
        case StreakDayKind.restored:
          // A repair: a small ember dot, quieter than a trained day.
          canvas.drawCircle(
            pos,
            beadR * 0.7,
            Paint()..color = TrainColors.ember.withValues(alpha: 0.65),
          );
        case StreakDayKind.rest:
          // The rest the rule assumes — a faint tick, present but unlit, so
          // the loop stays continuous instead of showing a hole.
          canvas.drawCircle(
            pos,
            beadR * 0.42,
            Paint()..color = TrainColors.inkAt(0.28),
          );
      }
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.rotation != rotation ||
      old.pulse != pulse ||
      old.active != active ||
      old.days != days;
}

/// The rule the number obeys, and how much room is left in it — the two lines
/// that turn a score into a statement about the next few days. Mirrors the
/// hub page's rule line so the two never say different things.
class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.streak});

  final TrainingStreak streak;

  @override
  Widget build(BuildContext context) {
    final left = streak.daysUntilBreak;
    return Column(
      children: [
        Text(
          streak.isActive
              ? l(context).workoutStreakRule(kStreakMaxGapDays)
              : l(context).workoutStreakEmpty,
          textAlign: TextAlign.center,
          style: TrainType.ui(size: 12.5, color: TrainColors.ink3),
        ),
        const SizedBox(height: 4),
        Text(
          left == null
              ? l(context).workoutStreakBroken
              : l(context).workoutStreakDaysLeft(left),
          textAlign: TextAlign.center,
          style: TrainType.mono(
            size: 10,
            tracking: 0.08,
            color: streak.isAtRisk
                ? TrainColors.ember
                : TrainColors.inkAt(0.4),
          ),
        ),
      ],
    );
  }
}

/// One record: a big mono figure over a caption, on the house glass surface.
class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
      decoration: BoxDecoration(
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ltrFor(context, value),
            style: TrainType.mono(
              size: 26,
              weight: FontWeight.w300,
              tracking: -0.04,
              color: TrainColors.ink,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TrainType.caption(
              size: 9,
              tracking: 0.14,
              color: TrainColors.ink4,
            ),
          ),
        ],
      ),
    );
  }
}
