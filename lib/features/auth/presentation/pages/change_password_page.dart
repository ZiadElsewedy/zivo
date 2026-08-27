import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/back_chip.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/auth_result.dart';
import '../../domain/password_policy.dart';
import '../widgets/auth_action_button.dart';
import '../widgets/auth_backdrop.dart';
import '../widgets/auth_footer_bar.dart';
import '../widgets/auth_header.dart';
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
        HapticFeedback.lightImpact();
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
        HapticFeedback.mediumImpact();
        setState(() => _error = failure.message);
      case AuthCancelled():
        break; // not applicable here
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: AuthBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 6, 22, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  // BackChip centres itself inside whatever box it's given
                  // (it's built for an AppBar leading slot), so it needs a
                  // chip-sized one to sit on the content's left margin.
                  child: SizedBox(width: 38, height: 38, child: BackChip()),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const RiseIn(
                        child: AuthHeader(
                          title: 'Change password',
                          aside: 'Confirm it’s you, then choose a new one.',
                        ),
                      ),
                      const SizedBox(height: 34),
                      // Two named groups, not three identical lock rows: the
                      // reauthentication and the new credential are different
                      // jobs, and the form should say so before you read a
                      // single placeholder.
                      RiseIn(
                        delay: const Duration(milliseconds: 70),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AuthSectionLabel('Confirm it’s you'),
                            AuthTextField(
                              controller: _current,
                              hint: 'Current password',
                              icon: Icons.lock_outline_rounded,
                              enabled: !_saving,
                              obscureText: true,
                              autofocus: true,
                              textInputAction: TextInputAction.next,
                              hasError: _error != null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      RiseIn(
                        delay: const Duration(milliseconds: 110),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const AuthSectionLabel('New password'),
                            AuthTextField(
                              controller: _password,
                              hint: 'New password',
                              icon: Icons.lock_outline_rounded,
                              enabled: !_saving,
                              obscureText: true,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 10),
                            // Inside the group it describes — the requirement
                            // panel is this field's feedback, not page content.
                            PasswordChecklist(password: _password.text),
                            const SizedBox(height: 10),
                            AuthTextField(
                              controller: _confirm,
                              hint: 'Confirm new password',
                              icon: Icons.lock_outline_rounded,
                              enabled: !_saving,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: _confirm.text.isEmpty ? 8 : 28,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: PasswordMatchHint(
                            matches: _confirm.text == _password.text,
                            visible: _confirm.text.isNotEmpty,
                          ),
                        ),
                      ),
                      _errorLine(),
                    ],
                  ),
                ),
              ),
              RiseIn(
                delay: const Duration(milliseconds: 150),
                child: AuthFooterBar(
                  child: AuthActionButton(
                    label: 'Update password',
                    background: AppColors.ember,
                    loading: _saving,
                    enabled: !_saving && _canSubmit,
                    onTap: _submit,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A line reserved for the failure message, so one arriving never shifts the
  /// form under the user's finger.
  Widget _errorLine() {
    return SizedBox(
      height: 30,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _error == null ? 0 : 1,
        child: Padding(
          padding: const EdgeInsets.only(top: 10, left: 4),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 15, color: AppColors.flareText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error ?? '',
                  style: AppText.meta.copyWith(color: AppColors.flareText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
