import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import 'auth_action_button.dart';

/// Email + password inputs with a submit button. Owns its text controllers and
/// light client-side validation (non-empty email with an `@`, password ≥ 6);
/// the trust-boundary validation stays server-side. In sign-up mode it also
/// offers an optional name.
class EmailAuthForm extends StatefulWidget {
  const EmailAuthForm({
    required this.isSignUp,
    required this.submitting,
    required this.enabled,
    required this.onSubmit,
    super.key,
  });

  final bool isSignUp;

  /// The email action is in flight (spinner on the submit button).
  final bool submitting;

  /// No other auth action is in flight (fields + button interactive).
  final bool enabled;

  final void Function({
    required String email,
    required String password,
    String? name,
  }) onSubmit;

  @override
  State<EmailAuthForm> createState() => _EmailAuthFormState();
}

class _EmailAuthFormState extends State<EmailAuthForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _email.addListener(_recompute);
    _password.addListener(_recompute);
  }

  void _recompute() {
    final email = _email.text.trim();
    final valid = email.contains('@') &&
        email.contains('.') &&
        _password.text.length >= 6;
    if (valid != _canSubmit) setState(() => _canSubmit = valid);
  }

  void _submit() {
    if (!_canSubmit) return;
    final name = _name.text.trim();
    widget.onSubmit(
      email: _email.text.trim(),
      password: _password.text,
      name: name.isEmpty ? null : name,
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.isSignUp) ...[
          _Field(
            controller: _name,
            hint: 'Name (optional)',
            icon: Icons.person_outline_rounded,
            enabled: widget.enabled,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
        ],
        _Field(
          controller: _email,
          hint: 'Email',
          icon: Icons.mail_outline_rounded,
          enabled: widget.enabled,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 10),
        _Field(
          controller: _password,
          hint: 'Password',
          icon: Icons.lock_outline_rounded,
          enabled: widget.enabled,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        AuthActionButton(
          label: widget.isSignUp ? 'Create account' : 'Sign in',
          icon: const Icon(Icons.arrow_forward_rounded,
              size: 18, color: Colors.white),
          background: AppColors.ember,
          loading: widget.submitting,
          enabled: widget.enabled && _canSubmit,
          onTap: _submit,
        ),
      ],
    );
  }
}

/// A single ZIVO-styled text field (white card, hairline border, warm ink).
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.enabled,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
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
