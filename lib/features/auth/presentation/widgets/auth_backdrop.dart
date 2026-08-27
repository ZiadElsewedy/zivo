import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// The warm ambient ground every auth surface sits on.
///
/// A flat `#15110D` fill reads as a dead black rectangle on an OLED phone;
/// ZIVO's ground is a *warm* charcoal, and the palette's depth only shows when
/// something lights it. This paints a single soft bloom of the surface's own
/// hue behind the header — the light source the header and the primary action
/// share — so the screen has a top and a bottom instead of being uniformly
/// flat.
///
/// One bloom, one hue: [hue] follows the hue that owns the surface (ember for
/// the sign-in/verify/change flows, flare for destructive ones), so the
/// backdrop never introduces a colour the screen doesn't already mean.
///
/// The [base] and the bloom are deliberately two separate layers: a
/// [BoxDecoration] carrying both a `color` and a `gradient` paints only the
/// gradient (the shader wins over the paint's colour), which would silently
/// drop the base fill and leave the surface transparent.
class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({
    required this.child,
    this.hue = AppColors.ember,
    this.base = AppColors.ground,
    this.alignment = const Alignment(-0.55, -0.9),
    this.intensity = 1,
    super.key,
  });

  final Widget child;

  /// The hue of the bloom — the surface's owning colour.
  final Color hue;

  /// The opaque surface the bloom is cast onto. `ground` for a full screen,
  /// `card` for a sheet.
  final Color base;

  /// Where the light falls. Defaults to just above the header's first line.
  final Alignment alignment;

  /// Scales the bloom's opacity (a sheet wants less than a full screen).
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: base,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: alignment,
            radius: 1.15,
            colors: [
              hue.withValues(alpha: 0.13 * intensity),
              hue.withValues(alpha: 0.045 * intensity),
              hue.withValues(alpha: 0),
            ],
            stops: const [0, 0.34, 1],
          ),
        ),
        child: child,
      ),
    );
  }
}
