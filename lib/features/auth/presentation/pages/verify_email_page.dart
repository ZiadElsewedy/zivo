import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/auth_repository.dart';
import '../../domain/otp_result.dart';
import '../widgets/auth_action_button.dart';
import '../widgets/auth_backdrop.dart';
import '../widgets/auth_footer_bar.dart';
import '../widgets/auth_header.dart';
import '../widgets/otp_code_input.dart';
import '../../../../core/theme/train_tokens.dart';

/// The email-OTP verification surface, shown by [AuthGate] for the
/// [AwaitingEmailVerification] state.
///
/// Owns only presentation + timers; all verification is decided server-side via
/// [AuthRepository.sendEmailOtp] / [AuthRepository.verifyEmailOtp]. On success
/// the repository refreshes the session and the gate swaps this page for the
/// app shell — so this page never navigates itself there.
class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({required this.email, super.key});

  /// The address the code is sent to (shown masked).
  final String email;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  static const int _codeLength = 6;

  final TextEditingController _code = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _verifying = false;
  bool _sending = false;
  String? _errorText; // shown under the field for invalid/expired/etc.
  bool _cellError = false; // paints the cells red + shakes

  int _cooldown = 0; // seconds until resend is allowed again
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Ask the backend to send the first code as soon as the screen opens. It's
    // idempotent: if a valid code was just sent, we get a cooldown instead.
    WidgetsBinding.instance.addPostFrameCallback((_) => _send(initial: true));
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  // --- actions ---------------------------------------------------------------

  Future<void> _send({bool initial = false}) async {
    if (_sending || (_cooldown > 0 && !initial)) return;
    final auth = AppScope.of(context).auth;
    setState(() {
      _sending = true;
      if (!initial) {
        _errorText = null;
        _cellError = false;
      }
    });
    final result = await auth.sendEmailOtp();
    if (!mounted) return;
    setState(() => _sending = false);

    switch (result) {
      case OtpSendSuccess(:final cooldownSeconds):
        _startCooldown(cooldownSeconds);
        if (!initial) _toast('A new code is on its way.');
      case OtpSendCooldown(:final retryAfterSeconds):
        _startCooldown(retryAfterSeconds);
      case OtpSendAlreadyVerified():
        // The address is already verified (flipped elsewhere). The repository
        // refreshed the session, so the gate advances on its own — nothing to
        // do here but stop showing "Sending…".
        break;
      case OtpSendFailed(:final failure, :final retryAfterSeconds):
        if (retryAfterSeconds != null) _startCooldown(retryAfterSeconds);
        setState(() => _errorText = failure.message);
    }
  }

  Future<void> _verify(String code) async {
    if (_verifying) return;
    final auth = AppScope.of(context).auth;
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _errorText = null;
      _cellError = false;
    });
    final result = await auth.verifyEmailOtp(code);
    if (!mounted) return;
    setState(() => _verifying = false);

    switch (result) {
      case OtpVerifySuccess():
        // The gate advances on the refreshed session; nothing to do here.
        break;
      case OtpVerifyInvalid(:final attemptsRemaining):
        _fail(
          attemptsRemaining != null && attemptsRemaining > 0
              ? 'That code isn’t right. $attemptsRemaining ${attemptsRemaining == 1 ? 'try' : 'tries'} left.'
              : 'That code isn’t right.',
        );
      case OtpVerifyExpired():
        _fail('That code has expired. Send a new one.');
      case OtpVerifyTooManyAttempts(:final retryAfterSeconds):
        if (retryAfterSeconds != null) _startCooldown(retryAfterSeconds);
        _fail('Too many attempts. Send a new code.');
      case OtpVerifyFailed(:final failure):
        _fail(failure.message);
    }
  }

  void _fail(String message) {
    setState(() {
      _errorText = message;
      _cellError = true;
      _code.clear();
    });
    _focus.requestFocus();
  }

  void _onCodeChanged(String value) {
    // Clear a stale error the moment the user starts correcting the code, and
    // rebuild so the Verify button's enabled state tracks the code length.
    setState(() {
      if (_cellError || _errorText != null) {
        _cellError = false;
        _errorText = null;
      }
    });
  }

  Future<void> _useAnotherAccount() async {
    await AppScope.of(context).auth.signOut();
    // The gate returns to the auth screen on Unauthenticated.
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

  String get _maskedEmail {
    final at = widget.email.indexOf('@');
    if (at <= 0) return widget.email;
    final name = widget.email.substring(0, at);
    final domain = widget.email.substring(at);
    if (name.length <= 2) return '${name[0]}•$domain';
    final visible = name.substring(0, 2);
    return '$visible${'•' * (name.length - 2).clamp(1, 6)}$domain';
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final canResend = _cooldown == 0 && !_sending;
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
                    // Not the house BackChip: leaving here isn't "back", it
                    // abandons a half-created session, so the affordance says
                    // what it actually does.
                    child: _UseAnotherAccountChip(
                      enabled: !_verifying,
                      onTap: _useAnotherAccount,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RiseIn(
                          child: AuthHeader(
                            title: 'Verify your email',
                            asideSpan: TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Enter the 6-digit code we sent to\n',
                                ),
                                TextSpan(
                                  text: _maskedEmail,
                                  style: AuthHeader.asideStyle.copyWith(
                                    color: TrainColors.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                        RiseIn(
                          delay: const Duration(milliseconds: 70),
                          child: OtpCodeInput(
                            controller: _code,
                            focusNode: _focus,
                            length: _codeLength,
                            enabled: !_verifying,
                            hasError: _cellError,
                            onChanged: _onCodeChanged,
                            onCompleted: _verify,
                          ),
                        ),
                        // Reserve a line for the error so nothing jumps.
                        SizedBox(
                          height: 34,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: _errorText == null ? 0 : 1,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    size: 15,
                                    color: TrainColors.ember,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _errorText ?? '',
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
                      ],
                    ),
                  ),
                ),
                RiseIn(
                  delay: const Duration(milliseconds: 120),
                  child: AuthFooterBar(
                    secondary: Center(child: _resendLine(canResend)),
                    child: AuthActionButton(
                      label: 'Verify',
                      loading: _verifying,
                      enabled: !_verifying && _code.text.length == _codeLength,
                      onTap: () => _verify(_code.text),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The resend affordance in its three states, each occupying the same line
  /// so the footer never resizes as the cooldown runs out.
  Widget _resendLine(bool canResend) {
    if (_sending) {
      return Text(
        'Sending…',
        style: AppText.meta.copyWith(color: TrainColors.ink3),
      );
    }
    if (!canResend) {
      return Text(
        'Resend code in ${_cooldown}s',
        style: AppText.meta.copyWith(color: TrainColors.ink3),
      );
    }
    return TextButton(
      onPressed: () => _send(),
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
}

/// The escape hatch from a half-finished sign-up: the house chip's shape, but
/// labelled for what it does — sign this session out and start over — rather
/// than borrowing a back arrow for a step you cannot go back from.
class _UseAnotherAccountChip extends StatelessWidget {
  const _UseAnotherAccountChip({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: PressableScale(
        enabled: enabled,
        child: Tooltip(
          message: 'Use another account',
          child: Material(
            color: TrainColors.raisedStrong,
            shape: const StadiumBorder(
              side: BorderSide(color: TrainColors.hairlineStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 15, 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.arrow_back_rounded,
                      size: 16,
                      color: TrainColors.ink2,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Use another account',
                      style: AppText.meta.copyWith(color: TrainColors.ink2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
