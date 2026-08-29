import 'package:flutter/material.dart';

import '../../domain/password_policy.dart';
import 'auth_action_button.dart';
import 'auth_text_field.dart';
import 'password_checklist.dart';
import '../../../../core/theme/train_tokens.dart';

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
    this.prefillEmail,
    super.key,
  });

  final bool isSignUp;

  /// An address to seed the email field with — currently the account a
  /// just-completed password reset was performed on. Only ever applied when it
  /// *changes*, so it can never overwrite what the user is typing.
  final String? prefillEmail;

  /// The email action is in flight (spinner on the submit button).
  final bool submitting;

  /// No other auth action is in flight (fields + button interactive).
  final bool enabled;

  final void Function({
    required String email,
    required String password,
    String? name,
  })
  onSubmit;

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
    if (widget.prefillEmail != null) _email.text = widget.prefillEmail!;
    _email.addListener(_recompute);
    _password.addListener(_recompute);
    _confirmPassword.addListener(_recompute);
  }

  @override
  void didUpdateWidget(covariant EmailAuthForm old) {
    super.didUpdateWidget(old);
    final seeded = widget.prefillEmail;
    if (seeded != null && seeded != old.prefillEmail) {
      _email.text = seeded;
    }
  }

  void _recompute() {
    final email = _email.text.trim();
    final validEmail = email.contains('@') && email.contains('.');
    if (widget.isSignUp) {
      // Rebuild unconditionally: the live requirement checklist needs to
      // update on every keystroke, not just when submittability flips.
      final valid =
          validEmail &&
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
            child: AuthTextField(
              controller: _name,
              hint: 'Name (optional)',
              icon: Icons.person_outline_rounded,
              enabled: widget.enabled,
              textInputAction: TextInputAction.next,
            ),
          ),
          const SizedBox(height: 10),
          AuthTextField(
            controller: _email,
            hint: 'Email',
            icon: Icons.mail_outline_rounded,
            enabled: widget.enabled,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          AuthTextField(
            controller: _password,
            hint: 'Password',
            icon: Icons.lock_outline_rounded,
            enabled: widget.enabled,
            obscureText: true,
            textInputAction: widget.isSignUp
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: widget.isSignUp ? null : (_) => _submit(),
          ),
          _Slot(
            visible: widget.isSignUp,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: PasswordChecklist(password: _password.text),
            ),
          ),
          _Slot(
            visible: widget.isSignUp,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                AuthTextField(
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
                  child: PasswordMatchHint(
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
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            background: TrainColors.ember,
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
