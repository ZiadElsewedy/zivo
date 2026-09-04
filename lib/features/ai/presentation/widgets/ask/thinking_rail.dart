import 'package:flutter/material.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../ask_constants.dart';
import '../../../../../l10n/l10n.dart';

/// The calm "the assistant is working" state: a softly glowing iris orb that
/// breathes beside the authoritative phase label, which cross-fades between
/// phases. After [kSlowTurnAfter] with no gateway activity, [slow] admits
/// the wait ("Still working on this one…") so a long turn never reads as a
/// silent hang. Shown only while a turn is in flight, so its looping pulse
/// is never left mounted (which would stall `pumpAndSettle`). No spinner.
class ThinkingRail extends StatefulWidget {
  const ThinkingRail({this.label, this.slow = false, super.key});

  /// The current phase label (authoritative when streaming). Null falls back
  /// to the localized "Thinking…" — resolved in `build` rather than as a
  /// default here, because a `const` constructor cannot reach `Localizations`.
  final String? label;

  /// The turn has gone quiet — add the honest reassurance line.
  final bool slow;

  @override
  State<ThinkingRail> createState() => _ThinkingRailState();
}

class _ThinkingRailState extends State<ThinkingRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
    upperBound: 1,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label ?? l(context).askThinking;
    final still = MediaQuery.of(context).disableAnimations;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The orb: an iris core inside its own glow.
              still
                  ? const GlowOrb(opacity: 0.9)
                  : FadeTransition(
                      opacity: _c,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.85, end: 1).animate(_c),
                        child: const GlowOrb(opacity: 1),
                      ),
                    ),
              const SizedBox(width: 9),
              AnimatedSwitcher(
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previousChildren, ?currentChild],
                ),
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: AppText.meta.copyWith(
                    color: TrainColors.violet,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          // Honest slow-turn reassurance — appears only when warranted.
          AnimatedSize(
            duration: still ? Duration.zero : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: widget.slow
                ? Padding(
                    key: const ValueKey('slow'),
                    padding: const EdgeInsets.only(left: 19, top: 4),
                    child: Text(
                      l(context).askStillWorking,
                      style: AppText.meta.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: TrainColors.ink3,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// A small iris dot wrapped in its own soft glow — the "alive" signal.
class GlowOrb extends StatelessWidget {
  const GlowOrb({required this.opacity, super.key});

  final double opacity;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    child: Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: TrainColors.violet.withValues(alpha: 0.45),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Center(child: IrisDot(1)),
    ),
  );
}

class IrisDot extends StatelessWidget {
  const IrisDot(this.opacity, {super.key});

  final double opacity;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: TrainColors.violet.withValues(alpha: opacity),
      shape: BoxShape.circle,
    ),
  );
}
