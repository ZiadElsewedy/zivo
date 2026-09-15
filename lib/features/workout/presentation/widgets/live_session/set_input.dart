import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/widgets/train_chrome.dart';
import '../../../../../core/util/parse.dart';
import '../../../../../l10n/l10n.dart';
import '../../../domain/weight_unit.dart';
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
            icon: TrainPlayGlyph(
              color: TrainColors.inkAt(0.6),
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
    this.trailing,
    super.key,
  });

  final String label;
  final TextEditingController controller;

  /// How much each ± tap moves the value — whole reps (1) or an
  /// equipment-sized weight jump, passed in per call site (see
  /// [weightStepFor]). Holding a ± button repeats it, accelerating.
  final double step;
  final VoidCallback onChanged;
  final String? hint;

  /// An optional control docked at the end of the label row — the weight
  /// field passes the KG/LB [UnitSelector] here so the unit sits right where
  /// the number it governs is entered.
  final Widget? trailing;

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
          // The label row: the caption, and (for the weight field) the KG/LB
          // selector at its trailing end. A fixed height keeps the two fields'
          // pills aligned whether or not one of them carries a selector.
          SizedBox(
            height: 22,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  widget.label.toUpperCase(),
                  style: TrainType.mono(
                    size: 8.5,
                    weight: FontWeight.w500,
                    tracking: 0.16,
                    color: TrainColors.ink4,
                  ),
                ),
                if (widget.trailing != null) ...[
                  const Spacer(),
                  widget.trailing!,
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          // The whole pill is one tap region, so the ± buttons never read as
          // "outside the field" and dismiss the keyboard mid-adjustment.
          TapRegion(
            groupId: kSetInputGroup,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: TrainColors.glassSoft,
                borderRadius: radius,
                border: Border.all(color: TrainColors.liftAt(0.078)),
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
                              color: TrainColors.inkAt(0.35),
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

/// The two load anchors under the steppers — the smart replacement for the old
/// `+2.5 / −2.5` chips.
///
/// The ± nudges lived here because there was nothing better; they hardcoded a
/// single 2.5 kg jump and said nothing. Micro-adjustment now belongs to the
/// steppers (unit- and equipment-aware, with hold-to-repeat), which frees this
/// row to carry the two loads that actually mean something mid-set:
///
/// - **Last** — what this exercise was last *actually* lifted at ([last]).
///   One tap to repeat it, instead of progressing.
/// - **Goal** — the progression engine's target ([goal]). One tap to jump to
///   the recommendation after nudging away from it.
///
/// Context-aware by omission: an exercise with no history shows no Last, and
/// Goal is hidden when it equals Last (nothing to choose between), so on a
/// first-ever set with only a plan target the row collapses to a single anchor
/// — never a fake number.
class LoadAnchorRow extends StatelessWidget {
  const LoadAnchorRow({
    required this.last,
    required this.goal,
    required this.unit,
    required this.onPick,
    super.key,
  });

  /// The last actually-lifted load (kg) — the carry-forward. Null on a
  /// bodyweight movement never logged with a load.
  final double? last;

  /// The progression target (kg), or null when there is nothing to suggest.
  final double? goal;

  final WeightUnit unit;

  /// Called with a canonical kilogram value — the caller converts for display.
  final ValueChanged<double> onPick;

  @override
  Widget build(BuildContext context) {
    final last = this.last;
    final goal = this.goal;
    // Goal is only worth its own chip when it differs from Last — otherwise the
    // two would read as duplicates. 0.05 kg guards float noise.
    final showGoal = goal != null && (last == null || (goal - last).abs() >= 0.05);
    final anchors = <Widget>[
      if (last != null)
        LoadAnchorChip(
          key: const Key('anchor-last'),
          label: l(context).liveQuickLast(weightWithUnit(l(context), last, unit)),
          onTap: () => onPick(last),
        ),
      if (showGoal)
        LoadAnchorChip(
          key: const Key('anchor-goal'),
          label: l(context).liveQuickGoal(weightWithUnit(l(context), goal, unit)),
          onTap: () => onPick(goal),
          // Goal points forward — the progression hue, matching the goal card.
          accent: TrainColors.green,
          icon: last != null && goal > last
              ? Icons.trending_up_rounded
              : null,
        ),
    ];
    if (anchors.isEmpty) return const SizedBox.shrink();
    // Part of the input cluster, not "outside" it — picking an anchor while
    // typing shouldn't yank the keyboard away mid-decision.
    return TapRegion(
      groupId: kSetInputGroup,
      child: Row(
        children: [
          for (final (i, chip) in anchors.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpacing.s),
            chip,
          ],
        ],
      ),
    );
  }
}

class LoadAnchorChip extends StatelessWidget {
  const LoadAnchorChip({
    required this.label,
    required this.onTap,
    this.accent,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  /// Present on the Goal anchor — tints it the progression hue; Last stays
  /// neutral.
  final Color? accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent;
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: accent != null
                ? accent.withValues(alpha: 0.08)
                : TrainColors.glassSoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: accent != null
                  ? accent.withValues(alpha: 0.30)
                  : TrainColors.liftAt(0.078),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: accent),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TrainType.mono(
                  size: 11.5,
                  weight: FontWeight.w500,
                  color: accent ?? TrainColors.inkAt(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The KG/LB selector — a compact monochrome segmented control that sits on the
/// weight field's label row. Deliberately hue-less: the unit is chrome, not a
/// committing action, so ember stays reserved for Log set. The selected segment
/// reads as a raised neutral wash under page-ink text (the same idiom as the
/// set chips on this screen), rather than an inverted ink thumb — both segments
/// then stay legible on either skin.
///
/// Inside [kSetInputGroup] so switching units mid-entry doesn't dismiss the
/// keyboard.
class UnitSelector extends StatelessWidget {
  const UnitSelector({required this.unit, required this.onChanged, super.key});

  final WeightUnit unit;
  final ValueChanged<WeightUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: kSetInputGroup,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: TrainColors.glassSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: TrainColors.liftAt(0.078)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final u in WeightUnit.values)
              _UnitSegment(
                label: u.symbolCaps,
                selected: u == unit,
                onTap: () => onChanged(u),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnitSegment extends StatelessWidget {
  const _UnitSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? TrainColors.inkAt(0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? TrainColors.inkAt(0.14) : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TrainType.mono(
              size: 9.5,
              weight: selected ? FontWeight.w700 : FontWeight.w600,
              tracking: 0.12,
              color: selected ? TrainColors.ink : TrainColors.inkAt(0.45),
            ),
          ),
        ),
      ),
    );
  }
}

/// One ± segment of a [StepperField]'s pill. A tap nudges once; a press-and-
/// hold repeats, accelerating from ~9/s to ~22/s so 70→100 is a hold, not
/// thirty taps. The first nudge fires on touch-down for instant feedback,
/// and an ember wash marks the pressed state (a plain [InkWell] splash can't
/// stay lit through a hold).
class StepButton extends StatefulWidget {
  const StepButton({required this.icon, required this.onTap, super.key});

  final IconData icon;

  /// One nudge — [StepperField._step], which itself haptics and springs.
  final VoidCallback onTap;

  @override
  State<StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<StepButton> {
  Timer? _repeat;
  int _fires = 0;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _beginRepeat() {
    _fires = 0;
    _repeat?.cancel();
    _repeat = Timer(const Duration(milliseconds: 110), _tickRepeat);
  }

  void _tickRepeat() {
    widget.onTap();
    _fires++;
    // Ramp the cadence so a long hold covers ground without overshooting on a
    // short one.
    final ms = _fires < 6
        ? 110
        : _fires < 14
        ? 70
        : 45;
    _repeat = Timer(Duration(milliseconds: ms), _tickRepeat);
  }

  void _endRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The single nudge fires on touch-down (immediate), so a long press
        // never has to wait out the recognizer before anything happens; the
        // hold below then adds the repeats.
        onTapDown: (_) {
          _setPressed(true);
          widget.onTap();
        },
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onLongPressStart: (_) {
          _setPressed(true);
          _beginRepeat();
        },
        onLongPressEnd: (_) {
          _setPressed(false);
          _endRepeat();
        },
        onLongPressCancel: () {
          _setPressed(false);
          _endRepeat();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          color: _pressed
              ? TrainColors.ember.withValues(alpha: 0.12)
              : Colors.transparent,
          width: 46,
          height: 52,
          child: Center(
            child: Icon(widget.icon, size: 18, color: TrainColors.ink2),
          ),
        ),
      ),
    );
  }
}
