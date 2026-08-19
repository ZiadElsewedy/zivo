import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// What the user chose to capture.
enum CaptureChoice { expense, task, event, university, note, moment, workout }

/// Opens the Quick Capture bottom sheet and resolves to the chosen kind.
/// Capture is a verb, not five destinations: one sheet, one pick.
Future<CaptureChoice?> showQuickCaptureSheet(BuildContext context) {
  return showModalBottomSheet<CaptureChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _QuickCaptureSheet(),
  );
}

class _QuickCaptureSheet extends StatelessWidget {
  const _QuickCaptureSheet();

  static const _neutralTile = AppColors.surfaceRaised;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: AppSpacing.screen,
        right: AppSpacing.screen,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.l,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline2,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text('Capture', style: AppText.cardTitle),
          ),
          _Option(
            choice: CaptureChoice.expense,
            icon: Icons.payments_rounded,
            iconBg: AppColors.solarWash,
            iconColor: AppColors.solarText,
            label: 'Expense',
            hint: 'Amount, category — in seconds',
          ),
          _Option(
            choice: CaptureChoice.task,
            icon: Icons.check_rounded,
            iconBg: _neutralTile,
            iconColor: AppColors.ink,
            label: 'Task',
            hint: 'A quick to-do',
          ),
          _Option(
            choice: CaptureChoice.event,
            icon: Icons.calendar_today_rounded,
            iconBg: AppColors.emberWash,
            iconColor: AppColors.emberText,
            label: 'Event',
            hint: 'Block time on your day',
          ),
          _Option(
            choice: CaptureChoice.university,
            icon: Icons.school_outlined,
            iconBg: _neutralTile,
            iconColor: AppColors.irisText,
            label: 'University',
            hint: 'Assignment or exam',
          ),
          _Option(
            choice: CaptureChoice.note,
            icon: Icons.sticky_note_2_rounded,
            iconBg: _neutralTile,
            iconColor: AppColors.ink,
            label: 'Note',
            hint: 'Catch a thought',
          ),
          _Option(
            choice: CaptureChoice.moment,
            icon: Icons.photo_camera_rounded,
            iconBg: _neutralTile,
            iconColor: AppColors.ink,
            label: 'Moment',
            hint: 'Photo + a line',
          ),
          _Option(
            choice: CaptureChoice.workout,
            icon: Icons.fitness_center_rounded,
            iconBg: AppColors.pulseWash,
            iconColor: AppColors.pulseText,
            label: 'Workout',
            hint: 'Log a training session',
            last: true,
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.choice,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.hint,
    this.last = false,
  });

  final CaptureChoice choice;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String hint;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(choice),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 21, color: iconColor),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppText.rowTitle.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: AppText.body.copyWith(
                      fontSize: 13,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.ink3,
            ),
          ],
        ),
      ),
    );
  }
}
