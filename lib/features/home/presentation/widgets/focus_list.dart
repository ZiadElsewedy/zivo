import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/today_snapshot.dart';
import 'hue.dart';

/// Today's merged focus list — tasks + university deadlines, by relevance.
/// The list container is neutral; each row's dot encodes its source/status.
/// Task-backed rows can be completed by tapping their checkbox.
class FocusList extends StatelessWidget {
  const FocusList(this.items, {this.onToggle, super.key});

  final List<FocusItem> items;
  final void Function(String taskId, bool done)? onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          _FocusRow(items[i], first: i == 0, onToggle: onToggle),
      ],
    );
  }
}

class _FocusRow extends StatelessWidget {
  const _FocusRow(this.item, {required this.first, this.onToggle});

  final FocusItem item;
  final bool first;
  final void Function(String taskId, bool done)? onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: first
              ? const BorderSide(color: AppColors.hairline)
              : BorderSide.none,
          bottom: const BorderSide(color: AppColors.hairline),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 2),
      child: Row(
        children: [
          _leading(),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              item.title,
              style: AppText.rowTitle.copyWith(
                color: item.done ? AppColors.ink3 : AppColors.ink,
                decoration:
                    item.done ? TextDecoration.lineThrough : TextDecoration.none,
                decorationColor: AppColors.ink3,
              ),
            ),
          ),
          if (item.meta != null) ...[
            const SizedBox(width: AppSpacing.s),
            Text(
              item.meta!,
              style: AppText.meta.copyWith(
                color: item.hue == ZHue.flare
                    ? AppColors.flareText
                    : AppColors.ink3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _leading() {
    // Tasks/deadlines show a checkbox; overdue shows its Flare meaning dot.
    if (item.hue == ZHue.iris || item.hue == ZHue.neutral) {
      final box = _CheckBox(checked: item.done);
      if (item.taskId != null && onToggle != null) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onToggle!(item.taskId!, !item.done),
          child: box,
        );
      }
      return box;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: HueDot(item.hue),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked ? AppColors.iris : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: checked ? AppColors.iris : AppColors.hairline2,
          width: 1.6,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }
}
