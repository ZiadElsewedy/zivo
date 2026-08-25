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
///
/// Motion: every field lives in a fixed slot that fades/slides in and out as
/// the mode flips, with the whole form resizing smoothly around them —
/// toggling reads as one continuous morph instead of widgets popping.
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
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        // Every slot below exists in BOTH modes; [_Slot] swaps its content so
        // the TextFields' elements stay put and never lose focus or text.
        children: [
          _Slot(
            visible: widget.isSignUp,
            child: _Field(
              controller: _name,
              hint: 'Name (optional)',
              icon: Icons.person_outline_rounded,
              enabled: widget.enabled,
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(height: 10),
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
          _Slot(
            visible: widget.isSignUp,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _PasswordChecklist(password: _password.text),
            ),
          ),
          _Slot(
            visible: widget.isSignUp,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                SizedBox(
                  height: _confirmPassword.text.isEmpty ? 0 : 24,
                  child: _MatchHint(
                    matches: _confirmPassword.text == _password.text,
                    visible: _confirmPassword.text.isNotEmpty,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AuthActionButton(
            label: widget.isSignUp ? 'Create account' : 'Sign in',
            icon: Icon(Icons.arrow_forward_rounded,
                size: 18, color: AppColors.ground),
            background: AppColors.ember,
            loading: widget.submitting,
            enabled: widget.enabled && _canSubmit,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}

/// A fixed-size slot whose content fades/rises in and out. Keeping the slot
/// present in both auth modes means sibling [TextField]s keep their elements
/// (and their text/focus) when the mode flips.
class _Slot extends StatelessWidget {
  const _Slot({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.25),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [...previousChildren, ?currentChild],
      ),
      child: visible
          ? KeyedSubtree(key: ValueKey(visible), child: child)
          : SizedBox.shrink(key: ValueKey(visible)),
    );
  }
}

/// Live per-rule feedback for [PasswordPolicy], rendered under the password
/// field during sign-up so the user knows exactly what's missing. Each rule's
/// tint eases between met/unmet rather than snapping.
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
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: AppColors.ink3, end: met ? AppColors.pulseText : AppColors.ink3),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, color, child) => Padding(
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
      ),
    );
  }
}

/// Inline feedback on whether the confirm-password field matches the first
/// password. Fades in once something has been typed; its tint eases between
/// the match/mismatch colors rather than snapping.
class _MatchHint extends StatelessWidget {
  const _MatchHint({required this.matches, required this.visible});

  final bool matches;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        begin: AppColors.flareText,
        end: matches ? AppColors.pulseText : AppColors.flareText,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, color, _) {
        final icon = matches
            ? Icons.check_circle_rounded
            : Icons.error_outline_rounded;
        final label = matches ? 'Passwords match' : "Passwords don't match";
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: visible ? 1 : 0,
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Text(label, style: AppText.meta.copyWith(color: color)),
            ],
          ),
        );
      },
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
