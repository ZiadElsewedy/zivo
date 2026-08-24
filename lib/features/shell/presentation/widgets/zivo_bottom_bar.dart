import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';

/// Shared sizing so callers needing clearance above [ZivoBottomBar] (e.g. a
/// page's scroll padding) can derive it exactly instead of guessing a magic
/// number — keeps that clearance from drifting out of sync with the bar's
/// actual layout.
abstract final class ZivoBottomBarMetrics {
  /// The bar's device-independent content height: outer top inset (10) +
  /// inner tab padding (4 + 4) + icon (24) + icon-label gap (5) + label
  /// line height (~14 at 9.5sp).
  static const double contentHeight = 61;

  /// Total rendered height of [ZivoBottomBar] for the current context,
  /// including whatever bottom safe-area inset it applies.
  static double height(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return contentHeight + (bottomInset > 0 ? bottomInset : 12);
  }
}

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
                icon: AppIcons.today,
                activeIcon: AppIcons.todayFill,
                filled: true,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _Tab(
                index: 1,
                label: 'Hub',
                icon: AppIcons.hub,
                activeIcon: AppIcons.hubFill,
                filled: true,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _Tab(
                index: 2,
                label: 'Ask',
                icon: AppIcons.ask,
                activeIcon: AppIcons.askFill,
                filled: true,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _Tab(
                index: 3,
                label: 'You',
                icon: AppIcons.you,
                activeIcon: AppIcons.youFill,
                filled: true,
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

class _Tab extends StatefulWidget {
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
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> with SingleTickerProviderStateMixin {
  bool get _active => widget.index == widget.currentIndex;

  /// 0 = inactive, 1 = active — drives both the icon's spring-in scale and
  /// the outline↔fill glyph cross-fade below.
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: _active ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _Tab old) {
    super.didUpdateWidget(old);
    final wasActive = old.index == old.currentIndex;
    if (_active != wasActive) {
      if (reducedMotion(context)) {
        _c.value = _active ? 1 : 0;
      } else {
        // A momentum moment the tap itself earned — the only place overshoot
        // belongs (see AppSprings.bounce doc).
        _c.springTo(_active ? 1 : 0, spring: AppSprings.bounce);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _active ? AppColors.ember : AppColors.tabInactive;
    return Expanded(
      child: InkWell(
        onTap: () => widget.onTap(widget.index),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value.clamp(0.0, 1.0);
                  return Transform.scale(
                    scale: 1.0 + 0.12 * t,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: 1 - t,
                            child: Icon(
                              widget.icon,
                              size: 24,
                              color: AppColors.tabInactive,
                            ),
                          ),
                          Opacity(
                            opacity: t,
                            child: Icon(
                              widget.activeIcon ?? widget.icon,
                              size: 24,
                              color: AppColors.ember,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 5),
              // Color here is semantic state (active/inactive), not
              // decoration — an implicit tween is cheap and idiomatic in
              // Flutter, so it's allowed to cross-fade alongside the icon
              // rather than snapping.
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                style: AppText.tabLabel.copyWith(color: color),
                child: Text(widget.label.toUpperCase()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
