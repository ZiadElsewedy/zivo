import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';

enum KeypadKey { digit, dot, backspace }

/// The amount keypad. Digits raise their own callback; "." and backspace use
/// [onKey]. Keys are big and lifted for confident, glanceable tapping.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    required this.onDigit,
    required this.onKey,
    super.key,
  });

  final ValueChanged<String> onDigit;
  final ValueChanged<KeypadKey> onKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          _row(['1', '2', '3']),
          const SizedBox(height: 8),
          _row(['4', '5', '6']),
          const SizedBox(height: 8),
          _row(['7', '8', '9']),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _FnKey(child: const Text('.'), onTap: () => onKey(KeypadKey.dot))),
              const SizedBox(width: 8),
              Expanded(child: _DigitKey('0', onTap: () => onDigit('0'))),
              const SizedBox(width: 8),
              Expanded(
                child: _FnKey(
                  child: const Icon(Icons.backspace_outlined,
                      size: 22, color: AppColors.ink2),
                  onTap: () => onKey(KeypadKey.backspace),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(List<String> digits) {
    return Row(
      children: [
        for (var i = 0; i < digits.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _DigitKey(digits[i], onTap: () => onDigit(digits[i]))),
        ],
      ],
    );
  }
}

class _DigitKey extends StatelessWidget {
  const _DigitKey(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.card,
          ),
          child: Text(
            label,
            style: AppText.cardTitle.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _FnKey extends StatelessWidget {
  const _FnKey({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        child: DefaultTextStyle(
          style: AppText.cardTitle.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w500,
            color: AppColors.ink2,
          ),
          child: child,
        ),
      ),
    );
  }
}
