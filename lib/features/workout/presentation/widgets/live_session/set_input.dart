import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/widgets/train_chrome.dart';
import '../../../../../core/util/parse.dart';
import '../../../../../l10n/l10n.dart';
import 'live_session_format.dart';
import 'phases/phase_scaffold.dart';

/// Every tappable thing that belongs to the reps/weight cluster shares this
/// tap-region group: the two fields, their four ± buttons and the quick-load
/// chips. A tap **anywhere else** on the screen therefore counts as "outside
/// the input" and puts the keyboard away, while nudging a value or picking a
/// preset leaves it up. Without the shared id each field would treat the
/// other's stepper buttons as outside itself.
const Object kSetInputGroup = #zivoSetInput;

class ActionCluster extends StatelessWidget {
  const ActionCluster({required this.onSkip, required this.onDone, super.key});

  final VoidCallback onSkip;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Deliberately fixed-width and muted next to Log set — Skip is the
        // exception path, logging is the expected one, and an accidental tap
        // should default toward the common case.
        SizedBox(
          width: 104,
          height: kCommitRowHeight,
          child: TrainGhostButton(
            key: const Key('skip-set'),
            label: l(context).liveSkip,
            mono: false,
            height: kCommitRowHeight,
            icon: const TrainPlayGlyph(
              color: Color(0x99F4F4F0),
              size: 11,
              bar: true,
            ),
            onTap: onSkip,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TrainPrimaryButton(
            key: const Key('log-set'),
            label: l(context).liveLogSet,
            height: kCommitRowHeight,
            icon: const Icon(
              Icons.check_rounded,
              size: 18,
              color: Colors.white,
            ),
            onTap: onDone,
          ),
        ),
      ],
    );
  }
}

/// A premium tap-to-step reps/weight input (Feature C) — the same
/// [TextField] the plain field always used (typing directly into it, the
/// fallback, still works exactly as before — nothing about that path
/// changed), now flanked by ± stepper buttons that nudge the value by
/// [step] with a selection-click haptic and a small spring "punch" on the
/// field itself, the "alive" feedback the plain field never had.
class StepperField extends StatefulWidget {
  const StepperField({
    required this.label,
    required this.controller,
    required this.step,
    required this.onChanged,
    this.hint,
    super.key,
  });

  final String label;
  final TextEditingController controller;

  /// How much each ± tap moves the value — whole reps (1) or a plate-sized
  /// weight jump (2.5kg), passed in per call site.
  final double step;
  final VoidCallback onChanged;
  final String? hint;

  @override
  State<StepperField> createState() => _StepperFieldState();
}

class _StepperFieldState extends State<StepperField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _punch = AnimationController(
    vsync: this,
    value: 1,
  );

  double? get _value => parseDecimal(widget.controller.text);

  /// Nudges the value by [delta] and writes it straight back into
  /// [widget.controller] — the same controller the typed fallback edits, so
  /// both paths always agree on what's actually entered.
  void _step(double delta) {
    HapticFeedback.selectionClick();
    final raw = (_value ?? 0) + delta;
    final next = raw < 0 ? 0.0 : raw;
    widget.controller.text = trimWeight(next);
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    if (reducedMotion(context)) {
      _punch.value = 1;
    } else {
      _punch.value = 0.88;
      _punch.springTo(1, spring: AppSprings.bounce);
    }
    widget.onChanged();
  }

  @override
  void dispose() {
    _punch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One bordered pill housing minus/value/plus — a single tactile unit
    // with hairline dividers marking its three regions, rather than three
    // separate floating chips with gaps between them.
    final radius = BorderRadius.circular(16);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: TrainType.mono(
              size: 8.5,
              weight: FontWeight.w500,
              tracking: 0.16,
              color: const Color(0x52F4F4F0),
            ),
          ),
          const SizedBox(height: 8),
          // The whole pill is one tap region, so the ± buttons never read as
          // "outside the field" and dismiss the keyboard mid-adjustment.
          TapRegion(
            groupId: kSetInputGroup,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: TrainColors.glassSoft,
                borderRadius: radius,
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Row(
                  children: [
                    StepButton(
                      icon: Icons.remove_rounded,
                      onTap: () => _step(-widget.step),
                    ),
                    Container(width: 1, color: TrainColors.hairlineStrong),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _punch,
                        builder: (context, child) =>
                            Transform.scale(scale: _punch.value, child: child),
                        child: TextField(
                          controller: widget.controller,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          groupId: kSetInputGroup,
                          // A decimal pad has no Return key on iOS, so the
                          // field cannot close its own keyboard. A tap on
                          // anything that isn't part of the input cluster does
                          // it instead — the goal card, the header, the
                          // background — alongside the drag-to-dismiss on the
                          // phase scroll and the explicit Done pill above the
                          // commit row.
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          // Keep the focused field clear of the PINNED commit
                          // row when the keyboard scrolls it into view; the
                          // default 20 only clears the viewport edge, which the
                          // buttons float over.
                          scrollPadding: const EdgeInsets.only(
                            bottom: kCommitRowSpace + 20,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          cursorColor: TrainColors.ember,
                          style: TrainType.mono(
                            size: 20,
                            color: TrainColors.ink,
                          ),
                          onChanged: (_) => widget.onChanged(),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: widget.hint,
                            hintStyle: TrainType.mono(
                              size: 20,
                              color: const Color(0x59F4F4F0),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 4,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    Container(width: 1, color: TrainColors.hairlineStrong),
                    StepButton(
                      icon: Icons.add_rounded,
                      onTap: () => _step(widget.step),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One-tap load decisions under the steppers — "Same" (the reference
/// weight: last time's actual, or the plan's target on first run), plus
/// ±[stepKg] nudges. The 80% case ("same again", "go up") becomes one tap
/// instead of typing or repeated stepping.
class QuickWeightRow extends StatelessWidget {
  const QuickWeightRow({
    required this.baseWeight,
    required this.stepKg,
    required this.onPick,
    super.key,
  });

  final double baseWeight;
  final double stepKg;
  final ValueChanged<double> onPick;

  @override
  Widget build(BuildContext context) {
    // Part of the input cluster, not "outside" it — picking a preset while
    // typing shouldn't yank the keyboard away mid-decision.
    return TapRegion(
      groupId: kSetInputGroup,
      child: Row(
        children: [
          QuickWeightChip(
            label: l(context).liveSameWeight(trimWeight(baseWeight)),
            onTap: () => onPick(baseWeight),
            primary: true,
          ),
          const SizedBox(width: AppSpacing.s),
          QuickWeightChip(
            label: '+${trimWeight(stepKg)}',
            onTap: () => onPick(baseWeight + stepKg),
          ),
          const SizedBox(width: AppSpacing.s),
          QuickWeightChip(
            label: '−${trimWeight(stepKg)}',
            onTap: () => onPick(baseWeight - stepKg),
          ),
        ],
      ),
    );
  }
}

class QuickWeightChip extends StatelessWidget {
  const QuickWeightChip({
    required this.label,
    required this.onTap,
    this.primary = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  /// The "Same" chip — the expected pick — reads as the default: filled,
  /// not outlined.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: primary
                ? TrainColors.green.withValues(alpha: 0.08)
                : TrainColors.glassSoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: primary
                  ? TrainColors.green.withValues(alpha: 0.30)
                  : const Color(0x14FFFFFF),
            ),
          ),
          child: Text(
            label,
            style: TrainType.mono(
              size: 11.5,
              weight: FontWeight.w500,
              color: primary ? TrainColors.green : const Color(0x99F4F4F0),
            ),
          ),
        ),
      ),
    );
  }
}

/// One ± segment of a [StepperField]'s pill — no background/border of its
/// own (the pill's outer [Container] owns those; [ClipRRect] keeps the ink
/// response inside the shared shape), just a clear tap target with an
/// ember-tinted splash/highlight for a tactile press state.
class StepButton extends StatelessWidget {
  const StepButton({required this.icon, required this.onTap, super.key});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: TrainColors.ember.withValues(alpha: 0.18),
          highlightColor: TrainColors.ember.withValues(alpha: 0.10),
          child: SizedBox(
            width: 46,
            height: 52,
            child: Center(child: Icon(icon, size: 18, color: TrainColors.ink2)),
          ),
        ),
      ),
    );
  }
}
