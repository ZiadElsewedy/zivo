import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// The four-tab command bar: Today · Hub · Ask · You (decision D-1).
class ZivoBottomBar extends StatelessWidget {
  const ZivoBottomBar({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xE0211A14),
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          padding: EdgeInsets.only(top: 10, bottom: bottomInset > 0 ? bottomInset : 12),
          child: Row(
            children: [
              _Tab(
                index: 0,
                label: 'Today',
                icon: Icons.home_rounded,
                activeIcon: Icons.home_rounded,
                filled: true,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _Tab(
                index: 1,
                label: 'Hub',
                icon: Icons.grid_view_rounded,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _Tab(
                index: 2,
                label: 'Ask',
                icon: Icons.adjust_rounded,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _Tab(
                index: 3,
                label: 'You',
                icon: Icons.person_outline_rounded,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.index,
    required this.label,
    required this.icon,
    required this.currentIndex,
    required this.onTap,
    this.activeIcon,
    this.filled = false,
  });

  final int index;
  final String label;
  final IconData icon;
  final IconData? activeIcon;
  final bool filled;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final active = index == currentIndex;
    final color = active ? AppColors.ember : AppColors.tabInactive;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(active ? (activeIcon ?? icon) : icon, size: 24, color: color),
              const SizedBox(height: 5),
              Text(
                label.toUpperCase(),
                style: AppText.tabLabel.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
