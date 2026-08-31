import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import 'pressable_scale.dart';
import '../theme/train_tokens.dart';
import '../../l10n/l10n.dart';

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
  const BackChip({this.onTap, this.enabled = true, super.key});

  /// Where "back" goes. Defaults to popping the route — override it only for a
  /// multi-step page where back means back one *step* (the password-reset
  /// flow), so those pages keep the house affordance instead of forking a
  /// look-alike.
  final VoidCallback? onTap;

  /// Dims and disarms the chip while an action is in flight.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: PressableScale(
          enabled: enabled,
          child: Tooltip(
            message: l(context).actionBack,
            child: InkWell(
              onTap: enabled
                  ? (onTap ?? () => Navigator.of(context).maybePop())
                  : null,
              customBorder: const CircleBorder(),
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TrainColors.raisedStrong,
                  shape: BoxShape.circle,
                  border: Border.all(color: TrainColors.hairlineStrong),
                ),
                child: const Icon(
                  AppIcons.back,
                  size: 18,
                  color: TrainColors.ink2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
