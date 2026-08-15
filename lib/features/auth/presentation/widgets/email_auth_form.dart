import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/password_policy.dart';
import 'auth_action_button.dart';

/// Email + password inputs with a submit button. Owns its text controllers and
/// light client-side validation (non-empty email with an `@`, password ≥ 6);
/// the trust-boundary validation stays server-side. In sign-up mode it also
/// offers an optional name, enforces [PasswordPolicy] with a live checklist,
/// and requires a matching confirm-password field.
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
  final _confirmPassword = TextEditingController();
  final _name = TextEditingController();
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _email.addListener(_recompute);
    _password.addListener(_recompute);
    _confirmPassword.addListener(_recompute);
  }

  void _recompute() {
    final email = _email.text.trim();
    final validEmail = email.contains('@') && email.contains('.');
    if (widget.isSignUp) {
      // Rebuild unconditionally: the live requirement checklist needs to
      // update on every keystroke, not just when submittability flips.
      final valid = validEmail &&
          PasswordPolicy.isSatisfiedBy(_password.text) &&
          _confirmPassword.text == _password.text;
      setState(() => _canSubmit = valid);
      return;
    }
    final valid = validEmail && _password.text.length >= 6;
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
    _confirmPassword.dispose();
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
          textInputAction:
              widget.isSignUp ? TextInputAction.next : TextInputAction.done,
          onSubmitted: widget.isSignUp ? null : (_) => _submit(),
        ),
        if (widget.isSignUp) ...[
          const SizedBox(height: 10),
          _PasswordChecklist(password: _password.text),
          const SizedBox(height: 10),
          _Field(
            controller: _confirmPassword,
            hint: 'Confirm password',
            icon: Icons.lock_outline_rounded,
            enabled: widget.enabled,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_confirmPassword.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            _MatchHint(matches: _confirmPassword.text == _password.text),
          ],
        ],
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

/// Live per-rule feedback for [PasswordPolicy], rendered under the password
/// field during sign-up so the user knows exactly what's missing.
class _PasswordChecklist extends StatelessWidget {
  const _PasswordChecklist({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rule in PasswordPolicy.rules)
          _ChecklistRow(
            label: rule.label,
            met: rule.isSatisfiedBy(password),
          ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final color = met ? AppColors.pulseText : AppColors.ink3;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(label, style: AppText.meta.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Inline feedback on whether the confirm-password field matches [_password].
class _MatchHint extends StatelessWidget {
  const _MatchHint({required this.matches});

  final bool matches;

  @override
  Widget build(BuildContext context) {
    final color = matches ? AppColors.pulseText : AppColors.flareText;
    return Row(
      children: [
        Icon(
          matches ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(
          matches ? 'Passwords match' : "Passwords don't match",
          style: AppText.meta.copyWith(color: color),
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
