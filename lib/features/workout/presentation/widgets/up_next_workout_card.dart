import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../home/presentation/widgets/common.dart';
import '../../../home/presentation/widgets/hue.dart';
import '../../domain/live_session.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../pages/live_session_page.dart';
import 'workout_start_sheet.dart';

/// The "up next" training card — the day due next in the active plan's
/// rotation, in the app's pulse (green/training) hue, with a prominent
/// Start/Resume CTA that (after a confirming dark sheet, guarding against an
/// accidental tap) drops straight into [LiveSessionPage]. Shared by the Today
/// page's Training card and the Workout Dashboard's "Today" section — the
/// exact second use this widget was originally factored out for.
///
/// Always carries a slow, continuous drifting pulse wash (see
/// [AliveColorDrift]) as a visibly-moving premium ambient effect, and
/// additionally compacts to a smaller scale (see [CardScale]) whenever
/// [resumable] is non-null — an active/paused session is already under way
/// for this day. Its confirm sheet and motion chrome live in
/// `workout_start_sheet.dart`, factored out so any future second
/// training-card style widget can reuse them without a forked copy.
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
    final confirmed = await showStartConfirmSheet(
      context: context,
      anchorKey: _ctaKey,
      dayLabel: widget.day.label,
      exerciseCount: widget.day.exerciseCount,
      isResume: isResume,
    );
    if (confirmed != true || !mounted) return;
    // The confirm's own selectionClick already fired at the moment of tap
    // (see workout_start_sheet.dart's `_StartConfirmSheetState._resolve`) —
    // no second haptic here.
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
          const Positioned.fill(child: AliveColorDrift(color: AppColors.pulse)),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardHeaderRow(hue: ZHue.pulse, label: 'Training'),
                const SizedBox(height: AppSpacing.m + 1),
                Text(widget.day.label, style: AppText.cardTitle),
                const SizedBox(height: 6),
                Text(
                  '${widget.day.exerciseCount} exercise${widget.day.exerciseCount == 1 ? '' : 's'}',
                  style: AppText.meta.copyWith(color: AppColors.pulseText),
                ),
                const SizedBox(height: 18),
                Container(
                  key: _ctaKey,
                  child: PillButton(
                    label: isResume ? 'Resume Workout' : 'Start Workout',
                    icon: Icons.play_arrow_rounded,
                    color: AppColors.pulse,
                    enabled: true,
                    onTap: _onTap,
                  ),
                ),
              ],
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
