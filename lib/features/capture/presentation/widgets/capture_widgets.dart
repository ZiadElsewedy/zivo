import 'package:flutter/material.dart';

import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../l10n/l10n.dart';

/// The chrome every capture and edit flow shares — the close/title top bar,
/// its icon chips, the commit pill, and the selectable chip.
///
/// On the design handoff's material, because these screens are opened FROM
/// handoff screens: the capture flow is the same world as the surface that
/// launched it, so it uses the same glass, hairlines, Manrope and mono.

/// A close button + centred title, shared by the capture screens.
class CaptureTopBar extends StatelessWidget {
  const CaptureTopBar({
    required this.title,
    required this.onClose,
    this.trailing,
    this.titleColor = TrainColors.ink2,
    this.iconColor = TrainColors.ink2,
    this.chipColor = TrainColors.glassStrong,
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
            semanticLabel: l(context).actionClose,
            iconColor: iconColor,
            chipColor: chipColor,
          ),
          Expanded(
            child: Center(
              child: Text(
                // A screen title stays a title: Manrope, sentence case. The
                // handoff's mono-uppercase caption rule is for LABELS on a
                // screen, not for the screen's own name.
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TrainType.ui(
                  size: 14.5,
                  weight: FontWeight.w700,
                  color: titleColor,
                  height: 1,
                ),
              ),
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
    this.iconColor = TrainColors.ink2,
    this.chipColor = TrainColors.glassStrong,
    super.key,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final Color iconColor;
  final Color chipColor;

  /// The visible chip diameter — the handoff's 36px circular control.
  static const double chipSize = 36;

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
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: chipColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width pill action button used to commit a capture.
///
/// [busy] is the "this button's own action is running" state: the glyph
/// becomes a spinner and the label stays put, so the press has visible
/// consequences even when the commit takes a beat. It does not disable on its
/// own — hosts pass `enabled: ... && !actionInFlight` (see
/// `core/widgets/async_action.dart`), which is what actually stops a second
/// tap from committing a second copy.
class PillButton extends StatelessWidget {
  const PillButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.busy = false,
    this.color = TrainColors.ember,
    this.textColor = Colors.white,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  /// Whether this button's action is currently in flight.
  final bool busy;

  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        // The one shadow the identity doc allows: the colored bloom under a
        // primary pill (§5). Only when enabled — a disabled action shouldn't
        // glow like a committing one.
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: enabled
                ? TrainColors.actionGlow(color, alpha: 0.30)
                : null,
          ),
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 17),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Same 18pt box either way, so the label never shifts as
                    // the button flips into its committing state.
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: busy
                          ? Padding(
                              padding: const EdgeInsets.all(1.5),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: textColor,
                              ),
                            )
                          : Icon(icon, size: 18, color: textColor),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TrainType.ui(
                          size: 16.5,
                          weight: FontWeight.w800,
                          tracking: -0.01,
                          color: textColor,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [ChipTone.flare] keeps its name for its call sites, but on the handoff's
/// palette it is ember — the colour reserved for the thing that wants your
/// attention. There is no separate red.
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
      bg = TrainColors.ember;
      fg = Colors.white;
      border = TrainColors.ember;
    } else if (selected) {
      bg = TrainColors.ink;
      fg = TrainColors.base;
      border = TrainColors.ink;
    } else {
      bg = TrainColors.glass;
      fg = tone == ChipTone.flare ? TrainColors.ember : TrainColors.ink2;
      border = tone == ChipTone.flare
          ? TrainColors.ember.withValues(alpha: 0.35)
          : TrainColors.hairline;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TrainType.ui(
                size: 13,
                weight: FontWeight.w700,
                color: fg,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
