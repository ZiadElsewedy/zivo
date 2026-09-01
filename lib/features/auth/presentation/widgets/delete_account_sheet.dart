import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/auth_result.dart';
import 'auth_backdrop.dart';
import 'auth_text_field.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/zivo_sheet.dart';

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
    return showZivoSheet<void>(
      context: context,
      useSafeArea: true,
      // A modal, irreversible task: push the page behind it properly back
      // rather than leaving Settings legible right up against the sheet. The
      // dim is what makes this read as a decision instead of another row.
      barrierColor: const Color(0xB3000000),
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
    HapticFeedback.mediumImpact();
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
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    // `padding` (not `viewPadding`) is the home-indicator gap *minus* whatever
    // the keyboard already covers, so the footer clears the indicator when the
    // keyboard is down without gaining a phantom 34pt when it's up.
    final bottomSafe = media.padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: TrainColors.hairlineStrong)),
          ),
          // The sheet's own light is flare, not ember — the surface is tinted
          // by the thing it's about, so the warning is in the material before
          // it's in the copy.
          child: AuthBackdrop(
            base: TrainColors.raised,
            hue: TrainColors.ember,
            alignment: const Alignment(-0.75, -1.6),
            intensity: 0.85,
            child: Padding(
              padding: EdgeInsets.fromLTRB(22, 12, 22, 18 + bottomSafe),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: ZivoSheetHandle()),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: TrainColors.emberWash,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: TrainColors.ember.withValues(alpha: 0.28),
                          ),
                        ),
                        child: const Icon(
                          AppIcons.trash,
                          size: 19,
                          color: TrainColors.ember,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          'Delete account',
                          style: AppText.cardTitle.copyWith(fontSize: 21),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'This permanently deletes your account and everything in '
                    'it — workouts, diet, moments, expenses, and profile. This '
                    'cannot be undone.',
                    style: AppText.body.copyWith(
                      color: TrainColors.ink2,
                      height: 1.45,
                    ),
                  ),
                  if (widget.isPasswordAccount) ...[
                    const SizedBox(height: 20),
                    AuthTextField(
                      controller: _password,
                      hint: 'Enter your password to confirm',
                      icon: Icons.lock_outline_rounded,
                      enabled: !_deleting,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      hasError: _error != null,
                      onSubmitted: (_) => _confirm(),
                    ),
                  ],
                  SizedBox(
                    height: 30,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _error == null ? 0 : 1,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10, left: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 15,
                              color: TrainColors.ember,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error ?? '',
                                style: AppText.meta.copyWith(
                                  color: TrainColors.ember,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Cancel is given the same weight and shape as the delete —
                  // backing out of an irreversible action shouldn't be the
                  // harder target to hit.
                  Row(
                    children: [
                      Expanded(
                        child: _SheetButton(
                          label: 'Cancel',
                          enabled: !_deleting,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SheetButton(
                          label: 'Delete my account',
                          destructive: true,
                          loading: _deleting,
                          enabled: _canConfirm,
                          onTap: _confirm,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet's footer buttons. One shape, two weights: the destructive action
/// carries the flare wash and border (the same tinted-glass treatment as
/// Settings' sign-out, so the two destructive moments read alike), and Cancel
/// is the quiet neutral next to it.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.destructive = false,
    this.loading = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool destructive;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    final tint = destructive ? TrainColors.ember : TrainColors.ink2;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: PressableScale(
        enabled: active,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: AppMotion.ease,
          height: 52,
          decoration: BoxDecoration(
            color: destructive
                ? TrainColors.ember.withValues(alpha: 0.13)
                : TrainColors.raisedStrong,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: destructive
                  ? TrainColors.ember.withValues(alpha: 0.38)
                  : TrainColors.hairlineStrong,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: active ? onTap : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: TrainColors.ember,
                        ),
                      )
                    : Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.button.copyWith(
                          fontSize: 15,
                          color: tint,
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
