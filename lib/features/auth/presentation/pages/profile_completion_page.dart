import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/auth_user.dart';

/// Minimal placeholder shown when a signed-in user has no complete profile
/// yet. This is a FOUNDATION stand-in only — a later task replaces it with
/// the real name/date-of-birth form.
class ProfileCompletionPage extends StatelessWidget {
  const ProfileCompletionPage({required this.user, this.suggestedName, super.key});

  final AuthUser user;
  final String? suggestedName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Complete your profile', style: AppText.greeting),
              const SizedBox(height: AppSpacing.s),
              Text(
                "We just need a couple of details before you're in.",
                style: AppText.body,
              ),
              const SizedBox(height: AppSpacing.l),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    AppScope.of(context).profiles.saveProfile(
                      uid: user.uid,
                      name: suggestedName ?? 'ZIVO User',
                      dateOfBirth: DateTime(2000, 1, 1),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  child: Text('Continue', style: AppText.button.copyWith(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
