import 'dart:async';
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';

/// Shared "Start a workout" chrome for the Today page's training card
/// ([UpNextWorkoutCard]) — factored out of it so a future second card in
/// this style reuses it rather than forking a copy: the confirm sheet
/// ([showStartConfirmSheet]), the compact-while-active spring ([CardScale]),
/// and the drifting "alive" background ([AliveColorDrift]).

/// Springs a card to a slightly smaller, more compact scale whenever [active]
/// is true (a session is under way) — critically damped, ~0.4s response, no
/// bounce (this is a state reflection, not a momentum-driven gesture).
/// Settles instantly under reduced motion.
class CardScale extends StatefulWidget {
  const CardScale({required this.active, required this.child, super.key});

  final bool active;
  final Widget child;

  @override
  State<CardScale> createState() => _CardScaleState();
}

class _CardScaleState extends State<CardScale>
    with SingleTickerProviderStateMixin {
  static const _compactScale = 0.96;
  static final _spring = appleSpring(damping: 1.0, response: 0.4);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.active ? _compactScale : 1.0,
  );

  @override
  void didUpdateWidget(covariant CardScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    final target = widget.active ? _compactScale : 1.0;
    if (reducedMotion(context)) {
      _controller.value = target;
    } else {
      _controller.animateWith(
        SpringSimulation(_spring, _controller.value, target, 0),
      );
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
      builder: (context, child) =>
          Transform.scale(scale: _controller.value, child: child),
      child: widget.child,
    );
  }
}

/// A card's continuous, always-on "alive" background — two soft, blurred
/// blobs of [color] (different sizes/positions/phase) that drift slowly
/// through the card, meant to sit behind its real content. Callers pass
/// their OWN card's existing hue (e.g. pulse for [UpNextWorkoutCard]) —
/// never a new color. Each blob is built ONCE and passed as
/// [AnimatedBuilder]'s `child`, so only a [Transform.translate] repaints per
/// frame — the blur and gradient are never re-rendered, keeping this
/// compositor-friendly. Motion is slow (18s round trip, well clear of the
/// ~5s/0.2Hz range the reduced-motion guidance warns about) but deliberately
/// strong enough in alpha/travel distance to actually read as moving color
/// at a glance, not just a barely-there wash — two blobs on an inverse phase
/// (one's `t`, the other's `1 - t`) cross paths rather than mirroring each
/// other 1:1, which is what makes it read as color *flowing* through the
/// card instead of one shape sliding. Deliberately always mounted (not
/// gated on any active state) — the owner wants continuous, clearly visible
/// color motion on the card at all times, independent of [CardScale]'s
/// active-only compacting.
class AliveColorDrift extends StatefulWidget {
  const AliveColorDrift({required this.color, super.key});

  final Color color;

  @override
  State<AliveColorDrift> createState() => _AliveColorDriftState();
}

class _AliveColorDriftState extends State<AliveColorDrift>
    with SingleTickerProviderStateMixin {
  /// 3s half-cycle (6s round trip via `reverse: true`) — fast enough to be
  /// clearly noticeable at a glance, not just on close inspection, while
  /// `Curves.easeInOut` keeps each reversal smooth rather than jarring.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A soft-core, edgeless disc: a radial gradient fading all the way to
  /// fully transparent at its own rim, so there is no boundary anywhere —
  /// unlike a solid-fill circle, which keeps a visible soft-edged ring even
  /// under a heavy blur (that ring was the "line" Ziad saw). The blur on
  /// top is extra softness, not what removes the edge — the alpha-0 stop
  /// does that. [size] is deliberately much larger than the card itself
  /// (see [build]) so the gradient's soft core sweeps across the WHOLE
  /// surface as it drifts, never just one corner.
  Widget _blob({
    required double size,
    required double alpha,
    required double blurSigma,
  }) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              widget.color.withValues(alpha: alpha),
              widget.color.withValues(alpha: 0),
            ],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A flat low-alpha wash first — the base tone under and between the
    // moving blobs, so corners/edges the blobs aren't currently sweeping
    // over still read as green, never near-black. Genuinely full-bleed:
    // callers mount this behind everything else, unpadded (see
    // [UpNextWorkoutCard] — this must NOT sit inside a padded child, or the
    // padding gutter shows the card's plain fill instead and reads as a
    // seam around an "inset" animated rectangle).
    final base = DecoratedBox(
      decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.14)),
    );
    // Both well past a typical card's width so the soft core is always
    // covering real card surface, never shrinking down to a visible disc.
    final blobA = _blob(size: 440, alpha: 0.5, blurSigma: 30);
    final blobB = _blob(size: 380, alpha: 0.4, blurSigma: 26);
    if (reducedMotion(context)) {
      // A barely-there static wash instead of drifting motion.
      return Stack(
        children: [
          Positioned.fill(child: base),
          Opacity(
            opacity: 0.6,
            child: Stack(
              children: [
                Align(alignment: const Alignment(0.4, -0.3), child: blobA),
                Align(alignment: const Alignment(-0.5, 0.5), child: blobB),
              ],
            ),
          ),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: base),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_controller.value);
            final dxA = lerpDouble(-70, 70, t)!;
            final dyA = lerpDouble(-55, 55, t)!;
            // Inverse phase — crosses blob A's path rather than mirroring
            // it, so the pair reads as color flowing through the whole
            // card (top corners included), not one shape sliding in place.
            final dxB = lerpDouble(64, -64, t)!;
            final dyB = lerpDouble(50, -50, t)!;
            return Stack(
              children: [
                Align(
                  alignment: const Alignment(0.3, -0.35),
                  child: Transform.translate(
                    offset: Offset(dxA, dyA),
                    child: blobA,
                  ),
                ),
                Align(
                  alignment: const Alignment(-0.4, 0.4),
                  child: Transform.translate(
                    offset: Offset(dxB, dyB),
                    child: blobB,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Shows the dark confirm sheet, anchored (its spring-in transform origin)
/// to the CTA button measured via [anchorKey]. Falls back to a bottom anchor
/// if the button's [RenderBox] isn't available for some reason. Resolves to
/// `true` on Start/Resume, `false`/null on Cancel, a drag-down dismiss, or a
/// tap on the dimmed backdrop.
Future<bool?> showStartConfirmSheet({
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
    barrierLabel: l(context).workoutStart,
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

class _StartConfirmSheetState extends State<_StartConfirmSheet>
    with TickerProviderStateMixin {
  /// Materialize: drives scale + opacity + backdrop blur together, 0 (not
  /// arrived) to 1 (settled/dismissed-away) — critically damped (no
  /// overshoot; a confirm sheet isn't a momentum-driven gesture), at Apple's
  /// own drawer/sheet response (~0.35s). Also driven back to 0 for the
  /// symmetric non-drag exit (Cancel/backdrop/Start) — see [_resolve].
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 0,
  );

  /// The live vertical drag-down offset in px — tracked 1:1 with the
  /// pointer while dragging (never itself animated mid-drag, only on
  /// release; see [_onDragUpdate]/[_onDragEnd]), same "always animate from
  /// the presentation value" rule as the rest of this app's motion.
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

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
    await _controller.animateWith(
      SpringSimulation(AppSprings.standard, _controller.value, 0, 0),
    );
    if (mounted) Navigator.of(context).pop(confirmed);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_resolving) return;
    final next = _drag.value + details.delta.dy;
    _drag.value = next < 0
        ? 0
        : next; // drag-down only; ignore upward past origin
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
        SpringSimulation(
          AppSprings.standard,
          _drag.value,
          _drag.value + 400,
          velocity,
        ),
      );
      unawaited(_resolve(false));
      return;
    }
    // Short of the threshold — spring back, handing off the release
    // velocity so the reversal doesn't brick-wall.
    _drag.animateWith(
      SpringSimulation(AppSprings.standard, _drag.value, 0, velocity),
    );
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

/// The confirm card itself, on the shared [TrainColors] dark theme — a
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
          color: TrainColors.raised.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(AppRadius.card + 4),
          border: Border.all(color: TrainColors.hairlineStrong),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 40,
              offset: Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isResume ? l(context).workoutReadyToResume : l(context).workoutReadyToStart(dayLabel),
              style: AppText.cardTitle.copyWith(
                color: TrainColors.ink,
                fontSize: 21,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isResume
                  ? '$dayLabel · $exerciseCount exercise${exerciseCount == 1 ? '' : 's'}'
                  : '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'} today.',
              style: AppText.body.copyWith(color: TrainColors.ink2),
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
                          border: Border.all(
                            color: TrainColors.hairlineStrong,
                            width: 1.4,
                          ),
                        ),
                        child: Text(
                          l(context).actionCancel,
                          style: AppText.button.copyWith(
                            color: TrainColors.ink2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PillButton(
                    label: isResume ? l(context).actionResume : l(context).actionStart,
                    icon: Icons.play_arrow_rounded,
                    color: TrainColors.ember,
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
double _projectMomentum(
  double velocityPxPerSec, {
  double decelerationRate = 0.998,
}) => (velocityPxPerSec / 1000) * decelerationRate / (1 - decelerationRate);

/// Drag-down distance (or equivalent projected momentum) past which
/// releasing the confirm sheet commits to Cancel rather than springing back.
const double _dismissDistance = 120;
