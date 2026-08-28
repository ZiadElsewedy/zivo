import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/train_tokens.dart';
import 'pressable_scale.dart';
import 'train_surfaces.dart';

/// A grouped, hairline-divided list of [SettingsRow]s under a mono uppercase
/// [label] — the iOS Settings "inset grouped" pattern in the design handoff's
/// material: a 1px hairline over a barely-there fill, with each rule inset
/// past the icon column so it starts at the row's title.
///
/// Shared by You, Settings, and Settings' own sub-pages, which is why it
/// carries the handoff's list-row spec directly rather than each page
/// re-deriving it.
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
          padding: const EdgeInsets.only(bottom: 11),
          child: TrainSectionLabel(label),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0x08FFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: TrainColors.hairline),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// One row inside a [SettingsSectionCard]: a leading 32px icon tile, a title,
/// a right-aligned mono value, and either a custom [trailing] widget or (when
/// [onTap] is set) a chevron.
///
/// [accent] colours the leading tile — a **13% tint of that one hue behind a
/// 22% border, with the glyph itself in the hue**. Deliberately not the
/// saturated gradient chip this row used to carry: the handoff's identity doc
/// rules out multi-hue saturated icon tiles outright (§8), because a column
/// of them reads as decoration competing with the values beside it. Without
/// an accent the tile falls back to neutral ink.
///
/// Dividers are inset past the icon column (63px, the handoff's figure), so
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

  /// Optional custom mark shown inside the leading tile instead of [icon]
  /// (e.g. a brand logo like the Google or Google Drive mark).
  final Widget? iconWidget;
  final String title;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The row's identity hue. Null keeps the neutral tile.
  final Color? accent;

  /// Retained for call sites that used it; every value is mono now — figures
  /// are instruments (identity §1.2) — so it no longer changes anything.
  final bool monospace;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final editable = onTap != null;
    final hue = accent ?? const Color(0xFFF4F4F0);

    final tile = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hue.withValues(alpha: accent == null ? 0.06 : 0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hue.withValues(alpha: accent == null ? 0.10 : 0.22),
        ),
      ),
      child:
          iconWidget ??
          Icon(icon, size: 15, color: accent ?? TrainColors.ink2),
    );

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 17),
          child: Row(
            children: [
              tile,
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.ui(
                    size: 15,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                    height: 1.1,
                  ),
                ),
              ),
              if (value.isNotEmpty)
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TrainType.mono(
                      size: 12.5,
                      color: TrainColors.ink4,
                      height: 1.2,
                    ),
                  ),
                ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (editable) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0x4DF4F4F0),
                ),
              ],
            ],
          ),
        ),
        // Inset hairline — starts at the title, not the card edge.
        if (!last)
          const Padding(
            padding: EdgeInsets.only(left: TrainListRow.dividerInset),
            child: Divider(height: 1, thickness: 1, color: TrainColors.hairline),
          ),
      ],
    );

    if (!editable) return content;
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap!();
          },
          child: content,
        ),
      ),
    );
  }
}
