import 'dart:async';
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../workout/domain/live_session.dart';
import '../../../workout/domain/workout_day.dart';
import '../../../workout/domain/workout_plan.dart';
import '../../../workout/presentation/pages/live_session_page.dart';
import 'common.dart';
import 'hue.dart';

/// A light "Up next" card for the Today page's Training section — the day
/// due next in the active plan's rotation, with a prominent Start/Resume CTA
/// that (after a confirming dark sheet, guarding against an accidental tap)
/// drops straight into [LiveSessionPage], skipping Hub → Workout entirely.
///
/// Compacts and comes "alive" with a slow drifting ember wash (see
/// [_AliveBackground]) whenever [resumable] is non-null — an active/paused
/// session is already under way for this day.
class UpNextWorkoutCard extends StatefulWidget {
  const UpNextWorkoutCard({required this.plan, required this.day, required this.resumable, super.key});

  final WorkoutPlan plan;
  final WorkoutDay day;

  /// A same plan/day active session to resume into, or null to start fresh.
  final LiveSession? resumable;

  @override
  State<UpNextWorkoutCard> createState() => _UpNextWorkoutCardState();
}

class _UpNextWorkoutCardState extends State<UpNextWorkoutCard> {
  /// Measures the CTA's own on-screen position so the confirm sheet can
  /// spring in anchored to it, rather than just materializing screen-center.
  final _ctaKey = GlobalKey();

  Future<void> _onTap() async {
    final isResume = widget.resumable != null;
    final confirmed = await _showStartConfirmSheet(
      context: context,
      anchorKey: _ctaKey,
      dayLabel: widget.day.label,
      exerciseCount: widget.day.exerciseCount,
      isResume: isResume,
    );
    if (confirmed != true || !mounted) return;
    // The confirm's own selectionClick already fired at the moment of tap
    // (see [_StartConfirmSheetState._resolve]) — no second haptic here.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LiveSessionPage(day: widget.day, plan: widget.plan, resume: widget.resumable),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isResume = widget.resumable != null;
    final card = ZCard(
      // While active, the fill goes transparent so the drifting ember wash
      // behind it (see [_AliveBackground]) shows through the card itself —
      // otherwise the normal opaque ember gradient.
      wash: isResume ? Colors.transparent : null,
      gradient: isResume
          ? null
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.emberWash, AppColors.card],
              stops: [0.0, 0.85],
            ),
      borderColor: AppColors.ember.withValues(alpha: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeaderRow(hue: ZHue.ember, label: isResume ? 'Resume' : 'Up next'),
          const SizedBox(height: AppSpacing.m + 1),
          Text(widget.day.label, style: AppText.cardTitle),
          const SizedBox(height: 6),
          Text(
            '${widget.day.exerciseCount} exercise${widget.day.exerciseCount == 1 ? '' : 's'}',
            style: AppText.meta.copyWith(color: AppColors.emberText),
          ),
          const SizedBox(height: 18),
          Container(
            key: _ctaKey,
            child: PillButton(
              label: isResume ? 'Resume Workout' : 'Start Workout',
              icon: Icons.play_arrow_rounded,
              color: AppColors.ember,
              enabled: true,
              onTap: _onTap,
            ),
          ),
        ],
      ),
    );
    return _CardScale(
      active: isResume,
      child: isResume
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Stack(
                children: [const Positioned.fill(child: _AliveBackground()), card],
              ),
            )
          : card,
    );
  }
}

/// Springs the card to a slightly smaller, more compact scale whenever
/// [active] is true (a session is under way for this day) — critically
/// damped, ~0.4s response, no bounce (this is a state reflection, not a
/// momentum-driven gesture). Settles instantly under reduced motion.
class _CardScale extends StatefulWidget {
  const _CardScale({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_CardScale> createState() => _CardScaleState();
}

class _CardScaleState extends State<_CardScale> with SingleTickerProviderStateMixin {
  static const _compactScale = 0.96;
  static final _spring = appleSpring(damping: 1.0, response: 0.4);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.active ? _compactScale : 1.0,
  );

  @override
  void didUpdateWidget(covariant _CardScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    final target = widget.active ? _compactScale : 1.0;
    if (reducedMotion(context)) {
      _controller.value = target;
    } else {
      _controller.animateWith(SpringSimulation(_spring, _controller.value, target, 0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(scale: _controller.value, child: child),
      child: widget.child,
    );
  }
}

/// The card's "alive while active" background (Feature 2) — a single soft,
/// blurred ember-colored blob that drifts slowly back and forth, clipped to
/// the card. Reuses only [AppColors.ember] (the card's own hue, no new
/// colors); the blob itself is built ONCE and passed as [AnimatedBuilder]'s
/// `child`, so only a [Transform.translate] repaints per frame — the blur
/// and gradient are never re-rendered, keeping this compositor-friendly.
/// Motion is slow (18s round trip, well clear of the ~5s/0.2Hz range the
/// reduced-motion guidance warns about) and low-opacity — ambient warmth,
/// not a distraction. Only ever mounted while the session is active (see
/// [_UpNextWorkoutCardState.build]), so its ticker starts/stops with that —
/// nothing runs when there's nothing to show.
class _AliveBackground extends StatefulWidget {
  const _AliveBackground();

  @override
  State<_AliveBackground> createState() => _AliveBackgroundState();
}

class _AliveBackgroundState extends State<_AliveBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blob = ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.ember.withValues(alpha: 0.22),
        ),
      ),
    );
    if (reducedMotion(context)) {
      // A barely-there static wash instead of drifting motion.
      return Opacity(opacity: 0.6, child: Align(alignment: const Alignment(0.4, -0.3), child: blob));
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final dx = lerpDouble(-26, 26, t)!;
        final dy = lerpDouble(-14, 18, t)!;
        return Align(
          alignment: const Alignment(0.3, -0.2),
          child: Transform.translate(offset: Offset(dx, dy), child: child),
        );
      },
      child: blob,
    );
  }
}

/// Shows the dark confirm sheet, anchored (its spring-in transform origin)
/// to the CTA button measured via [anchorKey]. Falls back to a bottom anchor
/// if the button's [RenderBox] isn't available for some reason. Resolves to
/// `true` on Start/Resume, `false`/null on Cancel, a drag-down dismiss, or a
/// tap on the dimmed backdrop.
Future<bool?> _showStartConfirmSheet({
  required BuildContext context,
  required GlobalKey anchorKey,
  required String dayLabel,
  required int exerciseCount,
  required bool isResume,
}) {
  final anchorBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  var anchor = const Alignment(0, 0.6);
  if (anchorBox != null && anchorBox.hasSize) {
    final screenSize = MediaQuery.of(context).size;
    final center = anchorBox.localToGlobal(anchorBox.size.center(Offset.zero));
    anchor = Alignment(
      ((center.dx / screenSize.width) * 2 - 1).clamp(-1.0, 1.0),
      ((center.dy / screenSize.height) * 2 - 1).clamp(-1.0, 1.0),
    );
  }
  return showGeneralDialog<bool>(
    context: context,
    // The sheet handles its own animated, backdrop-tap dismiss (see
    // [_StartConfirmSheetState._resolve]) so the exit stays symmetric with
    // the entrance rather than the framework's instant barrier-tap pop.
    barrierDismissible: false,
    barrierLabel: 'Start workout',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    // Zero — the built-in route transition is skipped entirely; the sheet
    // drives its own spring on mount/dismiss (see [_StartConfirmSheet]),
    // same convention as the live session's own [_PopIn]/[_GoalBlock] pops.
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => _StartConfirmSheet(
      anchor: anchor,
      dayLabel: dayLabel,
      exerciseCount: exerciseCount,
      isResume: isResume,
    ),
  );
}

class _StartConfirmSheet extends StatefulWidget {
  const _StartConfirmSheet({
    required this.anchor,
    required this.dayLabel,
    required this.exerciseCount,
    required this.isResume,
  });

  final Alignment anchor;
  final String dayLabel;
  final int exerciseCount;
  final bool isResume;

  @override
  State<_StartConfirmSheet> createState() => _StartConfirmSheetState();
}

class _StartConfirmSheetState extends State<_StartConfirmSheet> with TickerProviderStateMixin {
  /// Materialize: drives scale + opacity + backdrop blur together, 0 (not
  /// arrived) to 1 (settled/dismissed-away) — critically damped (no
  /// overshoot; a confirm sheet isn't a momentum-driven gesture), at Apple's
  /// own drawer/sheet response (~0.35s). Also driven back to 0 for the
  /// symmetric non-drag exit (Cancel/backdrop/Start) — see [_resolve].
  late final AnimationController _controller = AnimationController(vsync: this, value: 0);

  /// The live vertical drag-down offset in px — tracked 1:1 with the
  /// pointer while dragging (never itself animated mid-drag, only on
  /// release; see [_onDragUpdate]/[_onDragEnd]), same "always animate from
  /// the presentation value" rule as the rest of this app's motion.
  late final AnimationController _drag = AnimationController.unbounded(vsync: this, value: 0);

  bool _resolving = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery isn't available in initState — this is the earliest safe
    // place, and it only needs to run once, on arrival.
    if (_started) return;
    _started = true;
    if (reducedMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.animateWith(SpringSimulation(AppSprings.standard, 0, 1, 0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _drag.dispose();
    super.dispose();
  }

  /// The single exit path for Cancel, a backdrop tap, and Start/Resume:
  /// retraces the entrance (scale/opacity/blur spring back to 0 from
  /// wherever they currently sit — mid-flight-safe) before popping, so the
  /// sheet never just vanishes. The drag-down-past-threshold dismiss in
  /// [_onDragEnd] is deliberately separate — it continues the gesture's own
  /// downward trajectory instead (spatial consistency: a thrown gesture
  /// exits the way it was already going, not back the way it came).
  Future<void> _resolve(bool confirmed) async {
    if (_resolving) return;
    _resolving = true;
    if (confirmed) HapticFeedback.selectionClick();
    if (reducedMotion(context)) {
      if (mounted) Navigator.of(context).pop(confirmed);
      return;
    }
    await _controller.animateWith(SpringSimulation(AppSprings.standard, _controller.value, 0, 0));
    if (mounted) Navigator.of(context).pop(confirmed);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_resolving) return;
    final next = _drag.value + details.delta.dy;
    _drag.value = next < 0 ? 0 : next; // drag-down only; ignore upward past origin
  }

  void _onDragEnd(DragEndDetails details) {
    if (_resolving) return;
    final velocity = details.velocity.pixelsPerSecond.dy;
    // Momentum projection (see the apple-design skill's §6): decide by
    // where the gesture is *going*, not just where it was released.
    final projected = _drag.value + _projectMomentum(velocity);
    if (projected > _dismissDistance) {
      // Continue the drag's own downward trajectory while the surface
      // fades — velocity carried through, no hard cut.
      _drag.animateWith(
        SpringSimulation(AppSprings.standard, _drag.value, _drag.value + 400, velocity),
      );
      unawaited(_resolve(false));
      return;
    }
    // Short of the threshold — spring back, handing off the release
    // velocity so the reversal doesn't brick-wall.
    _drag.animateWith(SpringSimulation(AppSprings.standard, _drag.value, 0, velocity));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _drag]),
      builder: (context, child) {
        final t = _controller.value.clamp(0.0, 1.0);
        final blur = 20 * t;
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            // A Stack, not a wrapping GestureDetector, deliberately — the
            // backdrop tap-catcher and the card are SIBLINGS here rather
            // than ancestor/descendant, so there's no competing `onTap` in
            // the same gesture arena as the card's own buttons (three
            // nested tap recognizers is exactly the kind of ambiguity that
            // silently swallows the innermost tap). This is the same
            // pattern Flutter's own `ModalBarrier` uses for barrier-dismiss.
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _resolve(false),
                  ),
                ),
                Opacity(
                  // A literal 0 scale collapses the child's layout, so
                  // floor it just above zero rather than clamping
                  // independently.
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, _drag.value),
                    child: Transform.scale(
                      scale: t < 0.01 ? 0.01 : t,
                      alignment: widget.anchor,
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: GestureDetector(
        // Only the drag-down-to-cancel gesture — no competing `onTap` here,
        // so a stationary tap passes straight through to the card's own
        // buttons uncontested.
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: _StartConfirmCard(
              dayLabel: widget.dayLabel,
              exerciseCount: widget.exerciseCount,
              isResume: widget.isResume,
              onCancel: () => _resolve(false),
              onConfirm: () => _resolve(true),
            ),
          ),
        ),
      ),
    );
  }
}

/// The confirm card itself, on the shared [AppColors] dark theme — a
/// translucent glass surface (paired with the sheet's own backdrop blur
/// above it, see [_StartConfirmSheetState.build]) rather than a flat solid
/// card, so the materializing blur reads through it.
class _StartConfirmCard extends StatelessWidget {
  const _StartConfirmCard({
    required this.dayLabel,
    required this.exerciseCount,
    required this.isResume,
    required this.onCancel,
    required this.onConfirm,
  });

  final String dayLabel;
  final int exerciseCount;
  final bool isResume;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        decoration: BoxDecoration(
          color: AppColors.card.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(AppRadius.card + 4),
          border: Border.all(color: AppColors.hairline2),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 20)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isResume ? 'Ready to jump back in?' : 'Ready to start $dayLabel?',
              style: AppText.cardTitle.copyWith(color: AppColors.ink, fontSize: 21),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isResume
                  ? '$dayLabel · $exerciseCount exercise${exerciseCount == 1 ? '' : 's'}'
                  : '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'} today.',
              style: AppText.body.copyWith(color: AppColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: PressableScale(
                    child: InkWell(
                      onTap: onCancel,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.hairline2, width: 1.4),
                        ),
                        child: Text(
                          'Cancel',
                          style: AppText.button.copyWith(color: AppColors.ink2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PillButton(
                    label: isResume ? 'Resume' : 'Start',
                    icon: Icons.play_arrow_rounded,
                    color: AppColors.ember,
                    enabled: true,
                    onTap: onConfirm,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Apple's momentum-projection formula (see the apple-design skill, §6) —
/// where released momentum would coast to a stop, absent further input.
/// `decelerationRate` ≈ 0.998 matches normal scroll/fling feel.
double _projectMomentum(double velocityPxPerSec, {double decelerationRate = 0.998}) =>
    (velocityPxPerSec / 1000) * decelerationRate / (1 - decelerationRate);

/// Drag-down distance (or equivalent projected momentum) past which
/// releasing the confirm sheet commits to Cancel rather than springing back.
const double _dismissDistance = 120;
