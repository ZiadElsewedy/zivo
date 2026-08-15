import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/auth_user.dart';

/// Minimal "You" surface: shows the signed-in identity and the sign-out action.
/// Deliberately small — a full Profile/Settings feature comes later; this exists
/// so authentication has a real home for sign-out without redesigning the app.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    final auth = AppScope.of(context).auth;
    setState(() => _signingOut = true);
    await auth.signOut();
    // The auth gate reacts to the stream and swaps this whole subtree out, so
    // there's nothing to navigate here; guard setState in case we're still up.
    if (mounted) setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final AuthUser? user = AppScope.of(context).auth.currentUser;
    final name = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : 'Signed in';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RiseIn(child: Text('You', style: AppText.greeting)),
            const SizedBox(height: 24),
            RiseIn(
              delay: const Duration(milliseconds: 60),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  boxShadow: AppShadows.card,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.cardTitle),
                    if (user?.email != null) ...[
                      const SizedBox(height: 6),
                      Text(user!.email!, style: AppText.body),
                    ],
                    const SizedBox(height: 18),
                    const Divider(color: AppColors.hairline, height: 1),
                    const SizedBox(height: 16),
                    Text('IDENTITY', style: AppText.sectionLabel),
                    const SizedBox(height: 8),
                    _IdRow(label: 'User ID', value: user?.uid ?? '—'),
                    if (user != null && user.providerIds.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _IdRow(
                        label: 'Sign-in',
                        value: user.providerIds.map(_providerLabel).join(', '),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            RiseIn(
              delay: const Duration(milliseconds: 120),
              child: _SignOutButton(loading: _signingOut, onTap: _signOut),
            ),
          ],
        ),
      ),
    );
  }

  String _providerLabel(String id) => switch (id) {
    'password' => 'Email',
    'google.com' => 'Google',
    'apple.com' => 'Apple',
    _ => id,
  };
}

class _IdRow extends StatelessWidget {
  const _IdRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(label, style: AppText.meta.copyWith(color: AppColors.ink3)),
        ),
        Expanded(
          child: Text(
            value,
            style: AppText.meta.copyWith(color: AppColors.ink2),
          ),
        ),
      ],
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.hairline2, width: 1.4),
          ),
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.flareText,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout_rounded,
                        size: 18, color: AppColors.flareText),
                    const SizedBox(width: 8),
                    Text(
                      'Sign out',
                      style: AppText.button
                          .copyWith(fontSize: 15, color: AppColors.flareText),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
