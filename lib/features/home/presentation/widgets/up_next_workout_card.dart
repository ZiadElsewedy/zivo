import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/session_colors.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../workout/domain/live_session.dart';
import '../../../workout/domain/workout_day.dart';
import '../../../workout/domain/workout_plan.dart';
import '../../../workout/domain/workout_plan_format.dart';
import '../../../workout/presentation/pages/live_session_page.dart';
import 'common.dart';
import 'hue.dart';

/// A light "Up next" card for the Today page's Training section — the day
/// due next in the active plan's rotation, with a prominent Start/Resume CTA
/// that (after a confirming dark sheet, guarding against an accidental tap)
/// drops straight into [LiveSessionPage], skipping Hub → Workout entirely.
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
    HapticFeedback.mediumImpact();
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
    return ZCard(
      gradient: const LinearGradient(
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
          Text(_dayTitle(widget.day), style: AppText.cardTitle),
          const SizedBox(height: 6),
          Text(
            workoutDayMeta(widget.day),
            style: AppText.meta.copyWith(color: AppColors.emberText),
          ),
          const SizedBox(height: 18),
          Container(
            key: _ctaKey,
            child: PillButton(
              label: isResume ? 'Resume' : 'Start',
              icon: Icons.play_arrow_rounded,
              color: AppColors.ember,
              enabled: true,
              onTap: _onTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Day D · Full Arm" — same convention as the workout tab's own day title,
/// duplicated locally rather than reaching into a presentation-layer page.
String _dayTitle(WorkoutDay day) => 'Day ${day.slot} · ${day.label}';

/// Shows the dark confirm sheet, anchored (its spring-in transform origin)
/// to the CTA button measured via [anchorKey]. Falls back to a bottom anchor
/// if the button's [RenderBox] isn't available for some reason. Resolves to
/// `true` on Start/Resume, `false`/null on Cancel or a barrier tap.
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
    barrierDismissible: true,
    barrierLabel: 'Start workout',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    // Zero — the built-in route transition is skipped entirely; the sheet
    // drives its own one-shot spring on mount (see [_StartConfirmSheet]),
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

class _StartConfirmSheetState extends State<_StartConfirmSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, value: 0);
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
      _controller.springTo(1, spring: AppSprings.bounce);
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
      builder: (context, child) {
        final t = _controller.value;
        return Opacity(
          // A literal 0 scale collapses the child's layout, so floor it just
          // above zero rather than clamping opacity/scale independently.
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: t < 0.01 ? 0.01 : t,
            alignment: widget.anchor,
            child: child,
          ),
        );
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: _StartConfirmCard(
            dayLabel: widget.dayLabel,
            exerciseCount: widget.exerciseCount,
            isResume: widget.isResume,
          ),
        ),
      ),
    );
  }
}

/// The dark card itself — deliberately on [SessionColors], not the light
/// [AppColors] the Today page otherwise uses, as a preview of the immersive
/// session it's about to open into.
class _StartConfirmCard extends StatelessWidget {
  const _StartConfirmCard({
    required this.dayLabel,
    required this.exerciseCount,
    required this.isResume,
  });

  final String dayLabel;
  final int exerciseCount;
  final bool isResume;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        decoration: BoxDecoration(
          color: SessionColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card + 4),
          border: Border.all(color: SessionColors.hairline2),
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
              style: AppText.cardTitle.copyWith(color: SessionColors.ink, fontSize: 21),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isResume
                  ? '$dayLabel · $exerciseCount exercise${exerciseCount == 1 ? '' : 's'}'
                  : '$exerciseCount exercise${exerciseCount == 1 ? '' : 's'} today.',
              style: AppText.body.copyWith(color: SessionColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: PressableScale(
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(false),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: SessionColors.hairline2, width: 1.4),
                        ),
                        child: Text(
                          'Cancel',
                          style: AppText.button.copyWith(color: SessionColors.ink2),
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
                    onTap: () => Navigator.of(context).pop(true),
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
