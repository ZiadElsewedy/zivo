import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/auth_repository.dart';
import '../../domain/auth_result.dart';
import '../widgets/auth_backdrop.dart';
import '../widgets/email_auth_form.dart';
import '../widgets/social_auth_buttons.dart';
import 'forgot_password_page.dart';
import '../../../../core/theme/train_tokens.dart';

/// The signed-out surface: Sign in with Apple, Continue with Google, and an
/// email/password form that toggles between sign-in and account creation.
///
/// Success is handled by [AuthGate]: a successful call flips the auth stream to
/// `Authenticated`, which swaps this page out for the app shell — so this page
/// only owns loading and error presentation. Cancellations (Apple/Google) show
/// nothing.
///
/// Motion: the brand block, social buttons, form, and mode toggle rise in
/// staggered ([RiseIn]); the tagline cross-fades when modes flip; errors slide
/// into a reserved line so nothing else jumps.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isSignUp = false;
  AuthAction _inFlight = AuthAction.none;
  String? _error;

  /// An address handed back by the reset flow, to seed the email field.
  String? _prefillEmail;

  Future<void> _run(
    AuthAction action,
    Future<AuthResult> Function(AuthRepository auth) op,
  ) async {
    if (_inFlight != AuthAction.none) return;
    final auth = AppScope.of(context).auth; // read before await
    setState(() {
      _inFlight = action;
      _error = null;
    });
    final result = await op(auth);
    if (!mounted) return;
    setState(() {
      _inFlight = AuthAction.none;
      // AuthSuccess → the gate swaps us out; AuthCancelled → stay silent.
      if (result is AuthFailed) _error = result.failure.message;
    });
  }

  void _toggleMode() {
    if (_inFlight != AuthAction.none) return;
    setState(() {
      _isSignUp = !_isSignUp;
      _error = null;
    });
  }

  /// Opens the reset flow and handles its return. A successful reset pops with
  /// the address it was performed on and leaves the session signed out, so the
  /// user lands back here with the email already filled and the password they
  /// just chose as the only thing left to type.
  Future<void> _openForgotPassword() async {
    final resetEmail = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
    );
    if (!mounted || resetEmail == null) return;
    setState(() {
      _isSignUp = false;
      _error = null;
      _prefillEmail = resetEmail;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Password updated. Sign in with your new password.',
            style: AppText.meta.copyWith(color: TrainColors.ink),
          ),
          backgroundColor: TrainColors.raisedStrong,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TrainColors.base,
      body: AuthBackdrop(
        // The bloom sits behind the wordmark, so the mark reads as the
        // thing lighting the screen rather than a logo dropped on black.
        alignment: const Alignment(-0.5, -0.78),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.vertical -
                    40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  RiseIn(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset(
                          'assets/transparent/zivo-mark-paper-256.png',
                          width: 44,
                          height: 44,
                        ),
                        const SizedBox(height: 18),
                        // The wordmark is set wider than the display face's own
                        // tracking — at this size it reads as a mark, not a
                        // heading, which is the one place positive tracking on
                        // large type earns its keep.
                        Text(
                          'ZIVO',
                          style: AppText.greeting.copyWith(
                            fontSize: 36,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Cross-fade between the two taglines as modes flip —
                        // the copy change reads instead of snapping.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.35),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Text(
                            key: ValueKey(_isSignUp),
                            _isSignUp
                                ? 'Make your space.'
                                : 'Your whole day, in one place.',
                            style: AppText.aside,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  RiseIn(
                    delay: const Duration(milliseconds: 60),
                    child: SocialAuthButtons(
                      inFlight: _inFlight,
                      onApple: () =>
                          _run(AuthAction.apple, (a) => a.signInWithApple()),
                      onGoogle: () =>
                          _run(AuthAction.google, (a) => a.signInWithGoogle()),
                      showApple:
                          !kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.iOS,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _OrDivider(),
                  const SizedBox(height: 22),
                  RiseIn(
                    delay: const Duration(milliseconds: 120),
                    child: EmailAuthForm(
                      isSignUp: _isSignUp,
                      prefillEmail: _prefillEmail,
                      submitting: _inFlight == AuthAction.email,
                      enabled:
                          _inFlight == AuthAction.none ||
                          _inFlight == AuthAction.email,
                      onSubmit: ({required email, required password, name}) {
                        _run(
                          AuthAction.email,
                          (a) => _isSignUp
                              ? a.signUpWithEmail(
                                  email: email,
                                  password: password,
                                  displayName: name,
                                )
                              : a.signInWithEmail(
                                  email: email,
                                  password: password,
                                ),
                        );
                      },
                    ),
                  ),
                  // Password recovery — sign-in only (sign-up has no password to
                  // recover yet). Kept quiet so it doesn't compete with the CTA.
                  if (!_isSignUp)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _inFlight == AuthAction.none
                              ? _openForgotPassword
                              : null,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Forgot password?',
                            style: AppText.meta.copyWith(
                              color: TrainColors.ink2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Reserved line so an arriving error never shifts layout.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: _error == null ? 0 : 1,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        offset: _error == null
                            ? const Offset(0, -0.4)
                            : Offset.zero,
                        child: _error == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: _ErrorBanner(message: _error!),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: _inFlight == AuthAction.none
                          ? _toggleMode
                          : null,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: Text.rich(
                          key: ValueKey(_isSignUp),
                          TextSpan(
                            style: AppText.body,
                            children: [
                              TextSpan(
                                text: _isSignUp
                                    ? 'Already have an account?  '
                                    : 'New to ZIVO?  ',
                              ),
                              TextSpan(
                                text: _isSignUp ? 'Sign in' : 'Create account',
                                style: AppText.button.copyWith(
                                  fontSize: 14.5,
                                  color: TrainColors.ember,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: TrainColors.hairline, thickness: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or',
            style: AppText.sectionLabel.copyWith(fontSize: 10.5),
          ),
        ),
        const Expanded(
          child: Divider(color: TrainColors.hairline, thickness: 1),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0x14FF3D6E), // flare wash
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x33FF3D6E), width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: TrainColors.ember,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppText.meta.copyWith(color: TrainColors.ember),
            ),
          ),
        ],
      ),
    );
  }
}
