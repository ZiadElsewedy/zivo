import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/train_tokens.dart';

/// A small, recognizable brand mark for an AI provider, drawn in code (no image
/// assets, no trademarked files embedded). These are brand-*evocative* marks in
/// each provider's signature treatment — the same nominative use as the Google
/// and Spotify marks already in the app — not pixel-exact official logos.
///
/// Uses fixed brand colours on purpose (a `const Color`, not a `TrainColors`
/// token): a brand's identity colour is the same in light and dark, exactly
/// like the bundled `google-icon.png`. Everything ELSE on the settings page
/// dresses from the theme; only the mark itself is brand-fixed.
///   - `'gemini'`   → a four-point spark under Gemini's blue→violet→pink sweep.
///   - `'anthropic'`→ Anthropic's clay-coloured radial burst.
///   - `'auto'`     → the neutral ZIVO spark (violet) — "let ZIVO choose".
class ProviderMark extends StatelessWidget {
  const ProviderMark({required this.provider, this.size = 22, super.key});

  final String provider;
  final double size;

  /// Gemini's signature gradient (blue → violet → pink), approximated.
  static const _geminiGradient = LinearGradient(
    colors: [Color(0xFF1BA1E3), Color(0xFF9B72CB), Color(0xFFD96570)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Anthropic's "clay" brand colour.
  static const _anthropicClay = Color(0xFFCC785C);

  @override
  Widget build(BuildContext context) {
    switch (provider) {
      case 'gemini':
        // The spark shape, painted through the Gemini gradient.
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => _geminiGradient.createShader(rect),
          child: Icon(AppIcons.askFill, size: size, color: Colors.white),
        );
      case 'anthropic':
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _AnthropicBurstPainter(color: _anthropicClay),
          ),
        );
      default:
        // 'auto' (and any future/unknown provider): the neutral ZIVO spark.
        return Icon(AppIcons.askFill, size: size, color: TrainColors.violet);
    }
  }
}

/// Draws Anthropic's radial burst: a ring of slim, rounded rays tapering from
/// the centre — the recognizable "sunburst" silhouette, in one flat colour.
class _AnthropicBurstPainter extends CustomPainter {
  _AnthropicBurstPainter({required this.color});

  final Color color;

  static const _rays = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2;
    // Rays stop short of the centre, leaving the small open core the mark has.
    final inner = outer * 0.16;
    final halfWidth = size.width * 0.055;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    for (var i = 0; i < _rays; i++) {
      final angle = (i / _rays) * 2 * math.pi - math.pi / 2;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      // One ray pointing "up" (−y): a rounded, slightly tapered sliver.
      final path = Path()
        ..moveTo(-halfWidth, -inner)
        ..lineTo(-halfWidth * 0.55, -outer)
        ..quadraticBezierTo(0, -outer - halfWidth * 0.4, halfWidth * 0.55, -outer)
        ..lineTo(halfWidth, -inner)
        ..quadraticBezierTo(0, -inner + halfWidth * 0.4, -halfWidth, -inner)
        ..close();
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AnthropicBurstPainter oldDelegate) =>
      oldDelegate.color != color;
}
