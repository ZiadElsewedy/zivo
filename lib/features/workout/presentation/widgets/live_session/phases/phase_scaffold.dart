import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../core/motion/springs.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/theme/train_tokens.dart';
import '../../../../../../core/widgets/train_chrome.dart';
import '../../../../../../l10n/l10n.dart';
import '../../../../domain/session_exercise.dart';
import '../session_effects.dart';

/// The commit row's own height. Deliberately shorter than the 60 the design
/// tokens use elsewhere: this row is PINNED over the bottom of the logging
/// screen, so every point it takes is a point the reps/weight steppers —
/// the thing you actually reach for — lose to it, and the steppers were
/// ending up pressed against the fold.
const double kCommitRowHeight = 52.0;

/// What the floating commit row occupies at the foot of the logging screen:
/// the button's own height, its bottom inset, and a gap above it that content
/// fades into.
const double kCommitRowSpace =
    kCommitRowHeight + AppSpacing.base + AppSpacing.m;

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
/// scrolling rather than as "nothing to scroll" — that is what
/// [AlwaysScrollableScrollPhysics] is doing here, and it was documented long
/// before it was actually wired.
///
/// A downward drag also puts the keyboard away
/// ([ScrollViewKeyboardDismissBehavior.onDrag]): the reps/weight fields open
/// a decimal pad, and a decimal pad has no Return key to close itself with.
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
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
///
/// The two gaps are EQUAL, which is the whole point: spare height is split
/// evenly instead of being dumped in one place. With a single gap above the
/// hero, all of it piled up between the set chips and the goal card — a void
/// mid-screen — and the cluster hung off the bottom of whatever space was
/// left, which is why the reps/weight steppers ended up pressed against the
/// commit row. Halving that gap lifts the steppers by the other half.
///
/// That same single gap is why the screen re-laid-out when music started:
/// the companion dock takes a bar's height out of the phase, and every point
/// of it came off one gap. Split across two, a track starting shifts things
/// half as far, gently, instead of visibly re-flowing the screen you are
/// mid-set on.
class RunningScaffold extends StatefulWidget {
  const RunningScaffold({
    required this.top,
    required this.hero,
    required this.done,
    super.key,
  });

  final List<Widget> top;
  final List<Widget> hero;
  final Widget done;

  @override
  State<RunningScaffold> createState() => _RunningScaffoldState();
}

class _RunningScaffoldState extends State<RunningScaffold> {
  /// Whether one of the reps/weight fields currently holds focus — i.e.
  /// whether the keyboard is up because of this screen. Tracked through the
  /// focus tree rather than `MediaQuery.viewInsets`, which a resizing
  /// `Scaffold` strips out of its own body.
  bool _editing = false;

  void _onFocusChange(bool hasFocus) {
    if (hasFocus == _editing) return;
    setState(() => _editing = hasFocus);
  }

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
    return Focus(
      // Inert: it exists only to hear when a descendant field takes or loses
      // focus, never to take focus itself or to sit in the tab order.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onFocusChange,
      child: LayoutBuilder(
        key: const ValueKey('running-list'),
        builder: (context, constraints) {
          // Below this there is no room to pin anything — a keyboard up on a
          // very short device — and reserving the commit row's full height out
          // of what's left would leave the content nothing at all. Scroll the
          // whole column instead, which is what this screen always did.
          const minPinnableHeight = 260.0;
          final content = [
            ...widget.top,
            // A hard floor under the balancing gap. The `Spacer` collapses to
            // zero the instant content outgrows the viewport, and when it does
            // the set chips weld to the goal card — one extra line inside the
            // card is enough to trigger it, so the layout visibly tightened as a
            // side effect of nudging the weight.
            const SizedBox(height: AppSpacing.l),
            const Spacer(),
            ...widget.hero,
            // The matching floor UNDER the hero. Without it the steppers sat
            // flush on the commit row's reserved space — the "reps and weight
            // are jammed at the bottom" the pinned row was supposed to
            // prevent.
            const SizedBox(height: AppSpacing.m),
            const Spacer(),
          ];
          if (constraints.maxHeight < minPinnableHeight) {
            return PhaseScroll(
              key: const ValueKey('running-scroll'),
              cross: CrossAxisAlignment.start,
              children: [
                ...content,
                const SizedBox(height: AppSpacing.base),
                widget.done,
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
                    AppSpacing.base,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    // Stretch, not end: the commit row is a `Row` with an
                    // `Expanded` in it and needs a bounded width. The Done
                    // pill aligns itself instead.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KeyboardDoneBar(visible: _editing),
                      widget.done,
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The way out of the reps/weight keyboard.
///
/// iOS's decimal pad ships no Return key, so a numeric field there has no
/// self-contained way to dismiss itself: without this the only exits were
/// committing the set or backing out of the screen. Tapping anywhere outside
/// the steppers works too (see `StepperField`), as does dragging the phase
/// down — this is the *visible* affordance for both, and it only exists while
/// a field is actually focused.
class KeyboardDoneBar extends StatelessWidget {
  const KeyboardDoneBar({required this.visible, super.key});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: reducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TrainGhostButton(
                  key: const Key('dismiss-keyboard'),
                  label: l(context).actionDone,
                  mono: false,
                  height: 34,
                  icon: const Icon(
                    Icons.keyboard_hide_rounded,
                    size: 14,
                    color: Color(0x99F4F4F0),
                  ),
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                ),
              ),
            ),
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
        // Capped at two lines. Real movement names run long ("Seated
        // Dumbbell Incline Rear Delt Fly"), and at 34pt with no cap a third
        // line pushed the goal card — the thing this screen exists for —
        // under the fold on a phone.
        Text(
          exercise.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
