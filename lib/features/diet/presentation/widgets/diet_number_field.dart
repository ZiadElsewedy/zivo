import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';

/// A labelled numeric field on the handoff's material — the one used by every
/// diet screen that asks for a number (targets, body data).
///
/// It returns an [Expanded], because every one of its call sites lays these
/// out two-to-a-[Row] and the alternative is wrapping each one at the call
/// site. Put it in a Row, or wrap it yourself.
class DietNumberField extends StatelessWidget {
  const DietNumberField({
    required this.label,
    required this.controller,
    required this.fieldKey,
    this.hint,
    this.decimal = true,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final Key fieldKey;
  final String? hint;

  /// Whether a fractional value makes sense here. False for calories and age,
  /// where a decimal point is only ever a typo.
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppText.meta.copyWith(
              color: TrainColors.ink3,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: fieldKey,
            controller: controller,
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
              ),
            ],
            cursorColor: TrainColors.green,
            style: AppText.rowTitle,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: AppText.rowTitle.copyWith(color: TrainColors.ink3),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 12,
              ),
              filled: true,
              fillColor: TrainColors.base,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Parses a decimal the user typed, accepting a comma as the decimal mark.
/// Null for anything that isn't a positive number — a blank field and "abc"
/// are the same thing here: not a number.
double? parsePositiveDecimal(String text) {
  final parsed = double.tryParse(text.trim().replaceAll(',', '.'));
  return (parsed == null || parsed <= 0) ? null : parsed;
}

/// Parses a whole number the user typed; null unless it's positive.
int? parsePositiveInt(String text) {
  final parsed = int.tryParse(text.trim());
  return (parsed == null || parsed <= 0) ? null : parsed;
}
