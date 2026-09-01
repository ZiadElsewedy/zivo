import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/widgets/train_chrome.dart';
import '../../../../../l10n/l10n.dart';
import 'live_session_format.dart';

/// The in-session top bar as a translucent, blurred material rather than a
/// flat opaque strip — chrome that reads as a physical layer over the
/// session, matching the ground beneath it in hue so it darkens rather than
/// washes out. `prefers-reduced-transparency`-style: falls back to a solid
/// (unblurred) surface when reduced motion is on, since blur is itself a
/// subtle, continuous visual effect best paired with the rest of the
/// session's motion.
/// The session header: close on the left, the day and the running clock in
/// the middle, discard on the right.
///
/// The clock doubles as the pause control — the handoff draws no separate
/// pause button, and tapping the time is where a hand already goes to check
/// it. Paused swaps the day caption for a PAUSED badge, so the state is
/// unmissable rather than a small icon change.
class SessionHeader extends StatelessWidget {
  const SessionHeader({
    required this.title,
    required this.elapsed,
    required this.isPaused,
    required this.onClose,
    required this.onDiscard,
    required this.onTogglePause,
    super.key,
  });

  final String title;
  final Duration elapsed;
  final bool isPaused;
  final VoidCallback onClose;
  final VoidCallback onDiscard;

  /// Null once the session completes — nothing left to pause.
  final VoidCallback? onTogglePause;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TrainCircleButton(
          semanticLabel: l(context).actionClose,
          onTap: onClose,
          child: const Icon(
            Icons.close_rounded,
            size: 15,
            color: Color(0xBFF4F4F0),
          ),
        ),
        Expanded(
          child: Semantics(
            button: onTogglePause != null,
            label: isPaused
                ? l(context).workoutResume
                : l(context).workoutPause,
            child: GestureDetector(
              key: const Key('pause-toggle'),
              behavior: HitTestBehavior.opaque,
              onTap: onTogglePause == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTogglePause!();
                    },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPaused)
                    Container(
                      key: const Key('paused-badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: TrainColors.ember.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: TrainColors.ember.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        l(context).livePausedTapResume,
                        style: TrainType.mono(
                          size: 8.5,
                          weight: FontWeight.w600,
                          tracking: 0.16,
                          color: TrainColors.ember,
                        ),
                      ),
                    )
                  else
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TrainType.mono(
                        size: 9,
                        weight: FontWeight.w600,
                        tracking: 0.18,
                        color: const Color(0x66F4F4F0),
                      ),
                    ),
                  const SizedBox(height: 7),
                  Text(
                    formatElapsed(elapsed),
                    key: const Key('elapsed-timer'),
                    style: TrainType.mono(
                      size: 13,
                      color: isPaused
                          ? const Color(0x66F4F4F0)
                          : TrainColors.inkPlain,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        TrainCircleButton(
          semanticLabel: l(context).liveDiscardWorkout,
          onTap: onDiscard,
          // Neutral, same weight as Close — a destructive action still gated
          // behind its own confirm dialog shouldn't also be the loudest thing
          // in the bar. Flare stays reserved for the confirm dialog's actual
          // "Discard" button, where committing to it is the whole point.
          child: const Icon(
            Icons.delete_outline_rounded,
            size: 16,
            color: Color(0x99F4F4F0),
          ),
        ),
      ],
    );
  }
}

/// Walk back one set. Only rendered once something has actually been
/// resolved, so the header matches the design exactly until there's a reason
/// for it not to.
class SessionBackChip extends StatelessWidget {
  const SessionBackChip({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.only(top: 8, right: 12, bottom: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.back, size: 11, color: Color(0x66F4F4F0)),
              const SizedBox(width: 5),
              Text(
                l(context).actionBackCaps,
                style: TrainType.mono(
                  size: 8.5,
                  weight: FontWeight.w600,
                  tracking: 0.16,
                  color: const Color(0x66F4F4F0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A phase eyebrow — the pill that names what the screen is doing right now
/// (REST, PRE-WORKOUT, COMPLETE).
class PhaseEyebrow extends StatelessWidget {
  const PhaseEyebrow(
    this.text, {
    required this.color,
    this.icon,
    this.glyph,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final String text;
  final Color color;

  /// An optional mark inside the chip — the phase's identity at a glance.
  final IconData? icon;

  /// A custom-painted mark, used where the handoff draws a filled glyph
  /// rather than a stroked icon (rest's pause bars).
  final Widget? glyph;

  /// Makes the pill a real control. The rest phase uses it to pause/resume:
  /// the chip already wore a pause glyph, so anything less than an actual
  /// button there was a lie.
  final VoidCallback? onTap;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final chip = _chip();
    if (onTap == null) return chip;
    return PressableScale(
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap!();
          },
          child: chip,
        ),
      ),
    );
  }

  Widget _chip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[glyph!, const SizedBox(width: 8)],
          if (glyph == null && icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 8),
          ],
          Text(
            text.toUpperCase(),
            style: TrainType.mono(
              size: 10,
              weight: FontWeight.w600,
              tracking: 0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// "+2.5kg from your previous set" — how this set compares to your own
/// previous one today.
///
/// Present for every set after the first, changed or not (see
/// [intraSessionDeltaLabel]), so the goal card holds one height while you
/// step the weight. Only its colour and copy move: ember with a bolt when
/// you've actually changed something, quiet neutral when you're repeating the
/// load — the accent has to mean "this is different", or it stops meaning
/// anything.
class IntraSessionChip extends StatelessWidget {
  const IntraSessionChip({required this.delta, super.key});

  final ({String label, bool changed}) delta;

  @override
  Widget build(BuildContext context) {
    final color = delta.changed ? TrainColors.ember : TrainColors.ink3;
    return AnimatedContainer(
      duration: reducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: delta.changed
            ? TrainColors.ember.withValues(alpha: 0.12)
            : TrainColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            delta.changed ? Icons.bolt_rounded : Icons.remove_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              delta.label,
              style: TrainType.ui(
                size: 11.5,
                weight: FontWeight.w700,
                height: 1.2,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
