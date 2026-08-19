import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';

/// A close button + centred title, shared by the capture screens.
class CaptureTopBar extends StatelessWidget {
  const CaptureTopBar({
    required this.title,
    required this.onClose,
    this.trailing,
    this.titleColor = AppColors.ink2,
    this.iconColor = AppColors.ink2,
    this.chipColor = AppColors.surfaceRaised,
    super.key,
  });

  final String title;
  final VoidCallback onClose;

  /// Optional trailing action (e.g. delete) replacing the balancing spacer.
  final Widget? trailing;

  /// Overridable per host; defaults are the app-wide dark theme.
  final Color titleColor;
  final Color iconColor;
  final Color chipColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 2),
      child: Row(
        children: [
          CaptureIconButton(
            icon: Icons.close_rounded,
            onTap: onClose,
            semanticLabel: 'Close',
            iconColor: iconColor,
            chipColor: chipColor,
          ),
          Expanded(
            child: Center(
              child: Text(title, style: AppText.button.copyWith(color: titleColor)),
            ),
          ),
          SizedBox(
            width: CaptureIconButton.targetSize,
            height: CaptureIconButton.targetSize,
            child: trailing,
          ),
        ],
      ),
    );
  }
}

/// A circular icon control for capture top bars — the close button and the
/// per-screen delete action. The visible chip stays 34px to preserve the
/// existing look, but the tap target is padded out to 44px (WCAG 2.5.5 / Apple
/// HIG), and [semanticLabel] gives the otherwise icon-only button a name for
/// screen readers (also surfaced as a long-press tooltip).
class CaptureIconButton extends StatelessWidget {
  const CaptureIconButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.iconColor = AppColors.ink2,
    this.chipColor = AppColors.surfaceRaised,
    super.key,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final Color iconColor;
  final Color chipColor;

  /// The visible chip diameter.
  static const double chipSize = 34;

  /// The tap target the chip is centred within — the accessible minimum.
  static const double targetSize = 44;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Tooltip(
        message: semanticLabel,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: targetSize,
            height: targetSize,
            child: Center(
              child: Container(
                width: chipSize,
                height: chipSize,
                decoration: BoxDecoration(color: chipColor, shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ),
          ),
        ),
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
    return PressableScale(
      enabled: enabled,
      child: Opacity(
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
      fg = AppColors.ground;
      border = AppColors.flare;
    } else if (selected) {
      bg = AppColors.ink;
      fg = AppColors.ground;
      border = AppColors.ink;
    } else {
      bg = Colors.transparent;
      fg = tone == ChipTone.flare ? AppColors.flareText : AppColors.ink2;
      border = tone == ChipTone.flare ? const Color(0x59FF3D6E) : AppColors.hairline2;
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
