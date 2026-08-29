import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../theme/train_tokens.dart';

/// The tone of a [showZivoToast] message — sets its accent and glyph.
enum ToastKind { success, info, error }

/// Shows a premium, top-anchored toast: a translucent, blurred pill that
/// springs down from the top edge, auto-dismisses, and can be tapped away.
/// Replaces Flutter's default bottom SnackBar for a more polished feel.
void showZivoToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  Duration duration = const Duration(milliseconds: 2600),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  // Only one toast at a time — retire any in flight.
  _current?.dismiss?.call();

  final controller = _ToastController();
  final entry = OverlayEntry(
    builder: (_) => _ZivoToast(
      controller: controller,
      message: message,
      kind: kind,
      duration: duration,
    ),
  );
  controller.entry = entry;
  _current = controller;
  overlay.insert(entry);
}

_ToastController? _current;

class _ToastController {
  OverlayEntry? entry;
  VoidCallback? dismiss;
}

class _ZivoToast extends StatefulWidget {
  const _ZivoToast({
    required this.controller,
    required this.message,
    required this.kind,
    required this.duration,
  });

  final _ToastController controller;
  final String message;
  final ToastKind kind;
  final Duration duration;

  @override
  State<_ZivoToast> createState() => _ZivoToastState();
}

class _ZivoToastState extends State<_ZivoToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 260),
    );
    widget.controller.dismiss = _dismiss;
    _anim.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    await _anim.reverse();
    widget.controller.entry?.remove();
    widget.controller.entry = null;
    if (identical(_current, widget.controller)) _current = null;
  }

  (Color, IconData) get _accent => switch (widget.kind) {
    ToastKind.success => (TrainColors.green, AppIcons.success),
    ToastKind.error => (TrainColors.ember, AppIcons.warning),
    ToastKind.info => (TrainColors.ink2, AppIcons.infoFill),
  };

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _accent;
    final curved = CurvedAnimation(
      parent: _anim,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: IgnorePointer(
        ignoring: _leaving,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, child) {
            final t = curved.value.clamp(0.0, 1.0);
            return Opacity(
              opacity: _anim.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -24 * (1 - t)),
                child: child,
              ),
            );
          },
          child: Center(
            child: GestureDetector(
              onTap: _dismiss,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: TrainColors.raised.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: TrainColors.hairlineStrong,
                        width: 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 24,
                          spreadRadius: -6,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 20, color: color),
                        const SizedBox(width: 11),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: AppText.button.copyWith(
                              color: TrainColors.ink,
                              fontSize: 14,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
