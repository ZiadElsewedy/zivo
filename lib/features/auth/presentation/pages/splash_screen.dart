import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/theme/app_colors.dart';

/// Minimal branded surface shown while the persisted session is being restored
/// on launch. Kept quiet: the ZIVO mark on the warm ground with the branded
/// loading animation, so an already-signed-in user never sees the auth screen
/// flash past.
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
            Image.asset(
              'assets/transparent/zivo-mark-paper-256.png',
              width: 72,
              height: 72,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 96,
              height: 96,
              child: Lottie.asset('assets/loading.json', fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }
}
