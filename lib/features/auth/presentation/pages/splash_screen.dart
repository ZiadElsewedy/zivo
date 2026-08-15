import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Minimal branded surface shown while the persisted session is being restored
/// on launch. Kept quiet: the wordmark on the warm ground with a soft spinner,
/// so an already-signed-in user never sees the auth screen flash past.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ZIVO',
              style: AppText.greeting.copyWith(letterSpacing: 2),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.ember,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
