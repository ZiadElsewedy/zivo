import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// A single ZIVO-styled auth text field (white card, hairline border, warm
/// ink, ember focus) — the same treatment as the sign-in form's fields, shared
/// by the password-reset and change-password surfaces so every auth input
/// reads identically.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.enabled,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      autocorrect: false,
      enableSuggestions: !obscureText,
      style: AppText.rowTitle,
      cursorColor: AppColors.ember,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.rowTitle.copyWith(color: AppColors.ink3),
        prefixIcon: Icon(icon, size: 20, color: AppColors.ink3),
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: const BorderSide(color: AppColors.hairline2, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: const BorderSide(color: AppColors.hairline2, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          borderSide: const BorderSide(color: AppColors.ember, width: 1.6),
        ),
      ),
    );
  }
}
