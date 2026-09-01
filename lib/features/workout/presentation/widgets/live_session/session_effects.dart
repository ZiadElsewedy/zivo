import 'package:flutter/material.dart';
import '../../../../../core/motion/springs.dart';

/// Dissolves the last stretch of a scroll area instead of letting the
/// content be cut by a hard line where the floating commit row begins.
///
/// [reserved] is how much of the bottom the row occupies; content is fully
/// transparent below that line and fades into it over [fade] above it. Uses
/// `dstIn` so the content fades to *transparent*, not to a guessed colour —
/// the screen behind it is a live radial wash that shifts with the phase and
/// the current track, and no fixed scrim colour could sit on it invisibly.
class FadeOutBottom extends StatelessWidget {
  const FadeOutBottom({required this.child, required this.reserved, super.key});

  final Widget child;
  final double reserved;

  /// How far above [reserved] the dissolve starts.
  static const fade = 26.0;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final height = rect.height;
        if (height <= reserved + fade) {
          // Too short to fade anything without eating the content itself.
          return const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
          ).createShader(rect);
        }
        final end = 1 - reserved / height;
        final start = end - fade / height;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0, start, end, 1],
        ).createShader(rect);
      },
      child: child,
    );
  }
}

/// A one-shot scale-in — used for the completion checkmark.
/// The completion checkmark's one-shot arrival — the one other genuinely
/// earned momentum moment (alongside a set chip completing), so it springs
/// in with the same slight, controlled overshoot rather than a scripted
/// multi-wiggle elastic curve.
class PopIn extends StatefulWidget {
  const PopIn({required this.child, super.key});

  final Widget child;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 0,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery isn't available yet in initState — this is the earliest
    // safe place to read it, and it only needs to run once, on arrival.
    if (_started) return;
    _started = true;
    if (reducedMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.springTo(1, spring: AppSprings.bounce);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) =>
          Transform.scale(scale: _controller.value, child: child),
      child: widget.child,
    );
  }
}
