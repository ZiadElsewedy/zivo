import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/google_g_mark.dart';
import 'auth_action_button.dart';

/// Which auth action, if any, is currently in flight — so the busy button shows
/// a spinner and the others disable.
enum AuthAction { none, apple, google, email }

/// The Apple + Google buttons. Apple is presented per its guidelines' white
/// style: a solid white button with the black Apple mark and the "Sign in
/// with Apple" wording — matching the Google card's light-on-dark treatment
/// so the two sit as one visual family.
class SocialAuthButtons extends StatelessWidget {
  const SocialAuthButtons({
    required this.inFlight,
    required this.onApple,
    required this.onGoogle,
    this.showApple = true,
    super.key,
  });

  final AuthAction inFlight;
  final VoidCallback onApple;
  final VoidCallback onGoogle;
  final bool showApple;

  @override
  Widget build(BuildContext context) {
    final busy = inFlight != AuthAction.none;
    return Column(
      children: [
        if (showApple) ...[
          AuthActionButton(
            label: 'Sign in with Apple',
            icon: const Icon(Icons.apple, size: 22, color: Colors.black),
            background: Colors.white,
            foreground: Colors.black,
            loading: inFlight == AuthAction.apple,
            enabled: !busy || inFlight == AuthAction.apple,
            onTap: onApple,
          ),
          const SizedBox(height: 12),
        ],
        AuthActionButton(
          label: 'Continue with Google',
          icon: const GoogleGMark(size: 20),
          background: AppColors.card,
          foreground: AppColors.ink,
          border: AppColors.hairline2,
          loading: inFlight == AuthAction.google,
          enabled: !busy || inFlight == AuthAction.google,
          onTap: onGoogle,
        ),
      ],
    );
  }
}
