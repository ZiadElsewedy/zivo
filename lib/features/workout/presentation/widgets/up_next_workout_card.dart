import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../domain/live_session.dart';
import '../../domain/session_estimate.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../pages/live_session_page.dart';
import '../pages/workout_day_details_page.dart';
import 'change_workout_sheet.dart';
import 'workout_start_sheet.dart' show CardScale;

/// The "up next" training card — the day due next in the active plan's
/// rotation, built to the workout-tracking design handoff: a green slab with
/// its own bloom, the day as the hero, its shape as three mono stats, and the
/// **one ember action on the screen** dropping STRAIGHT into
/// [LiveSessionPage] (no re-selection, no confirm sheet — the tap that opened
/// the card was already deliberate).
///
/// "Change" opens a day picker for when life doesn't follow the rotation, and
/// tapping the card body opens a read-only details page for the day.
///
/// Shared by the Today page's session card and the Workout Dashboard's
/// "Today" section — the exact second use this widget was originally
/// factored out for.
///
/// Compacts to a smaller scale (see [CardScale]) whenever [resumable] is
/// non-null — an active/paused session is already under way for this day.
class UpNextWorkoutCard extends StatefulWidget {
  const UpNextWorkoutCard({
    required this.plan,
    required this.day,
    required this.resumable,
    super.key,
  });

  final WorkoutPlan plan;
  final WorkoutDay day;

  /// A same plan/day active session to resume into, or null to start fresh.
  final LiveSession? resumable;

  @override
  State<UpNextWorkoutCard> createState() => _UpNextWorkoutCardState();
}

class _UpNextWorkoutCardState extends State<UpNextWorkoutCard> {
  Future<void> _start([WorkoutDay? dayOverride]) async {
    final day = dayOverride ?? widget.day;
    final resume = dayOverride == null ? widget.resumable : null;
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LiveSessionPage(day: day, plan: widget.plan, resume: resume),
      ),
    );
  }

  Future<void> _openDetails() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            WorkoutDayDetailsPage(plan: widget.plan, day: widget.day),
      ),
    );
  }

  /// The "Change Workout" picker — any other day of the split, started
  /// directly on pick (the same one-tap contract as the main CTA).
  Future<void> _changeWorkout() async {
    HapticFeedback.selectionClick();
    final selection = await showChangeWorkoutSheet(
      context,
      plan: widget.plan,
      activeSession: widget.resumable,
    );
    if (!mounted || selection == null) return;
    await _start(selection.day);
  }

  @override
  Widget build(BuildContext context) {
    final isResume = widget.resumable != null;
    final day = widget.day;
    final minutes = estimatedDayDuration(day).inMinutes;

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: TrainColors.sessionGradient,
                borderRadius: BorderRadius.circular(26),
              ),
            ),
          ),
          // The card's own green bloom off the top-right — the single soft
          // glow this surface is allowed, in place of a shadow.
          const Positioned(
            top: -60,
            right: -40,
            child: IgnorePointer(
              child: SizedBox(
                width: 180,
                height: 180,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x471FE08A), Color(0x001FE08A)],
                      stops: [0.0, 0.68],
                    ),
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            // The card body is its own affordance: everything outside the
            // CTA row opens the day's detail view ("what am I training?").
            behavior: HitTestBehavior.opaque,
            onTap: _openDetails,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: TrainColors.green.withValues(alpha: 0.22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: TrainColors.green,
                          boxShadow: [
                            BoxShadow(
                              color: TrainColors.green.withValues(alpha: 0.8),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          isResume
                              ? 'IN PROGRESS'
                              : 'DAY ${day.slot.toUpperCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TrainType.mono(
                            size: 9.5,
                            weight: FontWeight.w600,
                            tracking: 0.16,
                            color: const Color(0xFF7EF0BB),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ChangePill(onTap: _changeWorkout),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    day.label,
                    style: TrainType.ui(
                      size: 30,
                      weight: FontWeight.w800,
                      tracking: -0.025,
                      height: 1.05,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _StatRow(
                    stats: [
                      ('${day.exerciseCount}', 'EXERCISES'),
                      ('${plannedSetCount(day)}', 'SETS'),
                      if (minutes > 0) ('~$minutes', 'MINUTES'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  TrainPrimaryButton(
                    key: isResume
                        ? const Key('training-resume')
                        : const Key('training-start'),
                    label: isResume ? 'Resume Workout' : 'Start Workout',
                    height: 56,
                    glowAlpha: 0.35,
                    icon: const TrainPlayGlyph(color: Colors.white, size: 15),
                    onTap: _start,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return CardScale(active: isResume, child: card);
  }
}

/// The outlined "Change" pill — a secondary way out of the rotation, kept
/// deliberately quiet next to the ember CTA below it.
class _ChangePill extends StatelessWidget {
  const _ChangePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          key: const Key('training-change'),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x38FFFFFF)),
          ),
          child: Text(
            'Change',
            style: TrainType.ui(
              size: 11.5,
              weight: FontWeight.w700,
              height: 1,
              color: const Color(0xFFEAFFF4),
            ),
          ),
        ),
      ),
    );
  }
}

/// The day's shape in three mono numbers, split by hairline rules — what the
/// session actually costs before you commit to it.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats});

  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (value, label)) in stats.indexed) ...[
            if (i > 0) ...[
              const SizedBox(width: 22),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: Color(0x29FFFFFF),
              ),
              const SizedBox(width: 22),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TrainType.mono(size: 18, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TrainType.mono(
                    size: 8.5,
                    weight: FontWeight.w500,
                    tracking: 0.14,
                    color: const Color(0x8CEAFFF4),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
