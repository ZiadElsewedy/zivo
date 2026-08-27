import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/otp_result.dart';
import '../../domain/password_policy.dart';
import '../widgets/auth_action_button.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/otp_code_input.dart';
import '../widgets/password_checklist.dart';

/// The signed-out "forgot password" surface, reached from [AuthPage].
///
/// Two steps in one page: (1) enter your email and we send a 6-digit reset
/// code, (2) enter the code and a new password. All verification and the
/// password set happen server-side ([AuthRepository.sendPasswordResetOtp] /
/// [AuthRepository.resetPasswordWithOtp]); a successful reset signs the user in
/// and the auth gate swaps this page for the app shell — so on success this
/// page just pops itself so the shell shows through.
///
/// Styling deliberately matches `verify_email_page.dart` (the OTP surface) and
/// the sign-in form so the reset flow feels like the same product.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

enum _Step { email, code }

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  static const int _codeLength = 6;

  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final FocusNode _codeFocus = FocusNode();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  _Step _step = _Step.email;
  bool _sending = false;
  bool _verifying = false;
  String? _errorText;
  bool _cellError = false;

  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _email.addListener(_onFieldChanged);
    _password.addListener(_onFieldChanged);
    _confirm.addListener(_onFieldChanged);
    // The code field is driven by OtpCodeInput.onChanged (user input only), not
    // a controller listener — so programmatically clearing it in [_failCode]
    // can't wipe the error we just set.
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _email.dispose();
    _code.dispose();
    _codeFocus.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (_cellError || _errorText != null) {
      setState(() {
        _cellError = false;
        _errorText = null;
      });
    } else {
      setState(() {}); // keep submit-button enabled state in sync
    }
  }

  /// Fired by [OtpCodeInput] on user input only (never on a programmatic
  /// clear): rebuilds so the button's enabled state tracks the code length,
  /// and clears a stale error as the user starts retyping.
  void _onCodeChanged(String _) => _onFieldChanged();

  bool get _validEmail {
    final email = _email.text.trim();
    return email.contains('@') && email.contains('.');
  }

  bool get _canReset =>
      _code.text.length == _codeLength &&
      PasswordPolicy.isSatisfiedBy(_password.text) &&
      _confirm.text == _password.text;

  // --- actions ---------------------------------------------------------------

  Future<void> _sendCode({bool resend = false}) async {
    if (_sending || (resend && _cooldown > 0)) return;
    if (!_validEmail) {
      setState(() => _errorText = "That email address doesn't look right.");
      return;
    }
    final auth = AppScope.of(context).auth;
    setState(() {
      _sending = true;
      _errorText = null;
      _cellError = false;
    });
    final result = await auth.sendPasswordResetOtp(email: _email.text.trim());
    if (!mounted) return;
    setState(() => _sending = false);

    switch (result) {
      case OtpSendSuccess(:final cooldownSeconds):
        _goToCodeStep();
        _startCooldown(cooldownSeconds);
        if (resend) _toast('A new code is on its way.');
      case OtpSendCooldown(:final retryAfterSeconds):
        _goToCodeStep();
        _startCooldown(retryAfterSeconds);
      case OtpSendAlreadyVerified():
        // Not expected for a reset; treat as "code step" defensively.
        _goToCodeStep();
      case OtpSendFailed(:final failure, :final retryAfterSeconds):
        if (retryAfterSeconds != null) _startCooldown(retryAfterSeconds);
        setState(() => _errorText = failure.message);
    }
  }

  void _goToCodeStep() {
    if (_step == _Step.code) return;
    setState(() => _step = _Step.code);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _codeFocus.requestFocus());
  }

  Future<void> _submitReset() async {
    if (_verifying || !_canReset) return;
    final auth = AppScope.of(context).auth;
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _errorText = null;
      _cellError = false;
    });
    final result = await auth.resetPasswordWithOtp(
      email: _email.text.trim(),
      code: _code.text,
      newPassword: _password.text,
    );
    if (!mounted) return;
    setState(() => _verifying = false);

    switch (result) {
      case OtpVerifySuccess():
        // The repo signed the user in; the gate now shows the shell beneath
        // this pushed route. Pop back so it's visible, and confirm.
        _toast('Password updated.');
        Navigator.of(context).popUntil((route) => route.isFirst);
      case OtpVerifyInvalid(:final attemptsRemaining):
        _failCode(
          attemptsRemaining != null && attemptsRemaining > 0
              ? 'That code isn’t right. $attemptsRemaining ${attemptsRemaining == 1 ? 'try' : 'tries'} left.'
              : 'That code isn’t right.',
        );
      case OtpVerifyExpired():
        _failCode('That code has expired. Send a new one.');
      case OtpVerifyTooManyAttempts(:final retryAfterSeconds):
        if (retryAfterSeconds != null) _startCooldown(retryAfterSeconds);
        _failCode('Too many attempts. Send a new code.');
      case OtpVerifyFailed(:final failure):
        setState(() => _errorText = failure.message);
    }
  }

  void _failCode(String message) {
    setState(() {
      _errorText = message;
      _cellError = true;
      _code.clear();
    });
    _codeFocus.requestFocus();
  }

  // --- helpers ---------------------------------------------------------------

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _cooldown -= 1;
        if (_cooldown <= 0) t.cancel();
      });
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message,
              style: AppText.meta.copyWith(color: AppColors.ink)),
          backgroundColor: AppColors.surfaceRaised,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _back() {
    if (_step == _Step.code) {
      setState(() {
        _step = _Step.email;
        _errorText = null;
        _cellError = false;
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  // --- build -----------------------------------------------------------------

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
          onPressed: (_sending || _verifying) ? null : _back,
        ),
      ),
      body: SafeArea(
        child: AutofillGroup(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
            child: _step == _Step.email ? _emailStep() : _codeStep(),
          ),
        ),
      ),
    );
  }

  Widget _emailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        RiseIn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reset your password',
                  style: AppText.greeting.copyWith(fontSize: 28)),
              const SizedBox(height: 10),
              Text(
                'Enter your account email and we’ll send you a 6-digit code.',
                style: AppText.aside,
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        RiseIn(
          delay: const Duration(milliseconds: 70),
          child: AuthTextField(
            controller: _email,
            hint: 'Email',
            icon: Icons.mail_outline_rounded,
            enabled: !_sending,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendCode(),
          ),
        ),
        _errorLine(),
        const SizedBox(height: 8),
        RiseIn(
          delay: const Duration(milliseconds: 120),
          child: AuthActionButton(
            label: 'Send code',
            icon: const SizedBox.shrink(),
            background: AppColors.ember,
            loading: _sending,
            enabled: !_sending && _validEmail,
            onTap: _sendCode,
          ),
        ),
      ],
    );
  }

  Widget _codeStep() {
    final canResend = _cooldown == 0 && !_sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        RiseIn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter the code',
                  style: AppText.greeting.copyWith(fontSize: 28)),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  style: AppText.aside,
                  children: [
                    const TextSpan(text: 'Enter the 6-digit code we sent to\n'),
                    TextSpan(
                      text: _email.text.trim(),
                      style: AppText.aside.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(text: ', then choose a new password.'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        RiseIn(
          delay: const Duration(milliseconds: 70),
          child: OtpCodeInput(
            controller: _code,
            focusNode: _codeFocus,
            length: _codeLength,
            enabled: !_verifying,
            hasError: _cellError,
            autofocus: false,
            onChanged: _onCodeChanged,
            // Advancing to the password fields is intentional here rather than
            // auto-submitting, since a new password is still required.
            onCompleted: (_) {},
          ),
        ),
        const SizedBox(height: 18),
        RiseIn(
          delay: const Duration(milliseconds: 100),
          child: AuthTextField(
            controller: _password,
            hint: 'New password',
            icon: Icons.lock_outline_rounded,
            enabled: !_verifying,
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
            hint: 'Confirm password',
            icon: Icons.lock_outline_rounded,
            enabled: !_verifying,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitReset(),
          ),
        ),
        SizedBox(
          height: _confirm.text.isEmpty ? 0 : 24,
          child: PasswordMatchHint(
            matches: _confirm.text == _password.text,
            visible: _confirm.text.isNotEmpty,
          ),
        ),
        _errorLine(),
        const SizedBox(height: 8),
        RiseIn(
          delay: const Duration(milliseconds: 160),
          child: AuthActionButton(
            label: 'Reset password',
            icon: const SizedBox.shrink(),
            background: AppColors.ember,
            loading: _verifying,
            enabled: !_verifying && _canReset,
            onTap: _submitReset,
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: _sending
              ? Text('Sending…',
                  style: AppText.meta.copyWith(color: AppColors.ink3))
              : canResend
                  ? TextButton(
                      onPressed: () => _sendCode(resend: true),
                      child: Text.rich(
                        TextSpan(
                          style: AppText.body,
                          children: [
                            const TextSpan(text: 'Didn’t get it?  '),
                            TextSpan(
                              text: 'Resend code',
                              style: AppText.button.copyWith(
                                fontSize: 14.5,
                                color: AppColors.emberText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Text(
                      'Resend code in ${_cooldown}s',
                      style: AppText.meta.copyWith(color: AppColors.ink3),
                    ),
        ),
      ],
    );
  }

  Widget _errorLine() {
    return SizedBox(
      height: 28,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _errorText == null ? 0 : 1,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _errorText ?? '',
            style: AppText.meta.copyWith(color: AppColors.flareText),
          ),
        ),
      ),
    );
  }
}
