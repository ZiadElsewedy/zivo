import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'auth_action_button.dart';

/// Which auth action, if any, is currently in flight — so the busy button shows
/// a spinner and the others disable.
enum AuthAction { none, apple, google, email }

/// The Apple + Google buttons. Apple is presented per its guidelines: a solid
/// dark button with the Apple mark and the "Sign in with Apple" wording.
class SocialAuthButtons extends StatelessWidget {
  const SocialAuthButtons({
    required this.inFlight,
    required this.onApple,
    required this.onGoogle,
    super.key,
  });

  final AuthAction inFlight;
  final VoidCallback onApple;
  final VoidCallback onGoogle;

  @override
  Widget build(BuildContext context) {
    final busy = inFlight != AuthAction.none;
    return Column(
      children: [
        AuthActionButton(
          label: 'Sign in with Apple',
          icon: const Icon(Icons.apple, size: 22, color: Colors.white),
          background: Colors.black,
          loading: inFlight == AuthAction.apple,
          enabled: !busy || inFlight == AuthAction.apple,
          onTap: onApple,
        ),
        const SizedBox(height: 12),
        AuthActionButton(
          label: 'Continue with Google',
          icon: const _GoogleMark(),
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

/// A simple, recognisable Google "G" badge (avoids bundling an image asset).
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF4285F4), // Google blue
          height: 1.1,
        ),
      ),
    );
  }
}
