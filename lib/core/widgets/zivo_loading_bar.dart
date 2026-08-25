import 'package:flutter/material.dart';

import '../motion/springs.dart';
import '../theme/app_colors.dart';

/// ZIVO's loading indicator: a hairline-thin capsule with a warm ember→solar
/// light sweeping through it. Deliberately quiet — one moving element, no
/// spinner chrome — so it reads as the app breathing, not a machine waiting.
///
/// Indeterminate by default ([value] null): the light glides end-to-end on a
/// gentle ping-pong. Pass a 0–1 [value] for a determinate fill that springs
/// between positions as progress advances. Honors the platform "reduce
/// motion" setting with a static, softly-lit fill instead.
class ZivoLoadingBar extends StatefulWidget {
  const ZivoLoadingBar({
    required this.width,
    this.height = 3,
    this.value,
    super.key,
  });

  /// Full width of the track.
  final double width;

  /// Track thickness. Hairline-thin by design; don't fatten it.
  final double height;

  /// Progress from 0 to 1, or null for the continuous sweep.
  final double? value;

  @override
  State<ZivoLoadingBar> createState() => _ZivoLoadingBarState();
}

class _ZivoLoadingBarState extends State<ZivoLoadingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Started here (not initState) because reduce-motion needs MediaQuery.
    // Guarded so rebuilds never restart or re-pace an already-running bar.
    if (_started) return;
    _started = true;
    final v = widget.value;
    if (reducedMotion(context)) return;
    if (v == null) {
      _c.duration = const Duration(milliseconds: 1700);
      _c.repeat(reverse: true);
    } else {
      // Determinate starts at the reported progress and springs forward from
      // there on every subsequent [value] change (see didUpdateWidget).
      _c.value = v.clamp(0.0, 1.0);
    }
  }

  @override
  void didUpdateWidget(covariant ZivoLoadingBar old) {
    super.didUpdateWidget(old);
    final v = widget.value;
    if (v == null || old.value == v || reducedMotion(context)) return;
    // Retarget mid-flight from wherever the fill actually is — progress
    // updates glide instead of jumping.
    _c.springTo(v.clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return _track(_staticFill());
    return _track(
      ClipRRect(
        borderRadius: BorderRadius.circular(widget.height),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) =>
              widget.value == null ? _sweepLight(child) : _fillLight(child),
          child: const _Light(),
        ),
      ),
    );
  }

  /// Indeterminate: a fixed-width light whose *position* ping-pongs across
  /// the track, eased so the turnarounds feel weighty rather than robotic.
  Widget _sweepLight(Widget? child) {
    final eased = Curves.easeInOut.transform(_c.value);
    return Align(
      alignment: Alignment.lerp(
        const Alignment(-1.35, 0),
        const Alignment(1.35, 0),
        eased,
      )!,
      child: FractionallySizedBox(widthFactor: 0.55, child: child),
    );
  }

  /// Determinate: the fill grows from the left edge, following the spring.
  Widget _fillLight(Widget? child) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: _c.value.clamp(0.0, 1.0),
        child: child,
      ),
    );
  }

  Widget _staticFill() {
    final fraction = widget.value ?? 0.6;
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(widthFactor: fraction, child: const _Light()),
    );
  }

  Widget _track(Widget child) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.hairline2,
          borderRadius: BorderRadius.circular(widget.height),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.height),
          child: child,
        ),
      ),
    );
  }
}

/// The moving gradient itself: ember→solar→ember with transparent ends, so
/// the leading and trailing edges dissolve into the track.
class _Light extends StatelessWidget {
  const _Light();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0x00FF5A1F), // transparent ember
            AppColors.ember,
            AppColors.solar,
            AppColors.ember,
            Color(0x00FF5A1F), // transparent ember
          ],
          stops: [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
      ),
    );
  }
}
