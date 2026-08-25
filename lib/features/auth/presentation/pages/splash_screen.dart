import 'package:flutter/material.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/zivo_loading_bar.dart';

/// The branded surface shown while the persisted session is being restored on
/// launch (and while the profile stream resolves). Quiet by design — the ZIVO
/// mark rises in with a soft spring above a hairline ember sweep — so an
/// already-signed-in user never sees the auth screen flash past, and a cold
/// start feels composed rather than stalled.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// Drives the mark's one-shot entrance: scale + rise settling on the house
  /// spring.
  late final AnimationController _entrance = AnimationController(vsync: this);

  void _begin() {
    if (_entrance.isAnimating || _entrance.value > 0) return;
    // Reduced motion: land instantly instead of animating (or never showing).
    if (reducedMotion(context)) {
      setState(() => _entrance.value = 1);
      return;
    }
    _entrance.springTo(1);
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Kick the entrance after the first frame so it always plays, even when
    // this surface mounts during the same frame as the app's first build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());

    return Scaffold(
      backgroundColor: AppColors.ground,
      body: Center(
        child: AnimatedBuilder(
          animation: _entrance,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_entrance.value);
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - t)),
                child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/transparent/zivo-mark-paper-256.png',
                width: 72,
                height: 72,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(height: 28),
              const ZivoLoadingBar(width: 120),
              const SizedBox(height: 20),
              Text(
                'your whole day, in one place',
                style: AppText.meta.copyWith(
                  color: AppColors.ink3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
