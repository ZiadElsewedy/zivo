import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'pressable_scale.dart';

/// The app's ONE back affordance for pushed pages — the 38px neutral chip
/// (surfaceRaised circle, hairline edge, left arrow) used by Settings,
/// Storage & Sync, Analysis, History, and every other drill-down surface.
///
/// Deliberately NOT used by:
/// - capture flows, whose top bar is an X (modal semantics: "close", not
///   "go back"),
/// - fullscreen overlays (photo viewer X; music player chevron-down),
/// - root tabs, which have no back at all.
///
/// Any page pushed onto the navigator should mount this — as an AppBar
/// `leading` or inline in a custom header — so navigation reads as one
/// system instead of Material-default arrows mixing with house chrome.
class BackChip extends StatelessWidget {
  const BackChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PressableScale(
        child: Tooltip(
          message: 'Back',
          child: InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            customBorder: const CircleBorder(),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hairline2),
              ),
              child: const Icon(AppIcons.back, size: 18, color: AppColors.ink2),
            ),
          ),
        ),
      ),
    );
  }
}
