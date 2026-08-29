import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/back_chip.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/otp_result.dart';
import '../../domain/password_policy.dart';
import '../widgets/auth_action_button.dart';
import '../widgets/auth_backdrop.dart';
import '../widgets/auth_footer_bar.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/otp_code_input.dart';
import '../widgets/password_checklist.dart';
import '../../../../core/theme/train_tokens.dart';

/// The signed-out "forgot password" surface, reached from [AuthPage].
///
/// Two steps in one page: (1) enter your email and we send a 6-digit reset
/// code, (2) enter the code and a new password. All verification and the
/// password set happen server-side ([AuthRepository.sendPasswordResetOtp] /
/// [AuthRepository.resetPasswordWithOtp]).
///
/// A successful reset leaves the user **signed out** and pops with the address
/// they reset, so [AuthPage] can pre-fill it and they sign in with the password
/// they just chose. Receiving a code proves you own the mailbox; it is not the
/// same claim as knowing the password, so the new credential earns its first
/// session the normal way.
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _codeFocus.requestFocus(),
    );
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
        // The reset does NOT sign the user in — it sets the credential and
        // hands them back to sign-in to use it. Return the address so the
        // sign-in form can pre-fill it and the only thing left to type is the
        // password they just chose.
        HapticFeedback.lightImpact();
        Navigator.of(context).pop(_email.text.trim());
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
          content: Text(
            message,
            style: AppText.meta.copyWith(color: TrainColors.ink),
          ),
          backgroundColor: TrainColors.raisedStrong,
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
    final busy = _sending || _verifying;
    return Scaffold(
      backgroundColor: TrainColors.base,
      body: AuthBackdrop(
        child: SafeArea(
          child: AutofillGroup(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    // From the code step, back means back one *step*, not off
                    // the page — so the flow is escapable without losing the
                    // code you already asked for.
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: BackChip(enabled: !busy, onTap: _back),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
                    child: _step == _Step.email ? _emailStep() : _codeStep(),
                  ),
                ),
                _step == _Step.email ? _emailFooter() : _codeFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RiseIn(
          child: AuthHeader(
            title: 'Reset your password',
            aside:
                'Enter your account email and we’ll send you a 6-digit code.',
          ),
        ),
        const SizedBox(height: 34),
        RiseIn(
          delay: const Duration(milliseconds: 70),
          child: AuthTextField(
            controller: _email,
            hint: 'Email',
            icon: Icons.mail_outline_rounded,
            enabled: !_sending,
            // Raise the keyboard on arrival: there is exactly one thing to do
            // on this step, so making the user tap the field first is a step
            // that buys nothing.
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendCode(),
          ),
        ),
        _errorLine(),
      ],
    );
  }

  Widget _emailFooter() {
    return RiseIn(
      delay: const Duration(milliseconds: 120),
      child: AuthFooterBar(
        child: AuthActionButton(
          label: 'Send code',
          background: TrainColors.ember,
          loading: _sending,
          enabled: !_sending && _validEmail,
          onTap: _sendCode,
        ),
      ),
    );
  }

  Widget _codeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiseIn(
          child: AuthHeader(
            title: 'Enter the code',
            asideSpan: TextSpan(
              children: [
                const TextSpan(text: 'Enter the 6-digit code we sent to\n'),
                TextSpan(
                  text: _email.text.trim(),
                  style: AuthHeader.asideStyle.copyWith(
                    color: TrainColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const TextSpan(text: ', then choose a new password.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 30),
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
        const SizedBox(height: 26),
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
                enabled: !_verifying,
                obscureText: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              PasswordChecklist(password: _password.text),
              const SizedBox(height: 10),
              AuthTextField(
                controller: _confirm,
                hint: 'Confirm password',
                icon: Icons.lock_outline_rounded,
                enabled: !_verifying,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitReset(),
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
    );
  }

  Widget _codeFooter() {
    return RiseIn(
      delay: const Duration(milliseconds: 150),
      child: AuthFooterBar(
        secondary: Center(child: _resendLine()),
        child: AuthActionButton(
          label: 'Reset password',
          background: TrainColors.ember,
          loading: _verifying,
          enabled: !_verifying && _canReset,
          onTap: _submitReset,
        ),
      ),
    );
  }

  /// The resend affordance in its three states, each on the same line so the
  /// footer never resizes as the cooldown runs out.
  Widget _resendLine() {
    if (_sending) {
      return Text(
        'Sending…',
        style: AppText.meta.copyWith(color: TrainColors.ink3),
      );
    }
    if (_cooldown > 0) {
      return Text(
        'Resend code in ${_cooldown}s',
        style: AppText.meta.copyWith(color: TrainColors.ink3),
      );
    }
    return TextButton(
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
                color: TrainColors.ember,
              ),
            ),
          ],
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
        opacity: _errorText == null ? 0 : 1,
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
                  _errorText ?? '',
                  style: AppText.meta.copyWith(color: TrainColors.ember),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
