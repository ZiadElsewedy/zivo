import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../home/presentation/widgets/common.dart';
import '../../../home/presentation/widgets/hue.dart';
import '../../domain/live_session.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../pages/live_session_page.dart';
import '../pages/workout_day_details_page.dart';
import 'change_workout_sheet.dart';
import 'workout_start_sheet.dart' show AliveColorDrift, CardScale;

/// The "up next" training card — the day due next in the active plan's
/// rotation, in the app's pulse (green/training) hue. The split decides what
/// today's workout is, so the card leads with it and the Start/Resume CTA
/// drops STRAIGHT into [LiveSessionPage] (no re-selection, no confirm sheet
/// — the tap that opened the card was already deliberate). "Change Workout"
/// opens a day picker for when life doesn't follow the rotation, and tapping
 /// the card body opens a read-only details page for the day's exercises.
///
/// Shared by the Today page's Training card and the Workout Dashboard's
/// "Today" section — the exact second use this widget was originally
/// factored out for.
///
/// Always carries a slow, continuous drifting pulse wash (see
/// [AliveColorDrift]) as a visibly-moving premium ambient effect, and
/// additionally compacts to a smaller scale (see [CardScale]) whenever
/// [resumable] is non-null — an active/paused session is already under way
/// for this day.
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
        builder: (_) => LiveSessionPage(day: day, plan: widget.plan, resume: resume),
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
    // The drift sits OUTSIDE `ZCard`'s own padded child, as a sibling behind
    // it in this outer Stack/ClipRRect — not nested inside `ZCard.child`.
    // `ZCard` pads its child (see `common.dart`), so a drift mounted inside
    // that child is inset by the padding on every side, leaving the gutter
    // showing the card's plain fill — that mismatch reads as a seam/line
    // around an "animated rectangle" floating inside a static card. Mounted
    // here instead, the drift genuinely fills the card's full outer rect,
    // corners included; this ClipRRect (matching the card's own radius) is
    // the only boundary anywhere. `ZCard` itself goes fully transparent so
    // the drift shows straight through it, including under the padding.
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Stack(
        children: [
          Positioned.fill(
            child: AliveColorDrift(color: AppColors.pulse),
          ),
          ZCard(
            wash: Colors.transparent,
            borderColor: AppColors.pulse.withValues(alpha: 0.14),
            washShadow: const [
              BoxShadow(color: Color(0x0F0A8F63), blurRadius: 4, offset: Offset(0, 2)),
              BoxShadow(
                color: Color(0x420A8F63),
                blurRadius: 34,
                spreadRadius: -18,
                offset: Offset(0, 16),
              ),
            ],
            child: GestureDetector(
              // The card body is its own affordance: everything outside the
              // CTA row opens the day's detail view ("what am I training?").
              behavior: HitTestBehavior.opaque,
              onTap: _openDetails,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: CardHeaderRow(hue: ZHue.pulse, label: 'Training'),
                      ),
                      PressableScale(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _changeWorkout,
                          child: Container(
                            key: const Key('training-change'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.pulse.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppColors.pulse.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Text(
                              'Change',
                              style: AppText.meta.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.pulseText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.m + 1),
                  Text(widget.day.label, style: AppText.cardTitle),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.day.exerciseCount} exercise${widget.day.exerciseCount == 1 ? '' : 's'}'
                    '${isResume ? ' · in progress' : ''}',
                    style: AppText.meta.copyWith(color: AppColors.pulseText),
                  ),
                  const SizedBox(height: 18),
                  PillButton(
                    key: isResume
                        ? const Key('training-resume')
                        : const Key('training-start'),
                    label: isResume ? 'Resume Workout' : 'Start Workout',
                    icon: Icons.play_arrow_rounded,
                    color: AppColors.pulse,
                    enabled: true,
                    onTap: () => _start(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    // Compacting is still the active-session state change — the color
    // drift above is unconditional, this scale is not.
    return CardScale(active: isResume, child: card);
  }
}
