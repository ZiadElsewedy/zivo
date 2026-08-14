import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/today_snapshot.dart';
import 'hue.dart';

/// Today's merged focus list — tasks + university deadlines, by relevance.
/// The list container is neutral; each row's dot encodes its source/status.
class FocusList extends StatelessWidget {
  const FocusList(this.items, {super.key});

  final List<FocusItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          _FocusRow(items[i], first: i == 0),
      ],
    );
  }
}

class _FocusRow extends StatelessWidget {
  const _FocusRow(this.item, {required this.first});

  final FocusItem item;
  final bool first;

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
          Expanded(child: Text(item.title, style: AppText.rowTitle)),
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
    // Tasks show a checkbox; deadlines/overdue show their meaning dot.
    if (item.hue == ZHue.iris || item.hue == ZHue.neutral) {
      return _CheckBox(checked: item.done);
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
