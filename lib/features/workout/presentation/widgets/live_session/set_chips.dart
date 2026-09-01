import 'package:flutter/material.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../domain/logged_set.dart';
import '../../../domain/session_exercise.dart';
import '../../../../../l10n/l10n.dart';
import 'live_session_format.dart';

enum SetChipStatus { done, current, upcoming }

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
    super.key,
  });

  final SessionExercise exercise;
  final String currentSetId;

  /// The steppers' live values, echoed into the current chip.
  final String liveReps;
  final String liveWeight;

  /// Past four, equal-width chips get too narrow for "12 × 42.5", so the row
  /// scrolls instead of squeezing.
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
      return '$reps × ${weight == null ? '—' : trimWeight(weight)}';
    }
    return '— × —';
  }

  @override
  Widget build(BuildContext context) {
    var number = 0;
    final chips = <Widget>[];
    for (final s in exercise.sets) {
      number++;
      final state = s.done
          ? SetChipStatus.done
          : s.id == currentSetId
          ? SetChipStatus.current
          : SetChipStatus.upcoming;
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
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    if (chips.length <= _maxInlineChips) {
      return Row(
        children: [
          for (final (i, chip) in chips.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: chip),
          ],
        ],
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, chip) in chips.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            SizedBox(width: 104, child: chip),
          ],
        ],
      ),
    );
  }
}

class SetChip extends StatefulWidget {
  const SetChip({
    required this.number,
    required this.state,
    required this.label,
    super.key,
  });

  final int number;
  final SetChipStatus state;
  final String label;

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
        SetChipStatus.current => (
          fill: TrainColors.ember.withValues(alpha: 0.12),
          border: TrainColors.ember.withValues(alpha: 0.35),
          label: const Color(0xE6FFA87C),
          value: Colors.white,
        ),
        SetChipStatus.upcoming => (
          fill: TrainColors.glassSoft,
          border: TrainColors.hairline,
          label: const Color(0x59F4F4F0),
          value: const Color(0x66F4F4F0),
        ),
      };

  @override
  Widget build(BuildContext context) {
    final tone = _tone;
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
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
                const Icon(AppIcons.check, size: 10, color: TrainColors.green),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TrainType.mono(size: 14, color: tone.value),
          ),
        ],
      ),
    );
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: chip,
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
