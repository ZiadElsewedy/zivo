import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/auth_result.dart';
import '../../domain/password_policy.dart';
import '../widgets/auth_action_button.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/password_checklist.dart';

/// Change-password surface for a signed-in password account, pushed from
/// [SettingsPage]. Collects the current password (Firebase requires a recent
/// login) and a new one, enforcing the same [PasswordPolicy] as sign-up. On
/// success it pops back to Settings with a confirmation; the account's
/// bookkeeping records the change server-adjacent.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _current.addListener(_onChanged);
    _password.addListener(_onChanged);
    _confirm.addListener(_onChanged);
  }

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_error != null) {
      setState(() => _error = null);
    } else {
      setState(() {});
    }
  }

  bool get _canSubmit =>
      _current.text.isNotEmpty &&
      PasswordPolicy.isSatisfiedBy(_password.text) &&
      _confirm.text == _password.text &&
      _password.text != _current.text;

  Future<void> _submit() async {
    if (_saving || !_canSubmit) return;
    final auth = AppScope.of(context).auth;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await auth.changePassword(
      currentPassword: _current.text,
      newPassword: _password.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case AuthSuccess():
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Password updated.',
                  style: AppText.meta.copyWith(color: AppColors.ink)),
              backgroundColor: AppColors.surfaceRaised,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        navigator.pop();
      case AuthFailed(:final failure):
        setState(() => _error = failure.message);
      case AuthCancelled():
        break; // not applicable here
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
          tooltip: 'Back',
          onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              RiseIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Change password',
                        style: AppText.greeting.copyWith(fontSize: 28)),
                    const SizedBox(height: 10),
                    Text(
                      'Enter your current password, then choose a new one.',
                      style: AppText.aside,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              RiseIn(
                delay: const Duration(milliseconds: 70),
                child: AuthTextField(
                  controller: _current,
                  hint: 'Current password',
                  icon: Icons.lock_outline_rounded,
                  enabled: !_saving,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(height: 10),
              RiseIn(
                delay: const Duration(milliseconds: 100),
                child: AuthTextField(
                  controller: _password,
                  hint: 'New password',
                  icon: Icons.lock_outline_rounded,
                  enabled: !_saving,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: PasswordChecklist(password: _password.text),
              ),
              const SizedBox(height: 10),
              RiseIn(
                delay: const Duration(milliseconds: 130),
                child: AuthTextField(
                  controller: _confirm,
                  hint: 'Confirm new password',
                  icon: Icons.lock_outline_rounded,
                  enabled: !_saving,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              SizedBox(
                height: _confirm.text.isEmpty ? 0 : 24,
                child: PasswordMatchHint(
                  matches: _confirm.text == _password.text,
                  visible: _confirm.text.isNotEmpty,
                ),
              ),
              SizedBox(
                height: 28,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _error == null ? 0 : 1,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error ?? '',
                      style: AppText.meta.copyWith(color: AppColors.flareText),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              RiseIn(
                delay: const Duration(milliseconds: 160),
                child: AuthActionButton(
                  label: 'Update password',
                  icon: const SizedBox.shrink(),
                  background: AppColors.ember,
                  loading: _saving,
                  enabled: !_saving && _canSubmit,
                  onTap: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
