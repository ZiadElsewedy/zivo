import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/theme/train_tokens.dart';
import '../../../../../../core/widgets/train_chrome.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../domain/session_exercise.dart';
import '../session_effects.dart';

/// What the floating commit row occupies at the foot of the logging screen:
/// the button's own 60, its bottom inset, and a gap above it that content
/// fades into.
const double kCommitRowSpace = 60.0 + AppSpacing.l + AppSpacing.base;

const EdgeInsets kPhasePadding = EdgeInsets.fromLTRB(
  AppSpacing.screen,
  AppSpacing.base,
  AppSpacing.screen,
  AppSpacing.l,
);

/// The scroll shell every phase is built in.
///
/// "Fill the viewport, or scroll if you can't": the [ConstrainedBox] gives the
/// column at least the visible height so the `Spacer`s have something to
/// distribute, and [IntrinsicHeight] lets them collapse gracefully past that
/// instead of overflowing.
///
/// Shared because the three phases had drifted apart — the logging screen
/// padded 24/12/24/24 and the two countdowns 22/20/22/20, so the same content
/// sat at different heights and different insets depending on which phase you
/// were in, and the logging screen's 24 didn't line up with the header's own
/// 22 either. The physics are always-scrollable on purpose: a surface that
/// ignores a drag whenever its content happens to fit reads as broken
/// scrolling rather than as "nothing to scroll".
class PhaseScroll extends StatelessWidget {
  const PhaseScroll({
    required this.children,
    this.cross = CrossAxisAlignment.stretch,
    this.padding,
    super.key,
  });

  final List<Widget> children;
  final CrossAxisAlignment cross;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final insets = padding ?? kPhasePadding;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: insets,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0, constraints.maxHeight - insets.vertical),
            ),
            child: IntrinsicHeight(
              child: Column(crossAxisAlignment: cross, children: children),
            ),
          ),
        );
      },
    );
  }
}

/// The logging screen's shell. [top] (the exercise header + set chips) and
/// [done] (the action cluster) stay put; [hero] (the Goal card + steppers)
/// sits between two flexible gaps rather than one dump zone below everything
/// — on a tall screen that pulls the hero cluster toward the middle of the
/// available space instead of leaving it stranded up top with a void beneath,
/// while [done] keeps breathing room above it instead of sitting flush on the
/// last gap. Both gaps collapse to 0 together when content plus the keyboard
/// overflow a short screen.
class RunningScaffold extends StatelessWidget {
  const RunningScaffold({
    required this.top,
    required this.hero,
    required this.done,
    this.musicSlot,
    super.key,
  });

  final List<Widget> top;
  final List<Widget> hero;
  final Widget done;
  final Widget? musicSlot;

  @override
  Widget build(BuildContext context) {
    // The commit row is PINNED, not scrolled with everything else.
    //
    // It used to be the last child of the scroll column, which meant the
    // screen's primary action moved whenever anything above it grew — and the
    // goal card grows for ordinary reasons (a delta line, a progression hint,
    // a two-line exercise name), so "Log set" could sit below the fold on the
    // one screen you tap most. Pinning it also makes the card's height changes
    // harmless: they consume scroll, not the button.
    return LayoutBuilder(
      key: const ValueKey('running-list'),
      builder: (context, constraints) {
        // Below this there is no room to pin anything — a keyboard up on a
        // very short device — and reserving the commit row's full height out
        // of what's left would leave the content nothing at all. Scroll the
        // whole column instead, which is what this screen always did.
        const minPinnableHeight = 260.0;
        final content = [
          ...top,
          // A hard floor under the balancing gap. The `Spacer` collapses to
          // zero the instant content outgrows the viewport, and when it does
          // the set chips weld to the goal card — one extra line inside the
          // card is enough to trigger it, so the layout visibly tightened as a
          // side effect of nudging the weight.
          const SizedBox(height: AppSpacing.l),
          const Spacer(),
          ...hero,
          if (musicSlot != null) ...[
            const SizedBox(height: AppSpacing.m),
            musicSlot!,
          ],
        ];
        if (constraints.maxHeight < minPinnableHeight) {
          return PhaseScroll(
            key: const ValueKey('running-scroll'),
            cross: CrossAxisAlignment.start,
            children: [
              ...content,
              const SizedBox(height: AppSpacing.base),
              done,
            ],
          );
        }
        // The scroll runs the FULL height and the commit row floats over its
        // last stretch, rather than the two splitting the space between them.
        // Splitting it sliced whatever happened to land on the seam clean in
        // half — a card cut by an invisible line, which reads as a rendering
        // bug rather than as "there's more below". Reserved padding keeps
        // content out from under the buttons, and the fade turns the seam into
        // an edge.
        return Stack(
          children: [
            Positioned.fill(
              child: FadeOutBottom(
                reserved: kCommitRowSpace,
                child: PhaseScroll(
                  key: const ValueKey('running-scroll'),
                  cross: CrossAxisAlignment.start,
                  padding: kPhasePadding.copyWith(bottom: kCommitRowSpace),
                  children: content,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  0,
                  AppSpacing.screen,
                  AppSpacing.l,
                ),
                child: done,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// NOW — the ember caption that names what this screen is for. The exercise
/// name is the hero; the muscle line is a mono caption under it, not a chip,
/// so nothing competes with the goal card below.
class ExerciseHeader extends StatelessWidget {
  const ExerciseHeader(this.exercise, {super.key});

  final SessionExercise exercise;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainCaption(l(context).liveNow, color: const Color(0xCCFF5C1A)),
        const SizedBox(height: 11),
        Text(
          exercise.name,
          style: TrainType.ui(
            size: 34,
            weight: FontWeight.w800,
            tracking: -0.03,
            height: 1.06,
            color: TrainColors.ink,
          ),
        ),
        if (exercise.muscleGroup != null) ...[
          const SizedBox(height: 9),
          Text(
            exercise.muscleGroup!.toUpperCase(),
            style: TrainType.mono(
              size: 11.5,
              tracking: 0.04,
              color: const Color(0x66F4F4F0),
            ),
          ),
        ],
      ],
    );
  }
}
