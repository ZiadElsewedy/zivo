import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';

/// A grouped, hairline-divided list of [SettingsRow]s under an uppercase
/// [label] — the iOS Settings "inset grouped" pattern, in ZIVO's dark
/// material. Shared by the Profile and Settings pages.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({required this.label, required this.children, super.key});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: AppText.sectionLabel),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
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
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    this.iconWidget,
    this.trailing,
    this.onTap,
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
  final bool monospace;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final editable = onTap != null;
    final row = Container(
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(9),
            ),
            child: iconWidget ?? Icon(icon, size: 16, color: AppColors.ink2),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(title, style: AppText.rowTitle.copyWith(fontSize: 15)),
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
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.ink3),
          ],
        ],
      ),
    );
    if (!editable) return row;
    return PressableScale(
      child: InkWell(onTap: onTap, child: row),
    );
  }
}
