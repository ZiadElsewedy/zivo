import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/zivo_field.dart';

/// The next cycle slot letter for a plan that already has [count] days: A, B,
/// C… (falls back to a number past Z).
String slotForIndex(int count) =>
    count < 26 ? String.fromCharCode(0x41 + count) : '${count + 1}';

/// A custom "lift" for drag-reordered items (day tiles, exercise rows) —
/// scales up slightly, gains elevation/shadow, and dims a touch while being
/// dragged, replacing [ReorderableListView]'s plain default proxy (a flat
/// `Material` with no real weight to it). [animation] is driven by
/// [ReorderableListView] itself (0 at pickup/drop, ~1 while actively
/// dragging) — the internal reflow/settle timing isn't swappable for a
/// custom spring via the public API, but it's already a smooth transition,
/// not an instant snap. Reduced motion drops the lift flourish entirely
/// (the reorder itself stays fully functional either way).
Widget liftProxyDecorator(
  Widget child,
  Animation<double> animation, {
  required double radius,
}) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, builtChild) {
      if (reducedMotion(context)) return builtChild!;
      final t = animation.value;
      return Transform.scale(
        scale: 1.0 + 0.03 * t,
        child: Material(
          color: Colors.transparent,
          elevation: 10 * t,
          shadowColor: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(radius),
          child: Opacity(opacity: 1 - 0.05 * t, child: builtChild!),
        ),
      );
    },
    child: child,
  );
}

class PlanEmptyDays extends StatelessWidget {
  const PlanEmptyDays({required this.onAdd, super.key});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.fitness_center_rounded,
            size: 30,
            color: TrainColors.ink4,
          ),
          const SizedBox(height: 12),
          Text(
            'No days yet.',
            style: TrainType.ui(
              size: 14,
              weight: FontWeight.w400,
              height: 1.5,
              color: TrainColors.ink2,
            ),
          ),
          const SizedBox(height: 14),
          PlanAddButton(label: 'Add day', onTap: onAdd),
        ],
      ),
    );
  }
}

class PlanAddButton extends StatelessWidget {
  const PlanAddButton({
    required this.label,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 18,
            vertical: compact ? 8 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: TrainColors.hairline, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quiet, not green: "Add day"/"Add exercise" sit above this
              // screen's real commit ("Save plan"), and two coloured actions
              // competing is the "one committing action" rule being broken.
              Icon(
                Icons.add_rounded,
                size: compact ? 14 : 17,
                color: const Color(0x99F4F4F0),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TrainType.ui(
                  size: compact ? 12.5 : 14,
                  weight: FontWeight.w700,
                  height: 1,
                  color: const Color(0xCCF4F4F0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shared bottom-sheet chrome (grabber + title + content), matching the
/// session/plan screens' dark palette.
class SheetShell extends StatelessWidget {
  const SheetShell({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Color(0x08FFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 12,
          left: 22,
          right: 22,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: TrainColors.hairline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: Text(
                title,
                style: TrainType.ui(
                  size: 20,
                  weight: FontWeight.w800,
                  tracking: -0.025,
                  height: 1.15,
                  color: TrainColors.ink,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A labelled single-line text field for the sheets.
class LabeledField extends StatelessWidget {
  const LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.autofocus = false,
    this.onSubmitted,
    this.fieldKey,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TrainType.mono(
            size: 10.5,
            tracking: 0.06,
            color: TrainColors.ink4,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          key: fieldKey,
          controller: controller,
          autofocus: autofocus,
          textInputAction: TextInputAction.next,
          onSubmitted: onSubmitted,
          cursorColor: TrainColors.green,
          style: TrainType.ui(
            size: 15,
            weight: FontWeight.w700,
            height: 1.1,
            color: TrainColors.ink,
          ),
          decoration: InputDecoration(
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: TrainColors.hairline),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: TrainColors.hairline),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: TrainColors.green, width: 1.6),
            ),
            hintText: hint,
            hintStyle: TrainType.ui(
              size: 15,
              weight: FontWeight.w700,
              height: 1.1,
              color: TrainColors.ink4,
            ),
          ),
        ),
      ],
    );
  }
}

class PlanNumberField extends StatelessWidget {
  const PlanNumberField({
    required this.label,
    required this.controller,
    this.hint,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TrainType.mono(
            size: 10.5,
            tracking: 0.06,
            color: TrainColors.ink4,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          cursorColor: TrainColors.green,
          style: TrainType.ui(
            size: 15,
            weight: FontWeight.w700,
            height: 1.1,
            color: TrainColors.ink,
          ),
          decoration: zivoFieldDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TrainType.ui(
              size: 15,
              weight: FontWeight.w700,
              height: 1.1,
              color: TrainColors.ink4,
            ),
            fill: TrainColors.glassStrong,
          ),
        ),
      ],
    );
  }
}
