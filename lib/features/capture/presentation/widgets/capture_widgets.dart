import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// A close button + centred title, shared by the capture screens.
class CaptureTopBar extends StatelessWidget {
  const CaptureTopBar({
    required this.title,
    required this.onClose,
    this.trailing,
    super.key,
  });

  final String title;
  final VoidCallback onClose;

  /// Optional trailing action (e.g. delete) replacing the balancing spacer.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 2),
      child: Row(
        children: [
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFFEFEBE3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 18, color: AppColors.ink2),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(title, style: AppText.button.copyWith(color: AppColors.ink2)),
            ),
          ),
          SizedBox(width: 34, height: 34, child: trailing),
        ],
      ),
    );
  }
}

/// A full-width pill action button used to commit a capture.
class PillButton extends StatelessWidget {
  const PillButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.color = AppColors.ember,
    this.textColor = Colors.white,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: textColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.button.copyWith(fontSize: 16, color: textColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum ChipTone { neutral, flare }

/// A selectable pill chip (due dates, priority, time, etc.).
class SelectChip extends StatelessWidget {
  const SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.tone = ChipTone.neutral,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    if (selected && tone == ChipTone.flare) {
      bg = AppColors.flare;
      fg = Colors.white;
      border = AppColors.flare;
    } else if (selected) {
      bg = AppColors.ink;
      fg = Colors.white;
      border = AppColors.ink;
    } else {
      bg = Colors.transparent;
      fg = tone == ChipTone.flare ? AppColors.flareText : AppColors.ink2;
      border = tone == ChipTone.flare ? const Color(0x59DE2C56) : AppColors.hairline2;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label, style: AppText.button.copyWith(fontSize: 13.5, color: fg)),
          ],
        ),
      ),
    );
  }
}
