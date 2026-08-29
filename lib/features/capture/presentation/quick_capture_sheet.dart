import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/train_tokens.dart';

/// What the user chose to capture.
enum CaptureChoice { expense, moment, workout }

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

  static const _neutralTile = TrainColors.raisedStrong;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: TrainColors.raised,
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
                color: TrainColors.hairlineStrong,
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
            iconBg: TrainColors.amberWash,
            iconColor: TrainColors.amber,
            label: 'Expense',
            hint: 'Amount, category — in seconds',
          ),
          _Option(
            choice: CaptureChoice.moment,
            icon: Icons.photo_camera_rounded,
            iconBg: _neutralTile,
            iconColor: TrainColors.ink,
            label: 'Moment',
            hint: 'Photo + a line',
          ),
          _Option(
            choice: CaptureChoice.workout,
            icon: Icons.fitness_center_rounded,
            iconBg: TrainColors.greenWash,
            iconColor: TrainColors.green,
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
              : const Border(bottom: BorderSide(color: TrainColors.hairline)),
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
                      color: TrainColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: TrainColors.ink3,
            ),
          ],
        ),
      ),
    );
  }
}
