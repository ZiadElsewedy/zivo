import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../domain/auth_result.dart';
import 'auth_text_field.dart';

/// The account-deletion confirmation sheet, opened from [SettingsPage].
///
/// Deletion is irreversible, so this is a deliberate, reauthenticated step:
/// password accounts type their password here; social accounts reauthenticate
/// by re-running their provider on confirm (handled inside
/// [AuthRepository.deleteAccount]). On success the account and all its data are
/// erased server-side, the session ends, and the app returns to sign-in.
class DeleteAccountSheet extends StatefulWidget {
  const DeleteAccountSheet({required this.isPasswordAccount, super.key});

  /// Whether the signed-in account has a `password` provider (so it needs an
  /// inline password to reauthenticate). Social accounts reauthenticate via
  /// their provider flow instead.
  final bool isPasswordAccount;

  /// Opens the sheet. Returns nothing — on success the whole navigation stack
  /// is popped to the auth gate.
  static Future<void> show(BuildContext context) {
    final user = AppScope.of(context).auth.currentUser;
    final isPassword = user?.providerIds.contains('password') ?? false;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DeleteAccountSheet(isPasswordAccount: isPassword),
    );
  }

  @override
  State<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<DeleteAccountSheet> {
  final TextEditingController _password = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Keep the confirm button's enabled state in sync as the password is typed.
    if (widget.isPasswordAccount) _password.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (_error != null) {
      setState(() => _error = null);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _canConfirm =>
      !widget.isPasswordAccount || _password.text.isNotEmpty;

  Future<void> _confirm() async {
    if (_deleting || !_canConfirm) return;
    final auth = AppScope.of(context).auth;
    final navigator = Navigator.of(context);
    FocusScope.of(context).unfocus();
    setState(() {
      _deleting = true;
      _error = null;
    });
    final result = await auth.deleteAccount(
      password: widget.isPasswordAccount ? _password.text : null,
    );
    if (!mounted) return;

    switch (result) {
      case AuthSuccess():
        // Session ended + data erased; drop the sheet and Settings so the gate
        // (now signed out) shows the sign-in screen.
        navigator.popUntil((route) => route.isFirst);
      case AuthCancelled():
        setState(() => _deleting = false); // backed out of provider reauth
      case AuthFailed(:final failure):
        setState(() {
          _deleting = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: AppColors.hairline2),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.flare.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(AppIcons.trash,
                      size: 18, color: AppColors.flareText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Delete account',
                      style: AppText.cardTitle.copyWith(fontSize: 19)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'This permanently deletes your account and everything in it — '
              'workouts, diet, moments, expenses, and profile. This cannot be '
              'undone.',
              style: AppText.body.copyWith(color: AppColors.ink2, height: 1.4),
            ),
            if (widget.isPasswordAccount) ...[
              const SizedBox(height: 18),
              AuthTextField(
                controller: _password,
                hint: 'Enter your password to confirm',
                icon: Icons.lock_outline_rounded,
                enabled: !_deleting,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _confirm(),
              ),
            ],
            SizedBox(
              height: 26,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _error == null ? 0 : 1,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error ?? '',
                    style: AppText.meta.copyWith(color: AppColors.flareText),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _DeleteButton(loading: _deleting, enabled: _canConfirm, onTap: _confirm),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed:
                    _deleting ? null : () => Navigator.of(context).maybePop(),
                child: Text('Cancel',
                    style: AppText.button
                        .copyWith(fontSize: 15, color: AppColors.ink2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The destructive confirm action — the same tinted-glass flare treatment as
/// Settings' sign-out button, so the two destructive moments read alike.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: PressableScale(
        enabled: active,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.flare.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.flare.withValues(alpha: 0.35)),
            ),
            child: InkWell(
              onTap: active ? onTap : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                alignment: Alignment.center,
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.flareText,
                        ),
                      )
                    : Text(
                        'Delete my account',
                        style: AppText.button.copyWith(
                          fontSize: 15,
                          color: AppColors.flareText,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
