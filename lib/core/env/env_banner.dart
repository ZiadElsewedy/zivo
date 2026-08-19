import 'package:flutter/material.dart';

import 'app_environment.dart';

/// Wraps [child] with a corner ribbon naming the active build configuration —
/// shown in Development and Profile, hidden in Release. Purely diagnostic: it
/// paints over a corner, ignores pointers, and is compiled out of the visible
/// tree in a production (release) build, so it never affects production UX.
class EnvBanner extends StatelessWidget {
  const EnvBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppEnvironment.showBadge) return child;
    return Banner(
      message: AppEnvironment.shortName,
      location: BannerLocation.topEnd,
      // Distinct colours so a Profile build is never mistaken for a dev run.
      color: AppEnvironment.isProfile
          ? const Color(0xFF2F4BDA)
          : const Color(0xFFB8860B),
      child: child,
    );
  }
}
