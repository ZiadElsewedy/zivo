import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'pressable_scale.dart';

/// A grouped, hairline-divided list of [SettingsRow]s under an uppercase
/// [label] — the iOS Settings "inset grouped" pattern, in ZIVO's dark
/// material: an elevated card edged with a glassy hairline and lifted on the
/// house card shadow. Shared by the Profile and Settings pages.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    required this.label,
    required this.children,
    super.key,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 9),
          child: Text(label, style: AppText.sectionLabel),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.card,
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// One row inside a [SettingsSectionCard]: a leading icon chip, a title, a
/// right-aligned value, and either a custom [trailing] widget or (when
/// [onTap] is set) a chevron.
///
/// Pass [accent] to get the iOS-Settings mark: a rounded square filled with a
/// diagonal gradient of the hue, carrying a white glyph and lifted on a soft
/// colored glow — color as wayfinding, one hue per row's meaning. Without it,
/// the chip falls back to ZIVO's quiet neutral.
///
/// Dividers are inset past the icon (the classic grouped-list detail), so
/// each row's mark reads as the start of its own line.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    this.iconWidget,
    this.trailing,
    this.onTap,
    this.accent,
    this.monospace = false,
    this.last = false,
    super.key,
  });

  final IconData icon;

  /// Optional custom mark shown inside the leading chip instead of [icon]
  /// (e.g. a brand logo like the Google Drive mark).
  final Widget? iconWidget;
  final String title;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The row's identity hue for a gradient-filled leading chip; null keeps
  /// the neutral raised chip.
  final Color? accent;
  final bool monospace;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final editable = onTap != null;
    final accent = this.accent;

    final Widget chip;
    if (accent != null) {
      chip = Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent, Color.lerp(accent, Colors.black, 0.32)!],
          ),
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 12,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: iconWidget ?? Icon(icon, size: 16, color: Colors.white),
      );
    } else {
      chip = Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(9),
        ),
        child: iconWidget ?? Icon(icon, size: 16, color: AppColors.ink2),
      );
    }

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
          child: Row(
            children: [
              chip,
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  title,
                  style: AppText.rowTitle.copyWith(fontSize: 15),
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppText.meta.copyWith(
                    color: AppColors.ink3,
                    fontFamily: monospace ? 'monospace' : null,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (editable) ...[
                const SizedBox(width: 4),
                const Icon(AppIcons.chevron, size: 18, color: AppColors.ink3),
              ],
            ],
          ),
        ),
        // Inset hairline — starts at the title, not the card edge.
        if (!last)
          Container(
            margin: const EdgeInsets.only(left: 59),
            height: 1,
            color: AppColors.hairline,
          ),
      ],
    );

    if (!editable) return content;
    return PressableScale(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: content,
      ),
    );
  }
}
