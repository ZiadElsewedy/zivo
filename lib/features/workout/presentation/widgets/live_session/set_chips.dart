import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../domain/logged_set.dart';
import '../../../domain/session_exercise.dart';
import '../../../domain/weight_unit.dart';
import '../../../../../l10n/l10n.dart';

enum SetChipStatus { done, skipped, current, upcoming }

/// The exercise's sets as a row of value chips.
///
/// Each chip carries its own numbers, not just a position: the current one
/// mirrors the steppers live (ember tint, ember border), a finished one shows
/// what was actually logged in green, and one still ahead shows `— × —`. So
/// the row answers "what have I done on this exercise so far" at a glance,
/// which a row of numbered dots never could.
class SetChipRow extends StatelessWidget {
  const SetChipRow({
    required this.exercise,
    required this.currentSetId,
    required this.liveReps,
    required this.liveWeight,
    required this.unit,
    this.onEditSet,
    this.onAddSet,
    super.key,
  });

  final SessionExercise exercise;
  final String currentSetId;

  /// Tapping a set already resolved opens it for correction — the weight was
  /// wrong, the skip was really a set. Null leaves the chips inert.
  final void Function(LoggedSet set, int position)? onEditSet;

  /// The trailing "+": one more set of this exercise, the extra action people
  /// reach for most, one tap away where the sets already are.
  final VoidCallback? onAddSet;

  /// The steppers' live values, echoed into the current chip.
  final String liveReps;
  final String liveWeight;

  /// The active display unit — a done chip's stored kg load is written in it.
  /// The current chip echoes [liveWeight], which is already in this unit.
  final WeightUnit unit;

  /// Past four slots (sets, plus the + chip when shown), equal-width chips
  /// get too narrow for "12 × 42.5", so the row scrolls instead of squeezing.
  static const _maxInlineChips = 4;

  String _labelFor(BuildContext context, LoggedSet set, SetChipStatus state) {
    if (state == SetChipStatus.current) {
      if (liveReps.isEmpty && liveWeight.isEmpty) return '— × —';
      return '${liveReps.isEmpty ? '—' : liveReps} × '
          '${liveWeight.isEmpty ? '—' : liveWeight}';
    }
    if (state == SetChipStatus.done) {
      final reps = set.actualReps;
      final weight = set.actualWeightKg;
      if (reps == null) return l(context).liveSkippedCaps;
      return '$reps × ${weight == null ? '—' : unit.display(weight)}';
    }
    if (state == SetChipStatus.skipped) return l(context).liveSkipped;
    return '— × —';
  }

  @override
  Widget build(BuildContext context) {
    var number = 0;
    final chips = <Widget>[];
    for (final s in exercise.sets) {
      number++;
      final position = number;
      // A skipped set used to fall through to "upcoming" and read `— × —`,
      // exactly like a set still to do — so a skip was invisible the moment
      // it happened. It is resolved, and it looks resolved.
      final state = s.done
          ? SetChipStatus.done
          : s.skipped
          ? SetChipStatus.skipped
          : s.id == currentSetId
          ? SetChipStatus.current
          : SetChipStatus.upcoming;
      final resolved =
          state == SetChipStatus.done || state == SetChipStatus.skipped;
      chips.add(
        SetChip(
          // The key carries both the position and the state, so a test can
          // assert *which* set is current without coupling to the chip's copy
          // — the coupling that left this screen's suite stale after the
          // redesign renamed "Set 1 of 2" into this row.
          key: Key('set-chip-$number-${state.name}'),
          number: number,
          state: state,
          label: _labelFor(context, s, state),
          onTap: resolved && onEditSet != null
              ? () => onEditSet!(s, position)
              : null,
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    final add = onAddSet == null
        ? null
        : AddSetChip(key: const Key('add-set-chip'), onTap: onAddSet!);

    // The + chip takes a slot of its own: four sets plus it no longer fit a
    // phone's width with "8 × 293" legible (found on a real session), so the
    // row switches to scrolling one chip earlier when it's shown.
    final slots = chips.length + (add == null ? 0 : 1);
    if (slots <= _maxInlineChips) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, chip) in chips.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: chip),
            ],
            if (add != null) ...[const SizedBox(width: 8), add],
          ],
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, chip) in chips.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              SizedBox(width: 104, child: chip),
            ],
            if (add != null) ...[const SizedBox(width: 8), add],
          ],
        ),
      ),
    );
  }
}

/// The "+" at the end of the set row. Deliberately the quietest chip in it —
/// a hairline outline with no fill — so it reads as an affordance, never as
/// a set, and the eye still lands on the ember one first.
class AddSetChip extends StatelessWidget {
  const AddSetChip({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: l(context).liveAddSet,
      excludeSemantics: true,
      child: PressableScale(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Container(
              width: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: TrainColors.hairlineStrong),
              ),
              alignment: Alignment.center,
              child: Icon(AppIcons.add, size: 15, color: TrainColors.ink3),
            ),
          ),
        ),
      ),
    );
  }
}

class SetChip extends StatefulWidget {
  const SetChip({
    required this.number,
    required this.state,
    required this.label,
    this.onTap,
    super.key,
  });

  final int number;
  final SetChipStatus state;
  final String label;

  /// Opens a resolved set for correction; null for a set still ahead.
  final VoidCallback? onTap;

  @override
  State<SetChip> createState() => _SetChipState();
}

class _SetChipState extends State<SetChip> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController(
    vsync: this,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant SetChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state == widget.state) return;
    if (reducedMotion(context)) return;
    // A set completing is the one momentum moment here — a set going
    // current/upcoming just settles, no overshoot earned.
    if (widget.state == SetChipStatus.done) {
      _scale.value = 0.94;
      _scale.springTo(1, spring: AppSprings.bounce);
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  ({Color fill, Color border, Color label, Color value}) get _tone =>
      switch (widget.state) {
        SetChipStatus.done => (
          fill: TrainColors.green.withValues(alpha: 0.10),
          border: TrainColors.green.withValues(alpha: 0.30),
          label: TrainColors.green.withValues(alpha: 0.85),
          value: TrainColors.inkPlain,
        ),
        // Resolved but not counted: quieter than done, never mistaken for a
        // set still to do.
        SetChipStatus.skipped => (
          fill: Colors.transparent,
          border: TrainColors.hairline,
          label: TrainColors.inkAt(0.35),
          value: TrainColors.ink3,
        ),
        SetChipStatus.current => (
          fill: TrainColors.ember.withValues(alpha: 0.12),
          border: TrainColors.ember.withValues(alpha: 0.35),
          label: TrainColors.emberPale.withValues(alpha: 0.9),
          // `inkPlain`, not `Colors.white`: this chip's fill is a 12% ember
          // wash, which is near-black on one skin and near-*white* on the
          // other — so its value has to be the page's ink, exactly like the
          // done chip beside it. (On dark the two differ by 11/255.)
          value: TrainColors.inkPlain,
        ),
        SetChipStatus.upcoming => (
          fill: TrainColors.glassSoft,
          border: TrainColors.hairline,
          label: TrainColors.inkAt(0.35),
          value: TrainColors.ink3,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final tone = _tone;
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  l(context).liveSetNumberCaps(widget.number),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.mono(
                    size: 8.5,
                    weight: FontWeight.w500,
                    tracking: 0.14,
                    color: tone.label,
                  ),
                ),
              ),
              if (widget.state == SetChipStatus.done) ...[
                const SizedBox(width: 5),
                Icon(AppIcons.check, size: 10, color: TrainColors.green),
              ],
              if (widget.state == SetChipStatus.skipped) ...[
                const SizedBox(width: 5),
                Icon(AppIcons.skipExercise, size: 10, color: TrainColors.ink3),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.state == SetChipStatus.skipped
                ? TrainType.ui(
                    size: 13,
                    weight: FontWeight.w600,
                    color: tone.value,
                  )
                : TrainType.mono(size: 14, color: tone.value),
          ),
        ],
      ),
    );
    final scaled = AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: chip,
    );
    final onTap = widget.onTap;
    if (onTap == null) return scaled;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: scaled,
      ),
    );
  }
}

/// A gentle breathing glow — used behind the current-set indicator to draw
/// the eye without being distracting.
class PulsingGlow extends StatefulWidget {
  const PulsingGlow({required this.color, required this.child, super.key});

  final Color color;
  final Widget child;

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.22 + 0.18 * t),
                blurRadius: 10 + 8 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
